## More behavior tests for statements in the guides: resources in containers, unsupported values,
## file and enum details, and equality details.
extends Node

const TMP_DIR = "user://behaviors_more/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	test_resources_in_containers()
	test_unsupported_values()
	test_files_and_enums()
	test_equality_details()
	TestUtil.finish("Behaviors (more)", get_tree())


func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


#region Resources in containers

func test_resources_in_containers() -> void:
	var texture: Texture2D = load("res://icon.svg")
	var nested: NestedResource = NestedResource.new()
	nested.label = "from disk"
	ResourceSaver.save(nested, TMP_DIR + "nested.tres")
	var nested_from_disk: NestedResource = ResourceLoader.load(TMP_DIR + "nested.tres", "", ResourceLoader.CACHE_MODE_IGNORE)

	var holder: TexHolder = TexHolder.new()
	holder.single = texture
	holder.textures = [texture, texture]
	holder.by_name = {"icon": texture}
	holder.untyped = [texture]
	var json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(holder))
	TestUtil.check(json["single"] == "res://icon.svg" and json["textures"] == ["res://icon.svg", "res://icon.svg"], "resources from files are saved as paths, also inside arrays")
	TestUtil.check(json["by_name"] == {"icon": "res://icon.svg"}, "resources from files are saved as paths, also inside dictionaries")
	TestUtil.check(json["untyped"] == [{"forge_resource_path": "res://icon.svg"}], "in an untyped Array a resource is saved as a marker object holding the path")

	var loaded: TexHolder = ForgeJSONGD.json_string_to_class(TexHolder, JSON.stringify(json))
	TestUtil.check(loaded.single != null and loaded.textures.size() == 2 and loaded.textures[1] == texture, "Array[Texture2D] loads the resources")
	TestUtil.check(loaded.by_name.size() == 1 and loaded.by_name["icon"] == texture, "Dictionary[String, Texture2D] loads the resources")
	TestUtil.check(loaded.untyped.size() == 1 and loaded.untyped[0] == texture, "an untyped Array loads the resource from its marker object")

	# Untyped places: Variant variables, untyped dictionaries and nested containers load the resource too.
	var anything: BuiltinsModel = BuiltinsModel.new()
	anything.any = texture
	anything.dict = {"icon": texture, "nested": {"list": [texture]}}
	var anything_loaded: BuiltinsModel = round_trip(BuiltinsModel, anything)
	TestUtil.check(anything_loaded.any == texture, "a Variant variable loads a resource from a file")
	TestUtil.check(anything_loaded.dict["icon"] == texture and anything_loaded.dict["nested"]["list"][0] == texture, "an untyped dictionary loads resources, also in nested containers")

	# A resource with a script, stored in a file that is not .tres.
	var scripted: NestedResource = NestedResource.new()
	scripted.label = "scripted"
	ResourceSaver.save(scripted, TMP_DIR + "scripted.res")
	var scripted_holder: BuiltinsModel = BuiltinsModel.new()
	scripted_holder.arr = [ResourceLoader.load(TMP_DIR + "scripted.res", "", ResourceLoader.CACHE_MODE_IGNORE)]
	var scripted_text: String = ForgeJSONGD.class_to_json_string(scripted_holder)
	var scripted_loaded: BuiltinsModel = ForgeJSONGD.json_string_to_class(BuiltinsModel, scripted_text)
	TestUtil.check(scripted_loaded.arr[0] is NestedResource and scripted_loaded.arr[0].label == "scripted", "a scripted resource in a .res file loads from an untyped array")
	ForgeJSONGD.register_script(MySuperClass)
	var scripted_blocked: BuiltinsModel = ForgeJSONGD.json_string_to_class(BuiltinsModel, scripted_text)
	ForgeJSONGD.clear_registered_scripts()
	TestUtil.check(scripted_blocked.arr[0] == null, "with a registry, a resource with an unregistered script is not loaded from an untyped array")

	var inline_holder: TexHolder = TexHolder.new()
	inline_holder.resources = [nested_from_disk]
	var inline_loaded: TexHolder = round_trip(TexHolder, inline_holder)
	TestUtil.check(inline_loaded.resources.size() == 1 and inline_loaded.resources[0].label == "from disk", "an Array of .tres resources is saved inline and loads")

	ForgeJSONGD.register_script(MySuperClass)
	var restricted: TexHolder = ForgeJSONGD.json_string_to_class(TexHolder, JSON.stringify(json))
	ForgeJSONGD.clear_registered_scripts()
	TestUtil.check(restricted.textures.size() == 2, "with a registry, resources without a script still load inside arrays")

