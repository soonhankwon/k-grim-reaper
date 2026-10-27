extends Control

const FONT = preload("res://assets/fonts/NotoSansKR.ttf")
const PAPER := Color("e5dfcb")
const MUTED := Color("9caba6")
const GOLD := Color("dac18c")
const TEAL := Color("88cbb7")
@export_file("*.json") var content_path := ItemCatalog.DEFAULT_PATH
var inventory: InventoryModel
var session: BattleSession
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

func _ready() -> void:
	_install_actions()
	_build_theme()
	_build_ui()
	session = BattleSession.new()
	add_child(session)
	session.presented.connect(_refresh)
	session.event_started.connect(_on_event_started)
	session.playback_recovered.connect(func(reason: String): _notice(reason, true))
	session.playback.bind_feedback(road)
	_reset_run()

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
	var weight_axis := TextServerManager.get_primary_interface().name_to_tag("wght")
	readable_font.variation_opentype = {weight_axis: 500.0}
	theme.default_font = readable_font
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_disabled_color", "Button", Color("667b79"))
	theme.set_stylebox("normal", "Button", _style(Color("4b4135")))
	theme.set_stylebox("hover", "Button", _style(Color("66553e"), TEAL))
	theme.set_stylebox("pressed", "Button", _style(Color("796344"), GOLD))
	theme.set_stylebox("disabled", "Button", _style(Color("19272c"), Color("29393c")))
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
	layout.buttons.restart.pressed.connect(func(): restart_dialog.popup_centered())
	board.picked.connect(_activate_item)
	board.hovered.connect(_inspect)
	board.placement_requested.connect(_place)
	board.cancelled.connect(_cancel)
	board.preview_changed.connect(_preview)
	restart_dialog = ConfirmationDialog.new()
	restart_dialog.title = "첫 인도 연습"
	restart_dialog.dialog_text = "보따리와 전투를 처음 상태로 되돌릴까요?"
	restart_dialog.ok_button_text = "다시 시작"
	restart_dialog.cancel_button_text = "계속하기"
	restart_dialog.confirmed.connect(_reset_run)
	add_child(restart_dialog)

func _reset_run() -> void:
	var next_inventory := ItemCatalog.create_inventory(content_path)
	if next_inventory == null:
		_notice("콘텐츠 로드 실패: " + ItemCatalog.last_error, true)
		return
	if inventory != null and inventory.changed.is_connected(session.refresh_layout):
		inventory.changed.disconnect(session.refresh_layout)
	selected = ""
	inspected = ""
	inventory = next_inventory
	board.select("", 0)
	board.cancel_motion()
	inventory.changed.connect(session.refresh_layout)
	session.reset(inventory)
	_notice("물건의 효과를 읽고 인접 조건에 맞게 보따리를 정리하세요.")

