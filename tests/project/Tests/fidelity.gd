## The whole chain on real files, for many kinds of data: create the file, load it, compare it (with the original object,
## with the loaded object, with a re-saved copy) and make sure a change is reported exactly.
extends Node

const TMP_DIR = "user://fidelity/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	for sample: Dictionary in _samples():
		_check_chain(sample.name, sample.script, sample.object, sample.get("plain", false))
	_check_text_and_dictionary_routes()
	_check_changes_are_reported()
	TestUtil.finish("Fidelity", get_tree())


#region Sample data

func _samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = []

	var player: PlayerData = PlayerData.new()
	player.name = "Bob"
	player.score = 100
	player.inventory = ["Sword", "Potion", 3, 2.5, true]
	samples.append({"name": "PlayerData", "script": PlayerData, "object": player})

	var rex: Dog = Dog.new()
	rex.name = "Rex"
	rex.tricks = ["sit", "roll"]
	var tom: Cat = Cat.new()
	tom.name = "Tom"
	var zoo: Zoo = Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, tom, Animal.new()]
	zoo.by_name = {"tom": tom, "rex": rex}
	samples.append({"name": "Zoo (children in every container)", "script": Zoo, "object": zoo})

	var typed: TypedModel = TypedModel.new()
	typed.text_keys = {"1": "123", "2": "true", "3": "[1, 2]", "4": "Vector2(1, 2)"}
	typed.scores = {"a": 5, "b": 9007199254740993}
	typed.points = {"p": Vector2(1.5, 2.5)}
	typed.ints = [4, 5, -6]
	typed.floats = [0.1, 1.0 / 3.0]
	typed.strings = ["1", "x", "forge_text:y"]
	typed.vecs = [Vector3(1, 2, 3)]
	typed.vecs2 = [Vector2(1, 2)]
	typed.colors = [Color.RED, Color(0.1, 0.2, 0.3, 0.4)]
	typed.nested = [[1, 2.0], ["a"], []]
	typed.mixed = {"t": "v", "n": 4, "f": true, "v": Vector2(1, 2), "l": [1, 2.0]}
	typed.path = NodePath("../x")
	typed.v2i = Vector2i(1, 2)
	typed.v4 = Vector4(1, 2, 3, 4)
	typed.flag = true
	samples.append({"name": "TypedModel", "script": TypedModel, "object": typed})

	samples.append({"name": "BuiltinPropsModel (every built-in type)", "script": BuiltinPropsModel, "object": BuiltinPropsModel.new()})

	var exact: ExactModel = ExactModel.new()
	exact.big = 9007199254740993
	exact.bigs = [9007199254740993, -9007199254740993, 5]
	exact.by_name = {"max": 9223372036854775807}
	exact.ids = PackedInt64Array([9007199254740993, 1])
	exact.floats = [1.0, 0.1, 3.141592653589793]
	exact.text = "Vector2(1, 2)"
	exact.texts = ["123", "true", "forge_text:", ""]
	exact.list = [5, 5.0, 2.5, -3, "123", "Rect2(1, 2, 3, 4)", null, true, [1, 2.0]]
	exact.dict = {"int": 1, "float": 1.0, 1: "int key", 1.5: "float key", true: "bool key", "1": "text key", "true": "text key", "forge_int:5": "lookalike", "nested": {"a": 1, "b": 2.0}}
	exact.any = 7.0
	samples.append({"name": "ExactModel (numbers, text, keys)", "script": ExactModel, "object": exact})

	var holder: InnerOwner = InnerOwner.new()
	holder.item = InnerOwner.SpecialItem.new()
	holder.item.label = "special"
	holder.items = [InnerOwner.Item.new(), InnerOwner.SpecialItem.new()]
	holder.by_name = {"a": InnerOwner.Item.new()}
	samples.append({"name": "InnerOwner (inner classes)", "script": InnerOwner, "object": holder})

	var user: UserDto = UserDto.new()
	user.id = 7
	user.user_name = "ann"
	user.score = 2.0
	user.tags = ["a", "b"]
	user.address = AddressDto.new()
	user.address.city = "Tokyo"
	user.meta = {"count": 5, "ratio": 2.0, "1": "one", "text": "Vector2(1, 2)", "list": [1, 2.5, "3"]}
	user.position = Vector2(1, 2)
	user.color = Color.RED
	user.role = UserDto.Role.ADMIN
	user.big_id = 123456789
	user.friends = [UserDto.new()]
	samples.append({"name": "UserDto (plain JSON)", "script": UserDto, "object": user, "plain": true})

	var saved: SavedUserDto = SavedUserDto.new()
	saved.user_name = "bob"
	saved.meta = {"count": 5, "ratio": 2.0, "1": "one", 7: "seven"}
	saved.position = Vector2(3, 4)
	saved.big_id = 9007199254740993
	samples.append({"name": "SavedUserDto (same data, exact format)", "script": SavedUserDto, "object": saved})

	var builtins: BuiltinsModel = BuiltinsModel.new()
	builtins.any = Rect2(1, 2, 3, 4)
	builtins.arr = [Rect2(1, 2, 3, 4), Transform3D(), Quaternion(), Color.RED, PackedByteArray([1, 2, 250]), PackedStringArray(["a"]), PackedVector2Array([Vector2(1, 2)]), Vector2i(1, 2), rex]
	builtins.dict = {"r": Rect2(1, 2, 3, 4), "nested": {"basis": Basis.IDENTITY, "list": [Rect2i(1, 2, 3, 4)]}, "dog": rex}
	builtins.typed_rects = [Rect2(1, 2, 3, 4)]
	samples.append({"name": "BuiltinsModel (built-in types in untyped places)", "script": BuiltinsModel, "object": builtins})

	var textures: TexHolder = TexHolder.new()
	var icon: Texture2D = load("res://icon.svg")
	textures.single = icon
	textures.textures = [icon, icon]
	textures.by_name = {"icon": icon}
	textures.untyped = [icon]
	samples.append({"name": "TexHolder (resources from files)", "script": TexHolder, "object": textures})

	var modes: ModeModel = ModeModel.new()
	modes.mode = ModeModel.Mode.VERY_SLOW_MODE
	samples.append({"name": "ModeModel (enum with custom values)", "script": ModeModel, "object": modes})

	var collection: Collection = Collection.new()
	collection.texture = icon
	for i: int in 3:
		var model: Model = Model.new()
		model.modelName = "Model %d" % i
		model.modelID = i * 10
		model.arrayOfVectors = [Vector3(i, i, i)]
		model.arrayOfColors = [Color.YELLOW]
		model.dictionary_var = {"key": i, "flag": true, "nested": {"x": 1.5}}
		model.enum_var = Model.MyEnum.OPTION_C
		model.arrayOfInnerModels = [InnerModel.new()]
		collection.modelCollection.append(model)
		collection.modelDict["m%d" % i] = model
	collection.model = collection.modelCollection[0]
	samples.append({"name": "Collection (nested models, shared objects, texture)", "script": Collection, "object": collection})
	return samples

