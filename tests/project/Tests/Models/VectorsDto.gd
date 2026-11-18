class_name VectorsDto extends RefCounted

var v2: Vector2 = Vector2(1.5, 2.5)
var v2i: Vector2i = Vector2i(1, 2)
var v3: Vector3 = Vector3(1, 2, 3)
var v3i: Vector3i = Vector3i(4, 5, 6)
var v4: Vector4 = Vector4(1, 2, 3, 4)
var v4i: Vector4i = Vector4i(5, 6, 7, 8)
var rect: Rect2 = Rect2(1, 2, 3, 4)
var points: Array[Vector2] = [Vector2(1, 2), Vector2(3, 4)]
var by_name: Dictionary[String, Vector3] = {"a": Vector3(1, 2, 3)}


# This class talks to a web API: it is written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
