## Script aliases, resources saved by path, extra built-in properties, renamed variables and output settings.
extends Node

const TMP_DIR = "user://options/"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	ForgeJSONGD.clear_script_aliases()
	test_aliases()
	test_save_by_path()
	test_extra_properties()
	test_renamed_properties()
	test_output_settings()
	TestUtil.finish("Options", get_tree())


func round_trip(script: Script, object: Object) -> Object:
	return ForgeJSONGD.json_string_to_class(script, ForgeJSONGD.class_to_json_string(object))


#region Script aliases

func test_aliases() -> void:
	var rex: Dog = Dog.new()
	rex.name = "Rex"
	var tom: Cat = Cat.new()
	var zoo: Zoo = Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, tom]
	zoo.by_name = {"tom": tom}

	TestUtil.check(ForgeJSONGD.class_to_json(rex, true)["script_inheritance"] == "Dog", "without an alias the class name is saved")
	ForgeJSONGD.register_script_alias(Dog, "dog_v1")
	ForgeJSONGD.register_script_alias(Cat, "cat_v1")
	TestUtil.check(ForgeJSONGD.class_to_json(rex, true)["script_inheritance"] == "dog_v1", "with an alias the alias is saved")
	var text: String = ForgeJSONGD.class_to_json_string(zoo)
	TestUtil.check(text.contains('"script_inheritance":"dog_v1"') and text.contains('"script_inheritance":"cat_v1"') and not text.contains('"Dog"'), "aliases are used in single variables, arrays and dictionaries")
	var loaded: Zoo = ForgeJSONGD.json_string_to_class(Zoo, text)
	TestUtil.check(loaded.star is Dog and loaded.animals[1] is Cat and loaded.by_name["tom"] is Cat, "child classes load through their aliases")
	TestUtil.check(ForgeJSONGD.json_to_class(null, ForgeJSONGD.class_to_json(rex, true)) is Dog, "loading without a class finds the alias")

	# The class is renamed in the code: the alias keeps old saves working. Here "dog_v1" stands for the old name.
	TestUtil.check(ForgeJSONGD.json_to_class(null, {"script_inheritance": "dog_v1", "name": "Old"}).name == "Old", "a save made under an alias loads")
	# A load-only alias for an old class name.
	ForgeJSONGD.register_script_alias(Dog, "Hound", false)
	TestUtil.check(ForgeJSONGD.json_to_class(null, {"script_inheritance": "Hound", "name": "Old"}) is Dog, "a load-only alias loads")
	TestUtil.check(ForgeJSONGD.class_to_json(rex, true)["script_inheritance"] == "dog_v1", "a load-only alias is never written")
	# Without an alias a script with no class_name is saved by path and uid; with one, only the alias.
	var plain_script: Script = load("res://Tests/Models/PlainScript.gd")
	var plain: Object = plain_script.new()
	TestUtil.check(ForgeJSONGD.class_to_json(plain, true).has("script_uid"), "a script without class_name stores its uid")
	ForgeJSONGD.register_script_alias(plain_script, "plain_v1")
	var plain_json: Dictionary = ForgeJSONGD.class_to_json(plain, true)
	TestUtil.check(plain_json["script_inheritance"] == "plain_v1" and not plain_json.has("script_uid"), "a script with an alias stores only the alias")
	TestUtil.check(ForgeJSONGD.json_to_class(null, plain_json).get_script() == plain_script, "a script without class_name loads through its alias")

	# Aliases and the allow-list are separate: an alias does not restrict anything.
	TestUtil.check(ForgeJSONGD.json_string_to_class(Zoo, text).animals[1] is Cat, "an alias does not turn on the allow-list")
	ForgeJSONGD.register_script(Dog)
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {"script_inheritance": "cat_v1"})), "with an allow-list, an alias of an unregistered script is not created")
	TestUtil.check(ForgeJSONGD.json_to_class(null, {"script_inheritance": "dog_v1"}) is Dog, "with an allow-list, an alias of a registered script loads")
	ForgeJSONGD.clear_registered_scripts()

	ForgeJSONGD.clear_script_aliases()
	TestUtil.check(ForgeJSONGD.class_to_json(rex, true)["script_inheritance"] == "Dog", "after clearing, the class name is saved again")
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {"script_inheritance": "dog_v1"})), "after clearing, the alias is no longer known")

#endregion


#region Resources saved by path

