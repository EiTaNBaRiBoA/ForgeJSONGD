## Bugs found by the code review: data of an unexpected shape must not crash, and initialized members keep polymorphism.
extends Node


func _ready() -> void:
	test_text_that_is_not_an_object()
	test_initialized_members()
	test_empty_nested_objects()
	test_odd_class_names_and_keys()
	test_stored_constructor_arguments()
	test_many_objects()
	test_enums_without_values()
	test_broken_hooks_do_not_leak_plain_mode()
	test_objects_freed_by_hand()
	test_safe_saving()
	TestUtil.finish("Robustness", get_tree())


#region Text that is not a JSON object

func test_text_that_is_not_an_object() -> void:
	for text: String in ["[1, 2]", "5", "\"text\"", "null", "true", "", "{ broken"]:
		TestUtil.check(ForgeJSONGD.json_string_to_class(Save, text) == null, "json_string_to_class gives null for '%s'" % text)
		TestUtil.check(ForgeJSONGD.json_string_to_class(UserDto, text) == null, "and for a plain class")
	TestUtil.check(ForgeJSONGD.json_string_to_class(Save, "{}") is Save, "an empty object gives an instance")
	# The compare functions take text too: something that is not an object is treated as a file path, and a missing file is empty.
	TestUtil.check(ForgeJSONGD.check_equal_jsons("[1, 2]", {}), "text that is not an object compares like an empty file")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(5, {}).is_empty(), "something that is not text, an object or a dictionary compares like an empty one")

#endregion


#region Members that already hold an object

func test_initialized_members() -> void:
	var dog: Dog = Dog.new()
	dog.name = "Rex"
	dog.tricks = ["sit"]
	var zoo: InitializedZoo = InitializedZoo.new()
	zoo.star = dog
	zoo.home.city = "Tokyo"
	var json: Dictionary = ForgeJSONGD.class_to_json(zoo)
	TestUtil.check(json["star"]["script_inheritance"] == "Dog", "the child class is written")
	for loaded: InitializedZoo in [ForgeJSONGD.json_to_class(InitializedZoo, json), ForgeJSONGD.json_string_to_class(InitializedZoo, ForgeJSONGD.class_to_json_string(zoo))]:
		TestUtil.check(loaded.star is Dog and (loaded.star as Dog).tricks == ["sit"] and loaded.star.name == "Rex", "a member that already holds a parent object loads as the child class named in the JSON")
		TestUtil.check(loaded.home.city == "Tokyo", "and a member of the same class is filled")
	# Without a class name in the JSON the class of the object the member holds is used.
	var plain: InitializedZoo = ForgeJSONGD.json_to_class(InitializedZoo, {"star": {"name": "Plain"}})
	TestUtil.check(plain.star.get_script() == Animal and plain.star.name == "Plain", "without a class name the member keeps its class")
	# Plain JSON never names a class, even when the member holds an object.
	var from_server: ApiInitializedZoo = ForgeJSONGD.json_to_class(ApiInitializedZoo, {"star": {"name": "Hostile", "script_inheritance": "Dog"}})
	TestUtil.check(from_server.star.get_script() == Animal and from_server.star.name == "Hostile", "plain JSON ignores the class name and keeps the class of the member")

#endregion


#region Empty nested objects

func test_empty_nested_objects() -> void:
	var user: UserDto = ForgeJSONGD.json_to_class(UserDto, {"address": {}})
	TestUtil.check(user.address is AddressDto and user.address.city == "", "an empty object creates the declared object with its defaults (plain class)")
	var normal: UserDto = ForgeJSONGD.json_to_class(SavedUserDto, {"address": {}})
	TestUtil.check(normal.address is AddressDto, "an empty object creates the declared object with its defaults (class that is not plain)")
	var nothing: UserDto = ForgeJSONGD.json_to_class(UserDto, {"address": null})
	TestUtil.check(nothing.address == null, "a null keeps the member as it is")
	var in_array: UserDto = ForgeJSONGD.json_to_class(UserDto, {"friends": [{}, {"id": 2}]})
	TestUtil.check(in_array.friends.size() == 2 and in_array.friends[0] is UserDto and in_array.friends[1].id == 2, "an empty object in an array creates an object")

#endregion


#region Odd class names and keys

