extends Control

const FONT = preload("res://assets/fonts/NotoSansKR.ttf")
const PAPER := Color("e5dfcb")
const MUTED := Color("9caba6")
const GOLD := Color("dac18c")
const TEAL := Color("88cbb7")
@export_file("*.json") var content_path := ItemCatalog.DEFAULT_PATH
@export var save_enabled := true
@export var save_path := SaveService.DEFAULT_PATH
@export var story_path := StoryBook.PATH
@export_file("*.json") var presentation_text_path := ""
var inventory: InventoryModel
var session: BattleSession
var cinematics: SceneCinematics
var vfx: VfxPlayer
var sounds: PresentationSound
var display_inventory: InventoryModel
var board: InventoryBoard
var road: RoadView
var selected := ""
var labels: Dictionary = {}
var stash_grid: GridContainer
var primary: Button
var skip_button: Button
var layout: BattleLayout
var inspected := ""
var rotate_button: Button
var stash_button: Button
var undo_button: Button
var hero_bar: ProgressBar
var enemy_bar: ProgressBar
var restart_dialog: ConfirmationDialog
var reward_inspected := ""
var _reward_selection := ""
var _event_selection := ""
var _save_blocked := false
var recovery_dialog: ConfirmationDialog
var guide_enabled := true
var guide_forced := false
var story_forced := false
var story_entries: Array[Dictionary] = []
var story_scenes: Dictionary = {}

func _ready() -> void:
	DisplayServer.window_set_title("Reaper's Bundle — First Delivery")
	_install_actions()
	_build_theme()
	_build_ui()
	story_entries = StoryBook.load_entries(story_path)
	if content_path == ItemCatalog.DEFAULT_PATH and story_path == StoryBook.PATH:
		story_scenes = StoryBook.load_scenes("res://data/presentation/arang-scenes.json")
	layout.encounter_event.scenes = story_scenes
	session = BattleSession.new()
	add_child(session)
	session.presented.connect(_refresh)
	session.event_presented.connect(_on_event_presented)
	session.playback_recovered.connect(func(reason: String): _notice(reason, true))
	session.playback.bind_feedback(road)
	session.playback.bind_board(board)
	vfx = VfxPlayer.new()
	vfx.board = board
	vfx.road = road
	vfx.z_index = 2
	layout.add_child(vfx)
	session.playback.bind_vfx(vfx)
	sounds = PresentationSound.new()
	add_child(sounds)
	cinematics = SceneCinematics.new()
	cinematics.story_dialogue_enabled = content_path == ItemCatalog.DEFAULT_PATH and story_path == StoryBook.PATH
	cinematics.z_index = 10
	cinematics.sound = sounds
	layout.add_child(cinematics)
	cinematics.skip_button.pressed.connect(func(): session.skip_playback())
	session.playback.bind_cinematics(cinematics)
	session.playback.bind_sound(sounds)
	layout.buttons.sound.pressed.connect(_toggle_sound)
	if save_enabled: session.save_service = SaveService.new(save_path)
	_open_run()

func _toggle_sound() -> void:
	sounds.set_enabled(not sounds.enabled)
	layout.buttons.sound.text = "Sound On" if sounds.enabled else "Sound Off"

func _install_actions() -> void:
	for entry in [["rotate_item", KEY_R], ["undo_layout", KEY_Z]]:
		if not InputMap.has_action(entry[0]):
			InputMap.add_action(entry[0])
		var key := InputEventKey.new()
		key.physical_keycode = entry[1]
		if entry[0] == "undo_layout":
			key.ctrl_pressed = true
		InputMap.action_add_event(entry[0], key)

func _style(fill: Color, border: Color = Color("34474a")) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(1)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box

func _build_theme() -> void:
	theme = Theme.new()
	var readable_font := FontVariation.new()
	readable_font.base_font = FONT
	readable_font.variation_opentype = {0x77676874: 600} # OpenType wght axis
	theme.default_font = readable_font
	theme.set_font("font", "Button", readable_font)
	theme.default_font_size = 18
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_disabled_color", "Button", Color("667b79"))
	theme.set_stylebox("normal", "Button", WoodcutSkin.box("button"))
	theme.set_stylebox("hover", "Button", WoodcutSkin.box("hover"))
	theme.set_stylebox("pressed", "Button", WoodcutSkin.box("pressed"))
	theme.set_stylebox("disabled", "Button", WoodcutSkin.box("disabled"))
	theme.set_stylebox("focus", "Button", _style(Color(0,0,0,0), GOLD))
	theme.set_stylebox("background", "ProgressBar", _style(Color("26383a"), Color("26383a")))
	theme.set_stylebox("fill", "ProgressBar", _style(Color("a66857"), Color("a66857")))
	theme.set_constant("separation", "VBoxContainer", 12)