func _refresh() -> void:
	var view := session.display_snapshot()
	if view.is_empty(): return
	# The board and labels always read the SAME event snapshot, including consumption.
	display_inventory = InventoryModel.new()
	display_inventory.definitions = inventory.definitions
	display_inventory.dimensions = Vector2i(view.config.grid_width, view.config.grid_height)
	display_inventory.config = view.config
	display_inventory.items = view.inventory_items.duplicate(true)
	display_inventory.locked = session.is_busy() or view.phase in ["battle", "defeat", "complete"]
	board.model = display_inventory
	if not display_inventory.items.has(selected):
		selected = ""
		board.select("", 0)
	board.used = view.used
	board.queue_redraw()
	road.player_visual = view.config.player_visual
	road.enemy_visual = CombatSimulator.enemy(view).visual
	road.defeated = view.phase in ["victory", "complete"]
	road.queue_redraw()
	labels.chapter.text = "길목 %02d / %02d  ·  %s" % [view.encounter + 1, view.config.encounters.size(), "전투 중 · %d턴" % view.turn if view.phase == "battle" else "인도 준비"]
	labels.enemy.text = CombatSimulator.enemy(view).name
	enemy_bar.max_value = CombatSimulator.enemy(view).hp
	enemy_bar.value = view.enemy_health
	labels.enemy_hp.text = "응어리 %d / %d  ·  방어 %d" % [view.enemy_health, CombatSimulator.enemy(view).hp, view.enemy_guard]
	var intent := CombatSimulator.intent(view)
	labels.intent.text = "다음 행동  ·  %s %d" % [EffectText.operation(intent.operation), intent.amount]
	hero_bar.max_value = view.config.max_health
	hero_bar.value = view.health
	labels.hero.text = "체력 %d / %d   ·   방어 %d" % [view.health, view.config.max_health, view.guard]
	labels.energy.text = "기력 %d / %d" % [view.energy, view.config.energy_per_turn]
	labels.log.text = "\n".join(view.messages.slice(maxi(0, view.messages.size() - 2)))
	labels.bag.text = "보따리   %d / %d" % [display_inventory.used_cells(), display_inventory.dimensions.x * display_inventory.dimensions.y]
	labels.passive.text = "공격 합계 %d   ·   턴 종료 방어 +%d" % [InventoryRules.totals(view.packed_items, "use", "enemy").damage, display_inventory.passive_guard()]
	match view.phase:
		"packing": primary.text = "전투 시작"
		"battle": primary.text = "턴 종료"
		"victory": primary.text = "인도 마치기" if view.encounter == view.config.encounters.size() - 1 else "다음 길목 준비"
		"defeat": primary.text = "귀환 · 다시 시작"
		"complete": primary.text = "다시 연습하기"
	if view.phase == "complete":
		labels.chapter.text = "첫 인도 연습 완료"
		labels.intent.text = "무사히 길을 열었습니다."
	elif view.phase == "defeat":
		labels.chapter.text = "선배와 함께 귀환"
		labels.intent.text = "보따리를 바꿔 다시 도전하세요."
	elif view.phase == "victory":
		labels.intent.text = "길이 열렸습니다 · 보따리를 정리하세요"
	layout.preparation.visible = view.phase in ["packing", "victory"]
	labels.help.text = "물건 클릭: 사용   ·   마우스 올리기: 효과 확인   ·   우측 버튼: 턴 종료" if view.phase == "battle" else "드래그 / 선택 후 빈칸 클릭: 배치   ·   R: 회전   ·   Ctrl+Z: 되돌리기   ·   Esc / 우클릭: 취소"
	_rebuild_stash()
	_refresh_details()
	undo_button.disabled = session.is_busy() or inventory.locked or inventory.history.is_empty()
	primary.disabled = session.is_busy()
	skip_button.disabled = not session.is_busy()
	skip_button.visible = session.is_busy()
	if session.is_busy(): primary.text = "연출 재생 중…"

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
	if session.is_busy() or display_inventory.locked: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select(uid)
		board.begin_external_drag(uid, slot.get_global_transform_with_canvas() * event.position)

func _inspect(uid: String) -> void:
	var next := uid if not uid.is_empty() else selected
	if inspected != next: layout.detail_scroll.scroll_vertical = 0
	inspected = next
	_refresh_details()

func _refresh_details() -> void:
	rotate_button.disabled = selected.is_empty() or display_inventory.locked
	stash_button.disabled = selected.is_empty() or display_inventory.locked or not display_inventory.is_packed(selected)
	layout.details.visible = not inspected.is_empty() and display_inventory.items.has(inspected)
	if not layout.details.visible: return
	var item := display_inventory.definition(inspected)
	labels.item_name.text = item.display_name
	labels.item_meta.text = "%d칸  ·  %s" % [item.footprint.size(), "보따리 안" if display_inventory.is_packed(inspected) else "보관대"]
	labels.description.text = item.description
	labels.item_meta.text += " · 기력 %d · 턴당 %d회" % [item.cost, item.uses_per_turn]
	var values := ItemCodec.item(item, display_inventory.occupied_cells(inspected))
	var packed := display_inventory.combat_snapshot()
	if not packed.has(inspected): packed = {inspected: values}
	labels.power.text = " · ".join(EffectText.lines(values, packed, inspected, display_inventory.config.tag_labels))
	var result := InventoryRules.action_result(packed, inspected)
	labels.sources.text = " · ".join(result.sources)
	labels.item_hint.text = "자동 효과"
	if EffectApplier.has_trigger(values, "use"):
		var error := session.use_error(inspected)
		labels.item_hint.text = error if not error.is_empty() else "클릭하여 사용"
	if not display_inventory.locked: labels.item_hint.text = "드래그하여 배치 · R로 회전"