func test_odd_class_names_and_keys() -> void:
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {"script_inheritance": 5})), "a class name that is not text gives a plain Object")
	TestUtil.check(TestUtil.is_plain_object(ForgeJSONGD.json_to_class(null, {"script_inheritance": null})), "a null class name gives a plain Object")
	var zoo: Zoo = ForgeJSONGD.json_to_class(Zoo, {"star": {"script_inheritance": 5, "name": "x"}, "animals": [{"script_inheritance": ["Dog"]}]})
	TestUtil.check(zoo.star is Animal and zoo.star.name == "x" and zoo.animals[0] is Animal, "a class name that is not text uses the declared class")
	var odd_keys: UserDto = ForgeJSONGD.json_to_class(UserDto, {1: "ignored", Vector2(1, 2): "ignored", "id": 3})
	TestUtil.check(odd_keys.id == 3, "keys that are not text are skipped when loading a class")
	TestUtil.check(ForgeJSONGD.json_to_class(UserDto, {2: "x", "id": 4}).id == 4, "also for a plain class")
	TestUtil.check(ForgeJSONGD.check_equal_jsons({"a": 1}, {"a": 1}) and not ForgeJSONGD.check_equal_jsons(null, {"a": 1}), "check_equal_jsons accepts any value without failing")

#endregion


#region Many objects

func test_stored_constructor_arguments() -> void:
	# Arguments stored in the data are only passed to _init by a class that gives its own (_forge_constructor_args).
	TestUtil.check(ForgeJSONGD.json_to_class(ArgsNoHook, {"script_constructor_args": [99]}).count == 7, "stored arguments are ignored by a class without _forge_constructor_args")
	var weapon: Weapon = ForgeJSONGD.json_to_class(Weapon, {"script_constructor_args": [25, "Sword"]})
	TestUtil.check(weapon.damage == 25 and weapon.title == "Sword", "and used by a class that has it")
	TestUtil.check(ForgeJSONGD.json_to_class(ArgsNoHook, {"script_inheritance": "ArgsNoHook", "script_constructor_args": [99]}).count == 7, "also when the class is named in the data")


func test_many_objects() -> void:
	var zoo: Zoo = Zoo.new()
	for i: int in 2000:
		var dog: Dog = Dog.new()
		dog.name = "Dog %d" % i
		var animal: Animal = dog
		if i % 2 == 1:
			animal = Cat.new()
		zoo.animals.append(animal)
	var started: int = Time.get_ticks_msec()
	var text: String = ForgeJSONGD.class_to_json_string(zoo)
	var loaded: Zoo = ForgeJSONGD.json_string_to_class(Zoo, text)
	var elapsed: int = Time.get_ticks_msec() - started
	TestUtil.check(loaded.animals.size() == 2000 and loaded.animals[0] is Dog and loaded.animals[1] is Cat and loaded.animals[1998].name == "Dog 1998", "2000 child objects round-trip")
	print("2000 child objects saved and loaded in %d ms" % elapsed)
	TestUtil.check(elapsed < 5000, "2000 child objects take well under 5 seconds (%d ms)" % elapsed)

#endregion


#region Enums made with @export_enum