func _build_ui() -> void:
	layout = BattleLayout.new()
	add_child(layout)
	labels = layout.labels
	board = layout.board
	road = layout.road
	stash_grid = layout.stash_grid
	enemy_bar = layout.enemy_bar
	hero_bar = layout.hero_bar
	primary = layout.buttons.primary
	skip_button = layout.buttons.skip
	rotate_button = layout.buttons.rotate
	stash_button = layout.buttons.stash
	undo_button = layout.buttons.undo
	primary.pressed.connect(_primary_action)
	skip_button.pressed.connect(func(): session.skip_playback())
	rotate_button.pressed.connect(_rotate)
	stash_button.pressed.connect(_stash_selected)
	undo_button.pressed.connect(_undo)
	layout.buttons.restart.pressed.connect(_show_restart)
	layout.buttons.guide.pressed.connect(_toggle_guide)
	layout.buttons.story.pressed.connect(_toggle_story)
	layout.buttons.story_teaser.pressed.connect(_toggle_story)
	layout.rewards.chosen.connect(_choose_reward)
	layout.routes.chosen.connect(_choose_route)
	layout.encounter_event.action_requested.connect(_event_action)
	layout.rewards.inspected.connect(_inspect_reward)
	layout.buttons.reward_skip.pressed.connect(func(): _reward_action("reward_skip"))
	layout.buttons.resolution.pressed.connect(func(): _submit({"type":"resolve_encounter"}))
	board.picked.connect(_activate_item)
	board.hovered.connect(_inspect)
	board.placement_requested.connect(_place)
	board.cancelled.connect(_cancel)
	board.preview_changed.connect(_preview)
	board.synergy_changed.connect(_on_synergy_changed)
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.title = "First Delivery"
	restart_dialog.dialog_text = "Restart this run from the beginning?"
	restart_dialog.ok_button_text = "Restart"
	restart_dialog.cancel_button_text = "Continue"
	restart_dialog.confirmed.connect(_reset_run)
	add_child(restart_dialog)

func _open_run() -> void:
	var next_inventory := _load_inventory()
	if next_inventory == null:
		_notice("Content load failed: " + ItemCatalog.last_error, true)
		return
	if session.save_service == null:
		_install_run(next_inventory)
		_notice("Read each item and arrange your bag to build synergies.")
		return
	var loaded := session.save_service.load_slot(next_inventory)
	if loaded.status == "ok":
		next_inventory.items = loaded.items
		next_inventory.history = loaded.history
		_install_run(next_inventory, loaded.state)
		if loaded.get("recovered", false):
			_notice("Restored the previous save. Recent actions may be missing.", true)
			var recovered := AcceptDialog.new()
			recovered.title = "Save Restored"
			recovered.dialog_text = "The current save could not be read. An earlier save was restored; recent actions may be missing. The damaged file will be preserved separately on the next save."
			add_child(recovered)
			recovered.popup_centered()
		else: _notice("Restored the previous save to the current route format." if loaded.get("migrated", false) else "Continuing from the last saved state.")
	elif loaded.status == "missing":
		var error := session.prepare_new(next_inventory)
		_install_run(next_inventory)
		_notice("Could not prepare save: " + error if not error.is_empty() else "Read item effects and arrange your bag.", not error.is_empty())
	else:
		_save_blocked = true
		_install_run(next_inventory)
		_notice("Cannot continue · " + str(loaded.error), true)
		if session.save_service.can_archive():
			recovery_dialog = ConfirmationDialog.new()
			recovery_dialog.title = "Save File Needs Attention"
			recovery_dialog.dialog_text = str(loaded.error) + "\n\nArchive the existing saves and start a new run? Your old progress cannot be resumed directly."
			recovery_dialog.ok_button_text = "Archive and Restart"
			recovery_dialog.cancel_button_text = "Close"
			recovery_dialog.confirmed.connect(_archive_new_run)
			add_child(recovery_dialog)
			recovery_dialog.popup_centered()
		else:
			var alert := AcceptDialog.new()
			alert.title = "Save File Needs Attention"
			alert.dialog_text = str(loaded.error) + "\n\nProgress is locked to protect your save. Close the game and check the save folder:\n" + session.save_service.path.get_base_dir()
			add_child(alert)
			alert.popup_centered()

func _show_restart() -> void:
	if _save_blocked:
		if recovery_dialog != null: recovery_dialog.popup_centered()
	else: restart_dialog.popup_centered()

func _archive_new_run() -> void:
	if not _save_blocked: return
	var next_inventory := _load_inventory()
	if next_inventory == null:
		_notice("Content load failed: " + ItemCatalog.last_error, true)
		return
	var error := session.prepare_archived_new(next_inventory)
	if not error.is_empty():
		_refresh()
		_notice("Could not archive save: " + error, true)
		return
	_save_blocked = false
	_install_run(next_inventory)
	_notice("Previous saves archived. Starting a new delivery.")

