extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	await process_frame
	var primary: Button = main.primary
	var before: Dictionary = main.session.state_snapshot()
	for control in [main.layout.guide, main.layout.story, main.layout.routes, main.layout.encounter_event, main.layout.rewards, main.layout.details, main.layout.turn_preview]:
		var frame: StyleBox = control.get_theme_stylebox("panel")
		check(frame is StyleBoxTexture and frame.texture != null and frame.get_texture_margin(SIDE_LEFT) == 8, "panel uses a textured nine-patch")
	for state in ["normal", "hover", "pressed", "disabled"]:
		check(primary.get_theme_stylebox(state) is StyleBoxTexture, "primary action has a nine-patch " + state + " state")
	check(primary is WoodenButton and main.theme.get_font("font", "Button") == main.theme.default_font, "button feedback and labels share the pixel font")
	var queue: ActionQueue = primary._feedback
	queue.cancel()
	queue.start([ButtonFeedbackCommand.new(primary, true)])
	queue._process(0)
	check(queue.is_busy(), "hover animation starts asynchronously")
	queue.cancel()
	queue.start([ButtonFeedbackCommand.new(primary, false)])
	queue._process(0)
	await create_timer(0.3).timeout
	check(primary.scale.is_equal_approx(Vector2.ONE) and not queue.is_busy(), "rapid exit cancels the hover and restores scale")
	check(main.session.state_snapshot() == before, "button feedback does not modify gameplay")
	queue.start([ButtonFeedbackCommand.new(primary, true)])
	queue._process(0)
	primary.hide()
	check(primary.scale == Vector2.ONE and not queue.is_busy(), "hiding a button cancels its feedback")
	main.queue_free()
	await process_frame
	print("WOODCUT UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
