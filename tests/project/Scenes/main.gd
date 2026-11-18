extends Control
class_name Main

const SAVE_PATH = "user://saves/collection_data.json"

@export var collection: Collection = Collection.new()
@export var texture: Texture2D


func _ready() -> void:
	populate_collection()
	test_round_trip()
	test_utilities()
	test_operations()
	TestUtil.finish("Main")


func populate_collection() -> void:
	collection.texture = texture
	for i in range(4):  # Create 3 models
		if i ==0:
			i+=1
		var new_model : Model = Model.new()
		new_model.modelName = "Model " + str(i + 1)
		new_model.modelID = i * 10
		new_model.modelVector2 = Vector2(i * 5, i * 10)
		new_model.modelVector3 = Vector3(i, i * 2, i * 3)
		new_model.arrayOfVectors = [Vector3(i*4, i*5, i*6), Vector3(7, 8, 9)]
		new_model.arrayOfColors = [Color.YELLOW, Color.GREEN]
		new_model.arrayOfVectors2 = [Vector2i(4, 5), Vector2i(7, 8)]
		new_model.bool_var = true
		new_model.int_var = 99
		new_model.float_var = 6.28
		new_model.string_var = "Goodbye, World!"
		new_model.vector2_var = Vector2(randi() % 10 + 1, randi() % 10 + 1)
		new_model.vector3_var = Vector3(4, randi() % 10 + 1, randi() % 10 + 1)
		new_model.vector4_var = Vector4(5, 6, 7, 8)
		new_model.color_var = Color(0, 1, 0, 1)  # Green
		new_model.nodepath_var = NodePath("..")
		new_model.enum_var = Model.MyEnum.OPTION_B
		new_model.int_array_var = [4, 5, 6]
		new_model.string_array_var = ["d", "e", "f"]
		new_model.dictionary_var = {"key3": "value3", "key4": 4, "key5" : Model.MyEnum.OPTION_B , "key6" : true}
			# Initialize inner models
		new_model.arrayOfInnerModels = [InnerModel.new(), InnerModel.new()]
		new_model.arrayOfInnerModels[0].innerModel = InnerModel.new()
		new_model.arrayOfInnerModels[0].TestInt = randi() % 10 + 1
		new_model.arrayOfInnerModels[0].innerModel.innerModel = InnerModel.new()
		new_model.arrayOfInnerModels[0].innerModel.innerModel.TestInt  = randi() % 10 + 1
		new_model.arrayOfInnerModels[0].innerModel.TestInt = randi() % 10 + 1
		collection.modelCollection.append(new_model)
		collection.modelDict["model1"] = new_model
		collection.modelCollection.append(new_model)
		collection.modelDict["model" + str(i + 1)] = new_model
		collection.model = new_model

	collection.model = collection.modelCollection[0]


