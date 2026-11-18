class_name InstanceHookModel

var value: int = 0


func _forge_serialize() -> Dictionary:
	return {"packed_value": value * 10}


# Not static: a new instance is created first, then this fills it (this is the form C# uses).
func _forge_deserialize(json: Dictionary) -> Object:
	value = floori(json.get("packed_value", 0) / 10.0)
	return self
