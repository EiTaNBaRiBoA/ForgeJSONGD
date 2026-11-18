class_name Weapon

var damage: int
var title: String


func _init(new_damage: int, new_title: String) -> void: # no default values
	damage = new_damage
	title = new_title


func _forge_constructor_args() -> Array:
	return [damage, title]
