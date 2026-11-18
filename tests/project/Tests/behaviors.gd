## Tests for the behaviors and limits the guides describe, so every statement in the docs is checked.
extends Node

const TMP_DIR = "user://behaviors/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	test_numbers()
	test_untyped_containers()
	test_export_modes()
	test_failure_results()
	test_public_helpers()
	test_registry_and_resources()
	test_object_inputs()
	test_unknown_scripts()
	TestUtil.finish("Behaviors", get_tree())


func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


#region Numbers

func test_numbers() -> void:
	var model: TypedModel = TypedModel.new()
	model.mixed = {"safe": 9007199254740992, "negative": -5, "float": 0.1, "big_float": 1.0e20}
	var loaded: TypedModel = round_trip(TypedModel, model)
	TestUtil.check(loaded.mixed["safe"] == 9007199254740992, "ints up to 2^53 round-trip")
	TestUtil.check(loaded.mixed["negative"] == -5 and loaded.mixed["float"] == 0.1 and loaded.mixed["big_float"] == 1.0e20, "negative numbers and floats round-trip")
	# Ints stay ints and floats stay floats, also in untyped containers.
	TestUtil.check(typeof(loaded.mixed["negative"]) == TYPE_INT and typeof(loaded.mixed["float"]) == TYPE_FLOAT, "numbers in untyped containers keep int and float")
	# Floats keep every digit, in files and in JSON text.
	var precise: TypedModel = TypedModel.new()
	precise.mixed = {"pi": 3.141592653589793, "third": 2.0 / 3.0, "tiny": 1e-7, "huge": 1e20, "tenth": 0.1}
	precise.floats = [3.141592653589793, 0.1]
	var precise_loaded: TypedModel = round_trip(TypedModel, precise)
	TestUtil.check(precise_loaded.mixed == precise.mixed and precise_loaded.floats == precise.floats, "floats round-trip exactly through JSON text")
	ForgeJSONGD.store_json_file(TMP_DIR + "precise.json", ForgeJSONGD.class_to_json(precise))
	var precise_file: TypedModel = ForgeJSONGD.json_file_to_class(TypedModel, TMP_DIR + "precise.json")
	TestUtil.check(precise_file.mixed == precise.mixed and precise_file.floats == precise.floats, "floats round-trip exactly through a file")
	var file_text: String = FileAccess.get_file_as_string(TMP_DIR + "precise.json")
	TestUtil.check(file_text.contains("0.1") and not file_text.contains("0.1000000"), "ordinary floats stay short and readable")
	var typed: BuiltinsModel = BuiltinsModel.new()
	typed.any = 9007199254740993
	TestUtil.check(round_trip(BuiltinsModel, typed).any == 9007199254740993, "ints above 2^53 keep every digit")

#endregion


#region Untyped containers

func test_untyped_containers() -> void:
	var model: TypedModel = TypedModel.new()
	model.nested = ["123", "true", "plain", "[1, 2]"]
	var loaded: TypedModel = round_trip(TypedModel, model)
	TestUtil.check(loaded.nested[0] is String and loaded.nested[1] is String and loaded.nested[3] is String, "number-like, bool-like and JSON-like text stays text in untyped containers")
	TestUtil.check(loaded.nested == ["123", "true", "plain", "[1, 2]"], "untyped containers keep text exactly")
	var typed: TypedModel = TypedModel.new()
	typed.strings = ["123", "true"]
	TestUtil.check(round_trip(TypedModel, typed).strings == typed.strings, "Array[String] keeps number-like text")

	var keyed: TypedModel = TypedModel.new()
	keyed.mixed = {1: "int key", "text": "text key"}
	var keyed_loaded: TypedModel = round_trip(TypedModel, keyed)
	TestUtil.check(keyed_loaded.mixed.size() == 2 and keyed_loaded.mixed.has("text"), "untyped dictionary keeps its entries")
	TestUtil.check(keyed_loaded.mixed.has(1) and typeof(keyed_loaded.mixed.keys()[0]) != TYPE_FLOAT, "int keys of an untyped dictionary come back as ints")
	var int_keys: Dictionary[int, String] = {1: "a"}
	var holder: Typed = Typed.new()
	holder.dic = int_keys
	TestUtil.check((round_trip(Typed, holder) as Typed).dic.has(1), "int keys of Dictionary[int, String] come back as ints")

