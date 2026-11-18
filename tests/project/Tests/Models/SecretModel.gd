class_name SecretModel extends RefCounted

@export var user_name: String = ""
@export var password: String = ""
var cache: String = ""


func _forge_excluded_properties() -> Array:
	return ["password", "cache"]