#endregion


#region The chain on one sample

## Plain JSON has no markers, so a float like 2.0 in a free-form place comes back as 2: equal as JSON, not as text.
func _check_chain(sample_name: String, script: Script, object: Object, plain: bool) -> void:
	var file_name: String = sample_name.get_slice(" ", 0)
	var first: String = TMP_DIR + file_name + "_1.json"
	var second: String = TMP_DIR + file_name + "_2.json"

	TestUtil.check(ForgeJSONGD.store_json_file(first, ForgeJSONGD.class_to_json(object)), "[%s] the file is created" % sample_name)
	var text: String = FileAccess.get_file_as_string(first)
	TestUtil.check(JSON.parse_string(text) is Dictionary, "[%s] the file holds a JSON object" % sample_name)

	var loaded: Object = ForgeJSONGD.json_file_to_class(script, first)
	TestUtil.check(loaded != null and loaded.get_script() == script, "[%s] the file loads into the class" % sample_name)

	# Compared with the original object, with the loaded object, and the two objects with each other.
	TestUtil.check(ForgeJSONGD.check_equal_jsons(first, object), "[%s] the file equals the original object" % sample_name)
	TestUtil.check(ForgeJSONGD.check_equal_jsons(first, loaded), "[%s] the file equals the loaded object" % sample_name)
	TestUtil.check(ForgeJSONGD.check_equal_jsons(object, loaded), "[%s] the original and the loaded object are equal" % sample_name)
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(first, loaded).is_empty() and ForgeJSONGD.compare_jsons_diff(object, loaded).is_empty(), "[%s] there is no difference" % sample_name)

	# Saving what was loaded gives the very same file, and the same text.
	ForgeJSONGD.store_json_file(second, ForgeJSONGD.class_to_json(loaded))
	TestUtil.check(plain or FileAccess.get_file_as_string(second) == text, "[%s] saving the loaded object again gives an identical file" % sample_name)
	TestUtil.check(ForgeJSONGD.check_equal_jsons(first, second), "[%s] the two files are equal" % sample_name)
	TestUtil.check(plain or ForgeJSONGD.class_to_json_string(object) == ForgeJSONGD.class_to_json_string(loaded), "[%s] the JSON text of both objects is identical" % sample_name)

	# A third generation is still the same: nothing drifts.
	var third_object: Object = ForgeJSONGD.json_file_to_class(script, second)
	TestUtil.check(ForgeJSONGD.check_equal_jsons(third_object, object) and (plain or ForgeJSONGD.class_to_json_string(third_object) == ForgeJSONGD.class_to_json_string(object)), "[%s] nothing drifts after two more round trips" % sample_name)

