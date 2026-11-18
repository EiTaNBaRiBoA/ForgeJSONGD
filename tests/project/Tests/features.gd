## Tests for the optional features: built-in types in untyped slots, excluded properties,
## constructor arguments, custom hooks and the script registry.
extends Node


func _ready() -> void:
	test_builtin_types()
	test_builtin_properties()
	test_excluded_properties()
	test_constructor_args()
	test_custom_hooks()
	test_script_registry()
	TestUtil.finish("Features", get_tree())


# Serializes to a JSON string and parses it back, like a real save file.
func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


#region Built-in types in untyped slots

func test_builtin_types() -> void:
	var model: BuiltinsModel = BuiltinsModel.new()
	model.any = Rect2(1, 2, 3, 4)
	model.arr = [
		Rect2(1, 2, 3, 4), Transform3D(), Quaternion(), AABB(), Plane(Vector3.UP, 2.0), Color.RED,
		PackedByteArray([1, 2, 3, 250]), PackedStringArray(["a", "b"]), PackedInt32Array([1, 2]),
		PackedVector2Array([Vector2(1, 2)]), PackedColorArray([Color.BLUE]), Vector2i(1, 2), "plain", 4, 1.5, true, null,
	]
	model.dict = {
		"rect": Rect2(1, 2, 3, 4),
		"bytes": PackedByteArray([9, 9]),
		"color": Color.GREEN,
		"nested": {"basis": Basis.IDENTITY, "list": [Rect2i(1, 2, 3, 4)], "text": "123"},
	}
	var loaded: BuiltinsModel = round_trip(BuiltinsModel, model)

	TestUtil.check(loaded.any is Rect2 and loaded.any == Rect2(1, 2, 3, 4), "Variant property keeps a Rect2")
	var expected_types: Array[int] = [
		TYPE_RECT2, TYPE_TRANSFORM3D, TYPE_QUATERNION, TYPE_AABB, TYPE_PLANE, TYPE_COLOR,
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_VECTOR2I, TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_NIL,
	]
	for i: int in expected_types.size():
		TestUtil.check(typeof(loaded.arr[i]) == expected_types[i], "untyped array element %d keeps type %s" % [i, type_string(expected_types[i])])
	TestUtil.check(loaded.arr[0] == Rect2(1, 2, 3, 4) and loaded.arr[6] == PackedByteArray([1, 2, 3, 250]), "untyped array values are exact")
	TestUtil.check(loaded.arr[7] == PackedStringArray(["a", "b"]) and loaded.arr[10] == PackedColorArray([Color.BLUE]), "packed array values are exact")

	TestUtil.check(loaded.dict["rect"] == Rect2(1, 2, 3, 4), "untyped dictionary keeps a Rect2")
	TestUtil.check(loaded.dict["bytes"] is PackedByteArray and loaded.dict["bytes"] == PackedByteArray([9, 9]), "untyped dictionary keeps a PackedByteArray")
	TestUtil.check(loaded.dict["color"] == Color.GREEN, "untyped dictionary keeps a Color")
	TestUtil.check(loaded.dict["nested"]["basis"] == Basis.IDENTITY, "nested dictionary keeps a Basis")
	TestUtil.check(loaded.dict["nested"]["list"][0] is Rect2i, "array inside a nested dictionary keeps a Rect2i")
	TestUtil.check(loaded.dict["nested"]["text"] is String, "plain text inside a nested dictionary stays text")

	# PackedByteArray is stored as compact base64, including the empty array.
	var bytes_model: BuiltinsModel = BuiltinsModel.new()
	bytes_model.arr = [PackedByteArray([1, 2, 3]), PackedByteArray(), PackedByteArray([0, 255])]
	var bytes_json: Dictionary = ForgeJSONGD.class_to_json(bytes_model)
	TestUtil.check(bytes_json["arr"][0] == 'PackedByteArray("AQID")', "PackedByteArray is stored as base64")
	var bytes_loaded: BuiltinsModel = round_trip(BuiltinsModel, bytes_model)
	TestUtil.check(bytes_loaded.arr == bytes_model.arr, "PackedByteArray values (including empty) round-trip")
	var old_format: BuiltinsModel = ForgeJSONGD.json_to_class(BuiltinsModel, {"arr": ["PackedByteArray(1, 2, 3)"]})
	TestUtil.check(old_format.arr[0] == PackedByteArray([1, 2, 3]), "the older list format of PackedByteArray still loads")

	# Keys stay plain text, so files stay readable and diffable.
	var keyed: BuiltinsModel = BuiltinsModel.new()
	keyed.dict = {&"name": 1, "other": 2}
	var json: Dictionary = ForgeJSONGD.class_to_json(keyed)
	TestUtil.check((json["dict"] as Dictionary).has("name"), "StringName keys are stored as plain text")

	# Typed containers keep their previous format.
	model.typed_rects = [Rect2(1, 2, 3, 4)]
	var typed_loaded: BuiltinsModel = round_trip(BuiltinsModel, model)
	TestUtil.check(typed_loaded.typed_rects == model.typed_rects, "Array[Rect2] still round-trips")

	# An object stored in a Variant property comes back as the same class.
	var holder: BuiltinsModel = BuiltinsModel.new()
	var child: MyChildClass = MyChildClass.new()
	child.my_child_prop = "c"
	holder.any = child
	var holder_loaded: BuiltinsModel = round_trip(BuiltinsModel, holder)
	TestUtil.check(holder_loaded.any is MyChildClass and holder_loaded.any.my_child_prop == "c", "Variant property keeps an object")

	var number: BuiltinsModel = BuiltinsModel.new()
	number.any = 5
	TestUtil.check(round_trip(BuiltinsModel, number).any == 5, "Variant property keeps an int")

