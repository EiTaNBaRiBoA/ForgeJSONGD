## Regression tests for scenarios that were fixed in ForgeJSONGD's history (see the git log of the addon).
extends Node

const TMP_DIR = "user://regression/"


func _ready() -> void:
	test_enums()
	test_typed_containers()
	test_untyped_containers()
	test_basic_types()
	test_script_inheritance()
	test_only_exported_values()
	test_nested_resource()
	test_unsafe_strings()
	test_files()
	test_compare_and_operations()
	TestUtil.finish("Regression", get_tree())


# Serializes to a JSON string and parses it back, like a real save file (ints become floats).
func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


#region Enums (custom values, underscores, lowercase)

func test_enums() -> void:
	for mode: int in ModeModel.Mode.values():
		var model: ModeModel = _mode(mode as ModeModel.Mode)
		var loaded: ModeModel = round_trip(ModeModel, model)
		TestUtil.check(loaded.mode == mode, "enum value %d round-trips" % mode)

	var stored: Variant = ForgeJSONGD.class_to_json(ModeModel.new()).get("mode")
	TestUtil.check(stored is String and not (stored as String).contains(" "), "enum names have no spaces")
	var name_json: String = ForgeJSONGD.class_to_json_string(_mode(ModeModel.Mode.VERY_SLOW_MODE))
	var stored_name: String = JSON.parse_string(name_json).get("mode")
	for variant: String in [stored_name.to_lower(), stored_name.to_upper()]:
		var loaded: ModeModel = ForgeJSONGD.json_to_class(ModeModel, {"mode": variant})
		TestUtil.check(loaded.mode == ModeModel.Mode.VERY_SLOW_MODE, "enum name '%s' loads (case-insensitive, underscores)" % variant)


func _mode(mode: ModeModel.Mode) -> ModeModel:
	var model: ModeModel = ModeModel.new()
	model.mode = mode
	return model

#endregion


#region Typed dictionaries and arrays

func test_typed_containers() -> void:
	var model: TypedModel = TypedModel.new()
	# Numeric strings must stay strings in String-typed containers.
	model.text_keys = {"1": "123", "2": "true", "3": "{\"a\": 1}", "4": "Vector2(1, 2)"}
	model.scores = {"a": 5, "b": 7}
	model.points = {"p": Vector2(1, 2)}
	model.ints = [4, 5, 6]
	model.floats = [1.5, 2.5]
	model.strings = ["1", "two", "3.0"]
	model.vecs2 = [Vector2(1, 2), Vector2(3, 4)]
	model.colors = [Color.YELLOW, Color.GREEN]
	var loaded: TypedModel = round_trip(TypedModel, model)

	TestUtil.check(loaded.text_keys == model.text_keys, "Dictionary[String, String] keeps numeric-looking strings")
	TestUtil.check(loaded.text_keys["1"] is String and loaded.text_keys["4"] is String, "Dictionary[String, String] values stay strings")
	TestUtil.check(loaded.scores == model.scores, "Dictionary[String, int] round-trips")
	TestUtil.check(loaded.points == model.points, "Dictionary[String, Vector2] round-trips")
	TestUtil.check(loaded.ints == model.ints, "Array[int] round-trips")
	TestUtil.check(loaded.floats == model.floats, "Array[float] round-trips")
	TestUtil.check(loaded.strings == model.strings, "Array[String] keeps numeric-looking strings")
	TestUtil.check(loaded.vecs2 == model.vecs2, "Array[Vector2] round-trips")
	TestUtil.check(loaded.colors == model.colors, "Array[Color] round-trips")

	var empty: TypedModel = round_trip(TypedModel, TypedModel.new())
	TestUtil.check(empty.ints.is_empty() and empty.text_keys.is_empty(), "empty typed containers round-trip")

#endregion


#region Untyped arrays and dictionaries