## An enum without values ("Warrior,Mage,Thief") was always saved as its last name and loaded as 0.
func test_enums_without_values() -> void:
	var model: JobModel = JobModel.new()
	var json: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.job == "Warrior" and json.speed == "Slow" and json.mixed == "Low" and json.hero == "Rebecca", "enum defaults are saved by their own name (%s)" % str(json))
	model.job = 1
	model.speed = 200
	model.mixed = 6
	model.hero = "Leah"
	json = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.job == "Mage", "an enum without values is saved by the name at its position (%s)" % json.job)
	TestUtil.check(json.speed == "Very_Fast", "an enum with values, and a space in the name (%s)" % json.speed)
	TestUtil.check(json.mixed == "Next", "a name without a value comes after the value before it (%s)" % json.mixed)
	TestUtil.check(json.hero == "Leah", "an @export_enum on a String is plain text")
	var loaded: JobModel = ForgeJSONGD.json_to_class(JobModel, JSON.parse_string(JSON.stringify(json)))
	TestUtil.check(loaded.job == 1 and loaded.speed == 200 and loaded.mixed == 6 and loaded.hero == "Leah", "and every one of them loads back (%d, %d, %d)" % [loaded.job, loaded.speed, loaded.mixed])
	model.job = 2
	model.mixed = 7
	loaded = ForgeJSONGD.json_string_to_class(JobModel, ForgeJSONGD.class_to_json_string(model))
	TestUtil.check(loaded.job == 2 and loaded.mixed == 7, "the last names too (Thief = 2, After = 7)")
	loaded = ForgeJSONGD.json_to_class(JobModel, {"job": "thief", "speed": "VERY FAST", "mixed": 6})
	TestUtil.check(loaded.job == 2 and loaded.speed == 200 and loaded.mixed == 6, "loading ignores capitals, reads a space or _, and takes a number")
	model.job = 9
	TestUtil.check(ForgeJSONGD.json_to_class(JobModel, {"job": "Bard"}).job == 0, "an unknown name loads as 0 (as before)")

	# A number that is none of the enum's values has no name. It was left out of the JSON (and lost); now the number is kept.
	var json_with_number: Dictionary = ForgeJSONGD.class_to_json(model)
	TestUtil.check(json_with_number.job == 9 and typeof(json_with_number.job) == TYPE_INT, "a value without a name is saved as its number (%s)" % str(json_with_number.get("job")))
	TestUtil.check((ForgeJSONGD.json_string_to_class(JobModel, ForgeJSONGD.class_to_json_string(model)) as JobModel).job == 9, "and loads back")
	var mode_model: ModeModel = ModeModel.new()
	mode_model.set("mode", 3) # not a value of the enum: FAST_MODE = 0, SLOW_MODE = 5, VERY_SLOW_MODE = 7
	TestUtil.check(ForgeJSONGD.class_to_json(mode_model).mode == 3 and (ForgeJSONGD.json_string_to_class(ModeModel, ForgeJSONGD.class_to_json_string(mode_model)) as ModeModel).mode == 3, "the same for an enum type with values")
	TestUtil.check(ForgeJSONGD.validate_json(mode_model, ModeModel).map(func(error: Dictionary) -> String: return error.path + " " + error.keyword) == ["/mode enum"], "validation reports such a number: it is not a value of the enum")
	TestUtil.check(ForgeJSONGD.class_to_json_schema(JobModel)["$defs"]["JobModel"].properties.job.enum == ["Warrior", "WARRIOR", "Mage", "MAGE", "Thief", "THIEF"], "the schema lists the names")
	model.job = 1
	TestUtil.check(ForgeJSONGD.validate_json(model, JobModel).is_empty(), "and its JSON passes it")

#endregion


#region A hook that fails must not switch plain JSON on for everything that follows

## A hook that returned the wrong type stopped loading half way and left plain mode on: later saves lost their markers.
## (Each broken hook prints one SCRIPT ERROR, on purpose.)
func test_broken_hooks_do_not_leak_plain_mode() -> void:
	var exact: ExactModel = ExactModel.new()
	exact.any = 7.0
	var expected: String = ForgeJSONGD.class_to_json_string(exact)
	TestUtil.check(expected.contains("forge_float"), "a save-file class writes its markers")
	for broken_hook: String in ["excluded", "renamed", "keys"]:
		var broken: BrokenHookDto = BrokenHookDto.new()
		broken.broken_hook = broken_hook
		ForgeJSONGD.class_to_json(broken)
		TestUtil.check(ForgeJSONGD.class_to_json_string(exact) == expected, "after saving a plain class with a broken '%s' hook, other classes are saved as before" % broken_hook)
		ForgeJSONGD.json_to_class(broken, {"value": 1})
		TestUtil.check(ForgeJSONGD.class_to_json_string(exact) == expected, "after loading it too")
		var reloaded: ExactModel = ForgeJSONGD.json_string_to_class(ExactModel, expected)
		TestUtil.check(reloaded.any is float and ForgeJSONGD.class_to_json_string(reloaded) == expected, "and they load as before")

#endregion


#region Classes that Godot does not free by itself (extend Object or Node)

## Points at an object it does not own (shared), and creates one of its own.
class SharingOwner extends Object:
	static var common: ManualChild = null
	var shared: ManualChild = common
	var own: ManualChild = ManualChild.new()


class ItemListOwner extends RefCounted:
	var items: Array[ManualChild] = []


## A tree of objects, 4 levels deep: member object -> array -> member object -> dictionary -> array.
func _deep_tree(number: int) -> ManualTree:
	var root: ManualTree = _tree_node("root", number)
	root.child = _tree_node("child", number + 1)
	root.child.items = [_tree_node("item 0", number + 2), _tree_node("item 1", number + 3)]
	root.child.items[1].child = _tree_node("deep child", number + 4)
	root.child.items[1].child.by_name = {"key": _tree_node("deepest", number + 5)}
	root.child.items[1].child.by_name["key"].items = [_tree_node("leaf", number + 6)]
	root.items = [_tree_node("top item", number + 7)]
	return root


