class_name UserDto extends RefCounted

enum Role { GUEST, ADMIN = 5 }

var id: int = 0
var user_name: String = ""
var score: float = 1.5
var tags: Array[String] = []
var address: AddressDto
var friends: Array[UserDto] = []
var meta: Dictionary = {}
var position: Vector2 = Vector2.ZERO
var color: Color = Color.WHITE
var role: Role = Role.GUEST
var big_id: int = 0
var nickname: String = "none"
var secret: String = ""


# The API calls these fields differently.
func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName", "big_id": "bigId"}


func _forge_excluded_properties() -> Array:
	return ["secret"]


# This class talks to a web API: it is written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
