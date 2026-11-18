class_name NativeHolder extends RefCounted

# Not exported: GDScript cannot export Object, Callable or RID variables, but they are still saved by default.
var obj: Object
var callback: Callable
var id: RID
var text: String = "keep"
