## A plain API class with validation rules in _forge_schema (by variable name; user_name is written as "userName").
class_name SchemaUserDto extends RefCounted

enum Role { GUEST, ADMIN }

var id: int = 0
var user_name: String = ""
var email: String = ""
var age: int = 0
var role: Role = Role.GUEST
var tags: Array[String] = []
var address: AddressDto


func _forge_plain_json() -> bool:
	return true


func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName"}


func _forge_schema() -> Dictionary:
	return {
		"required": ["id", "user_name"],
		"additionalProperties": false,
		"properties": {
			"id": {"minimum": 1},
			"user_name": {"minLength": 3, "maxLength": 20},
			"email": {"pattern": "^[^@\\s]+@[^@\\s]+$"},
			"age": {"minimum": 0, "maximum": 150},
			"tags": {"maxItems": 3, "uniqueItems": true},
			"address": {"type": "object"}, # not null: an address is required here
		},
	}
