class_name PolymorphicSave extends Resource

## Holders of a base type that contain child instances in different container kinds.
@export var single: MySuperClass
@export var typed_items: Array[MySuperClass]
@export var untyped_items: Array
@export var typed_dict: Dictionary[String, MySuperClass]
@export var untyped_dict: Dictionary
@export var nested: Save
