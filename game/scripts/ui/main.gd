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
var reward_inspected := ""
var _reward_selection := ""
var _event_selection := ""
var _save_blocked := false
var recovery_dialog: ConfirmationDialog
var guide_enabled := true
var guide_forced := false
var story_forced := false
var story_entries: Array[Dictionary] = []

func _ready() -> void:
	_install_actions()
	_build_theme()
	_build_ui()
	story_entries = StoryBook.load_entries(story_path)
	session = BattleSession.new()
	add_child(session)
	session.presented.connect(_refresh)
	session.event_presented.connect(_on_event_presented)
	session.playback_recovered.connect(func(reason: String): _notice(reason, true))
	session.playback.bind_feedback(road)
	if save_enabled: session.save_service = SaveService.new(save_path)
	_open_run()

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
	restart_dialog.title = "첫 인도 연습"
	restart_dialog.dialog_text = "보따리와 전투를 처음 상태로 되돌릴까요?"
	restart_dialog.ok_button_text = "다시 시작"
	restart_dialog.cancel_button_text = "계속하기"
	restart_dialog.confirmed.connect(_reset_run)
	add_child(restart_dialog)

func _open_run() -> void:
	var next_inventory := ItemCatalog.create_inventory(content_path)
	if next_inventory == null:
		_notice("콘텐츠 로드 실패: " + ItemCatalog.last_error, true)
		return
	if session.save_service == null:
		_install_run(next_inventory)
		_notice("물건의 효과를 읽고 인접 조건에 맞게 보따리를 정리하세요.")
		return
	var loaded := session.save_service.load_slot(next_inventory)
	if loaded.status == "ok":
		next_inventory.items = loaded.items
		next_inventory.history = loaded.history
		_install_run(next_inventory, loaded.state)
		if loaded.get("recovered", false):
			_notice("이전 정상 저장을 불러왔습니다. 최근 행동이 누락될 수 있습니다.", true)
			var recovered := AcceptDialog.new()
			recovered.title = "이전 저장에서 복구"
			recovered.dialog_text = "현재 저장을 읽을 수 없어 이전 정상 저장을 불러왔습니다. 최근 행동이 누락될 수 있으니 진행 상태를 확인해 주세요. 손상된 원본은 다음 저장 시 별도로 보관합니다."
			add_child(recovered)
			recovered.popup_centered()
		else: _notice("이전 저장을 새 경로 구조로 복원했습니다." if loaded.get("migrated", false) else "마지막으로 확정된 상태를 이어갑니다.")
	elif loaded.status == "missing":
		var error := session.prepare_new(next_inventory)
		_install_run(next_inventory)
		_notice("저장 준비 실패: " + error if not error.is_empty() else "물건의 효과를 읽고 보따리를 정리하세요.", not error.is_empty())
	else:
		_save_blocked = true
		_install_run(next_inventory)
		_notice("이어하기 불가 · " + str(loaded.error), true)
		if session.save_service.can_archive():
			recovery_dialog = ConfirmationDialog.new()
			recovery_dialog.title = "저장 파일 확인 필요"
			recovery_dialog.dialog_text = str(loaded.error) + "\n\n기존 저장과 이전 정상본을 보관하고 새로 시작할까요? 기존 진행을 바로 이어갈 수는 없습니다."
			recovery_dialog.ok_button_text = "보관하고 새로 시작"
			recovery_dialog.cancel_button_text = "닫기"
			recovery_dialog.confirmed.connect(_archive_new_run)
			add_child(recovery_dialog)
			recovery_dialog.popup_centered()
		else:
			var alert := AcceptDialog.new()
			alert.title = "저장 파일 확인 필요"
			alert.dialog_text = str(loaded.error) + "\n\n기존 파일을 보존하기 위해 진행을 잠갔습니다. 게임을 종료한 뒤 저장 폴더를 확인하세요:\n" + session.save_service.path.get_base_dir()
			add_child(alert)
			alert.popup_centered()

func _show_restart() -> void:
	if _save_blocked:
		if recovery_dialog != null: recovery_dialog.popup_centered()
	else: restart_dialog.popup_centered()

