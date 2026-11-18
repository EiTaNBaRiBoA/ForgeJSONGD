extends Node
class_name EnumTest


class testB:
	enum MyEnum { A=3, B=2, C=1 }
@export var my_enum: testB.MyEnum = testB.MyEnum.C
enum MyEnum2 { A, B, C }
@export var my_enum2: MyEnum2 = MyEnum2.A
const SAVE_GAME_PATH = "user://save_test.json"


func _ready() -> void:
	var json: Dictionary = ForgeJSONGD.class_to_json(self)
	TestUtil.check(json.get("my_enum") is String, "enum is stored as its key name")
	TestUtil.check(json.get("my_enum2") is String, "enum with default values is stored as its key name")
	TestUtil.check(ForgeJSONGD.store_json_file(SAVE_GAME_PATH, json), "enum file is stored")

	var return_class: EnumTest = ForgeJSONGD.json_file_to_class(EnumTest, SAVE_GAME_PATH)
	TestUtil.check(return_class.my_enum == my_enum, "enum with custom values round-trips")
	TestUtil.check(return_class.my_enum2 == my_enum2, "enum with default values round-trips")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(self, return_class), "loaded enum test equals the original")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(self, return_class).is_empty(), "no diff between the original and the loaded enum test")
	return_class.free()
	TestUtil.finish("Enum")
