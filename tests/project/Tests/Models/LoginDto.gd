class_name LoginDto extends RefCounted

var user_name: String = ""
var password: String = ""
var remember: bool = false
var attempts: int = 0


func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName"}


# This class talks to a web API: it is written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