func _archive_new_run() -> void:
	if not _save_blocked: return
	var next_inventory := ItemCatalog.create_inventory(content_path)
	if next_inventory == null:
		_notice("콘텐츠 로드 실패: " + ItemCatalog.last_error, true)
		return
	var error := session.prepare_archived_new(next_inventory)
	if not error.is_empty():
		_refresh()
		_notice("기존 저장 보관 실패: " + error, true)
		return
	_save_blocked = false
	_install_run(next_inventory)
	_notice("기존 저장을 보관하고 새 인도를 시작합니다.")

func _reset_run() -> void:
	if _save_blocked: return
	var next_inventory := ItemCatalog.create_inventory(content_path)
	if next_inventory == null:
		_notice("콘텐츠 로드 실패: " + ItemCatalog.last_error, true)
		return
	var error := session.prepare_new(next_inventory)
	if not error.is_empty():
		_notice("저장 실패 · 현재 진행을 유지합니다: " + error, true)
		return
	_install_run(next_inventory)
	_notice("물건의 효과를 읽고 인접 조건에 맞게 보따리를 정리하세요.")

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
	board.model = display_inventory
	board.presentation_busy = session.is_busy()
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
	var background := PresentationArt.background_for_actor(str(road.enemy_visual.get("presentation_id", "")))
	if layout.background_texture != background:
		layout.background_texture = background
		layout.queue_redraw()
	road.defeated = view.phase in ["reward", "victory", "route", "complete"]
	road.queue_redraw()
	labels.chapter.text = "길목 %02d / %02d  ·  %s" % [RouteRules.step(view) + 1, view.config.encounters.size(), "전투 중 · %d턴" % view.turn if view.phase == "battle" else "인도 준비"]
	var resolution: Dictionary = EventRules.resolution(view)
	var scenario: Array = view.config.get("resolutions", [])
	if not scenario.is_empty():
		var total: int = int(view.config.events[0].step) + 2
		labels.chapter.text = "길목 %02d / %02d  ·  %s" % [mini(RouteRules.step(view) + 1, total), total, "전투 중 · %d턴" % view.turn if view.phase == "battle" else "인도 준비"]
	labels.enemy.text = CombatSimulator.enemy(view).name
	enemy_bar.max_value = CombatSimulator.enemy(view).hp
	enemy_bar.value = view.enemy_health
	labels.enemy_hp.text = "응어리 %d / %d  ·  방어 %d" % [view.enemy_health, CombatSimulator.enemy(view).hp, view.enemy_guard]
	var intent := CombatSimulator.intent(view)
	labels.intent.text = "다음 행동  ·  %s %d" % [EffectText.operation(intent.operation), intent.amount]
	_refresh_turn_preview(view)
	hero_bar.max_value = view.config.max_health
	hero_bar.value = view.health
	labels.hero.text = "체력 %d / %d   ·   방어 %d" % [view.health, view.config.max_health, view.guard]
	labels.energy.text = "기력 %d / %d" % [view.energy, view.config.energy_per_turn]
	labels.log.text = "\n".join(view.messages.slice(maxi(0, view.messages.size() - 2)))
	var story_unlocked := StoryBook.unlocked(view, story_entries)
	var teaser: Button = layout.buttons.story_teaser
	teaser.visible = not _save_blocked and not session.is_busy() and view.phase in ["packing", "victory", "complete"] and not story_unlocked.is_empty()
	if teaser.visible:
		var latest: Dictionary = story_unlocked.back()
		teaser.text = "사연 · %s  ›\n%s" % [latest.title, latest.teaser]
	layout.buttons.story.disabled = _save_blocked or story_unlocked.is_empty()
	layout.buttons.story.text = "사연 %d" % story_unlocked.size() if not story_unlocked.is_empty() else "사연"
	labels.bag.text = "보따리   %d / %d" % [display_inventory.used_cells(), display_inventory.dimensions.x * display_inventory.dimensions.y]
	var attack_totals := InventoryRules.totals(view.packed_items, "use", "enemy")
	var guard_totals := InventoryRules.totals(view.packed_items, "turn_end")
	labels.passive.text = "효과 수치를 계산할 수 없습니다" if not attack_totals.error.is_empty() or not guard_totals.error.is_empty() else "공격 합계 %d   ·   턴 종료 방어 +%d" % [attack_totals.damage, guard_totals.guard]
	match view.phase:
		"packing": primary.text = "전투 시작"
		"battle": primary.text = "턴 종료"
		"reward": primary.text = "보상 확정" if display_inventory.is_packed(reward.uid) else "보따리에 보상을 넣으세요"
		"route": primary.text = "아래에서 길을 선택하세요"
		"event": primary.text = "유품 챙기기 확정" if view.event.selected == "take" and (display_inventory.is_packed(view.event.uid) or resolution.get("allow_stash", false)) else "유품을 보따리에 넣으세요"
		"event_result": primary.text = "사건 마치기"
		"victory": primary.text = "인도 마치기" if RouteRules.last(view) else ("길가로 이동" if not EventRules.due(view).is_empty() else ("갈림길로 이동" if RouteRules.enabled(view) and view.route.choice.is_empty() else "다음 길목 준비"))
		"defeat": primary.text = "귀환 · 다시 시작"
		"complete": primary.text = "다시 연습하기"
	if view.phase == "complete":
		labels.chapter.text = str(scenario[0].completion_title) if not scenario.is_empty() else "첫 인도 연습 완료"
		labels.intent.text = "무사히 길을 열었습니다."
	elif view.phase == "defeat":
		labels.chapter.text = "선배와 함께 귀환"
		labels.intent.text = "보따리를 바꿔 다시 도전하세요."
	elif view.phase == "victory":
		labels.intent.text = "길이 열렸습니다 · 보따리를 정리하세요"
	elif view.phase == "reward":
		labels.chapter.text = "길목 %02d 완료 · 보상과 재정비" % (RouteRules.step(view) + 1)
	elif view.phase == "route":
		labels.chapter.text = "첫 길목 완료 · 갈림길"
	elif view.phase in ["event", "event_result"]:
		labels.chapter.text = "인도 중 만난 사연"
	layout.preparation.visible = view.phase in ["packing", "reward", "victory", "event"]
	layout.rewards.refresh(view, display_inventory.definitions, session.is_busy())
	layout.routes.refresh(view, session.is_busy())
	layout.encounter_event.refresh(view, session.is_busy())
	layout.buttons.reward_skip.visible = view.phase == "reward" and not session.is_busy()
	layout.buttons.reward_skip.disabled = _save_blocked or session.is_busy()
	layout.buttons.restart.disabled = _save_blocked and (session.save_service == null or not session.save_service.can_archive())
	layout.buttons.restart.text = "저장 복구" if _save_blocked else "다시 시작"
	for key in ["enemy", "enemy_hp", "hero", "hero_name", "energy", "intent", "log"]:
		labels[key].visible = view.phase not in ["reward", "route", "event", "event_result"]
	if layout.buttons.story_teaser.visible: labels.log.hide()
	hero_bar.visible = view.phase not in ["reward", "route", "event", "event_result"]
	enemy_bar.visible = view.phase not in ["reward", "route", "event", "event_result"]
	labels.notice.position = Vector2(320, 446) if view.phase in ["reward", "route", "event", "event_result"] else Vector2(360, 452)
	labels.notice.size = Vector2(620, 38) if view.phase in ["reward", "route", "event", "event_result"] else Vector2(385, 48)
	labels.help.text = "물건 클릭: 사용   ·   마우스 올리기: 효과 확인   ·   우측 버튼: 턴 종료" if view.phase == "battle" else "드래그 / 선택 후 빈칸 클릭: 배치   ·   R: 회전   ·   Ctrl+Z: 되돌리기   ·   Esc / 우클릭: 취소"
	if view.phase == "reward": labels.help.text = "확정 전 후보 변경 가능 · 선택한 보상은 보관대에 표시 · 기존 물건은 꺼내기로 공간 확보 · Ctrl+Z: 배치 되돌리기"
	if view.phase == "event": labels.help.text = "유품은 보관대에 두고 확정할 수 있습니다. 후속 선택을 위해서는 다음 전투 전 보따리에 넣으세요." if resolution.get("allow_stash", false) else "유품을 선택하면 보관대에 나타납니다. 보따리에 넣고 확정하거나 그 자리에 두세요."
	if view.phase == "event_result": labels.help.text = "이번 선택의 결과를 확인하고 사건 마치기를 누르세요."
	if view.phase == "route": labels.help.text = "각 경로의 첫 적과 이후 순서를 확인하고 선택하세요. 선택한 길은 자동 저장됩니다."
	if _save_blocked:
		labels.help.text = "저장 복구 버튼에서 기존 파일을 보관하고 새로 시작할 수 있습니다." if session.save_service != null and session.save_service.can_archive() else "저장 파일을 보호하기 위해 진행이 잠겼습니다. 게임을 종료한 뒤 저장 폴더를 확인하세요."
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
	resolution_button.text = str(resolution.get("button", "")) if eligible else "증거를 보따리에 넣어야 합니다"
	resolution_button.tooltip_text = str(resolution.get("button", "")) if eligible else str(resolution.get("unavailable", ""))
	skip_button.disabled = not session.is_busy()
	skip_button.visible = session.is_busy()
	if session.is_busy(): primary.text = "연출 재생 중…"