func _activate_item(uid: String) -> void:
	if session.is_busy(): return
	_select(uid)
	if session.display_snapshot().phase == "battle":
		_submit({"type": "use_item", "uid": uid})

func _select(uid: String) -> void:
	if session.is_busy(): return
	if not display_inventory.items.has(uid):
		return
	selected = uid
	inspected = uid
	layout.detail_scroll.scroll_vertical = 0
	board.select(uid, display_inventory.items[uid].rotation)
	_refresh_details()
	_notice("%s 선택 · %s" % [display_inventory.definition(uid).display_name, "클릭하면 바로 사용합니다." if display_inventory.locked else "드래그하거나 빈칸을 클릭하세요. R로 회전합니다."])

func _place(uid: String, origin: Vector2i, rotation: int) -> void:
	if session.is_busy(): return
	var error := inventory.placement_error(uid, origin, rotation)
	if not error.is_empty():
		_notice(error + " 원래 배치는 유지됩니다.", true)
		return
	inventory.place(uid, origin, rotation)
	board.select(uid, rotation)
	_notice("%s 배치 완료 · Ctrl+Z로 되돌릴 수 있습니다." % inventory.definition(uid).display_name)

func _preview(origin: Vector2i) -> void:
	if session.is_busy(): return
	if selected.is_empty() or inventory.locked:
		return
	var error := inventory.placement_error(selected, origin, board.pending_rotation)
	if error.is_empty():
		var preview := inventory.preview(selected, origin, board.pending_rotation)
		var changes: PackedStringArray = []
		var before := inventory.combat_snapshot()
		for uid: String in preview.snapshot:
			var old := InventoryRules.action_result(before, uid)
			var next := InventoryRules.action_result(preview.snapshot, uid)
			if old.effects != next.effects:
				for i in next.effects.size():
					var previous: int = old.effects[i].amount if i < old.effects.size() else 0
					var effect: Dictionary = next.effects[i]
					if previous != effect.amount:
						changes.append("%s %s %d → %d" % [inventory.definition(uid).display_name, EffectText.operation(effect.kind), previous, effect.amount])
		changes.append("턴 종료 방어 %d → %d" % [inventory.passive_guard(), preview.guard])
		_notice("배치 예상: " + " · ".join(changes))
	else:
		_notice(error, true)

func _rotate() -> void:
	if session.is_busy(): return
	if selected.is_empty() or inventory.locked:
		return
	board.pending_rotation = posmod(board.pending_rotation + 1, 4)
	board.grab_offset = Vector2i.ZERO
	board.queue_redraw()
	_notice("%d° 회전 미리보기 · 빈칸을 클릭해 확정하세요. Esc로 취소합니다." % (board.pending_rotation * 90))

func _cancel() -> void:
	if session.is_busy(): return
	board.cancel_motion()
	selected = ""
	inspected = ""
	board.select("", 0)
	_refresh_details()
	_notice("선택을 취소했습니다. 확정된 배치는 유지됩니다.")

func _stash_selected() -> void:
	if session.is_busy(): return
	if inventory.move_to_stash(selected):
		_notice("보관대로 옮겼습니다. 빈칸을 클릭해 다시 배치하세요.")

func _undo() -> void:
	if session.is_busy(): return
	if inventory.undo():
		if inventory.items.has(selected):
			board.select(selected, inventory.items[selected].rotation)
		_notice("이전 배치로 되돌렸습니다.")

func _primary_action() -> void:
	if session.is_busy(): return
	board.cancel_motion()
	match session.display_snapshot().phase:
		"packing": _submit({"type": "start"})
		"battle": _submit({"type": "end_turn"})
		"victory": _submit({"type": "advance"})
		_: _reset_run()

func _submit(request: Dictionary) -> void:
	var error := session.submit(request)
	if not error.is_empty(): _notice(error, true)
	else: _notice("행동 결과를 순서대로 재생합니다.")

func _on_event_started(event: Dictionary) -> void:
	_notice(event.message)

func _notice(message: String, error := false) -> void:
	labels.notice.text = message
	labels.notice.add_theme_color_override("font_color", Color("e9997b") if error else MUTED)

func _unhandled_key_input(event: InputEvent) -> void:
	if restart_dialog.visible or session.is_busy():
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