#endregion


#region Export modes

func test_export_modes() -> void:
	var model: StorageModel = StorageModel.new()
	var all_json: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(all_json.has("exported") and all_json.has("stored") and all_json.has("plain"), "by default every script variable is saved")
	ForgeJSONGD.only_exported_values = true
	var export_json: Dictionary = ForgeJSONGD.class_to_json(model)
	ForgeJSONGD.only_exported_values = false
	TestUtil.check(export_json.has("exported") and export_json.has("stored") and not export_json.has("plain"), "only_exported_values keeps @export and @export_storage variables")

#endregion


#region Failure results

func test_failure_results() -> void:
	var blocker_path: String = TMP_DIR + "blocker"
	var blocker: FileAccess = FileAccess.open(blocker_path, FileAccess.WRITE)
	blocker.store_string("a file, not a folder")
	blocker.close()
	TestUtil.check(not ForgeJSONGD.store_json_file(blocker_path + "/inside.json", {"a": 1}), "store_json_file returns false when it cannot write")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(TMP_DIR + "missing.json") == {}, "json_file_to_dict returns an empty dictionary for a missing file")
	TestUtil.check(ForgeJSONGD.json_string_to_class(Save, "{ broken") == null, "json_string_to_class returns null for invalid JSON")
	var fresh: Object = ForgeJSONGD.json_file_to_class(Save, TMP_DIR + "missing.json")
	TestUtil.check(fresh is Save, "json_file_to_class returns a new instance when the file is missing")
	ForgeJSONGD.store_json_file(TMP_DIR + "array.json", {"x": 1})
	var array_file: FileAccess = FileAccess.open(TMP_DIR + "array_root.json", FileAccess.WRITE)
	array_file.store_string("[1, 2, 3]")
	array_file.close()
	TestUtil.check(ForgeJSONGD.check_equal_jsons(TMP_DIR + "array.json", {"x": 1}), "check_equal_jsons reads a file path")

#endregion


#region Public helpers

func test_public_helpers() -> void:
	var child: MyChildClass = MyChildClass.new()
	child.my_child_prop = "c"
	var items: Array = [child, 5, "text", Vector2(1, 2), Rect2(1, 2, 3, 4)]
	var json_array: Array = ForgeJSONGD.convert_array_to_json(items)
	TestUtil.check(json_array[0] is Dictionary and json_array[0][ForgeJSONGD.SCRIPT_INHERITANCE] == "MyChildClass", "convert_array_to_json stores objects with their script")
	TestUtil.check(json_array[1] == 5.0 and json_array[2] == "text" and json_array[3] == "Vector2(1, 2)", "convert_array_to_json converts values")
	TestUtil.check(json_array[4] == "Rect2(1, 2, 3, 4)", "convert_array_to_json tags built-in types")
	var json_dict: Dictionary = ForgeJSONGD.convert_dictionary_to_json({"child": child, "n": 3})
	TestUtil.check(json_dict["child"] is Dictionary and json_dict["n"] == 3.0, "convert_dictionary_to_json converts values")
	TestUtil.check(ForgeJSONGD.SCRIPT_INHERITANCE == "script_inheritance" and ForgeJSONGD.CONSTRUCTOR_ARGS == "script_constructor_args", "the JSON key names are the documented ones")

#endregion


#region Registry and resources