func _refresh_turn_preview(view: Dictionary) -> void:
	layout.turn_preview.visible = view.phase == "battle" and not session.is_busy() and not _save_blocked
	if not layout.turn_preview.visible: return
	var result := session.preview_end_turn()
	if not result.error.is_empty():
		labels.preview_summary.text = "결과를 예측할 수 없습니다"
		labels.preview_body.text = result.error
		return
	var after := result.after()
	var damage := 0
	var victory := false
	var lines: Array[String] = []
	for event: Dictionary in result.events():
		if event.kind == "turn_started": continue
		if event.kind == "damage" and event.target == "player": damage += int(event.health_damage)
		if event.kind == "victory": victory = true
		var target := ""
		if event.get("target", "") == "player": target = "나 · "
		elif event.get("target", "") == "enemy": target = "적 · "
		lines.append(target + str(event.message))
	var outcome := " · 패배" if after.phase == "defeat" else (" · 승리" if victory else "")
	labels.preview_summary.text = "예상 피해 %d · 종료 체력 %d%s" % [damage, after.health, outcome]
	labels.preview_body.text = "\n".join(lines) if not lines.is_empty() else "추가 효과 없음"

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
	layout.story.refresh(StoryBook.unlocked(session.display_snapshot(), story_entries))
	layout.guide.refresh(session.display_snapshot(), session.is_busy(), _save_blocked)
	_refresh_synergy_info()
	if not layout.details.visible: return
	var item: ItemData = display_inventory.definitions[reward_inspected] if candidate else display_inventory.definition(inspected)
	var detail_uid := "candidate" if candidate else inspected
	labels.item_name.text = item.display_name
	labels.item_meta.text = "%d칸  ·  %s" % [item.footprint.size(), "보따리 안" if display_inventory.is_packed(inspected) else "보관대"]
	if candidate: labels.item_meta.text = "%d칸 · 보상 후보 (인접 효과 미적용)" % item.footprint.size()
	labels.description.text = item.description
	labels.item_meta.text += " · 기력 %d · 턴당 %d회" % [item.cost, item.uses_per_turn]
	var detail_cells: Array[Vector2i] = []
	if not candidate: detail_cells = display_inventory.occupied_cells(inspected)
	var values := ItemCodec.item(item, detail_cells)
	var packed := display_inventory.combat_snapshot()
	var synergy := board.synergy_view()
	if not candidate and inspected == selected and synergy.mode == "preview" and synergy.items.has(detail_uid):
		packed = synergy.items
		values = packed[detail_uid]
		labels.item_meta.text += "\n배치 예상"
	if candidate or not packed.has(detail_uid): packed = {detail_uid: values}
	labels.power.text = " · ".join(EffectText.lines(values, packed, detail_uid, display_inventory.config.tag_labels))
	var result := InventoryRules.action_result(packed, detail_uid)
	labels.sources.text = " · ".join(result.sources)
	labels.item_hint.text = "자동 효과"
	if EffectApplier.has_trigger(values, "use"):
		var error := session.use_error(inspected)
		labels.item_hint.text = error if not error.is_empty() else "클릭하여 사용"
	if not display_inventory.locked: labels.item_hint.text = "드래그하여 배치 · R로 회전"
	if candidate: labels.item_hint.text = "아래 후보를 클릭해 선택한 뒤 보따리에 놓으세요."