#endregion


#region The other routes: text and dictionary

func _check_text_and_dictionary_routes() -> void:
	var rex: Dog = Dog.new()
	rex.name = "Rex"
	var zoo: Zoo = Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, Cat.new()]
	var dictionary: Dictionary = ForgeJSONGD.class_to_json(zoo)
	var text: String = ForgeJSONGD.class_to_json_string(zoo)
	var via_text: Zoo = ForgeJSONGD.json_string_to_class(Zoo, text)
	var via_dictionary: Zoo = ForgeJSONGD.json_to_class(Zoo, dictionary)
	var via_json_parse: Zoo = ForgeJSONGD.json_to_class(Zoo, JSON.parse_string(text))
	TestUtil.check(ForgeJSONGD.class_to_json_string(via_text) == text and ForgeJSONGD.class_to_json_string(via_dictionary) == text and ForgeJSONGD.class_to_json_string(via_json_parse) == text, "text, dictionary and parsed text give the same object")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(text, dictionary) and ForgeJSONGD.check_equal_jsons(zoo, text) and ForgeJSONGD.check_equal_jsons(dictionary, via_text), "text, dictionary and objects compare equal with each other")
	# Loading without a class: the class comes from the file.
	var with_class: Dictionary = ForgeJSONGD.class_to_json(zoo, true)
	var any_zoo: Object = ForgeJSONGD.json_to_class(null, with_class)
	TestUtil.check(any_zoo is Zoo and ForgeJSONGD.class_to_json_string(any_zoo) == text, "loading without a class gives an equal object")
	# Encrypted files hold the same data.
	ForgeJSONGD.store_json_file(TMP_DIR + "secret.json", dictionary, "key")
	TestUtil.check(ForgeJSONGD.json_file_to_dict(TMP_DIR + "secret.json", "key") == ForgeJSONGD.json_file_to_dict(TMP_DIR + "secret.json", "key") and ForgeJSONGD.check_equal_jsons(ForgeJSONGD.json_file_to_dict(TMP_DIR + "secret.json", "key"), dictionary), "an encrypted file loads as the same data")
	TestUtil.check(ForgeJSONGD.class_to_json_string(ForgeJSONGD.json_file_to_class(Zoo, TMP_DIR + "secret.json", "key")) == text, "and into an equal object")

	# Godot's JSON.stringify writes a vertical tab (character 11) as "\v", which is not JSON: the file could not be read.
	var vertical_tab: String = String.chr(11)
	for text_value: String in ["a" + vertical_tab + "b", "back\\v", "back\\" + vertical_tab, "\\\\v" + vertical_tab]:
		var player: PlayerData = PlayerData.new()
		player.name = text_value
		player.inventory = [text_value]
		ForgeJSONGD.store_json_file(TMP_DIR + "vertical_tab.json", ForgeJSONGD.class_to_json(player))
		var from_file: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, TMP_DIR + "vertical_tab.json")
		var from_text: PlayerData = ForgeJSONGD.json_string_to_class(PlayerData, ForgeJSONGD.class_to_json_string(player))
		TestUtil.check(from_file.name == text_value and from_file.inventory == [text_value] and from_text.name == text_value, "text with a vertical tab or \\v is saved as valid JSON and loads back (%s)" % text_value.c_escape())
		TestUtil.check(ForgeJSONGD.check_equal_jsons(player, TMP_DIR + "vertical_tab.json"), "and compares equal (%s)" % text_value.c_escape())

