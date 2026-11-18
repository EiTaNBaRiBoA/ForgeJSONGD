## Numbers, text, dictionary keys, moved scripts and inner classes: everything must come back exactly as it was saved.
extends Node

const TMP_DIR = "user://exactness/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	test_numbers()
	test_big_numbers()
	test_text()
	test_keys()
	test_moved_scripts()
	test_inner_classes()
	test_inheritance_still_works()
	TestUtil.finish("Exactness", get_tree())


func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


func from_file(script: Script, object: Object, file_name: String) -> Object:
	ForgeJSONGD.store_json_file(TMP_DIR + file_name, ForgeJSONGD.class_to_json(object))
	return ForgeJSONGD.json_file_to_class(script, TMP_DIR + file_name)


#region Whole numbers, floats and ints in untyped places

func test_numbers() -> void:
	var model: ExactModel = ExactModel.new()
	model.list = [5, 5.0, 2.5, -3, -3.0, 0, 0.0, true, null]
	model.dict = {"int": 5, "float": 5.0, "fraction": 2.5, "zero": 0, "zero_float": 0.0, "nested": {"i": 1, "f": 1.0}}
	model.any = 7.0
	model.floats = [1.0, 2.0]
	var types: Array[int] = [TYPE_INT, TYPE_FLOAT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL]
	for loaded: ExactModel in [round_trip(ExactModel, model), from_file(ExactModel, model, "numbers.json")]:
		for i: int in types.size():
			TestUtil.check(typeof(loaded.list[i]) == types[i], "untyped array element %d keeps its type (%s)" % [i, type_string(types[i])])
		TestUtil.check(typeof(loaded.dict["int"]) == TYPE_INT and typeof(loaded.dict["float"]) == TYPE_FLOAT, "untyped dictionary keeps int and float")
		TestUtil.check(typeof(loaded.dict["zero"]) == TYPE_INT and typeof(loaded.dict["zero_float"]) == TYPE_FLOAT, "zero keeps int and float")
		TestUtil.check(typeof(loaded.dict["nested"]["i"]) == TYPE_INT and typeof(loaded.dict["nested"]["f"]) == TYPE_FLOAT, "nested dictionaries keep int and float")
		TestUtil.check(typeof(loaded.any) == TYPE_FLOAT and loaded.any == 7.0, "a Variant keeps a whole-number float")
		TestUtil.check(loaded.floats == [1.0, 2.0] and typeof(loaded.floats[0]) == TYPE_FLOAT, "Array[float] stays floats")
		TestUtil.check(loaded.dict == model.dict and loaded.list == model.list, "the whole untyped data compares equal")

	# Files from older versions wrote every number in untyped places as a float: whole numbers load as ints.
	var old_file: ExactModel = ForgeJSONGD.json_to_class(ExactModel, {"list": [4.0, 2.5], "dict": {"n": 3.0}, "any": 6.0})
	TestUtil.check(typeof(old_file.list[0]) == TYPE_INT and typeof(old_file.list[1]) == TYPE_FLOAT and typeof(old_file.dict["n"]) == TYPE_INT and typeof(old_file.any) == TYPE_INT, "whole numbers written by older versions as floats load as ints")

	var as_int: ExactModel = ExactModel.new()
	as_int.any = 7
	TestUtil.check(typeof(round_trip(ExactModel, as_int).any) == TYPE_INT, "a Variant keeps an int")

	# The file stays readable: ints are plain numbers, only whole-number floats in untyped places get a marker.
	var json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(model))
	TestUtil.check(json["list"][0] == 5.0 and json["list"][2] == 2.5, "ints and fractions are plain JSON numbers")
	TestUtil.check(json["list"][1] == {"forge_float": 5.0}, "a whole-number float in an untyped place has a marker")
	TestUtil.check(json["floats"] == [1.0, 2.0], "a typed float array has no marker")

#endregion


#region Numbers a JSON number cannot hold

