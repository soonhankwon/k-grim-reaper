class_name VfxPlayer
extends Control
## Presentation-only particles driven by recorded event snapshots and queue progress.
const PATH := "res://data/presentation/vfx.json"
const ATLAS = preload("res://assets/visuals/vfx-particles-v1.png")
var data: Dictionary = {}
var active_rule: Dictionary = {}
var active_profile: Dictionary = {}
var burst: GPUParticles2D
var board: InventoryBoard
var road: RoadView
var elapsed := 0.0
var impacted := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1280, 720)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if validate(parsed).is_empty(): data = parsed
	burst = GPUParticles2D.new()
	burst.name = "EventParticles"
	burst.emitting = false
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.local_coords = true
	burst.fixed_fps = 60
	burst.use_fixed_seed = true
	burst.seed = 1742
	burst.speed_scale = 0.0
	burst.visibility_rect = Rect2(-600, -300, 1200, 600)
	burst.hide()
	add_child(burst)

static func validate(value: Variant) -> String:
	if not value is Dictionary or not value.get("profiles") is Dictionary or not value.get("rules") is Array: return "VFX invalid table format"
	if value.profiles.size() > 32 or value.rules.size() > 64: return "VFX too many definitions."
	for key in value.profiles:
		var profile: Variant = value.profiles[key]
		if not key is String or key.is_empty() or not profile is Dictionary: return "VFX invalid profile"
		for field in ["tile", "count", "lifetime", "velocity_min", "velocity_max", "gravity_y", "spread", "scale_min", "scale_max", "advance_seconds"]:
			var number: Variant = profile.get(field)
			if not (number is int or number is float) or not is_finite(float(number)): return "VFX invalid value: " + field
		if int(profile.tile) != profile.tile or int(profile.tile) < 0 or int(profile.tile) > 3 or int(profile.count) != profile.count or int(profile.count) < 1 or int(profile.count) > 32: return "VFX invalid tile or count"
		if profile.lifetime <= 0 or profile.lifetime > 2 or profile.advance_seconds <= 0 or profile.advance_seconds > 2: return "VFX invalid duration"
		if profile.velocity_min < 0 or profile.velocity_max < profile.velocity_min or profile.velocity_max > 200 or absf(float(profile.gravity_y)) > 200 or profile.spread < 0 or profile.spread > 180: return "VFX invalid motion"
		if profile.scale_min <= 0 or profile.scale_max < profile.scale_min or profile.scale_max > 2: return "VFX invalid scale"
	var seen: Dictionary = {}
	for rule: Variant in value.rules:
		if not rule is Dictionary: return "VFX invalid rule"
		for field in ["event", "effect_id", "condition", "anchor", "profile"]:
			if not rule.get(field) is String: return "VFX invalid rule field: " + field
		if rule.event.is_empty() or rule.event.length() > 64 or rule.effect_id.length() > 64 or not value.profiles.has(rule.profile): return "VFX invalid reference"
		if rule.condition not in ["always", "enemy_defeated", "hazard_added"] or rule.anchor not in ["enemy", "source", "hazards"]: return "VFX invalid condition"
		var signature: String = rule.event + "/" + rule.effect_id + "/" + rule.condition
		if seen.has(signature): return "VFX duplicate rule"
		seen[signature] = true
	return ""

func begin_feedback(event: Dictionary, before: Dictionary) -> bool:
	clear_feedback()
	if data.is_empty() or board == null or road == null: return false
	var after: Dictionary = event.get("after", {})
	for candidate: Dictionary in data.rules:
		if str(event.get("kind", "")) != candidate.event: continue
		if not candidate.effect_id.is_empty() and str(event.get("effect_id", "")) != candidate.effect_id: continue
		if not _condition(candidate.condition, event, before, after): continue
		var location := _location(candidate.anchor, event, before, after)
		if location.is_empty(): continue
		active_rule = candidate.duplicate(true)
		active_profile = data.profiles[candidate.profile].duplicate(true)
		_configure(location)
		return true
	return false

func _condition(condition: String, event: Dictionary, before: Dictionary, after: Dictionary) -> bool:
	match condition:
		"always": return true
		"enemy_defeated": return event.get("target", "") == "enemy" and int(event.get("health_damage", 0)) > 0 and int(before.get("enemy_health", 0)) > 0 and int(after.get("enemy_health", 1)) <= 0
		"hazard_added":
			var next := InventoryRules.active_hazards(after)
			return not next.is_empty() and next != InventoryRules.active_hazards(before)
	return false

func _location(anchor: String, event: Dictionary, before: Dictionary, after: Dictionary) -> Dictionary:
	if anchor == "enemy": return {"center":road.position + Vector2(941, 124), "extent":Vector2.ZERO}
	var cells: Array = []
	if anchor == "source":
		var uid := str(event.get("source", ""))
		var items: Dictionary = after.get("packed_items", {})
		if not items.has(uid): items = before.get("packed_items", {})
		if not items.has(uid): return {}
		cells = items[uid].get("cells", [])
	elif anchor == "hazards":
		for hazard: Dictionary in InventoryRules.active_hazards(after):
			for cell: Vector2i in hazard.cells:
				if cell not in cells: cells.append(cell)
	if cells.is_empty(): return {}
	var minimum := Vector2(10000, 10000)
	var maximum := Vector2(-10000, -10000)
	for cell: Vector2i in cells:
		var point := board.position + InventoryBoard.PAD + (Vector2(cell) + Vector2(0.5,0.5)) * board.cell_size
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	return {"center":(minimum + maximum) / 2.0, "extent":(maximum - minimum) / 2.0 if anchor == "hazards" else Vector2.ZERO}

func _configure(location: Dictionary) -> void:
	burst.amount = int(active_profile.count)
	burst.lifetime = float(active_profile.lifetime)
	burst.position = location.center
	var texture := AtlasTexture.new()
	texture.atlas = ATLAS
	texture.region = Rect2(int(active_profile.tile) * 16, 0, 16, 16)
	burst.texture = texture
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, -1, 0)
	material.spread = float(active_profile.spread)
	material.initial_velocity_min = float(active_profile.velocity_min)
	material.initial_velocity_max = float(active_profile.velocity_max)
	material.gravity = Vector3(0, float(active_profile.gravity_y), 0)
	material.scale_min = float(active_profile.scale_min)
	material.scale_max = float(active_profile.scale_max)
	var extent: Vector2 = location.extent
	if extent.length_squared() > 0:
		material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		material.emission_box_extents = Vector3(extent.x, extent.y, 0)
	burst.process_material = material

func impact_feedback() -> void:
	if active_rule.is_empty() or impacted: return
	impacted = true
	elapsed = 0.0
	burst.speed_scale = 0.0
	burst.restart(true)
	burst.show()
	burst.request_particles_process(0.001)

func set_feedback_progress(value: float) -> void:
	if not impacted or not burst.visible: return
	var desired := maxf(0.0, (clampf(value, 0.0, 1.0) - 0.5) * float(active_profile.advance_seconds))
	var delta := maxf(0.0, desired - elapsed)
	if delta > 0.0:
		burst.request_particles_process(delta)
		elapsed = desired

func clear_feedback() -> void:
	active_rule = {}
	active_profile = {}
	elapsed = 0.0
	impacted = false
	if burst != null:
		burst.emitting = false
		burst.speed_scale = 0.0
		burst.hide()
