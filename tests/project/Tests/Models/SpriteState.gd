class_name SpriteState extends Node2D

var health: int = 10


# Besides the script variables, save where the node is.
func _forge_extra_properties() -> Array:
	return ["position", "rotation", "scale", "modulate"]