func test_big_numbers() -> void:
	var model: ExactModel = ExactModel.new()
	model.big = 9007199254740993
	model.bigs = [9007199254740993, -9007199254740993, 5, 9223372036854775807, -9223372036854775807]
	model.by_name = {"max": 9223372036854775807, "small": 3}
	model.ids = PackedInt64Array([9007199254740993, 1])
	model.list = [9007199254740993, -9007199254740993, 9223372036854775807, 9007199254740992]
	model.dict = {"big": 9007199254740993}
	model.any = 9007199254740993
	for loaded: ExactModel in [round_trip(ExactModel, model), from_file(ExactModel, model, "big.json")]:
		TestUtil.check(loaded.big == 9007199254740993 and typeof(loaded.big) == TYPE_INT, "an int property above 2^53 is exact")
		TestUtil.check(loaded.bigs == model.bigs, "Array[int] with large values is exact")
		TestUtil.check(loaded.by_name == model.by_name, "Dictionary[String, int] with large values is exact")
		TestUtil.check(loaded.ids == model.ids, "PackedInt64Array with large values is exact")
		TestUtil.check(loaded.list == model.list and typeof(loaded.list[0]) == TYPE_INT, "an untyped Array with large ints is exact")
		TestUtil.check(loaded.dict["big"] == 9007199254740993 and loaded.any == 9007199254740993, "a Variant and an untyped dictionary with a large int are exact")
	# Small values are still plain numbers.
	var json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(model))
	TestUtil.check(json["bigs"][2] == 5.0, "small ints in the same array are still plain numbers")

#endregion


#region Text stays text

func test_text() -> void:
	var tricky: Array[String] = [
		"Vector2(1, 2)", "Rect2(1, 2, 3, 4)", "Color(1, 0, 0, 1)", "PackedByteArray(1, 2)", "&\"name\"", "@\"path\"",
		"123", "1.5", "true", "false", "null", "[1, 2]", "{\"a\": 1}", "forge_text:already", "forge_text:", "", " ", "plain",
		"res://icon.svg", "\\backslash", "Object(Node)",
	]
	for loaded_name: String in ["string", "file"]:
		for text: String in tricky:
			var model: ExactModel = ExactModel.new()
			model.text = text
			model.texts = [text, "x"]
			model.list = [text, 1]
			model.dict = {"value": text}
			model.any = text
			var loaded: ExactModel = round_trip(ExactModel, model) if loaded_name == "string" else from_file(ExactModel, model, "text.json")
			var shown: String = text.replace("\n", " ")
			TestUtil.check(loaded.text == text and typeof(loaded.text) == TYPE_STRING, "[%s] String variable keeps '%s'" % [loaded_name, shown])
			TestUtil.check(loaded.texts == model.texts, "[%s] Array[String] keeps '%s'" % [loaded_name, shown])
			TestUtil.check(loaded.list[0] is String and loaded.list[0] == text, "[%s] untyped Array keeps '%s'" % [loaded_name, shown])
			TestUtil.check(loaded.dict["value"] is String and loaded.dict["value"] == text, "[%s] untyped Dictionary keeps '%s'" % [loaded_name, shown])
			TestUtil.check(loaded.any is String and loaded.any == text, "[%s] Variant keeps '%s'" % [loaded_name, shown])

	# Text that stays plain in the file: only ambiguous text gets the prefix.
	var plain_model: ExactModel = ExactModel.new()
	plain_model.text = "hello"
	plain_model.list = ["world"]
	var plain_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(plain_model))
	TestUtil.check(plain_json["text"] == "hello" and plain_json["list"] == ["world"], "ordinary text is written as is")
	var escaped_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(_text_model("Vector2(1, 2)")))
	TestUtil.check(escaped_json["text"] == "forge_text:Vector2(1, 2)", "text that looks like a Godot value is written with a prefix")
	TestUtil.check(JSON.parse_string(ForgeJSONGD.class_to_json_string(_text_model("123")))["text"] == "123", "number-like text in a String variable needs no prefix")


func _text_model(text: String) -> ExactModel:
	var model: ExactModel = ExactModel.new()
	model.text = text
	return model

#endregion


#region Dictionary keys

