class_name SavedUserDto
extends UserDto


# The same class as UserDto, but written in the exact format of a save file.
func _forge_plain_json() -> bool:
	return false
