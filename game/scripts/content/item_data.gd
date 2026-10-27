class_name ItemData
extends Resource
## Authored data only. Placement, execution and presentation live outside this resource.

@export var id: StringName
@export var display_name: String
@export_multiline var description: String
@export var footprint: Array[Vector2i] = [Vector2i.ZERO]
@export var tags: PackedStringArray = []
@export var cost: int = 0
@export var uses_per_turn: int = 1
@export var consumable: bool = false
@export var effects: Array[EffectUnit] = []
@export var icon: Dictionary = {}