func test_keys() -> void:
	var model: ExactModel = ExactModel.new()
	model.dict = {1: "int", "1": "text one", 1.5: "float", true: "bool", "true": "text true", "1.5": "text float", "Vector2(1, 2)": "text vector", Vector2(3, 4): "vector", -7: "negative", 9007199254740993: "big", "plain": "plain", "forge_text:1": "prefixed"}
	model.list = [{2: "nested int key", "2": "nested text key"}]
	for loaded: ExactModel in [round_trip(ExactModel, model), from_file(ExactModel, model, "keys.json")]:
		TestUtil.check(loaded.dict.size() == model.dict.size(), "no key is lost or merged (%d)" % loaded.dict.size())
		TestUtil.check(loaded.dict[1] == "int" and loaded.dict["1"] == "text one", "int key 1 and text key '1' stay different")
		TestUtil.check(loaded.dict[1.5] == "float" and loaded.dict["1.5"] == "text float", "float key and text key '1.5' stay different")
		TestUtil.check(loaded.dict[true] == "bool" and loaded.dict["true"] == "text true", "bool key and text key 'true' stay different")
		TestUtil.check(loaded.dict["Vector2(1, 2)"] == "text vector" and loaded.dict[Vector2(3, 4)] == "vector", "text key that looks like a vector and a real vector key stay different")
		TestUtil.check(loaded.dict[-7] == "negative" and loaded.dict[9007199254740993] == "big", "negative and large int keys are exact")
		TestUtil.check(loaded.dict["forge_text:1"] == "prefixed" and loaded.dict["plain"] == "plain", "keys with the prefix and plain keys are kept")
		TestUtil.check(loaded.list[0][2] == "nested int key" and loaded.list[0]["2"] == "nested text key", "keys of a dictionary inside an array are exact")
		TestUtil.check(loaded.dict == model.dict, "the whole dictionary compares equal")
	# What the file looks like: text keys are never changed, only number and bool keys of an untyped dictionary are tagged.
	var text_keys: ExactModel = ExactModel.new()
	text_keys.dict = {"123": "a", "true": "b", "1.5": "c", "name": "d", "-7": "e"}
	var text_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(text_keys))
	var written: Array = text_json["dict"].keys()
	written.sort()
	TestUtil.check(written == ["-7", "1.5", "123", "name", "true"], "text keys that look like numbers or bools are written as they are")
	var number_keys: ExactModel = ExactModel.new()
	number_keys.dict = {1: "a", 2.5: "b", true: "c", 9007199254740993: "d"}
	var number_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(number_keys))
	var tagged: Array = number_json["dict"].keys()
	tagged.sort()
	TestUtil.check(tagged == ["forge_bool:true", "forge_float:2.5", "forge_int:1", "forge_int:9007199254740993"], "number and bool keys of an untyped dictionary are tagged with their type")
	var typed_keys: Typed = Typed.new()
	typed_keys.dic = {1: "a", 20: "b"}
	var typed_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(typed_keys))
	TestUtil.check(typed_json["dic"].keys() == ["1", "20"], "the keys of Dictionary[int, String] are plain text: the type is known")
	typed_keys.free()
	var tricky_text: ExactModel = ExactModel.new()
	tricky_text.dict = {"forge_int:5": "text that looks like a tag", "forge_text:x": "prefix", "Vector2(1, 2)": "vector text"}
	var tricky_loaded: ExactModel = round_trip(ExactModel, tricky_text)
	TestUtil.check(tricky_loaded.dict == tricky_text.dict, "text that looks like a key tag, the text prefix or a Godot value is escaped and comes back as text")
	# Typed key dictionaries.
	var typed: ExactModel = ExactModel.new()
	typed.by_name = {"1": 1, "true": 2, "Vector2(1, 2)": 3}
	TestUtil.check(round_trip(ExactModel, typed).by_name == typed.by_name, "Dictionary[String, int] keeps keys that look like numbers or values")
	var keyed: Typed = Typed.new()
	keyed.dic = {1: "a", -2: "b", 3: "c"}
	TestUtil.check((round_trip(Typed, keyed) as Typed).dic == keyed.dic, "Dictionary[int, String] keeps int keys")
	keyed.free()

#endregion


#region Scripts without a class_name

func test_moved_scripts() -> void:
	var plain_script: Script = load("res://Tests/Models/PlainScript.gd")
	var plain: Object = plain_script.new()
	plain.value = 7
	var json: Dictionary = ForgeJSONGD.class_to_json(plain, true)
	TestUtil.check(json.get("script_uid", "").begins_with("uid://"), "a script without a class_name also stores its uid")
	TestUtil.check(not ForgeJSONGD.class_to_json(Dog.new(), true).has("script_uid"), "a script with a class_name does not need a uid")
	# Pretend the file was moved: the old path no longer exists, the uid still finds the script.
	var moved: Dictionary = json.duplicate()
	moved["script_inheritance"] = "res://somewhere/old/PlainScript.gd"
	var loaded: Object = ForgeJSONGD.json_to_class(null, moved)
	TestUtil.check(loaded != null and loaded.get("value") == 7, "a moved script is found again through its uid")
	var in_array: BuiltinsModel = ForgeJSONGD.json_to_class(BuiltinsModel, {"arr": [moved]})
	TestUtil.check(in_array.arr[0].get("value") == 7, "also inside an untyped array")
	# An old file without a uid keeps working while the path is right.
	var old_style: Dictionary = json.duplicate()
	old_style.erase("script_uid")
	TestUtil.check(ForgeJSONGD.json_to_class(null, old_style).get("value") == 7, "files without a uid load by path")
	TestUtil.check(ForgeJSONGD.json_operation(json, {"script_uid": "uid://other", "value": 1}, ForgeJSONGD.Operation.Replace).get("script_uid") == json["script_uid"], "operations never change script_uid")
	ForgeJSONGD.register_script(MySuperClass)
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, moved)), "the registry also applies to scripts found by uid")
	ForgeJSONGD.clear_registered_scripts()