#endregion


#region Unsupported values

func test_unsupported_values() -> void:
	var holder: NativeHolder = NativeHolder.new()
	holder.obj = RefCounted.new()
	holder.callback = Callable(self, "queue_free")
	holder.id = RID()
	var json: Dictionary = ForgeJSONGD.class_to_json(holder)
	TestUtil.check(json["obj"] == null, "an object without a script is saved as null")
	TestUtil.check(json["text"] == "keep", "other variables are still saved")
	var loaded: NativeHolder = round_trip(NativeHolder, holder)
	TestUtil.check(loaded.obj == null and loaded.callback.is_null() and loaded.id == RID() and loaded.text == "keep", "an object without a script, a Callable and an RID are not restored")
	var untyped: BuiltinsModel = BuiltinsModel.new()
	untyped.arr = [RefCounted.new(), "after"]
	var untyped_loaded: BuiltinsModel = round_trip(BuiltinsModel, untyped)
	TestUtil.check(untyped_loaded.arr[0] == null and untyped_loaded.arr[1] == "after", "an object without a script inside an array is saved as null")
	TestUtil.check(ForgeJSONGD.class_to_json(RefCounted.new(), true).get(ForgeJSONGD.SCRIPT_INHERITANCE) == "", "class_to_json on an object without a script does not fail")

	# A class whose _init needs arguments but has no _forge_constructor_args cannot be created.
	var plain_weapon: Object = ForgeJSONGD.json_to_class(Weapon, {"damage": 5})
	TestUtil.check(TestUtil.is_plain_object(plain_weapon), "a class with required _init arguments and no hook loads as a plain Object")

	# Nodes: only script variables are saved.
	var collection: Collection = Collection.new()
	collection.add_child(InnerModel.new())
	var keys: Array = ForgeJSONGD.class_to_json(collection).keys()
	keys.sort()
	TestUtil.check(keys == ["model", "modelCollection", "modelDict", "texture"], "a Node class saves only its script variables")
	collection.free()

#endregion


#region Files and enums