func _on_synergy_changed() -> void:
	if display_inventory == null or session == null: return
	_refresh_details()

func _refresh_synergy_info() -> void:
	var view := board.synergy_view()
	var text := ""
	match view.mode:
		"current": text = "현재 연결 · +증가  ×배율  ○조건"
		"preview": text = "배치 예상 · 점선  +증가  ×배율  ○조건"
		"invalid": text = "배치 불가 · 연결 미표시"
		"error": text = "연결 계산 불가"
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
		var when: String = {"use":"사용", "turn_end":"턴 종료", "damage_taken":"피해 반응"}[link.trigger]
		var range_name: String = {"orthogonal":"상하좌우", "diagonal":"대각선", "neighbor":"주변 8칸"}.get(link.range, "자기 자신" if link.source == link.target else "범위")
		var value := "조건 · 최대 %d개" % link.limit if link.kind == "condition" else ("%s ×%d" % [EffectText.operation(link.operation), link.amount] if link.kind == "multiply" else "%s +%d" % [EffectText.operation(link.operation), link.amount])
		lines.append("%s → %s · %s · %s · %s" % [source, target, range_name, when, value])
	var title := "배치 예상 연결" if view.mode == "preview" else "현재 연결"
	labels.connections.text = title + ("\n" + "\n".join(lines) if not lines.is_empty() else " · 없음")

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
	_notice("%s 선택 · %s" % [display_inventory.definition(uid).display_name, "클릭하면 바로 사용합니다." if display_inventory.locked else "드래그하거나 빈칸을 클릭하세요. R로 회전합니다."])

