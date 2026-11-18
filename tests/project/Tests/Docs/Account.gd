class_name Account

var user_name: String
var password: String # never written to the save file
var level: int


func _forge_excluded_properties() -> Array:
	return ["password"]
