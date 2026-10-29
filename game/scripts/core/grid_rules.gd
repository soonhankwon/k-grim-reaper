class_name GridRules
extends RefCounted

static func cells(footprint: Array[Vector2i], rotation := 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var minimum := Vector2i(2147483647, 2147483647)
	for point in footprint:
		var rotated := point
		for step in posmod(rotation, 4): rotated = Vector2i(-rotated.y, rotated.x)
		minimum = minimum.min(rotated)
		result.append(rotated)
	for index in result.size(): result[index] -= minimum
	return result

static func adjacent(first: Dictionary, second: Dictionary) -> bool:
	return in_range(first, second, "orthogonal")

static func in_range(first: Dictionary, second: Dictionary, mode: String) -> bool:
	for a: Vector2i in first.cells:
		for b: Vector2i in second.cells:
			var dx := absi(a.x - b.x)
			var dy := absi(a.y - b.y)
			var orthogonal := dx + dy == 1
			var diagonal := dx == 1 and dy == 1
			if (mode == "orthogonal" and orthogonal) or (mode == "diagonal" and diagonal) or (mode == "neighbor" and (orthogonal or diagonal)): return true
	return false
