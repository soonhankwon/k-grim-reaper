extends SceneTree
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(1280,720)
	var main := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.save_enabled = false
	root.add_child(main)
	main.sounds.set_enabled(false)
	var args := OS.get_cmdline_user_args()
	var name := "frost"
	var state: Dictionary = main.session.display_snapshot()
	if "--embers" in args:
		name = "embers"
		main.session.place("ring", Vector2i(1,1), 0)
		main.session.submit({"type":"start"})
		main.session.skip_playback()
		main.session.submit({"type":"end_turn"})
	elif "--gilded" in args:
		name = "gilded"
		state.phase = "battle"
		state.enemy_health = 1
		main.session.reset(main.inventory, state)
		main.session.submit({"type":"use_item", "uid":"sword"})
		main.session.skip_playback()
		state = main.session.display_snapshot()
		var offer: String = state.reward.offer_id
		main.session.submit({"type":"reward_select", "offer_id":offer, "item_id":state.reward.candidates[0]})
		main.session.skip_playback()
		var uid: String = main.session.display_snapshot().reward.uid
		main.session.stash("hat")
		main.session.place(uid, Vector2i(1,2), 1)
		main.session.submit({"type":"reward_confirm", "offer_id":offer})
	else:
		state.phase = "route"
		state.route = {"choice":"", "step":0}
		main.session.reset(main.inventory, state)
		main.session.submit({"type":"choose_route", "route_id":state.config.routes[0].id})
	main.session.playback.queue._process(0)
	var command: CombatEventCommand = main.session.playback.queue._current
	if command._tween != null: command._tween.pause()
	command._impact()
	main.session.playback._update_feedback_progress(0.8)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/vfx-" + name + ".png"))
	main.vfx.burst.hide()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../build/vfx-" + name + "-without.png"))
	main.session.skip_playback()
	main.queue_free()
	await process_frame
	print("VFX CAPTURE: ", name)
	quit()
