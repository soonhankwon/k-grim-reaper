class_name EffectUnit
extends Resource
## A declarative instruction, never a script/Callable or item-specific behavior.

@export var id: StringName
@export var trigger: String = "use"
@export var operation: String = "damage"
@export var target: String = "opponent"
@export var amount: int = 0
@export var required_tags: PackedStringArray = []
@export var condition_tags: PackedStringArray = []
@export var scale: String = "flat"
@export var max_matches: int = 1
@export var affects: String = ""
@export var stack_group: String = ""
@export var max_per_action: int = 1
@export var priority: int = 0
