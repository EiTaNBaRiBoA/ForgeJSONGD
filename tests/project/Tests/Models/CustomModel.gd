class_name CustomModel extends RefCounted

var numbers: PackedInt32Array = PackedInt32Array()


# Stores the numbers as one comma separated text.
func _forge_serialize() -> Dictionary:
	var parts: PackedStringArray = []
	for number: int in numbers:
		parts.append(str(number))
	return {"numbers": ",".join(parts)}


static func _forge_deserialize(json: Dictionary) -> Object:
	var model: CustomModel = CustomModel.new()
	for part: String in String(json.get("numbers", "")).split(",", false):
		model.numbers.append(part.to_int())
	return model