func _reset_run() -> void:
	if _save_blocked: return
	var next_inventory := _load_inventory()
	if next_inventory == null:
		_notice("Content load failed: " + ItemCatalog.last_error, true)
		return
	var error := session.prepare_new(next_inventory)
	if not error.is_empty():
		_notice("Save failed · current progress preserved: " + error, true)
		return
	_install_run(next_inventory)
	_notice("Read each item and arrange your bag to build synergies.")

func _load_inventory() -> InventoryModel:
	var result := ItemCatalog.create_inventory(content_path)
	if result == null: return null
	var error := PresentationLocale.apply(result, presentation_text_path)
	if not error.is_empty():
		ItemCatalog.last_error = error
		return null
	return result

func _install_run(next_inventory: InventoryModel, initial: Dictionary = {}) -> void:
	if inventory != null and inventory.changed.is_connected(session.refresh_layout):
		inventory.changed.disconnect(session.refresh_layout)
	selected = ""
	inspected = ""
	reward_inspected = ""
	_reward_selection = ""
	_event_selection = ""
	story_forced = false
	inventory = next_inventory
	board.stop_placement_feedback()
	board.select("", 0)
	board.cancel_motion()
	inventory.changed.connect(session.refresh_layout)
	session.reset(inventory, initial)

func _refresh() -> void:
	var view := session.display_snapshot()
	if view.is_empty(): return
	# The board and labels always read the SAME event snapshot, including consumption.
	display_inventory = InventoryModel.new()
	display_inventory.definitions = inventory.definitions
	display_inventory.dimensions = Vector2i(view.config.grid_width, view.config.grid_height)
	display_inventory.config = view.config
	display_inventory.items = view.inventory_items.duplicate(true)
	display_inventory.locked = _save_blocked or session.is_busy() or view.phase in ["battle", "route", "event_result", "defeat", "complete"]
	if display_inventory.locked: board.stop_placement_feedback()
	board.model = display_inventory
	board.display_state = view
	board.hazards = InventoryRules.active_hazards(view)
	board.presentation_busy = session.is_busy()
	if display_inventory.locked and (board.dragging or not board.pressed_uid.is_empty()): board.cancel_motion()
	var reward: Dictionary = view.get("reward", {})
	if view.phase == "reward":
		if _reward_selection != reward.selected and display_inventory.items.has(reward.uid):
			selected = reward.uid
			inspected = selected
			board.select(selected, display_inventory.items[selected].rotation)
		_reward_selection = reward.selected
	else:
		_reward_selection = ""
		reward_inspected = ""
	if view.phase == "event":
		if _event_selection != view.event.selected and display_inventory.items.has(view.event.uid):
			selected = view.event.uid
			inspected = selected
			board.select(selected, display_inventory.items[selected].rotation)
		_event_selection = view.event.selected
	else: _event_selection = ""
	if not display_inventory.items.has(selected):
		selected = ""
		board.select("", 0)
	board.used = view.used if view.phase == "battle" else {}
	board.queue_redraw()
	road.player_visual = view.config.player_visual
	road.enemy_visual = CombatSimulator.enemy(view).visual
	var background := PresentationArt.background_for_visual(road.enemy_visual)
	if layout.background_texture != background:
		layout.background_texture = background
		layout.queue_redraw()
	road.defeated = view.phase in ["reward", "victory", "route", "complete"]
	road.enemy_lost = int(view.enemy_health) <= 0
	road.queue_redraw()
	labels.chapter.text = "Stage %02d / %02d  ·  %s" % [RouteRules.step(view) + 1, view.config.encounters.size(), "Battle · Turn %d" % view.turn if view.phase == "battle" else "Prepare"]
	var resolution: Dictionary = EventRules.resolution(view)
	var scenario: Array = view.config.get("resolutions", [])
	if not scenario.is_empty():
		var total: int = int(view.config.events[0].step) + 2
		labels.chapter.text = "Stage %02d / %02d  ·  %s" % [mini(RouteRules.step(view) + 1, total), total, "Battle · Turn %d" % view.turn if view.phase == "battle" else "Prepare"]
	labels.enemy.text = CombatSimulator.enemy(view).name
	enemy_bar.max_value = CombatSimulator.enemy(view).hp
	enemy_bar.value = view.enemy_health
	labels.enemy_hp.text = "Spirit %d / %d  ·  Block %d" % [view.enemy_health, CombatSimulator.enemy(view).hp, view.enemy_guard]
	var intent := CombatSimulator.intent(view)
	labels.intent.text = "Next · " + EffectText.intent(intent)
	var intent_size := 20
	var intent_font: Font = labels.intent.get_theme_font("font")
	while intent_size > 16 and intent_font.get_string_size(labels.intent.text, HORIZONTAL_ALIGNMENT_LEFT, -1, intent_size).x > labels.intent.size.x:
		intent_size -= 2
	labels.intent.add_theme_font_size_override("font_size", intent_size)
	layout.intent_icon.set_operation(str(intent.operation))
	var enemy_reactions := EffectText.enemy_reactions(CombatSimulator.enemy(view).reactions)
	labels.enemy_reactions.text = "\n".join(enemy_reactions)
	layout.reaction_panel.visible = not enemy_reactions.is_empty() and view.phase in ["packing", "battle"]
	labels.enemy_reactions.visible = layout.reaction_panel.visible
	_refresh_turn_preview(view)
	hero_bar.max_value = view.config.max_health
	hero_bar.value = view.health
	labels.hero.text = "HP %d / %d   ·   Block %d" % [view.health, view.config.max_health, view.guard]
	labels.energy.text = "Energy %d/%d" % [view.energy, view.config.energy_per_turn]
	var messages: PackedStringArray = []
	for message: String in view.messages.slice(maxi(0, view.messages.size() - 2)):
		messages.append(_display_message(message))
	labels.log.text = "\n".join(messages)
	var story_unlocked := StoryBook.unlocked(view, story_entries)
	var teaser: Button = layout.buttons.story_teaser
	teaser.visible = not _save_blocked and not session.is_busy() and view.phase in ["packing", "victory", "complete"] and not story_unlocked.is_empty()
	if teaser.visible:
		var latest: Dictionary = story_unlocked.back()
		teaser.text = "Story · %s  ›\n%s" % [latest.title, latest.teaser]
		var scene: Dictionary = story_scenes.get(view.get("event", {}).get("id", ""), {})
		if view.phase == "packing" and not scene.is_empty():
			var event_view: Dictionary = view.get("event", {})
			var approach := "approach_left" if event_view.get("status", "") == "left" else ("approach_packed" if view.packed_items.has(event_view.get("uid", "")) else "approach")
			teaser.text = "Story · The voice in the grove  ›\n" + str(scene[approach])
	layout.buttons.story.disabled = _save_blocked or story_unlocked.is_empty()
	layout.buttons.story.text = "Story %d" % story_unlocked.size() if not story_unlocked.is_empty() else "Story"
	labels.bag.text = "Bag   %d / %d" % [display_inventory.used_cells(), display_inventory.dimensions.x * display_inventory.dimensions.y]
	var attack_totals := InventoryRules.totals(view.packed_items, "use", "enemy")
	var guard_totals := InventoryRules.totals(view.packed_items, "turn_end")
	labels.passive.text = "Cannot calculate effects" if not attack_totals.error.is_empty() or not guard_totals.error.is_empty() else "ATK %d · End Block +%d" % [attack_totals.damage, guard_totals.guard]
	match view.phase:
		"packing": primary.text = "Start Battle"
		"battle": primary.text = "End Turn"
		"reward": primary.text = "Confirm Reward" if display_inventory.is_packed(reward.uid) else "Place reward in bag"
		"route": primary.text = "Choose a path below"
		"event":
			if view.event.selected != "take": primary.text = "Choose below"
			else: primary.text = "Confirm Keepsake" if display_inventory.is_packed(view.event.uid) or resolution.get("allow_stash", false) else "Place keepsake in bag"
		"event_result": primary.text = "Finish Event"
		"victory": primary.text = "Finish Delivery" if RouteRules.last(view) else ("Continue to Event" if not EventRules.due(view).is_empty() else ("Choose a Path" if RouteRules.enabled(view) and view.route.choice.is_empty() else "Next Encounter"))
		"defeat": primary.text = "Return · Restart"
		"complete": primary.text = "Restart Run"
	if view.phase == "complete":
		labels.chapter.text = str(scenario[0].completion_title) if not scenario.is_empty() else "First Delivery Complete"
		labels.intent.text = "The way is clear."
	elif view.phase == "defeat":
		labels.chapter.text = "Returned with your mentor"
		labels.intent.text = "Rearrange your bag and try again."
	elif view.phase == "victory":
		labels.chapter.text = "Encounter complete · Prepare"
		labels.intent.text = "Victory · Prepare your bag"
	elif view.phase == "reward":
		labels.chapter.text = "Stage %02d complete · Reward and preparation" % (RouteRules.step(view) + 1)
	elif view.phase == "route":
		labels.chapter.text = "First stage complete · Choose a path"
	elif view.phase in ["event", "event_result"]:
		labels.chapter.text = "An encounter on the road"
	layout.preparation.visible = view.phase in ["packing", "reward", "victory", "event"]
	layout.rewards.refresh(view, display_inventory.definitions, session.is_busy())
	layout.routes.refresh(view, session.is_busy())
	layout.encounter_event.refresh(view, session.is_busy())
	layout.buttons.reward_skip.visible = view.phase == "reward" and not session.is_busy()
	layout.buttons.reward_skip.disabled = _save_blocked or session.is_busy()
	layout.buttons.restart.disabled = _save_blocked and (session.save_service == null or not session.save_service.can_archive())
	layout.buttons.restart.text = "Restore Save" if _save_blocked else "Restart"
	for key in ["enemy", "enemy_hp", "hero", "hero_name", "energy", "intent", "log"]:
		labels[key].visible = view.phase not in ["reward", "route", "event", "event_result"]
	layout.intent_icon.visible = labels.intent.visible and view.phase in ["packing", "battle"]
	if layout.buttons.story_teaser.visible: labels.log.hide()
	hero_bar.visible = view.phase not in ["reward", "route", "event", "event_result"]
	enemy_bar.visible = view.phase not in ["reward", "route", "event", "event_result"]
	labels.notice.position = Vector2(320, 446) if view.phase in ["reward", "route", "event", "event_result"] else Vector2(360, 452)
	labels.notice.size = Vector2(620, 38) if view.phase in ["reward", "route", "event", "event_result"] else Vector2(385, 48)
	if layout.reaction_panel.visible:
		labels.notice.position.y = 464
		labels.notice.size.y = 44
	labels.help.text = "Click item: use · Hover: details · Right button: end turn" if view.phase == "battle" else "Drag or click empty cell: place · R: rotate · Ctrl+Z: undo · Esc / right click: cancel"
	if view.phase == "reward": labels.help.text = "Switch rewards before confirming · Move items to storage for space · Ctrl+Z: undo"
	if view.phase == "event": labels.help.text = "You may keep the evidence in storage. Put it in your bag before the next battle to use it." if resolution.get("allow_stash", false) else "The keepsake appears in storage. Place it in your bag to keep it, or leave it behind."
	if view.phase == "event_result": labels.help.text = "Scroll to read the outcome, then finish the event."
	if view.phase == "route": labels.help.text = "Compare the paths and enemies. Your choice is saved automatically."
	if not board.hazards.is_empty():
		var hazard: Dictionary = board.hazards[0]
		var targets: PackedStringArray = []
		for tag: String in hazard.required_tags: targets.append(str(view.config.tag_labels.get(tag, tag)))
		labels.help.text = "%s · %s on marked cells costs +%d energy · %s" % [hazard.label, "/".join(targets), hazard.cost_increase, hazard.description]
	if _save_blocked:
		labels.help.text = "Use Restore Save to archive your existing files and start a new run." if session.save_service != null and session.save_service.can_archive() else "Progress is locked to protect your save. Close the game and check the save folder."
	_rebuild_stash()
	_refresh_details()
	undo_button.disabled = _save_blocked or session.is_busy() or inventory.locked or inventory.history.is_empty()
	primary.disabled = _save_blocked or session.is_busy() or view.phase == "route" or (view.phase == "reward" and not display_inventory.is_packed(reward.uid)) or (view.phase == "event" and (view.event.selected != "take" or (not display_inventory.is_packed(view.event.uid) and not resolution.get("allow_stash", false))))
	var resolution_button: Button = layout.buttons.resolution
	var event: Dictionary = view.get("event", {})
	var event_entry := EventRules.definition(view)
	resolution_button.visible = not _save_blocked and not session.is_busy() and view.phase == "battle" and not resolution.is_empty() and not event_entry.is_empty() and event.get("status", "") in ["carried", "left"] and RouteRules.step(view) == int(event_entry.step) + 1
	var eligible: bool = event.get("status", "") == "carried" and view.packed_items.has(event.get("uid", ""))
	resolution_button.disabled = not eligible
	var evidence_left: bool = event.get("status", "") == "left"
	resolution_button.text = str(resolution.get("button", "")) if eligible else ("Evidence left behind" if evidence_left else "Place evidence in your bag")
	resolution_button.tooltip_text = str(resolution.get("button", "")) if eligible else ("You left the evidence in the grove." if evidence_left else str(resolution.get("unavailable", "")))
	skip_button.disabled = not session.is_busy()
	skip_button.visible = session.is_busy()
	if session.is_busy(): primary.text = "Playing…"