func _tree_node(label: String, value: int) -> ManualTree:
	var node: ManualTree = ManualTree.new()
	node.label = label
	node.value = value
	return node


## Remembers every object of a tree, to free them all at the end: the elements of an array or dictionary are replaced
## by new objects when the array is loaded again, and the ones it held before belong to the code that made them.
func _remember_tree(node: ManualTree, all_nodes: Dictionary) -> void:
	if node == null:
		return
	all_nodes[node] = true # a kept object is walked again: what it holds may be new
	_remember_tree(node.child, all_nodes)
	for item: ManualTree in node.items:
		_remember_tree(item, all_nodes)
	for item: ManualTree in node.by_name.values():
		_remember_tree(item, all_nodes)


## Loading does not look for what changed: it writes every value of the JSON at every level. An object that is
## filled where it is still gets every change inside it, however deep (also inside arrays and dictionaries).
func _check_deep_changes_are_loaded() -> void:
	var all_nodes: Dictionary = {}
	var first: ManualTree = _deep_tree(100)
	var existing: ManualTree = ForgeJSONGD.json_to_class(ManualTree, ForgeJSONGD.class_to_json(first))
	_remember_tree(existing, all_nodes)
	var kept_child: ManualTree = existing.child
	TestUtil.check(ForgeJSONGD.check_equal_jsons(existing, first), "a tree 4 levels deep loads")

	# Another tree: every number differs, one array is longer, one is shorter, a deep object is gone, a key is new.
	var second: ManualTree = _deep_tree(500)
	_remember_tree(second, all_nodes) # before the test takes objects out of its arrays
	second.child.items.append(_tree_node("item 2", 999))
	second.child.items[1].child.by_name["key"].items.clear()
	second.child.items[1].child.by_name["new key"] = _tree_node("added", 7)
	second.child.items[0].label = "renamed"
	second.items.clear()
	var second_json: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(second))
	ForgeJSONGD.json_to_class(existing, second_json)
	_remember_tree(existing, all_nodes)
	TestUtil.check(existing.child == kept_child, "the member object is the same object as before (filled where it is)")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(existing, second) and ForgeJSONGD.compare_jsons_diff(existing, second).is_empty(), "and after loading other data into it, every level holds the new data (%s)" % str(ForgeJSONGD.compare_jsons_diff(existing, second)))
	var deep: ManualTree = existing.child.items[1].child
	TestUtil.check(existing.value == 500 and existing.child.value == 501 and existing.child.items[0].label == "renamed" and existing.child.items[1].value == 503, "changed values: levels 1, 2 and 3")
	TestUtil.check(deep.value == 504 and deep.by_name["key"].value == 505 and deep.by_name["new key"].label == "added", "changed and added values: levels 4 and 5, inside a dictionary")
	TestUtil.check(existing.child.items.size() == 3 and existing.child.items[2].value == 999 and deep.by_name["key"].items.is_empty() and existing.items.is_empty(), "arrays that grew, shrank and were emptied")

	# One number changed 5 levels down: it arrives, and nothing else moves.
	second_json.child.items[1].child.by_name["key"].value = 12345
	var before_change: Dictionary = ForgeJSONGD.class_to_json(existing)
	ForgeJSONGD.json_to_class(existing, second_json)
	TestUtil.check(existing.child.items[1].child.by_name["key"].value == 12345, "a single change 5 levels down is loaded")
	var difference: Dictionary = ForgeJSONGD.compare_jsons_diff(before_change, existing)
	TestUtil.check(difference.keys() == ["child"] and ForgeJSONGD.check_equal_jsons(existing, second_json), "and it is the only difference")

	# The same through a file, into a new object.
	ForgeJSONGD.store_json_file("user://robustness_tree.json", second_json)
	var from_file: ManualTree = ForgeJSONGD.json_file_to_class(ManualTree, "user://robustness_tree.json")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(from_file, existing) and from_file.child.items[1].child.by_name["key"].value == 12345, "a new object loaded from the file holds the same deep data")

	for tree: ManualTree in [first, second, existing, from_file]:
		_remember_tree(tree, all_nodes)
	for node: ManualTree in all_nodes:
		node.free()


