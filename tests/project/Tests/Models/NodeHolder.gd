## A node with a child node it creates and keeps in a variable.
class_name NodeHolder extends Node

var sprite: SpriteState = SpriteState.new()
var label: String = ""


func _init() -> void:
	add_child(sprite)