func _refresh_turn_preview(view: Dictionary) -> void:
	layout.turn_preview.visible = view.phase == "battle" and not session.is_busy() and not _save_blocked
	if not layout.turn_preview.visible: return
	var result := session.preview_end_turn()
	if not result.error.is_empty():
		labels.preview_summary.text = "Cannot predict outcome"
		labels.preview_body.text = result.error
		return
	var after := result.after()
	var damage := 0
	var absorbed := 0
	var victory := false
	var lines: Array[String] = []
	for event: Dictionary in result.events():
		if event.kind == "turn_started": continue
		if event.kind == "damage" and event.target == "player":
			damage += int(event.health_damage)
			absorbed += int(event.get("absorbed", 0))
		if event.kind == "victory": victory = true
		var target := ""
		if event.get("target", "") == "player": target = "You · "
		elif event.get("target", "") == "enemy": target = "Enemy · "
		lines.append(target + str(event.message))
	var outcome := " · Defeat" if after.phase == "defeat" else (" · Victory" if victory else "")
	labels.preview_summary.text = "Expected damage %d · Blocked %d\nRemaining HP %d%s" % [damage, absorbed, after.health, outcome]
	labels.preview_body.text = "\n".join(lines) if not lines.is_empty() else "No additional effects"

func _rebuild_stash() -> void:
	for child in stash_grid.get_children():
		stash_grid.remove_child(child)
		child.queue_free()
	for uid: String in display_inventory.items:
		if display_inventory.is_packed(uid): continue
		var slot := StashSlot.new()
		slot.item = display_inventory.definition(uid)
		slot.disabled = display_inventory.locked
		slot.gui_input.connect(_stash_input.bind(uid, slot))
		slot.mouse_entered.connect(_inspect.bind(uid))
		slot.mouse_exited.connect(_inspect.bind(""))
		stash_grid.add_child(slot)