func _place(uid: String, origin: Vector2i, rotation: int) -> void:
	if _save_blocked or session.is_busy(): return
	var error := session.place(uid, origin, rotation)
	if not error.is_empty():
		_notice(error + " 원래 배치는 유지됩니다.", true)
		return
	board.select(uid, rotation)
	_notice("%s 배치 완료 · Ctrl+Z로 되돌릴 수 있습니다." % inventory.definition(uid).display_name)

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
		var current_guard := InventoryRules.totals(before, "turn_end")
		for uid: String in preview.snapshot:
			var old := InventoryRules.action_result(before, uid)
			var next := InventoryRules.action_result(preview.snapshot, uid)
			if not old.error.is_empty():
				changes.append("%s 계산 불가 → %d" % [inventory.definition(uid).display_name, next.power])
				continue
			if old.effects != next.effects:
				for i in next.effects.size():
					var previous: int = old.effects[i].amount if i < old.effects.size() else 0
					var effect: Dictionary = next.effects[i]
					if previous != effect.amount:
						changes.append("%s %s %d → %d" % [inventory.definition(uid).display_name, EffectText.operation(effect.kind), previous, effect.amount])
		changes.append("턴 종료 방어 계산 불가 → %d" % preview.guard if not current_guard.error.is_empty() else "턴 종료 방어 %d → %d" % [current_guard.guard, preview.guard])
		_notice("배치 예상: " + " · ".join(changes))
	else:
		_notice(error, true)

func _rotate() -> void:
	if _save_blocked or session.is_busy(): return
	if selected.is_empty() or inventory.locked:
		return
	board.pending_rotation = posmod(board.pending_rotation + 1, 4)
	board.grab_offset = Vector2i.ZERO
	board.synergy_changed.emit()
	board.queue_redraw()
	_notice("%d° 회전 미리보기 · 빈칸을 클릭해 확정하세요. Esc로 취소합니다." % (board.pending_rotation * 90))

func _cancel() -> void:
	if _save_blocked or session.is_busy(): return
	board.cancel_motion()
	selected = ""
	inspected = ""
	reward_inspected = ""
	board.select("", 0)
	_refresh_details()
	_notice("선택을 취소했습니다. 확정된 배치는 유지됩니다.")

func _stash_selected() -> void:
	if _save_blocked or session.is_busy(): return
	var error := session.stash(selected)
	if error.is_empty(): _notice("보관대로 옮겼습니다. 빈칸을 클릭해 다시 배치하세요.")
	else: _notice(error, true)

func _undo() -> void:
	if _save_blocked or session.is_busy(): return
	var error := session.undo_layout()
	if error.is_empty():
		if inventory.items.has(selected):
			board.select(selected, inventory.items[selected].rotation)
		_notice("이전 배치로 되돌렸습니다.")
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
	else: _notice("행동 결과를 순서대로 재생합니다.")

func _on_event_presented(event: Dictionary) -> void:
	_notice(event.message)

func _notice(message: String, error := false) -> void:
	labels.notice.text = message
	labels.notice.add_theme_color_override("font_color", Color("e9997b") if error else MUTED)

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
