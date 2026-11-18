extends Node2D
class_name Typed

const SAVE_GAME_PATH = "user://typed_test.json"
@export var dic: Dictionary[int, String]
@export var dicObj: Dictionary[ClassA, ClassB]
@export var classA: ClassA = ClassA.new()
@export var arrayTyped: Array[ClassA]

var variant_json := {
	"typed_dict": {
		"string_val": "foo",
		false: "bool_val",
		"int_val": 5,
		"float_val": 5.2
	}
}


func _ready() -> void:
	var result: TestResource = ForgeJSONGD.json_to_class(TestResource, variant_json)
	TestUtil.check(result.typed_dict.size() == 4, "Variant-typed dictionary keeps all entries")
	TestUtil.check(result.typed_dict.get("string_val") == "foo", "Variant-typed dictionary string value")
	TestUtil.check(result.typed_dict.get(false) == "bool_val", "Variant-typed dictionary bool key")

	dic = {
		1: "Test1",
		2: "Test2",
		3: "Test3",
		4: "Test4",
	}
	dicObj = {
		ClassA.new(): ClassB.new()
	}
	arrayTyped.append(ClassA.new())
	var json: Dictionary = ForgeJSONGD.class_to_json(self)
	TestUtil.check(ForgeJSONGD.store_json_file(SAVE_GAME_PATH, json), "typed file is stored")

	var return_class: Typed = ForgeJSONGD.json_file_to_class(Typed, SAVE_GAME_PATH)
	TestUtil.check(return_class.dic == dic, "Dictionary[int, String] round-trips")
	TestUtil.check(return_class.dicObj.size() == 1, "Dictionary[ClassA, ClassB] keeps its entry")
	var class_a_test: ClassA = return_class.dicObj.keys()[0]
	TestUtil.check(class_a_test.classAProperty == "ClassAText", "Dictionary object key round-trips")
	TestUtil.check(return_class.arrayTyped.size() == 1, "Array[ClassA] round-trips")
	TestUtil.check(return_class.dicObj.values()[0] is ClassB, "Dictionary[ClassA, ClassB] value keeps its class")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(self, return_class), "loaded typed test equals the original")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(self, return_class).is_empty(), "no diff between the original and the loaded typed test")
	TestUtil.finish("Typed")