func _stash_input(event: InputEvent, uid: String, slot: Control) -> void:
	if _save_blocked or session.is_busy() or display_inventory.locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(uid)
		board.begin_external_drag(uid, slot.get_global_transform_with_canvas() * event.position)

func _inspect(uid: String) -> void:
	story_forced = false
	guide_forced = false
	reward_inspected = ""
	var next := uid if not uid.is_empty() else selected
	if inspected != next: layout.detail_scroll.scroll_vertical = 0
	inspected = next
	_refresh_details()

func _refresh_details() -> void:
	rotate_button.disabled = selected.is_empty() or display_inventory.locked
	stash_button.disabled = selected.is_empty() or display_inventory.locked or not display_inventory.is_packed(selected)
	var candidate := not reward_inspected.is_empty() and display_inventory.definitions.has(reward_inspected)
	var has_details := candidate or (not inspected.is_empty() and display_inventory.items.has(inspected))
	layout.details.visible = has_details and not guide_forced and not story_forced
	layout.guide.visible = guide_enabled and not story_forced and (not has_details or guide_forced)
	layout.story.visible = story_forced and not _save_blocked
	var view := session.display_snapshot()
	var unlocked := StoryBook.unlocked(view, story_entries)
	layout.story.refresh(unlocked)
	layout.guide.refresh(view, session.is_busy(), _save_blocked)
	var teaser: Button = layout.buttons.story_teaser
	teaser.visible = not story_forced and not _save_blocked and not session.is_busy() and view.phase in ["packing", "victory", "complete"] and not unlocked.is_empty()
	labels.log.visible = not teaser.visible and view.phase not in ["reward", "route", "event", "event_result"]
	layout.log_scroll.visible = labels.log.visible
	_refresh_synergy_info()
	if not layout.details.visible: return
	var item: ItemData = display_inventory.definitions[reward_inspected] if candidate else display_inventory.definition(inspected)
	var detail_uid := "candidate" if candidate else inspected
	labels.item_name.text = item.display_name
	labels.item_meta.text = "%d cells  ·  %s" % [item.footprint.size(), "In bag" if display_inventory.is_packed(inspected) else "Storage"]
	if candidate: labels.item_meta.text = "%d cells · reward (no adjacency yet)" % item.footprint.size()
	labels.description.text = item.description
	var detail_cells: Array[Vector2i] = []
	if not candidate: detail_cells = display_inventory.occupied_cells(inspected)
	var values := ItemCodec.item(item, detail_cells)
	var packed := display_inventory.combat_snapshot()
	var synergy := board.synergy_view()
	if not candidate and inspected == selected and synergy.mode == "preview" and synergy.items.has(detail_uid):
		packed = synergy.items
		values = packed[detail_uid]
		labels.item_meta.text += "\nPlacement Preview"
	var cost := InventoryRules.action_cost(session.display_snapshot(), values)
	labels.item_meta.text += " · Energy %d%s · %d uses/turn" % [cost.total, " (" + ", ".join(cost.sources) + " +%d)" % cost.extra if cost.extra > 0 else "", item.uses_per_turn]
	if candidate or not packed.has(detail_uid): packed = {detail_uid: values}
	labels.power.text = " · ".join(EffectText.lines(values, packed, detail_uid, display_inventory.config.tag_labels))
	labels.sources.text = ""
	var plans: Array[Dictionary] = []
	for trigger in ["use", "turn_end", "damage_taken"]:
		for plan: Dictionary in EffectApplier.plan(packed, detail_uid, trigger): plans.append({"trigger":trigger, "plan":plan})
	var icons := {}
	for uid: String in packed:
		if display_inventory.items.has(uid): icons[uid] = display_inventory.definition(uid)
		elif candidate and uid == detail_uid: icons[uid] = item
	layout.synergy_breakdown.refresh(plans, icons)
	labels.item_hint.text = "Passive"
	if EffectApplier.has_trigger(values, "use"):
		var error := session.use_error(inspected)
		labels.item_hint.text = error if not error.is_empty() else "Click to use"
	if not display_inventory.locked: labels.item_hint.text = "Drag to place · R to rotate"
	if candidate: labels.item_hint.text = "Select a reward below, then place it in your bag."

