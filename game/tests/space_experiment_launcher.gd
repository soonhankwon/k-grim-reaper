extends SceneTree
## Starts a test fixture without opening or writing the player's save slot.

const Experiment = preload("res://tests/space_experiment_setup.gd")

func _initialize() -> void:
	call_deferred("_launch")

func _launch() -> void:
	var main := Experiment.create(root)
	if main.inventory == null:
		push_error("공간 실험 콘텐츠를 열지 못했습니다.")
		quit(1)