func _object_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


## Loading replaced a member object with a new one and left the old one unfreed (one leaked object per member and
## per load, the usual case for C# classes with "= new()" members), and class_to_json_schema left the member
## objects of the instance it reads the class from.
func test_objects_freed_by_hand() -> void:
	var json: Dictionary = {"title": "t", "child": {"label": "loaded"}}

	# A new object: exactly the owner and its two members exist afterwards.
	var before: int = _object_count()
	var loaded: ManualOwner = ForgeJSONGD.json_to_class(ManualOwner, json)
	TestUtil.check(_object_count() - before == 3, "loading creates the owner and its 2 members, nothing more (%d)" % (_object_count() - before))
	TestUtil.check(loaded.title == "t" and loaded.child.label == "loaded" and loaded.child.amount == 1 and loaded.other.label == "default", "and they hold the data and the defaults")
	TestUtil.free_object(loaded)
	TestUtil.check(_object_count() == before, "freeing the loaded object and its members frees everything")

	# An existing object: its member is filled where it is, so other references to it stay valid.
	var existing: ManualOwner = ManualOwner.new()
	var child: ManualChild = existing.child
	child.amount = 50
	before = _object_count()
	ForgeJSONGD.json_to_class(existing, json)
	TestUtil.check(existing.child == child and is_instance_valid(child) and _object_count() == before, "a member that is not reference counted is filled where it is")
	TestUtil.check(child.label == "loaded" and child.amount == 50, "values from the JSON are set, the others are left alone (as for the object itself)")
	ForgeJSONGD.json_to_class(existing, {"child": null, "other": 5})
	TestUtil.check(existing.child == child and existing.other != null, "null or data of the wrong shape leaves the member as it is")
	ForgeJSONGD.json_string_to_class(existing, ForgeJSONGD.class_to_json_string(existing))
	TestUtil.check(existing.child == child and _object_count() == before, "saving and loading the same object again and again creates nothing")

	# The JSON names another class: the member is replaced by an object of that class, the old one is left to its owner.
	ForgeJSONGD.json_to_class(existing, {"child": {"script_inheritance": "ManualSpecialChild", "bonus": 4}})
	TestUtil.check(existing.child is ManualSpecialChild and (existing.child as ManualSpecialChild).bonus == 4 and is_instance_valid(child), "a member is replaced only when the JSON names another class (the old object is not freed for you)")
	child.free()
	# Elements of containers are new objects.
	var holder_of_list: ItemListOwner = ItemListOwner.new()
	var first_item: ManualChild = ManualChild.new()
	holder_of_list.items = [first_item]
	ForgeJSONGD.json_to_class(holder_of_list, {"items": [{"label": "a"}, {"label": "b"}]})
	TestUtil.check(holder_of_list.items.size() == 2 and holder_of_list.items[0] != first_item and holder_of_list.items[1].label == "b" and is_instance_valid(first_item), "the elements of an array are new objects")
	first_item.free()
	for item: ManualChild in holder_of_list.items:
		item.free()
	TestUtil.free_object(existing)

	_check_deep_changes_are_loaded()

	# Reference counted members are replaced by a new object, as before.
	var zoo: Zoo = Zoo.new()
	var first_star: Dog = Dog.new()
	first_star.tricks = ["sit"]
	zoo.star = first_star
	ForgeJSONGD.json_to_class(zoo, {"star": {"name": "New"}})
	TestUtil.check(zoo.star != first_star and zoo.star is Dog and zoo.star.name == "New" and (zoo.star as Dog).tricks.is_empty(), "a reference counted member is still replaced by a new object")

	# A Node that is in the scene tree stays the same node.
	var holder: NodeHolder = NodeHolder.new()
	add_child(holder)
	var sprite: SpriteState = holder.sprite
	ForgeJSONGD.json_to_class(holder, {"sprite": {"health": 3}})
	TestUtil.check(holder.sprite == sprite and sprite.is_inside_tree() and sprite.health == 3, "a member node in the scene tree is filled, not swapped for a node outside the tree")
	holder.free()

	# The schema of such a class: the instance it is read from is freed with the members it created.
	before = _object_count()
	var schema: Dictionary = ForgeJSONGD.class_to_json_schema(ManualOwner)
	TestUtil.check(schema["$defs"]["ManualOwner"].properties.child.get("$ref") == "#/$defs/ManualChild" and _object_count() == before, "class_to_json_schema leaves no object behind (%d)" % (_object_count() - before))
	SharingOwner.common = ManualChild.new()
	before = _object_count()
	ForgeJSONGD.class_to_json_schema(SharingOwner)
	TestUtil.check(_object_count() == before and is_instance_valid(SharingOwner.common), "and never frees an object the class only points to (shared between instances)")
	SharingOwner.common.free()