func _on_synergy_changed() -> void:
	if display_inventory == null or session == null: return
	_refresh_details()

func _refresh_synergy_info() -> void:
	var view := board.synergy_view()
	var text := ""
	match view.mode:
		"current": text = "Gold: add · Blue: mult · Red: condition"
		"preview": text = "Preview · gold / blue / red"
		"invalid": text = "Invalid placement · links hidden"
		"error": text = "Cannot calculate links"
	labels.synergy_state.text = text
	labels.connections.text = ""
	if not layout.details.visible or inspected != selected or not reward_inspected.is_empty(): return
	if view.mode == "error":
		labels.connections.text = view.error
		return
	if view.mode not in ["current", "preview"]: return
	var lines: Array[String] = []
	for link: Dictionary in view.links:
		var source: String = view.items[link.source].name
		var target: String = view.items[link.target].name
		var when: String = {"use":"Use", "turn_end":"End Turn", "damage_taken":"On damage"}[link.trigger]
		var range_name: String = {"orthogonal":"Adjacent", "diagonal":"Diagonal", "neighbor":"8 surrounding cells"}.get(link.range, "Self" if link.source == link.target else "Range")
		var value := "Condition · max %d" % link.limit if link.kind == "condition" else ("%s ×%d" % [EffectText.operation(link.operation), link.amount] if link.kind == "multiply" else "%s +%d" % [EffectText.operation(link.operation), link.amount])
		lines.append("%s → %s · %s · %s · %s" % [source, target, range_name, when, value])
	var title := "Preview links" if view.mode == "preview" else "Current links"
	labels.connections.text = title + ("\n" + "\n".join(lines) if not lines.is_empty() else " · None")