#endregion


#region Built-in types with a declared type

func test_builtin_properties() -> void:
	var model: BuiltinPropsModel = BuiltinPropsModel.new()
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	# Types JSON can only write as display text are stored with var_to_str (readable by GDScript and C#).
	for key: String in ["rect", "recti", "aabb", "plane", "quat", "basis", "t2", "t3", "projection", "bytes", "empty_bytes", "vec2s", "vec3s", "colors"]:
		TestUtil.check(json[key] is String and (json[key] as String).ends_with(")"), "%s is stored as var_to_str text" % key)
	TestUtil.check(json["bytes"] == 'PackedByteArray("AQID+g==")', "PackedByteArray property is stored as base64")
	var text_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(model))
	TestUtil.check(text_json["ints"] is Array and text_json["strings"] is Array and text_json["floats"] is Array, "number and string packed arrays are JSON arrays in the file")
	TestUtil.check(text_json["path"] == "a/b" and text_json["tag"] == "tag", "NodePath and StringName are plain text in the file")

	# Use a loaded object that starts with different values, so a failed load cannot look like a success.
	var loaded: BuiltinPropsModel = BuiltinPropsModel.new()
	loaded.rect = Rect2()
	loaded.recti = Rect2i()
	loaded.aabb = AABB()
	loaded.plane = Plane()
	loaded.quat = Quaternion()
	loaded.basis = Basis()
	loaded.t2 = Transform2D()
	loaded.t3 = Transform3D()
	loaded.projection = Projection()
	loaded.bytes = PackedByteArray()
	loaded.strings = PackedStringArray()
	loaded.ints = PackedInt32Array()
	loaded.floats = PackedFloat32Array()
	loaded.vec2s = PackedVector2Array()
	loaded.vec3s = PackedVector3Array()
	loaded.colors = PackedColorArray()
	loaded.path = NodePath()
	loaded.tag = &""
	ForgeJSONGD.json_to_class(loaded, JSON.parse_string(ForgeJSONGD.class_to_json_string(model)))
	for property: Dictionary in model.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var property_name: String = property.name
			TestUtil.check(typeof(loaded.get(property_name)) == typeof(model.get(property_name)) and loaded.get(property_name) == model.get(property_name), "%s round-trips with its type" % property_name)

#endregion


#region Excluded properties

func test_excluded_properties() -> void:
	var model: SecretModel = SecretModel.new()
	model.user_name = "player"
	model.password = "hunter2"
	model.cache = "temp"
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.has("user_name") and not json.has("password") and not json.has("cache"), "excluded properties are not saved")

	var loaded: SecretModel = ForgeJSONGD.json_to_class(SecretModel, {"user_name": "a", "password": "from_file", "cache": "x"})
	TestUtil.check(loaded.user_name == "a" and loaded.password == "" and loaded.cache == "", "excluded properties are not loaded")

#endregion


#region Constructor arguments