func test_round_trip() -> void:
	var json_data: Dictionary = ForgeJSONGD.class_to_json(collection)
	TestUtil.check(ForgeJSONGD.store_json_file(SAVE_PATH, json_data), "collection is stored")

	var loaded: Collection = ForgeJSONGD.json_file_to_class(Collection, SAVE_PATH)
	TestUtil.check(loaded != null, "collection is loaded")
	TestUtil.check(loaded.modelCollection.size() == collection.modelCollection.size(), "model count round-trips")
	TestUtil.check(loaded.modelDict.size() == collection.modelDict.size(), "model dictionary round-trips")
	TestUtil.check(loaded.texture != null and loaded.texture.resource_path == texture.resource_path, "resource is stored by path")

	var original_model: Model = collection.modelCollection[0]
	var loaded_model: Model = loaded.modelCollection[0]
	TestUtil.check(loaded_model.modelName == original_model.modelName, "string round-trips")
	TestUtil.check(loaded_model.modelVector3 == original_model.modelVector3, "Vector3 round-trips")
	TestUtil.check(loaded_model.color_var == original_model.color_var, "Color round-trips")
	TestUtil.check(loaded_model.enum_var == original_model.enum_var, "enum round-trips")
	TestUtil.check(loaded_model.arrayOfColors == original_model.arrayOfColors, "typed Color array round-trips")
	TestUtil.check(loaded_model.int_array_var == original_model.int_array_var, "typed int array round-trips")
	TestUtil.check(loaded_model.arrayOfInnerModels.size() == 2, "array of inner models round-trips")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(loaded, collection), "loaded collection equals the original")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(loaded, collection).is_empty(), "no diff between the loaded and the original collection")
	TestUtil.check(ForgeJSONGD.check_equal_jsons(SAVE_PATH, loaded), "stored file equals the loaded collection")

	# The string form must parse back into the same data.
	var from_string: Collection = ForgeJSONGD.json_string_to_class(Collection, ForgeJSONGD.class_to_json_string(collection))
	TestUtil.check(from_string != null and from_string.modelCollection.size() == collection.modelCollection.size(), "JSON string round-trips")
	TestUtil.check(ForgeJSONGD.json_string_to_class(Collection, "not json") == null, "invalid JSON string returns null")

	# Encrypted files need the same key to be read back.
	var encrypted_path: String = "user://saves/collection_encrypted.json"
	TestUtil.check(ForgeJSONGD.store_json_file(encrypted_path, json_data, "test_key"), "encrypted file is stored")
	var decrypted: Dictionary = ForgeJSONGD.json_file_to_dict(encrypted_path, "test_key")
	TestUtil.check(decrypted.hash() == ForgeJSONGD.json_file_to_dict(SAVE_PATH).hash(), "encrypted file decrypts to the same data")


func test_utilities() -> void:
	var first: Dictionary = {"a": 1, "b": 2}
	var second: Dictionary = {"a": 1, "b": 3, "c": 4}
	TestUtil.check(ForgeJSONGD.check_equal_jsons(first, first.duplicate()), "equal dictionaries are equal")
	TestUtil.check(not ForgeJSONGD.check_equal_jsons(first, second), "different dictionaries are not equal")
	# Parsed JSON numbers are floats, so a string round-trip is only compared on non-numeric values.
	var text_only: Dictionary = {"a": "x", "b": ["y"]}
	TestUtil.check(ForgeJSONGD.check_equal_jsons(JSON.stringify(text_only), text_only), "JSON string equals dictionary")

	var diff: Dictionary = ForgeJSONGD.compare_jsons_diff(first, second)
	TestUtil.check(diff.get("b") == {"old": 2, "new": 3}, "diff reports a changed value")
	TestUtil.check(diff.get("c") == {"old": null, "new": 4}, "diff reports an added key")
	TestUtil.check(not diff.has("a"), "diff skips unchanged keys")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(first, first).is_empty(), "diff of equal jsons is empty")


func test_operations() -> void:
	var base: Dictionary = {"a": 1, "b": 2, "list": [1, 2]}
	var ref: Dictionary = {"a": 1, "b": 3, "list": [2]}
	var expected: Dictionary = {
		ForgeJSONGD.Operation.Add: {"a": [1, 1], "b": [2, 3], "list": [1, 2, 2]},
		ForgeJSONGD.Operation.AddDiffer: {"a": 1, "b": [2, 3], "list": [1, 2]},
		ForgeJSONGD.Operation.Replace: {"a": 1, "b": 3, "list": [2]},
		ForgeJSONGD.Operation.Remove: {"list": [1]},
		ForgeJSONGD.Operation.RemoveValue: {"b": 2, "list": [1]},
	}
	for operation: ForgeJSONGD.Operation in expected:
		var result: Dictionary = ForgeJSONGD.json_operation(base, ref, operation)
		TestUtil.check(result.hash() == expected[operation].hash(), "operation %s" % ForgeJSONGD.Operation.keys()[operation])
	TestUtil.check(base.hash() == {"a": 1, "b": 2, "list": [1, 2]}.hash(), "operations do not modify the input")