func test_untyped_containers() -> void:
	var model: TypedModel = TypedModel.new()
	model.vecs = [Vector3(1, 2, 3), Vector3(4, 5, 6)]
	model.nested = [[1, 2], ["a", "b"], []]
	model.mixed = {"text": "value", "number": 4, "flag": true, "vec": Vector2(1, 2), "list": [1, 2]}
	var loaded: TypedModel = round_trip(TypedModel, model)

	TestUtil.check(loaded.vecs == model.vecs, "untyped array of Vector3 round-trips")
	# JSON has no int type, so numbers in untyped containers come back as floats.
	TestUtil.check(loaded.nested == [[1, 2], ["a", "b"], []] and typeof(loaded.nested[0][0]) == TYPE_INT, "nested untyped arrays round-trip, ints stay ints")
	TestUtil.check(loaded.mixed.get("text") == "value", "dictionary string value")
	TestUtil.check(loaded.mixed.get("number") == 4, "dictionary non-string value (int)")
	TestUtil.check(loaded.mixed.get("flag") == true, "dictionary bool value")
	TestUtil.check(loaded.mixed.get("vec") == Vector2(1, 2), "dictionary Vector2 value")
	TestUtil.check(loaded.mixed.get("list") == [1, 2], "dictionary array value")

#endregion


#region Basic types

func test_basic_types() -> void:
	var model: TypedModel = TypedModel.new()
	model.path = NodePath("../Some/Node")
	model.v2i = Vector2i(3, 4)
	model.v4 = Vector4(1, 2, 3, 4)
	model.flag = true
	var loaded: TypedModel = round_trip(TypedModel, model)
	TestUtil.check(loaded.path == model.path, "NodePath round-trips")
	TestUtil.check(loaded.v2i == model.v2i, "Vector2i round-trips")
	TestUtil.check(loaded.v4 == model.v4, "Vector4 round-trips")
	TestUtil.check(loaded.flag, "bool round-trips")

	var partial: TypedModel = ForgeJSONGD.json_to_class(TypedModel, {"flag": true, "unknown_key": 1})
	TestUtil.check(partial.flag and partial.ints.is_empty(), "missing keys keep defaults and unknown keys are ignored")

#endregion


#region Script inheritance / loading without a type hint

func test_script_inheritance() -> void:
	var child: MyChildClass = MyChildClass.new()
	child.my_child_prop = "child"
	child.my_super_prop = "super"

	var json: Dictionary = ForgeJSONGD.class_to_json(child, true)
	TestUtil.check(json.get(ForgeJSONGD.SCRIPT_INHERITANCE) == "MyChildClass", "global class name is stored")
	var loaded: Object = ForgeJSONGD.json_to_class(null, json)
	TestUtil.check(loaded is MyChildClass and loaded.my_child_prop == "child", "null script loads a global class from JSON")

	var plain_script: Script = load("res://Tests/Models/PlainScript.gd")
	var plain: Object = plain_script.new()
	plain.value = 7
	var plain_json: Dictionary = ForgeJSONGD.class_to_json(plain, true)
	TestUtil.check(plain_json.get(ForgeJSONGD.SCRIPT_INHERITANCE) == "res://Tests/Models/PlainScript.gd", "non-global class stores its script path")
	var plain_loaded: Object = ForgeJSONGD.json_to_class(null, plain_json)
	TestUtil.check(plain_loaded != null and plain_loaded.get("value") == 7, "null script loads a non-global class from its path")

	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {})), "null script without stored script does not crash (it gives a plain Object)")
	var from_string: Object = ForgeJSONGD.json_string_to_class(null, ForgeJSONGD.class_to_json_string(child, true))
	TestUtil.check(from_string is MyChildClass, "null script works with JSON strings")

	var existing: MyChildClass = MyChildClass.new()
	ForgeJSONGD.json_to_class(existing, {"my_child_prop": "filled"})
	TestUtil.check(existing.my_child_prop == "filled", "an existing instance can be filled")

	# Untyped array: every element must carry its own script.
	var model: Model = Model.new()
	model.arrayOfInnerModels = [InnerModel.new(), InnerModel.new()]
	model.arrayOfInnerModels[0].TestInt = 5
	var loaded_model: Model = round_trip(Model, model)
	TestUtil.check(loaded_model.arrayOfInnerModels[0] is InnerModel and loaded_model.arrayOfInnerModels[0].TestInt == 5, "untyped array of objects restores each element class")

#endregion


#region only_exported_values

func test_only_exported_values() -> void:
	var model: VisibilityModel = VisibilityModel.new()
	TestUtil.check(ForgeJSONGD.class_to_json(model).has("hidden"), "non-exported variables are serialized by default")
	ForgeJSONGD.only_exported_values = true
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	var loaded: VisibilityModel = ForgeJSONGD.json_to_class(VisibilityModel, {"shown": "a", "hidden": "b"})
	ForgeJSONGD.only_exported_values = false
	TestUtil.check(json.has("shown") and not json.has("hidden"), "only_exported_values skips non-exported variables")
	TestUtil.check(loaded.shown == "a" and loaded.hidden == "hidden", "only_exported_values ignores non-exported keys when loading")

