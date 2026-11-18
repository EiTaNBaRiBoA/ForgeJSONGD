# zoo.gd - every variable is typed with the PARENT class Animal
class_name Zoo
extends Resource

@export var star: Animal
@export var animals: Array[Animal]
@export var by_name: Dictionary[String, Animal]