func test_registry_and_resources() -> void:
	ForgeJSONGD.clear_registered_scripts()
	var nested: NestedResource = NestedResource.new()
	nested.label = "from disk"
	var resource_path: String = TMP_DIR + "nested.tres"
	ResourceSaver.save(nested, resource_path)
	# A JSON file can point at a resource file by path.
	var json: Dictionary = {"nested": resource_path}
	var open: ResourceHolder = ForgeJSONGD.json_to_class(ResourceHolder, json)
	TestUtil.check(open.nested != null and open.nested.label == "from disk", "a resource path in JSON loads the resource")
	ForgeJSONGD.register_script(MySuperClass)
	var blocked: ResourceHolder = ForgeJSONGD.json_to_class(ResourceHolder, json)
	TestUtil.check(blocked.nested == null, "with a registry, a resource whose script is not registered is not loaded")
	ForgeJSONGD.register_script(NestedResource)
	var allowed: ResourceHolder = ForgeJSONGD.json_to_class(ResourceHolder, json)
	TestUtil.check(allowed.nested != null and allowed.nested.label == "from disk", "a registered resource script loads")
	ForgeJSONGD.clear_registered_scripts()

	var texture_json: Dictionary = {"texture": "res://icon.svg"}
	var collection: Collection = ForgeJSONGD.json_to_class(Collection, texture_json)
	TestUtil.check(collection.texture != null, "a resource path without a script loads (for example a texture)")
	ForgeJSONGD.register_script(MySuperClass)
	TestUtil.check(ForgeJSONGD.json_to_class(Collection, texture_json).texture != null, "with a registry, resources without a script still load")
	ForgeJSONGD.clear_registered_scripts()

#endregion


#region Objects as inputs

func test_object_inputs() -> void:
	var first: MyChildClass = MyChildClass.new()
	first.my_child_prop = "a"
	var second: MyChildClass = MyChildClass.new()
	second.my_child_prop = "b"
	TestUtil.check(not ForgeJSONGD.check_equal_jsons(first, second), "check_equal_jsons compares two objects")
	var diff: Dictionary = ForgeJSONGD.compare_jsons_diff(first, second)
	TestUtil.check(diff == {"my_child_prop": {"old": "a", "new": "b"}}, "compare_jsons_diff has the documented old/new format")
	var text_diff: Dictionary = ForgeJSONGD.compare_jsons_diff(ForgeJSONGD.class_to_json_string(first), ForgeJSONGD.class_to_json_string(second))
	TestUtil.check(text_diff == diff, "compare_jsons_diff accepts JSON strings")
	ForgeJSONGD.store_json_file(TMP_DIR + "first.json", ForgeJSONGD.class_to_json(first))
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(TMP_DIR + "first.json", second) == diff, "compare_jsons_diff accepts file paths and objects")

#endregion


#region Unknown scripts

func test_unknown_scripts() -> void:
	# A script name that does not exist (for example a class you deleted since saving).
	var zoo_json: Dictionary = {
		"star": {"script_inheritance": "DoesNotExist", "name": "Star"},
		"animals": [{"name": "Plain"}, {"script_inheritance": "DoesNotExist", "name": "Ghost"}],
		"by_name": {"g": {"script_inheritance": "DoesNotExist", "name": "Ghost"}},
	}
	var zoo: Zoo = ForgeJSONGD.json_to_class(Zoo, zoo_json)
	TestUtil.check(zoo.star is Animal and zoo.star.name == "Star", "an unknown script in an object property loads as the declared type")
	TestUtil.check(zoo.animals.size() == 2 and zoo.animals[1].name == "Ghost", "an unknown script in a typed array loads as the declared type, the other elements are kept")
	TestUtil.check(zoo.by_name["g"] is Animal, "an unknown script in a typed dictionary loads as the declared type")
	var untyped: BuiltinsModel = ForgeJSONGD.json_to_class(BuiltinsModel, {"arr": [{"script_inheritance": "DoesNotExist", "x": 1}]})
	TestUtil.check(untyped.arr[0] is Dictionary and untyped.arr[0]["x"] == 1, "an unknown script in an untyped array stays plain data")
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {"script_inheritance": "DoesNotExist"})), "an unknown script without a type hint gives a plain Object")

#endregion
