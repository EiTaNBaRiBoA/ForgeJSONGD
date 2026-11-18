## Extends Object and creates its member objects itself (the form C# classes with "= new()" members have).
class_name ManualOwner extends Object

var title: String = ""
var child: ManualChild = ManualChild.new()
var other: ManualChild = ManualChild.new()
