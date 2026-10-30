extends Control
## Title screen creates the existing game only after the player continues.

var intro: LaunchIntro
var game: Control
@export var save_path := SaveService.DEFAULT_PATH
@export var save_enabled := true

func _ready() -> void:
	DisplayServer.window_set_title("Reaper's Bundle — First Delivery")
	intro = LaunchIntro.new()
	var has_save := save_enabled and (FileAccess.file_exists(save_path) or FileAccess.file_exists(save_path + ".bak"))
	intro.action_text = "Continue Delivery" if has_save else "Begin Delivery"
	intro.note = "Your saved delivery will continue." if has_save else "Your first delivery starts after you prepare your bag."
	intro.accepted.connect(_start_game)
	add_child(intro)

func _start_game() -> void:
	if game != null: return
	game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = save_enabled
	game.save_path = save_path
	add_child(game)
	intro.queue_free()
