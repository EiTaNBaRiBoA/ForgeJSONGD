class_name ApiRenamedModel
extends RenamedModel


# The same class as RenamedModel, but written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
