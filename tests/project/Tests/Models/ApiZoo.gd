class_name ApiZoo
extends Zoo


# The same class as Zoo, but written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