func test_save_by_path() -> void:
	var item: ItemResource = ItemResource.new()
	item.item_name = "Sword"
	var path: String = TMP_DIR + "sword.tres"
	ResourceSaver.save(item, path)
	var from_file: ItemResource = ResourceLoader.load(path)

	var holder: ItemHolder = ItemHolder.new()
	holder.item = from_file
	holder.items = [from_file, from_file]
	holder.by_slot = {"hand": from_file}
	holder.any = from_file
	var json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(holder))
	TestUtil.check(json["item"] == path and json["items"] == [path, path] and json["by_slot"] == {"hand": path}, "a resource that asks for it is saved as its path, in variables and typed containers")
	TestUtil.check(json["any"] == {"forge_resource_path": path}, "and as a marker holding the path in an untyped place")

	var loaded: ItemHolder = ForgeJSONGD.json_string_to_class(ItemHolder, JSON.stringify(json))
	TestUtil.check(loaded.item == from_file and loaded.items[0] == from_file and loaded.by_slot["hand"] == from_file and loaded.any == from_file, "the very same resource instance is loaded back, not a copy")
	TestUtil.check(loaded.item == loaded.items[1], "all references share one instance")

	# A change in the item file shows in the loaded save: the save only holds the path.
	var edited: ItemResource = ItemResource.new()
	edited.item_name = "Better Sword"
	ResourceSaver.save(edited, path)
	from_file.item_name = "Better Sword"
	TestUtil.check(loaded.item.item_name == "Better Sword", "changes to the resource are seen through the save")

	# Without the hook a .tres is saved inline, and a resource that was never saved to a file too.
	var not_in_file: ItemResource = ItemResource.new()
	not_in_file.item_name = "Loose"
	var loose: ItemHolder = ItemHolder.new()
	loose.item = not_in_file
	var loose_loaded: ItemHolder = round_trip(ItemHolder, loose)
	TestUtil.check(loose_loaded.item != null and loose_loaded.item.item_name == "Loose", "a resource that is not in a file is saved inline")
	var nested: NestedResource = NestedResource.new()
	nested.label = "inline"
	ResourceSaver.save(nested, TMP_DIR + "nested.tres")
	var inline: ItemHolder = ItemHolder.new()
	inline.copy = ResourceLoader.load(TMP_DIR + "nested.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	TestUtil.check(JSON.parse_string(ForgeJSONGD.class_to_json_string(inline))["copy"] is Dictionary, "a .tres without the hook is still saved inline")

	# The registry applies to resources loaded by path.
	ForgeJSONGD.register_script(MySuperClass)
	var blocked: ItemHolder = ForgeJSONGD.json_string_to_class(ItemHolder, JSON.stringify(json))
	ForgeJSONGD.clear_registered_scripts()
	TestUtil.check(blocked.item == null, "with an allow-list, a resource with an unregistered script is not loaded")

	# Plain JSON never loads files.
	TestUtil.check(ForgeJSONGD.json_to_class(ApiItemHolder, json).item == null, "a plain class does not load a resource named by a server")

#endregion


#region Extra built-in properties

func test_extra_properties() -> void:
	var sprite: SpriteState = SpriteState.new()
	sprite.health = 3
	sprite.position = Vector2(10, 20)
	sprite.rotation = 1.5
	sprite.scale = Vector2(2, 3)
	sprite.modulate = Color.RED
	var json: Dictionary = ForgeJSONGD.class_to_json(sprite)
	TestUtil.check(json.has("health") and json.has("position") and json.has("rotation") and json.has("scale") and json.has("modulate"), "script variables and the listed built-in properties are saved")
	TestUtil.check(not json.has("visible") and not json.has("z_index") and not json.has("name"), "other built-in properties are not saved")
	for loaded: SpriteState in [round_trip(SpriteState, sprite), ForgeJSONGD.json_to_class(SpriteState, json)]:
		TestUtil.check(loaded.health == 3 and loaded.position == Vector2(10, 20) and is_equal_approx(loaded.rotation, 1.5), "script variables, position and rotation are loaded")
		TestUtil.check(loaded.scale == Vector2(2, 3) and loaded.modulate == Color.RED, "scale and modulate are loaded")
		loaded.free()
	var fresh: SpriteState = ForgeJSONGD.json_to_class(SpriteState, {"position": {"x": 1, "y": 2}, "health": 9})
	TestUtil.check(fresh.position == Vector2(1, 2), "a position written as {x, y} loads too")
	fresh.free()
	var api_sprite: ApiSpriteState = ApiSpriteState.new()
	api_sprite.position = Vector2(10, 20)
	api_sprite.modulate = Color.RED
	var plain_json: Dictionary = ForgeJSONGD.class_to_json(api_sprite)
	api_sprite.free()
	TestUtil.check(plain_json["position"] == {"x": 10.0, "y": 20.0} and plain_json["modulate"] == "ff0000ff", "extra properties follow the plain format in a plain class")
	sprite.free()

#endregion


#region Renamed variables

func test_renamed_properties() -> void:
	TestUtil.check(ForgeJSONGD.json_to_class(RenamedModel, {"display_name": "now", "level": 3}).display_name == "now", "the current name loads")
	TestUtil.check(ForgeJSONGD.json_to_class(RenamedModel, {"name": "old", "level": 3}).display_name == "old", "an old name loads into the renamed variable")
	TestUtil.check(ForgeJSONGD.json_to_class(RenamedModel, {"title": "older"}).display_name == "older", "an even older name loads too")
	TestUtil.check(ForgeJSONGD.json_to_class(RenamedModel, {"name": "old", "display_name": "new"}).display_name == "new", "when both are in the file, the current name wins")
	TestUtil.check(ForgeJSONGD.json_to_class(RenamedModel, {"title": "t", "name": "n", "display_name": "new"}).display_name == "new", "also with two old names")
	var saved: Dictionary = ForgeJSONGD.class_to_json(RenamedModel.new())
	TestUtil.check(saved.has("display_name") and not saved.has("name") and not saved.has("title"), "saving always uses the current name")
	TestUtil.check(ForgeJSONGD.json_to_class(ApiRenamedModel, {"name": "old"}).display_name == "old", "renamed variables work in a plain class")
	# Together with _forge_json_keys: the API key wins, then the variable name, then the old names.
	TestUtil.check(ForgeJSONGD.json_to_class(UserDto, {"user_name": "by variable name"}).user_name == "by variable name", "a variable with a json key also loads under its own name")
	TestUtil.check(ForgeJSONGD.json_to_class(UserDto, {"user_name": "by variable name", "userName": "by key"}).user_name == "by key", "the json key wins over the variable name")

#endregion


#region Output settings

func test_output_settings() -> void:
	var order: OrderModel = OrderModel.new()
	TestUtil.check(ForgeJSONGD.class_to_json_string(order) == '{"alpha":"a","mid":true,"zeta":1}', "keys are sorted by default")
	ForgeJSONGD.sort_keys = false
	TestUtil.check(ForgeJSONGD.class_to_json_string(order) == '{"zeta":1,"alpha":"a","mid":true}', "with sort_keys off, keys follow the variables")
	ForgeJSONGD.store_json_file(TMP_DIR + "unsorted.json", ForgeJSONGD.class_to_json(order))
	var unsorted_text: String = FileAccess.get_file_as_string(TMP_DIR + "unsorted.json")
	TestUtil.check(unsorted_text.find("zeta") < unsorted_text.find("alpha") and unsorted_text.find("alpha") < unsorted_text.find("mid"), "files follow sort_keys too")
	ForgeJSONGD.sort_keys = true

	ForgeJSONGD.store_json_file(TMP_DIR + "tabs.json", ForgeJSONGD.class_to_json(order))
	TestUtil.check(FileAccess.get_file_as_string(TMP_DIR + "tabs.json") == '{\n\t"alpha": "a",\n\t"mid": true,\n\t"zeta": 1\n}', "files use a tab by default")
	ForgeJSONGD.json_indent = ""
	ForgeJSONGD.store_json_file(TMP_DIR + "compact.json", ForgeJSONGD.class_to_json(order))
	TestUtil.check(FileAccess.get_file_as_string(TMP_DIR + "compact.json") == '{"alpha":"a","mid":true,"zeta":1}', "an empty json_indent writes compact files")
	ForgeJSONGD.json_indent = "  "
	ForgeJSONGD.store_json_file(TMP_DIR + "spaces.json", ForgeJSONGD.class_to_json(order))
	TestUtil.check(FileAccess.get_file_as_string(TMP_DIR + "spaces.json") == '{\n  "alpha": "a",\n  "mid": true,\n  "zeta": 1\n}', "json_indent can be spaces")
	ForgeJSONGD.json_indent = "\t"
	for file_name: String in ["tabs.json", "compact.json", "spaces.json", "unsorted.json"]:
		TestUtil.check(ForgeJSONGD.json_file_to_class(OrderModel, TMP_DIR + file_name).zeta == 1, "%s loads" % file_name)

#endregion
