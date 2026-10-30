extends SceneTree

var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _submit(main: Control, command: Dictionary) -> bool:
	var error: String = main.session.submit(command)
	if error.is_empty(): main.session.skip_playback()
	return error.is_empty()

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, false)

func _wheel(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, false)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_WHEEL_DOWN
		event.pressed = pressed
		event.position = point
		event.global_position = point
		root.push_input(event, false)

func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	var state: Dictionary = main.session.display_snapshot()
	state.phase = "battle"
	state.enemy_health = 1
	main.session.reset(main.inventory, state)
	check(_submit(main, {"type":"use_item", "uid":"sword"}), "win the first encounter")
	check(_submit(main, {"type":"reward_skip", "offer_id":main.session.display_snapshot().reward.offer_id}) and _submit(main, {"type":"advance"}), "reach the event")
	check(_submit(main, {"type":"event_leave", "event_id":main.session.display_snapshot().event.id}), "reach the route choice")
	await process_frame
	await process_frame
	var before: Dictionary = main.session.display_snapshot()
	var choices: Array[Button] = main.layout.routes.choices
	check(choices.size() == 2 and choices[0] is RouteCard and choices[1] is RouteCard, "both paths use visual cards")
	if choices.size() != 2:
		quit(1)
		return
	var first: RouteCard = choices[0]
	var second: RouteCard = choices[1]
	check(first.motif == "bamboo" and second.motif == "pond", "authored route art distinguishes bamboo and pond")
	check(first.hp_label.text == "HP 30" and first.intent_label.text == "Set Block 6", "first card exposes the exact health and defense intent")
	check(second.hp_label.text == "HP 24" and second.intent_label.text == "Attack 6 (you)", "second card exposes the exact health, attack and target")
	check(not first.reaction_label.visible and second.reaction_label.visible and second.reaction_label.text.contains("HP hit → Attack 2 (you)") and second.reaction_label.text.contains("1/action") and second.reaction_label.text.contains("lethal: yes"), "risk reaction keeps its condition, target, limit and lethal timing")
	check(first.details_scroll.get_v_scroll_bar().max_value <= first.details_scroll.get_v_scroll_bar().page and second.details_scroll.get_v_scroll_bar().max_value <= second.details_scroll.get_v_scroll_bar().page, "current route details fit without scrolling")
	check(first.text.is_empty() and second.text.is_empty() and second.accessibility_name.contains("HP 24") and second.accessibility_name.contains("Attack 2 (you)"), "compact cards retain a complete accessible description")
	check(EffectText.intent({"operation":"damage", "amount":5, "target":"self"}).contains("(self)") and EffectText.intent({"operation":"heal", "amount":5, "target":"opponent"}).contains("(you)"), "unusual targets are disclosed")
	for size in [Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		await process_frame
		var card: RouteCard = main.layout.routes.choices[1]
		var window_point := root.get_screen_transform() * card.details_scroll.get_global_rect().get_center()
		_click(window_point)
		await process_frame
		check(main.session.state_snapshot().encounter == 2, "clicking the card contents selects the correct path at " + str(size))
		main.session.skip_playback()
		check(main.layout.intent_icon.operation == "damage" and main.labels.intent.text.contains("Attack 6 (you)"), "encounter intent icon follows the displayed snapshot")
		main.session.reset(main.inventory, before)
		await process_frame
	# Long authored reaction lists remain available through the card's scroll area.
	var long_view := before.duplicate(true)
	var route: Dictionary = long_view.config.routes[1]
	var enemy: Dictionary = long_view.config.encounters[route.encounters[1]]
	for i in 8: enemy.reactions.append(enemy.reactions[0].duplicate(true))
	main.layout.routes.refresh(long_view, false)
	await process_frame
	await process_frame
	var long_card: RouteCard = main.layout.routes.choices[1]
	check(long_card.details_scroll.get_v_scroll_bar().max_value > long_card.details_scroll.get_v_scroll_bar().page and long_card.reaction_label.text.count("HP hit") == 9, "long reaction lists remain available in a scrollable card")
	check(long_card.tooltip_text.count("HP hit") == 9, "full reaction details are also available in the tooltip")
	_wheel(root.get_screen_transform() * long_card.details_scroll.get_global_rect().get_center())
	await process_frame
	check(long_card.details_scroll.scroll_vertical > 0 and main.session.display_snapshot().phase == "route", "wheel scrolls the card without selecting the route")
	var wide_values := before.duplicate(true)
	var extra: Dictionary = wide_values.config.routes[0].duplicate(true)
	extra.id = "unmapped_route"
	wide_values.config.routes.append(extra)
	var large_enemy: Dictionary = wide_values.config.encounters[wide_values.config.routes[1].encounters[1]]
	large_enemy.hp = 1000000
	large_enemy.intents[0].amount = 100000
	main.layout.routes.refresh(wide_values, false)
	await process_frame
	await process_frame
	var narrow: RouteCard = main.layout.routes.choices[1]
	check(main.layout.routes.choices[2].motif.is_empty(), "unmapped routes use a neutral backdrop")
	check(narrow.hp_label.text == "HP 1000000" and narrow.intent_label.text == "Attack 100000 (you)", "large valid values remain exact")
	check(narrow.hp_label.get_global_rect().end.x <= narrow.details_scroll.get_global_rect().end.x and narrow.intent_label.get_global_rect().end.x <= narrow.details_scroll.get_global_rect().end.x, "stats wrap within a three-route card")
	var max_intent_view := before.duplicate(true)
	max_intent_view.phase = "packing"
	max_intent_view.encounter = 2
	max_intent_view.route = {"choice":max_intent_view.config.routes[1].id, "step":1}
	max_intent_view.enemy_health = max_intent_view.config.encounters[2].hp
	max_intent_view.config.encounters[2].intents[0].operation = "set_guard"
	max_intent_view.config.encounters[2].intents[0].target = "opponent"
	max_intent_view.config.encounters[2].intents[0].amount = 100000
	main.session.reset(main.inventory, max_intent_view)
	await process_frame
	var intent: Label = main.labels.intent
	check(intent.text.contains("Set Block 100000 (you)") and intent.get_theme_font("font").get_string_size(intent.text, HORIZONTAL_ALIGNMENT_LEFT, -1, intent.get_theme_font_size("font_size")).x <= intent.size.x, "large announced intent fits above the enemy")
	main.queue_free()
	await process_frame
	print("ROUTE CARDS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