func test_constructor_args() -> void:
	var model: ArgsModel = ArgsModel.new(7, "seven")
	model.loaded_extra = "changed"
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.has(ForgeJSONGD.CONSTRUCTOR_ARGS), "constructor arguments are stored")

	var loaded: ArgsModel = round_trip(ArgsModel, model)
	TestUtil.check(loaded != null and loaded.count == 7 and loaded.label == "seven", "a class with required _init arguments loads")
	TestUtil.check(loaded.loaded_extra == "changed", "properties are still loaded after the constructor")

	var via_hint: Object = ForgeJSONGD.json_to_class(null, ForgeJSONGD.class_to_json(model, true))
	TestUtil.check(via_hint is ArgsModel and via_hint.count == 7, "constructor arguments work without a type hint")

	var holder: Array = [model]
	var holder_json: Array = ForgeJSONGD.convert_array_to_json(holder)
	var from_array: Object = ForgeJSONGD.json_to_class(null, holder_json[0])
	TestUtil.check(from_array is ArgsModel and from_array.label == "seven", "constructor arguments work inside untyped arrays")

#endregion


#region Custom hooks

func test_custom_hooks() -> void:
	var model: CustomModel = CustomModel.new()
	model.numbers = PackedInt32Array([3, 1, 4])
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.get("numbers") == "3,1,4", "_forge_serialize replaces the automatic serialization")
	var loaded: CustomModel = round_trip(CustomModel, model)
	TestUtil.check(loaded.numbers == model.numbers, "_forge_deserialize builds the instance")

	var typed_json: Dictionary = ForgeJSONGD.class_to_json(model, true)
	TestUtil.check(typed_json.get(ForgeJSONGD.SCRIPT_INHERITANCE) == "CustomModel", "custom classes still store their script when asked")
	var via_hint: Object = ForgeJSONGD.json_to_class(null, typed_json)
	TestUtil.check(via_hint is CustomModel and via_hint.numbers == model.numbers, "custom classes load without a type hint")

#endregion


#region Script registry

func test_script_registry() -> void:
	ForgeJSONGD.clear_registered_scripts()
	var save: Save = Save.new()
	var child: MyChildClass = MyChildClass.new()
	child.my_child_prop = "c"
	save.child_class = child
	var plain_script: Script = load("res://Tests/Models/PlainScript.gd")
	var plain: Object = plain_script.new()
	plain.value = 7
	var holder: BuiltinsModel = BuiltinsModel.new()
	holder.any = plain
	holder.arr = [plain]
	var save_text: String = ForgeJSONGD.class_to_json_string(save)
	var holder_text: String = ForgeJSONGD.class_to_json_string(holder)

	# Nothing registered: everything loads.
	TestUtil.check((ForgeJSONGD.json_string_to_class(Save, save_text) as Save).child_class is MyChildClass, "no registry: child class loads")
	TestUtil.check((ForgeJSONGD.json_string_to_class(BuiltinsModel, holder_text) as BuiltinsModel).any is Object, "no registry: any script loads")

	# A registry with only the parent class: the child script is blocked, so the property stays unset.
	ForgeJSONGD.register_script(MySuperClass)
	var blocked: Save = ForgeJSONGD.json_string_to_class(Save, save_text)
	TestUtil.check(blocked.child_class != null and not blocked.child_class is MyChildClass, "registry: an unregistered child script is not created, the declared parent type is used")
	var blocked_holder: BuiltinsModel = ForgeJSONGD.json_string_to_class(BuiltinsModel, holder_text)
	TestUtil.check(not blocked_holder.any is Object and blocked_holder.arr[0] is Dictionary, "registry: an unregistered script path is not created")
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, ForgeJSONGD.class_to_json(child, true))), "registry: loading without a hint ignores unregistered scripts")
	var direct: Save = ForgeJSONGD.json_string_to_class(Save, "{}")
	TestUtil.check(direct is Save, "registry: scripts passed by the caller are always allowed")

	# Registering the child (and by path) lets them load again.
	ForgeJSONGD.register_scripts([MyChildClass, plain_script])
	ForgeJSONGD.register_script(MyChildClass) # registering twice is harmless
	TestUtil.check((ForgeJSONGD.json_string_to_class(Save, save_text) as Save).child_class is MyChildClass, "registry: a registered child script loads")
	TestUtil.check((ForgeJSONGD.json_string_to_class(BuiltinsModel, holder_text) as BuiltinsModel).any is Object, "registry: a registered script path loads")

	ForgeJSONGD.clear_registered_scripts()
	TestUtil.check((ForgeJSONGD.json_string_to_class(BuiltinsModel, holder_text) as BuiltinsModel).any is Object, "clearing the registry allows every script again")

#endregion