#endregion


#region Saving never leaves half a file

## A program can be stopped at any moment (Android ends a paused app), also while it saves. The file is
## written to "<path>.tmp" first and then renamed over the old one, so the file is always whole: the old
## data or the new.
func test_safe_saving() -> void:
	var path: String = "user://safe_saving/data.json"
	var tmp: String = path + ".tmp"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	for p: String in [path, tmp]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	TestUtil.check(ForgeJSONGD.store_json_file(path, {"n": 1}), "saving works")
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 1 and not FileAccess.file_exists(tmp), "the file holds the data, and no temporary file is left")
	TestUtil.check(ForgeJSONGD.store_json_file(path, {"n": 2}) and _n(ForgeJSONGD.json_file_to_dict(path)) == 2, "saving again replaces the old file")

	# Stopped after the new data was written and the old file removed, before the rename: loading uses the
	# whole new file and puts it in its place.
	DirAccess.remove_absolute(path)
	var whole: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	whole.store_string("{\"n\": 3}")
	whole.close()
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 3, "a load after a stop between the two steps gets the new data")
	TestUtil.check(FileAccess.file_exists(path) and not FileAccess.file_exists(tmp), "and the file is in its place again")

	# Stopped while the temporary file was being written: the old file is untouched and is what loads.
	var half: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	half.store_string("{\"n\": 4, \"li")
	half.close()
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 3, "a half-written temporary file does not replace the whole old file")
	TestUtil.check(ForgeJSONGD.store_json_file(path, {"n": 5}) and _n(ForgeJSONGD.json_file_to_dict(path)) == 5 and not FileAccess.file_exists(tmp), "the next save writes over it")

	# A save that cannot write leaves the old file as it was.
	DirAccess.make_dir_recursive_absolute(tmp)
	TestUtil.check(not ForgeJSONGD.store_json_file(path, {"n": 6}), "a save that cannot write its temporary file fails")
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 5, "and the old file is untouched")
	DirAccess.remove_absolute(tmp)

	# The same with a security key.
	TestUtil.check(ForgeJSONGD.store_json_file(path, {"n": 7}, "key") and _n(ForgeJSONGD.json_file_to_dict(path, "key")) == 7 and not FileAccess.file_exists(tmp), "an encrypted file is saved the same way")
	DirAccess.rename_absolute(path, tmp)
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path, "key")) == 7, "and found after a stop between the two steps")
	DirAccess.remove_absolute(path)

	# A rename can fail after the old file is gone (on Windows Godot's rename removes the old file
	# first, and the move fails while another program holds the new one). The whole new data is
	# then only in the temporary file: a load reads it even when it cannot rename it into place.
	var whole_new: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	whole_new.store_string("{\"n\": 8}")
	whole_new.close()
	var holder: FileAccess = FileAccess.open(tmp, FileAccess.READ)
	var moved: bool = DirAccess.rename_absolute(tmp, path) == OK
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 8, "a load reads the temporary file it cannot rename into place%s" % (" (the system let the rename through: nothing held)" if moved else ""))
	holder.close()
	TestUtil.check(_n(ForgeJSONGD.json_file_to_dict(path)) == 8 and FileAccess.file_exists(path) and not FileAccess.file_exists(tmp), "and puts it in place once it can")

	# A save whose rename fails never removes the old file itself: the old file stays while
	# another program holds it, and the save says it failed.
	var reader: FileAccess = FileAccess.open(path, FileAccess.READ)
	var saved: bool = ForgeJSONGD.store_json_file(path, {"n": 9})
	reader.close()
	var now: int = _n(ForgeJSONGD.json_file_to_dict(path))
	TestUtil.check((saved and now == 9) or (not saved and now == 8), "a save that cannot replace a held file keeps the old data (saved: %s, loaded %d)" % [saved, now])
	for p: String in [path, tmp]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)



## The "n" of a loaded file (JSON numbers come back as floats), or -1.
func _n(data: Dictionary) -> int:
	return int(data.get("n", -1))

#endregion
