## A class Godot does not free by itself that nests itself: a member object, an array and a dictionary of objects.
class_name ManualTree extends Object

var label: String = ""
var value: int = 0
var child: ManualTree = null
var items: Array[ManualTree] = []
var by_name: Dictionary[String, ManualTree] = {}
