## A plain class whose hooks return the wrong type on purpose (a mistake a developer can make).
class_name BrokenHookDto extends RefCounted

var value: float = 5.0
var broken_hook: String = ""


func _forge_plain_json() -> bool:
	return true


func _forge_excluded_properties() -> Variant:
	if broken_hook == "excluded":
		return "value"
	return []


func _forge_renamed_properties() -> Variant:
	if broken_hook == "renamed":
		return "value"
	return {}


func _forge_json_keys() -> Variant:
	if broken_hook == "keys":
		return "value"
	return {}
