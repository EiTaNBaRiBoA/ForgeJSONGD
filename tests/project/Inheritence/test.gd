extends Node2D

const SAVE_GAME_PATH = "user://save_test.json"


func _ready() -> void:
	test_child_in_parent_property()
	test_polymorphic_containers()
	TestUtil.finish("Inheritance")


func make_child(prop: String) -> MyChildClass:
	var child: MyChildClass = MyChildClass.new()
	child.my_child_prop = prop
	child.my_super_prop = "super_" + prop
	return child


func make_super(prop: String) -> MySuperClass:
	var base: MySuperClass = MySuperClass.new()
	base.my_super_prop = prop
	return base


func test_child_in_parent_property() -> void:
	var save: Save = Save.new()
	save.child_class = make_child("child_prop")

	var json: Dictionary = ForgeJSONGD.class_to_json(save)
	TestUtil.check(ForgeJSONGD.store_json_file(SAVE_GAME_PATH, json), "inheritance file is stored")

	# The member is typed as MySuperClass, the stored script must bring back the MyChildClass instance.
	var return_class: Save = ForgeJSONGD.json_file_to_class(Save, SAVE_GAME_PATH)
	TestUtil.check(return_class.child_class is MyChildClass, "child class type is restored")
	var loaded_child: MyChildClass = return_class.child_class as MyChildClass
	TestUtil.check(loaded_child != null and loaded_child.my_child_prop == "child_prop", "child property round-trips")
	TestUtil.check(return_class.child_class.my_super_prop == "super_child_prop", "super property round-trips")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(save, return_class), "loaded save equals the original")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(save, return_class).is_empty(), "no diff between the original and the loaded save")

	# A plain parent instance must stay a parent, not become a child.
	var base_save: Save = Save.new()
	base_save.child_class = make_super("only_super")
	var loaded_base: Save = ForgeJSONGD.json_string_to_class(Save, ForgeJSONGD.class_to_json_string(base_save))
	TestUtil.check(not (loaded_base.child_class is MyChildClass), "a parent instance is not turned into a child")
	TestUtil.check(loaded_base.child_class.my_super_prop == "only_super", "parent property round-trips")


func test_polymorphic_containers() -> void:
	var original: PolymorphicSave = PolymorphicSave.new()
	original.single = make_child("single")
	original.typed_items = [make_super("a"), make_child("b"), make_super("c"), make_child("d")]
	original.untyped_items = [make_super("e"), make_child("f")]
	original.typed_dict = {"parent": make_super("g"), "child": make_child("h")}
	original.untyped_dict = {"parent": make_super("i"), "child": make_child("j")}
	original.nested = Save.new()
	original.nested.child_class = make_child("nested")

	var loaded: PolymorphicSave = ForgeJSONGD.json_string_to_class(PolymorphicSave, ForgeJSONGD.class_to_json_string(original))
	TestUtil.check(loaded.single is MyChildClass, "child in a parent-typed property")
	TestUtil.check(loaded.typed_items.size() == 4, "typed array keeps all elements")
	TestUtil.check(not (loaded.typed_items[0] is MyChildClass) and loaded.typed_items[1] is MyChildClass, "typed array keeps parent and child elements apart")
	TestUtil.check(loaded.typed_items[3] is MyChildClass and loaded.typed_items[3].my_child_prop == "d", "typed array child keeps its child property")
	TestUtil.check(loaded.untyped_items[1] is MyChildClass and not (loaded.untyped_items[0] is MyChildClass), "untyped array keeps parent and child elements apart")
	TestUtil.check(loaded.typed_dict["child"] is MyChildClass and not (loaded.typed_dict["parent"] is MyChildClass), "typed dictionary keeps parent and child values apart")
	TestUtil.check(loaded.typed_dict["child"].my_child_prop == "h", "typed dictionary child keeps its child property")
	TestUtil.check(loaded.untyped_dict["child"] is MyChildClass and not (loaded.untyped_dict["parent"] is MyChildClass), "untyped dictionary keeps parent and child values apart")
	TestUtil.check(loaded.nested.child_class is MyChildClass, "child inside a nested object")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(original, loaded), "polymorphic save equals the loaded one")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(original, loaded).is_empty(), "no diff between the original and the loaded polymorphic save")

	# The same through a file, and loading without a type hint.
	ForgeJSONGD.store_json_file(SAVE_GAME_PATH, ForgeJSONGD.class_to_json(original, true))
	var from_file: PolymorphicSave = ForgeJSONGD.json_file_to_class(null, SAVE_GAME_PATH)
	TestUtil.check(from_file is PolymorphicSave and from_file.typed_items[1] is MyChildClass, "polymorphic save loads from a file without a type hint")