func _inspect_reward(item_id: String) -> void:
	story_forced = false
	guide_forced = false
	reward_inspected = item_id
	layout.detail_scroll.scroll_vertical = 0
	_refresh_details()

func _toggle_guide() -> void:
	if display_inventory == null or session == null: return
	story_forced = false
	if layout.guide.visible:
		guide_enabled = false
		guide_forced = false
	else:
		guide_enabled = true
		guide_forced = true
	_refresh_details()

func _toggle_story() -> void:
	if display_inventory == null or session == null or _save_blocked or story_entries.is_empty(): return
	story_forced = not story_forced
	guide_forced = false
	_refresh_details()

func _choose_reward(item_id: String) -> void:
	if _save_blocked or session.is_busy(): return
	reward_inspected = ""
	board.cancel_motion()
	var view := session.display_snapshot()
	if view.phase == "reward" and view.reward.selected == item_id:
		_select(view.reward.uid)
		return
	_reward_action("reward_select", item_id)

func _event_action(kind: String) -> void:
	if _save_blocked or session.is_busy(): return
	var view := session.display_snapshot()
	if view.phase not in ["event", "event_result"]: return
	_submit({"type": kind, "event_id": view.event.id})

func _choose_route(route_id: String) -> void:
	if _save_blocked or session.is_busy(): return
	_submit({"type":"choose_route", "route_id":route_id})

func _reward_action(kind: String, item_id := "") -> void:
	if session.is_busy(): return
	var view := session.display_snapshot()
	if view.phase != "reward": return
	_submit({"type": kind, "offer_id": view.reward.offer_id, "item_id": item_id})

func _activate_item(uid: String) -> void:
	if _save_blocked or session.is_busy(): return
	_select(uid)
	if session.display_snapshot().phase == "battle":
		_submit({"type": "use_item", "uid": uid})

func _select(uid: String) -> void:
	if _save_blocked or session.is_busy(): return
	if not display_inventory.items.has(uid):
		return
	selected = uid
	reward_inspected = ""
	inspected = uid
	layout.detail_scroll.scroll_vertical = 0
	board.select(uid, display_inventory.items[uid].rotation)
	_refresh_details()
	_notice("%s selected · %s" % [display_inventory.definition(uid).display_name, "Click to use." if display_inventory.locked else "Drag or click an empty cell. Press R to rotate."])

func _place(uid: String, origin: Vector2i, rotation: int) -> void:
	if _save_blocked or session.is_busy(): return
	var before := session.display_snapshot()
	var previous: Dictionary = before.get("inventory_items", {}).get(uid, {})
	var previous_origin: Vector2i = previous.get("origin", Vector2i(-1, -1))
	var old_links := InventoryRules.synergy_links(before.get("packed_items", {}), uid)
	var error := session.place(uid, origin, rotation)
	if not error.is_empty():
		_notice(error + " Original placement preserved.", true)
		return
	board.select(uid, rotation)
	var after := session.display_snapshot()
	var current: Dictionary = after.get("inventory_items", {}).get(uid, {})
	if previous != current:
		var next_links := InventoryRules.synergy_links(after.get("packed_items", {}), uid)
		var new_link := false
		if old_links.error.is_empty() and next_links.error.is_empty():
			for link: Dictionary in next_links.links:
				if link not in old_links.links: new_link = true
		board.start_placement_feedback(uid, previous_origin, new_link)
		sounds.cue("snap")
	_notice("%s placed · Ctrl+Z to undo." % inventory.definition(uid).display_name)