#endregion


#region Classes declared inside another script

func test_inner_classes() -> void:
	var holder: InnerOwner = InnerOwner.new()
	holder.item = InnerOwner.Item.new()
	holder.item.label = "single"
	holder.item.amount = 3
	var first: InnerOwner.Item = InnerOwner.Item.new()
	first.label = "first"
	first.amount = 1
	holder.items = [first]
	holder.by_name = {"a": first}
	for loaded: InnerOwner in [round_trip(InnerOwner, holder), from_file(InnerOwner, holder, "inner.json")]:
		TestUtil.check(loaded.item != null and loaded.item.label == "single" and loaded.item.amount == 3, "a variable declared with an inner class loads")
		TestUtil.check(loaded.items.size() == 1 and loaded.items[0].label == "first", "Array of an inner class loads")
		TestUtil.check(loaded.by_name.size() == 1 and loaded.by_name["a"].amount == 1, "Dictionary of an inner class loads")
	# A child inner class in a variable declared with its parent inner class.
	var special: InnerOwner = InnerOwner.new()
	special.item = InnerOwner.SpecialItem.new()
	special.item.label = "special"
	special.item.bonus = 5
	special.items = [InnerOwner.SpecialItem.new()]
	special.items[0].bonus = 8
	var special_json: Dictionary = ForgeJSONGD.class_to_json(special)
	TestUtil.check(special_json["item"]["script_inheritance"] == "::SpecialItem", "a child inner class is saved as '::Name'")
	for loaded_special: InnerOwner in [round_trip(InnerOwner, special), from_file(InnerOwner, special, "inner_special.json")]:
		TestUtil.check(loaded_special.item is InnerOwner.SpecialItem and loaded_special.item.bonus == 5 and loaded_special.item.label == "special", "a child inner class in a variable of its parent inner class loads")
		TestUtil.check(loaded_special.items.size() == 1 and loaded_special.items[0] is InnerOwner.SpecialItem and loaded_special.items[0].bonus == 8, "a child inner class in Array[parent inner class] is kept")
	# Loading an inner class directly works when the script is passed.
	var direct: Object = ForgeJSONGD.json_to_class(InnerOwner.Item, {"label": "direct", "amount": 9})
	TestUtil.check(direct.label == "direct" and direct.amount == 9, "an inner class passed as the script loads")

#endregion


#region Inheritance and polymorphism are unchanged

func test_inheritance_still_works() -> void:
	var rex: Dog = Dog.new()
	rex.name = "Rex"
	rex.tricks = ["sit"]
	var tom: Cat = Cat.new()
	tom.name = "Tom"
	tom.lives = 7
	var zoo: Zoo = Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, tom, Animal.new()]
	zoo.by_name = {"tom": tom}
	for loaded: Zoo in [round_trip(Zoo, zoo), from_file(Zoo, zoo, "zoo.json")]:
		TestUtil.check(loaded.star is Dog and loaded.animals[0] is Dog and loaded.animals[1] is Cat, "children keep their class")
		TestUtil.check(not loaded.animals[2] is Dog and not loaded.animals[2] is Cat, "a plain parent stays a parent")
		TestUtil.check((loaded.animals[1] as Cat).lives == 7 and loaded.by_name["tom"] is Cat, "child properties and typed dictionaries are kept")
		TestUtil.check((loaded.animals[0] as Dog).tricks == ["sit"], "typed arrays inside children are kept")
	var holder: BuiltinsModel = BuiltinsModel.new()
	holder.arr = [rex, tom]
	holder.dict = {"cat": tom}
	holder.any = rex
	var untyped: BuiltinsModel = round_trip(BuiltinsModel, holder)
	TestUtil.check(untyped.arr[0] is Dog and untyped.arr[1] is Cat and untyped.dict["cat"] is Cat and untyped.any is Dog, "children keep their class in untyped places")
	TestUtil.check((untyped.arr[1] as Cat).lives == 7, "children in untyped places keep their properties")

#endregion