#endregion


#region Resources

func test_nested_resource() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var nested: NestedResource = NestedResource.new()
	nested.label = "inside"
	ResourceSaver.save(nested, TMP_DIR + "nested.tres")
	var holder: ResourceHolder = ResourceHolder.new()
	holder.nested = ResourceLoader.load(TMP_DIR + "nested.tres", "", ResourceLoader.CACHE_MODE_IGNORE)

	var json: Dictionary = ForgeJSONGD.class_to_json(holder)
	TestUtil.check(json.get("nested") is Dictionary, ".tres resource is stored inline")
	var loaded: ResourceHolder = round_trip(ResourceHolder, holder)
	TestUtil.check(loaded.nested != null and loaded.nested.label == "inside", ".tres resource round-trips")

	var empty: ResourceHolder = round_trip(ResourceHolder, ResourceHolder.new())
	TestUtil.check(empty.nested == null, "null object property stays null")

#endregion


#region Unsafe strings (str_to_var)

func test_unsafe_strings() -> void:
	var safe: TestResource = ForgeJSONGD.json_to_class(TestResource, {"typed_dict": {"v": "Vector2(1, 2)"}})
	TestUtil.check(safe.typed_dict.get("v") == Vector2(1, 2), "safe Vector2 string is converted")

	var payloads: Array[String] = [
		"Vector2(1, 2), Object(Node)",
		"Color(1, 0, 0), Callable(1)",
		"Vector3(0, 0, 0) Signal(x)",
		"Object(Node, \"name\": \"evil\")",
		"Callable(Object, \"free\")",
	]
	for payload: String in payloads:
		var result: TestResource = ForgeJSONGD.json_to_class(TestResource, {"typed_dict": {"v": payload}})
		TestUtil.check(result.typed_dict.get("v") is String and result.typed_dict.get("v") == payload, "unsafe string stays a plain string: %s" % payload)

#endregion


#region Files

func test_files() -> void:
	var path: String = TMP_DIR + "sub/file.json"
	TestUtil.check(ForgeJSONGD.store_json_file(path, {"a": "b"}), "a missing directory is created")
	TestUtil.check(ForgeJSONGD.store_json_file(TMP_DIR + "deep/er/file.json", {"a": "b"}), "several missing directory levels are created")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(path) == {"a": "b"}, "stored file is read back")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(TMP_DIR + "missing.json").is_empty(), "missing file returns an empty dictionary")

	var bad_path: String = TMP_DIR + "bad.json"
	var bad_file: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
	bad_file.store_string("{ not json")
	bad_file.close()
	TestUtil.check(ForgeJSONGD.json_file_to_dict(bad_path).is_empty(), "invalid JSON file returns an empty dictionary")

	var fresh: Object = ForgeJSONGD.json_file_to_class(TypedModel, TMP_DIR + "missing.json")
	TestUtil.check(fresh is TypedModel, "missing file with a Script returns a fresh instance")

	var encrypted: String = TMP_DIR + "secret.json"
	ForgeJSONGD.store_json_file(encrypted, {"a": "b"}, "key")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(encrypted, "key") == {"a": "b"}, "encrypted file reads with the right key")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(encrypted, "wrong").is_empty(), "encrypted file with the wrong key returns an empty dictionary")

	var model: TypedModel = TypedModel.new()
	model.ints = [1, 2]
	ForgeJSONGD.store_json_file(TMP_DIR + "model.json", ForgeJSONGD.class_to_json(model))
	var loaded: TypedModel = ForgeJSONGD.json_file_to_class(TypedModel, TMP_DIR + "model.json")
	TestUtil.check(loaded.ints == model.ints, "class file round-trips")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(TMP_DIR + "model.json", loaded), "file path equals the object it was stored from (ints, NodePath)")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(TMP_DIR + "model.json", loaded).is_empty(), "diff of a file and the object it was stored from is empty")

	var text_model: VisibilityModel = VisibilityModel.new()
	ForgeJSONGD.store_json_file(TMP_DIR + "text.json", ForgeJSONGD.class_to_json(text_model))
	TestUtil.check(ForgeJSONGD.check_equal_jsons(TMP_DIR + "sub/file.json", {"a": "b"}), "file path can be compared with a dictionary")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(TMP_DIR + "text.json", text_model), "file path equals an object with a different key order")
	TestUtil.check(ForgeJSONGD.check_equal_jsons({"a": 1, "b": 2}, {"b": 2, "a": 1}), "dictionaries with the same content in a different key order are equal")
	TestUtil.check(ForgeJSONGD.check_equal_jsons({"a": [1, 2]}, {"a": [1.0, 2.0]}), "int and float arrays are equal")
	TestUtil.check(not ForgeJSONGD.check_equal_jsons({"a": [1, 2]}, {"a": [1, 3]}), "different arrays are not equal")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff({"a": 1, "b": [1]}, {"b": [1.0], "a": 1.0}).is_empty(), "diff ignores int/float and key order")
	TestUtil.check(ForgeJSONGD.json_operation({"a": 1, "b": 2}, {"b": 2, "a": 1}, ForgeJSONGD.Operation.Remove).is_empty(), "operation short-circuits on equal data in a different key order")