func _preview(origin: Vector2i) -> void:
	if session.is_busy(): return
	if selected.is_empty() or inventory.locked:
		return
	var error := inventory.placement_error(selected, origin, board.pending_rotation)
	if error.is_empty():
		var preview := inventory.preview(selected, origin, board.pending_rotation)
		if not preview.error.is_empty():
			_notice(preview.error, true)
			return
		var changes: PackedStringArray = []
		var before := inventory.combat_snapshot()
		var view := session.display_snapshot()
		if preview.snapshot.has(selected):
			var old_cost: int = InventoryRules.action_cost(view, before[selected]).total if before.has(selected) else inventory.definition(selected).cost
			var new_cost: int = InventoryRules.action_cost(view, preview.snapshot[selected]).total
			if old_cost != new_cost: changes.append("%s energy %d → %d" % [inventory.definition(selected).display_name, old_cost, new_cost])
		var current_guard := InventoryRules.totals(before, "turn_end")
		for uid: String in preview.snapshot:
			var old := InventoryRules.action_result(before, uid)
			var next := InventoryRules.action_result(preview.snapshot, uid)
			if not old.error.is_empty():
				changes.append("%s unavailable → %d" % [inventory.definition(uid).display_name, next.power])
				continue
			if old.effects != next.effects:
				for i in next.effects.size():
					var previous: int = old.effects[i].amount if i < old.effects.size() else 0
					var effect: Dictionary = next.effects[i]
					if previous != effect.amount:
						changes.append("%s %s %d → %d" % [inventory.definition(uid).display_name, EffectText.operation(effect.kind), previous, effect.amount])
		changes.append("End-turn block unavailable → %d" % preview.guard if not current_guard.error.is_empty() else "End-turn block %d → %d" % [current_guard.guard, preview.guard])
		_notice("Preview: " + " · ".join(changes))
	else:
		_notice(error, true)

func _rotate() -> void:
	if _save_blocked or session.is_busy(): return
	if selected.is_empty() or inventory.locked:
		return
	board.stop_placement_feedback()
	board.pending_rotation = posmod(board.pending_rotation + 1, 4)
	board.grab_offset = Vector2i.ZERO
	board.drag_anchor = Vector2.ONE * board.cell_size * 0.5
	board.synergy_changed.emit()
	board.queue_redraw()
	_notice("%d° rotation · Click an empty cell to place. Esc cancels." % (board.pending_rotation * 90))

func _cancel() -> void:
	if _save_blocked or session.is_busy(): return
	board.cancel_motion()
	board.stop_placement_feedback()
	selected = ""
	inspected = ""
	reward_inspected = ""
	board.select("", 0)
	_refresh_details()
	_notice("Selection canceled. Placed items remain unchanged.")

func _stash_selected() -> void:
	if _save_blocked or session.is_busy(): return
	board.stop_placement_feedback()
	var error := session.stash(selected)
	if error.is_empty(): _notice("Moved to storage. Click an empty cell to place it again.")
	else: _notice(error, true)

func _undo() -> void:
	if _save_blocked or session.is_busy(): return
	board.stop_placement_feedback()
	var error := session.undo_layout()
	if error.is_empty():
		if inventory.items.has(selected):
			board.select(selected, inventory.items[selected].rotation)
		_notice("Previous placement restored.")
	else: _notice(error, true)

func _primary_action() -> void:
	if _save_blocked or session.is_busy(): return
	board.cancel_motion()
	match session.display_snapshot().phase:
		"packing": _submit({"type": "start"})
		"battle": _submit({"type": "end_turn"})
		"reward": _reward_action("reward_confirm")
		"event": _event_action("event_confirm")
		"event_result": _event_action("event_continue")
		"victory": _submit({"type": "advance"})
		"defeat", "complete": _reset_run()

func _submit(request: Dictionary) -> void:
	var error := session.submit(request)
	if not error.is_empty(): _notice(error, true)
	else: _notice("Playing action results in order.")

func _on_event_presented(event: Dictionary) -> void:
	_notice(event.message)

func _notice(message: String, error := false) -> void:
	labels.notice.text = _display_message(message)
	labels.notice.add_theme_color_override("font_color", Color("e9997b") if error else MUTED)

func _display_message(message: String) -> String:
	return PresentationLocale.message(message) if not presentation_text_path.is_empty() else message

func _unhandled_key_input(event: InputEvent) -> void:
	if _save_blocked or restart_dialog.visible or session.is_busy():
		return
	if event.is_action_pressed("rotate_item"):
		_rotate()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("undo_layout"):
		_undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
