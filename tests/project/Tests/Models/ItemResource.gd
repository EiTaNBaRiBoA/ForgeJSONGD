class_name ItemResource extends Resource

@export var item_name: String = ""


# A save should point at the item file, not hold a copy of it.
func _forge_save_by_path() -> bool:
	return true