func test_files_and_enums() -> void:
	var empty_file: FileAccess = FileAccess.open(TMP_DIR + "empty.json", FileAccess.WRITE)
	empty_file.close()
	TestUtil.check(ForgeJSONGD.json_file_to_dict(TMP_DIR + "empty.json").is_empty(), "an empty file gives an empty dictionary")
	TestUtil.check(ForgeJSONGD.json_file_to_class(Save, TMP_DIR + "empty.json") is Save, "an empty file gives a new instance")
	var array_file: FileAccess = FileAccess.open(TMP_DIR + "array_root.json", FileAccess.WRITE)
	array_file.store_string("[1, 2, 3]")
	array_file.close()
	TestUtil.check(ForgeJSONGD.json_file_to_dict(TMP_DIR + "array_root.json").is_empty(), "a file whose JSON is not an object gives an empty dictionary")
	var existing: Save = Save.new()
	TestUtil.check(ForgeJSONGD.json_file_to_class(existing, TMP_DIR + "missing.json") == existing, "an existing instance is returned unchanged when the file is missing")

	var mode: ModeModel = ModeModel.new()
	mode.mode = ModeModel.Mode.VERY_SLOW_MODE
	TestUtil.check(ForgeJSONGD.class_to_json(mode)["mode"] == "Very_Slow_Mode", "enum names are written like the inspector shows them, with underscores")
	TestUtil.check((ForgeJSONGD.json_to_class(ModeModel, {"mode": 5}) as ModeModel).mode == ModeModel.Mode.SLOW_MODE, "an enum loads from its number")
	TestUtil.check((ForgeJSONGD.json_to_class(ModeModel, {"mode": "very slow mode"}) as ModeModel).mode == ModeModel.Mode.VERY_SLOW_MODE, "an enum name with spaces and lower case loads")
	TestUtil.check((ForgeJSONGD.json_to_class(ModeModel, {"mode": "nonsense"}) as ModeModel).mode == 0, "an unknown enum name loads as 0")

	# Files from older versions wrote these types as display text. They load now.
	var old_text: BuiltinPropsModel = ForgeJSONGD.json_to_class(BuiltinPropsModel, {
		"rect": "[P: (5.0, 6.0), S: (7.0, 8.0)]",
		"recti": "[P: (1, 2), S: (3, 4)]",
		"aabb": "[P: (1.0, 2.0, 3.0), S: (4.0, 5.0, 6.0)]",
		"plane": "[N: (0.0, 1.0, 0.0), D: 2]",
		"quat": "(0.1, 0.2, 0.3, 0.9)",
		"t2": "[X: (1.0, 0.0), Y: (0.0, 1.0), O: (3.0, 4.0)]",
		"t3": "[X: (1.0, 0.0, 0.0), Y: (0.0, 1.0, 0.0), Z: (0.0, 0.0, 1.0), O: (7.0, 8.0, 9.0)]",
		"basis": "[X: (1.0, 0.0, 0.0), Y: (0.0, 1.0, 0.0), Z: (0.0, 0.0, 1.0)]",
		"bytes": "[1, 2, 250]",
		"vec2s": "[(1.0, 2.0), (3.0, 4.0)]",
		"vec3s": "[(1.0, 2.0, 3.0)]",
		"colors": "[(1.0, 0.0, 0.0, 1.0)]",
	})
	TestUtil.check(old_text.rect == Rect2(5, 6, 7, 8) and old_text.recti == Rect2i(1, 2, 3, 4), "older display-text Rect2 and Rect2i load")
	TestUtil.check(old_text.aabb == AABB(Vector3(1, 2, 3), Vector3(4, 5, 6)) and old_text.plane == Plane(Vector3.UP, 2.0), "older display-text AABB and Plane load")
	TestUtil.check(old_text.quat.is_equal_approx(Quaternion(0.1, 0.2, 0.3, 0.9)), "older display-text Quaternion loads")
	TestUtil.check(old_text.t2 == Transform2D(Vector2(1, 0), Vector2(0, 1), Vector2(3, 4)) and old_text.t3 == Transform3D(Basis.IDENTITY, Vector3(7, 8, 9)) and old_text.basis == Basis.IDENTITY, "older display-text Transform2D, Transform3D and Basis load")
	TestUtil.check(old_text.bytes == PackedByteArray([1, 2, 250]) and old_text.vec2s == PackedVector2Array([Vector2(1, 2), Vector2(3, 4)]), "older display-text packed arrays load")
	TestUtil.check(old_text.vec3s == PackedVector3Array([Vector3(1, 2, 3)]) and old_text.colors == PackedColorArray([Color.RED]), "older display-text packed vector and color arrays load")

	var colors: ColorsModel = ColorsModel.new()
	colors.colors = [Color.RED]
	colors.transforms = {"t": Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))}
	colors.packed = [PackedByteArray([1, 2, 3])]
	var colors_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(colors))
	TestUtil.check(colors_json["colors"] == ["ff0000ff"], "Array[Color] keeps the hex form")
	TestUtil.check(colors_json["packed"] == ['PackedByteArray("AQID")'], "Array[PackedByteArray] is stored as base64")
	var colors_loaded: ColorsModel = round_trip(ColorsModel, colors)
	TestUtil.check(colors_loaded.colors == colors.colors and colors_loaded.transforms == colors.transforms and colors_loaded.packed == colors.packed, "typed containers of built-in types round-trip")

#endregion


#region Equality details

func test_equality_details() -> void:
	TestUtil.check(not ForgeJSONGD.check_equal_jsons({"a": [1, 2]}, {"a": [2, 1]}), "array order matters for equality")
	TestUtil.check(not ForgeJSONGD.check_equal_jsons({"a": "1"}, {"a": 1}), "text and number are different")
	var base: Dictionary = {"script_inheritance": "A", "x": 1}
	var ref: Dictionary = {"script_inheritance": "B", "x": 2}
	for operation: int in ForgeJSONGD.Operation.values():
		var result: Dictionary = ForgeJSONGD.json_operation(base, ref, operation as ForgeJSONGD.Operation)
		TestUtil.check(result.get("script_inheritance", "A") == "A", "operation %s does not change script_inheritance" % ForgeJSONGD.Operation.keys()[operation])

#endregion
