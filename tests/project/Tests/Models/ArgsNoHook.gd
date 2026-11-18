class_name ArgsNoHook extends RefCounted

# Takes a start value, but does not say it wants stored arguments (no _forge_constructor_args).
var count: int = 0


func _init(start: int = 7) -> void:
	count = start
