class_name RenamedModel extends RefCounted

# Was called "name" and then "title" in older versions.
var display_name: String = "default"
var level: int = 1


func _forge_renamed_properties() -> Dictionary:
	return {"name": "display_name", "title": "display_name"}
