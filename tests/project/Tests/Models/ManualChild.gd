## A data class that extends Object: it is not freed by Godot, the code that owns it frees it.
class_name ManualChild extends Object

var label: String = "default"
var amount: int = 1
