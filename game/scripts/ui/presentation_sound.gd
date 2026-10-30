class_name PresentationSound
extends Node
## Original short synthetic cues. The presentation layer owns all audio.
const CUES := {
	"hit": preload("res://assets/audio/ink-hit-v1.wav"),
	"stamp": preload("res://assets/audio/seal-drum-v1.wav"),
	"wind": preload("res://assets/audio/bamboo-wind-v1.wav"),
	"snap": preload("res://assets/audio/item-snap-v1.wav"),
	"guard": preload("res://assets/audio/guard-chime-v1.wav")
}
var enabled := true
var player: AudioStreamPlayer

func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.volume_db = -9.0
	add_child(player)

func cue(id: String) -> void:
	if not enabled or not CUES.has(id) or player == null: return
	player.stream = CUES[id]
	# Headless runs have no audible output; still select the cue for validation.
	if DisplayServer.get_name() != "headless": player.play()

func set_enabled(value: bool) -> void:
	enabled = value
	if not enabled and player != null: player.stop()

func stop() -> void:
	if player != null: player.stop()

func _exit_tree() -> void:
	if player != null:
		player.stop()
		player.stream = null
