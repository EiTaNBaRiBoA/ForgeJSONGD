class_name InnerOwner extends RefCounted

# A class declared inside another script has no name or path of its own.
class Item:
	extends RefCounted
	var label: String = ""
	var amount: int = 0


class SpecialItem:
	extends Item
	var bonus: int = 0


var item: Item
var items: Array[Item] = []
var by_name: Dictionary[String, Item] = {}
