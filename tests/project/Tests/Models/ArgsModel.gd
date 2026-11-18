class_name ArgsModel extends RefCounted

# Required arguments: script.new() without them would fail.
var count: int
var label: String
var loaded_extra: String = "default"


func _init(new_count: int, new_label: String) -> void:
	count = new_count
	label = new_label


func _forge_constructor_args() -> Array:
	return [count, label]