#endregion


#region Compare and operations

func test_compare_and_operations() -> void:
	# ints parsed from JSON are floats, this must not create false differences.
	var model: Model = Model.new()
	model.modelID = 3
	model.int_array_var = [1, 2]
	var loaded: Model = round_trip(Model, model)
	TestUtil.check(ForgeJSONGD.check_equal_jsons(model, loaded), "objects are equal after an int/float round trip")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(model, loaded).is_empty(), "diff is empty after an int/float round trip")
	loaded.modelID = 4
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(model, loaded).has("modelID"), "diff between objects reports the changed property")

	TestUtil.check(ForgeJSONGD.compare_jsons_diff({"a": [1, 2]}, {"a": [1, 3]}) == {"a": {"old": [1, 2], "new": [1, 3]}}, "diff of arrays reports old and new")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff({"a": 1}, {"a": "1"}) == {"a": {"old": 1, "new": "1"}}, "diff reports a type change")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff({"o": {"x": 1, "y": 2}}, {"o": {"x": 1, "y": 3}}) == {"o": {"y": {"old": 2, "new": 3}}}, "diff recurses into dictionaries")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff({"a": 1}, {}) == {"a": {"old": 1, "new": null}}, "diff reports a removed key")

	# Same input on both sides (the Add-when-equal fix).
	var same: Dictionary = {"a": 1}
	TestUtil.check(ForgeJSONGD.json_operation(same, same, ForgeJSONGD.Operation.Add) == {"a": [1, 1]}, "Add with equal inputs combines values")
	TestUtil.check(ForgeJSONGD.json_operation(same, same, ForgeJSONGD.Operation.AddDiffer) == {"a": 1}, "AddDiffer with equal inputs changes nothing")
	TestUtil.check(ForgeJSONGD.json_operation(same, same, ForgeJSONGD.Operation.Replace) == {"a": 1}, "Replace with equal inputs changes nothing")
	TestUtil.check(ForgeJSONGD.json_operation(same, same, ForgeJSONGD.Operation.Remove).is_empty(), "Remove with equal inputs empties the result")
	TestUtil.check(ForgeJSONGD.json_operation(same, same, ForgeJSONGD.Operation.RemoveValue).is_empty(), "RemoveValue with equal inputs empties the result")

	# Nested dictionaries and keys missing from the base.
	var base: Dictionary = {"o": {"x": 1, "y": 2}}
	var ref: Dictionary = {"o": {"x": 1}, "new": 5}
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Remove) == {"o": {"y": 2}}, "Remove works on nested dictionaries and ignores unknown keys")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.RemoveValue) == {"o": {"y": 2}}, "RemoveValue works on nested dictionaries")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Replace).get("new") == 5, "Replace adds missing keys")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Add).get("new") == 5, "Add adds missing keys")

	# Operations must accept classes and not modify them.
	var model_b: Model = Model.new()
	model_b.modelName = "other"
	var result: Dictionary = ForgeJSONGD.json_operation(model, model_b, ForgeJSONGD.Operation.Replace)
	TestUtil.check(result.get("modelName") == "other" and model.modelName == "", "operation accepts classes without modifying them")

#endregion
