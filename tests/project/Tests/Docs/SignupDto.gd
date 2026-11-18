# signup_dto.gd
class_name SignupDto

var user_name: String = ""
var email: String = ""
var age: int = 0
var tags: Array[String] = []
var address: AddressDto


func _forge_plain_json() -> bool:
	return true


func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName"}


# Rules the types cannot say, in JSON Schema words. Use variable names or JSON keys.
func _forge_schema() -> Dictionary:
	return {
		"required": ["user_name", "email"],
		"properties": {
			"user_name": {"minLength": 3, "maxLength": 20},
			"email": {"pattern": "^[^@\\s]+@[^@\\s]+$"},
			"age": {"minimum": 13},
			"tags": {"maxItems": 5, "uniqueItems": true},
		},
	}