#endregion


#region A change is reported exactly

func _check_changes_are_reported() -> void:
	var player: PlayerData = PlayerData.new()
	player.name = "Bob"
	player.score = 100
	player.inventory = ["Sword"]
	var original: Dictionary = ForgeJSONGD.class_to_json(player)

	var changes: Dictionary = {
		"name": "Alice",
		"score": 101,
		"inventory": ["Sword", "Potion"],
	}
	for field: String in changes:
		var changed: PlayerData = ForgeJSONGD.json_to_class(PlayerData, original)
		changed.set(field, changes[field])
		var diff: Dictionary = ForgeJSONGD.compare_jsons_diff(player, changed)
		TestUtil.check(diff.keys() == [field], "changing only '%s' reports only '%s'" % [field, field])
		TestUtil.check(not ForgeJSONGD.check_equal_jsons(player, changed) and not ForgeJSONGD.check_equal_jsons(original, changed), "and the two are no longer equal ('%s')" % field)
		TestUtil.check(diff[field].old == original[field], "the old value is the original one ('%s')" % field)

	# Nested change: one number deep inside a model.
	var collection: Collection = Collection.new()
	var model: Model = Model.new()
	model.modelName = "A"
	model.dictionary_var = {"deep": {"value": 1}}
	collection.modelCollection.append(model)
	var loaded: Collection = ForgeJSONGD.json_to_class(Collection, ForgeJSONGD.class_to_json(collection))
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(collection, loaded).is_empty(), "equal before the change")
	loaded.modelCollection[0].dictionary_var["deep"]["value"] = 2
	var nested_diff: Dictionary = ForgeJSONGD.compare_jsons_diff(collection, loaded)
	TestUtil.check(nested_diff.keys() == ["modelCollection"], "a change deep inside is reported on the top-level key")

	# int/float, key order and NodePath/text are not differences; text vs number is.
	TestUtil.check(ForgeJSONGD.check_equal_jsons({"a": 1, "b": [1, 2]}, {"b": [1.0, 2.0], "a": 1.0}), "1 and 1.0, and key order, are not differences")
	TestUtil.check(not ForgeJSONGD.check_equal_jsons({"a": 1}, {"a": "1"}) and not ForgeJSONGD.check_equal_jsons({"a": [1, 2]}, {"a": [2, 1]}), "text vs number and array order are differences")

#endregion
