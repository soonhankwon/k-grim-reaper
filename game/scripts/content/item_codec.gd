class_name ItemCodec
extends RefCounted
## Resource -> detached value snapshots at the application boundary.

const EFFECT_FIELDS := ["id", "trigger", "operation", "target", "amount", "required_tags", "condition_tags", "scale", "max_matches", "affects", "stack_group", "max_per_action", "priority"]

static func effect(unit: EffectUnit) -> Dictionary:
	var values: Dictionary = {}
	for field in EFFECT_FIELDS:
		var value: Variant = unit.get(field)
		if value is PackedStringArray: value = Array(value)
		if value is StringName: value = str(value)
		values[field] = value
	return values

static func item(data: ItemData, cells: Array[Vector2i]) -> Dictionary:
	var effects: Array[Dictionary] = []
	for unit in data.effects: effects.append(effect(unit))
	return {"definition": str(data.id), "name": data.display_name, "cells": cells.duplicate(),
		"tags": Array(data.tags), "cost": data.cost, "uses_per_turn": data.uses_per_turn,
		"consumable": data.consumable, "effects": effects}
