## Runs the code examples of the GDScript guide, so the guide only shows code that works.
## The classes used here live in Tests/Docs/.
extends Node


func _ready() -> void:
	example_quick_start()
	example_string_and_dictionary()
	example_encryption()
	example_inheritance()
	example_loading_without_class()
	example_account_and_weapon()
	example_scoreboard()
	example_instance_hook()
	example_registry()
	example_equality_and_diff()
	example_operations()
	example_validation()
	TestUtil.finish("Docs examples", get_tree())


## "Validating JSON" in the guide: the printed lines and values it shows.
func example_validation() -> void:
	var text := '{"userName": "an", "email": "ann.example.com", "age": "20", "address": {"city": 5}}'
	var errors: Array[Dictionary] = ForgeJSONGD.validate_json(text, SignupDto)
	var printed: Array = []
	for error in errors:
		printed.append("%s: %s" % [error.path, error.message])
	TestUtil.check(printed == [
		"/userName: must be at least 3 characters long, got 2",
		"/email: must match the pattern \"^[^@\\\\s]+@[^@\\\\s]+$\", got \"ann.example.com\"",
		"/age: expected integer, got string",
		"/address/city: expected string, got integer",
	], "validation: the guide's printed problems (%s)" % str(printed))
	TestUtil.check(errors[0] == {"path": "/userName", "keyword": "minLength", "message": "must be at least 3 characters long, got 2", "schema_path": "/$ref/properties/userName/minLength"}, "validation: one problem in full (%s)" % str(errors[0]))

	var good := '{"userName": "ann", "email": "ann@example.com", "age": 20, "tags": ["new"]}'
	var signup: SignupDto = null
	var problems := ForgeJSONGD.validate_json(good, SignupDto)
	if problems.is_empty():
		signup = ForgeJSONGD.json_string_to_class(SignupDto, good)
	TestUtil.check(signup != null and signup.user_name == "ann" and signup.age == 20, "validation: validate, then load")
	TestUtil.check(ForgeJSONGD.validate_json('{"email": "a@b.c"}', SignupDto)[0].message == "the property 'userName' is required", "validation: a missing required field")
	TestUtil.check(ForgeJSONGD.validate_json('{"userName": "ann", "email": "a@b.c", "nickname": "x"}', SignupDto).is_empty(), "validation: unknown fields are allowed by default")
	TestUtil.check(ForgeJSONGD.validate_json('{"userName": "ann", "email": "a@b.c", "age": 20.0, "address": null}', SignupDto).is_empty(), "validation: 20.0 is an integer and an object may be null")

	var schema: Dictionary = ForgeJSONGD.class_to_json_schema(SignupDto)
	var definition: Dictionary = schema["$defs"]["SignupDto"]
	TestUtil.check(schema["$schema"] == "https://json-schema.org/draft/2020-12/schema" and schema["$id"] == "urn:forgejsongd:SignupDto" and schema["$ref"] == "#/$defs/SignupDto" and schema.type == "object", "validation: the schema's first keys")
	TestUtil.check(definition.title == "SignupDto" and definition.required == ["userName", "email"], "validation: title and required")
	TestUtil.check(definition.properties.userName == {"type": "string", "minLength": 3, "maxLength": 20}, "validation: userName")
	TestUtil.check(definition.properties.age == {"type": "integer", "minimum": 13}, "validation: age")
	TestUtil.check(definition.properties.tags == {"type": "array", "items": {"type": "string"}, "maxItems": 5, "uniqueItems": true}, "validation: tags")
	TestUtil.check(definition.properties.address == {"type": ["object", "null"], "$ref": "#/$defs/AddressDto"}, "validation: address")
	TestUtil.check(schema["$defs"]["AddressDto"].properties == {"city": {"type": "string"}, "zip": {"type": "string"}}, "validation: AddressDto")
	TestUtil.check(ForgeJSONGD.store_json_file("user://signup.schema.json", schema), "validation: the schema is saved as a file")

	var list_schema := {"type": "array", "items": ForgeJSONGD.class_to_json_schema(SignupDto)}
	TestUtil.check(ForgeJSONGD.validate_json('[{"userName": "ann", "email": "a@b.c"}, {"userName": 1, "email": "a@b.c"}]', list_schema)[0].path == "/1/userName", "validation: a list of objects of a class")

	var level_schema := {
		"type": "object",
		"required": ["name"],
		"properties": {
			"name": {"type": "string"},
			"level": {"type": "integer", "minimum": 1},
		},
	}
	var level_errors := ForgeJSONGD.validate_json({"level": 0}, level_schema)
	TestUtil.check(level_errors == [
		{"path": "", "keyword": "required", "message": "the property 'name' is required", "schema_path": "/required"},
		{"path": "/level", "keyword": "minimum", "message": "must be at least 1, got 0", "schema_path": "/properties/level/minimum"},
	], "validation: a schema written by hand (%s)" % str(level_errors))
	TestUtil.check(ForgeJSONGD.validate_json('"hello"', {"type": "string"}).is_empty(), "validation: a lone string is passed as JSON text")

	# "Schemas that refer to other schemas" in the guide.
	DirAccess.make_dir_recursive_absolute("user://schemas")
	FileAccess.open("user://schemas/common.schema.json", FileAccess.WRITE).store_string('{"$defs": {"id": {"type": "integer", "minimum": 1}}}')
	FileAccess.open("user://schemas/user.schema.json", FileAccess.WRITE).store_string('{"type": "object", "properties": {"id": {"$ref": "common.schema.json#/$defs/id"}}}')
	ForgeJSONGD.register_schema("user://schemas/common.schema.json")
	var id_errors := ForgeJSONGD.validate_json('{"id": 0}', "user://schemas/user.schema.json")
	TestUtil.check(id_errors.size() == 1 and id_errors[0].path == "/id" and id_errors[0].message == "must be at least 1, got 0", "validation: a registered schema file is found by its file name")
	ForgeJSONGD.register_schema({"$defs": {"id": {"type": "integer", "minimum": 1}}}, "https://example.com/schemas/common.schema.json")
	TestUtil.check(ForgeJSONGD.validate_json('{"id": 0}', {"properties": {"id": {"$ref": "https://example.com/schemas/common.schema.json#/$defs/id"}}}).size() == 1, "validation: registered under a URL, used offline")
	ForgeJSONGD.clear_registered_schemas()
	TestUtil.check(ForgeJSONGD.validate_json('{"id": 0}', "user://schemas/user.schema.json")[0].keyword == "$ref", "validation: after clear_registered_schemas the $ref is reported")


func example_quick_start() -> void:
	var player := PlayerData.new()
	player.name = "Bob"
	player.score = 100
	player.inventory = ["Sword", "Potion"]

	ForgeJSONGD.store_json_file("user://player.sav", ForgeJSONGD.class_to_json(player))
	var loaded_player: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://player.sav")
	TestUtil.check(loaded_player.name == "Bob" and loaded_player.score == 100, "quick start: name and score")
	TestUtil.check(loaded_player.inventory == ["Sword", "Potion"], "quick start: inventory")
	TestUtil.check(loaded_player.internal_variable == "This is not exported", "quick start: a variable without @export is saved too")

	var json_data: Dictionary = ForgeJSONGD.class_to_json(player)
	TestUtil.check(json_data.keys().size() == 4, "quick start: all four variables are in the dictionary")
	var json_string: String = ForgeJSONGD.class_to_json_string(player)
	TestUtil.check(JSON.parse_string(json_string)["name"] == "Bob", "class_to_json_string is valid JSON text")


func example_string_and_dictionary() -> void:
	var json_string := '{ "name": "Alice", "score": 1500 }'
	var from_string: PlayerData = ForgeJSONGD.json_string_to_class(PlayerData, json_string)
	TestUtil.check(from_string.name == "Alice" and from_string.score == 1500, "json_string_to_class example")

	var json_dict := { "name": "Bob", "score": 2000 }
	var from_dict: PlayerData = ForgeJSONGD.json_to_class(PlayerData, json_dict)
	TestUtil.check(from_dict.name == "Bob" and from_dict.score == 2000, "json_to_class example")
	TestUtil.check(from_dict.inventory.is_empty(), "variables missing from the JSON keep their default")

	ForgeJSONGD.store_json_file("user://saves/player_data.json", ForgeJSONGD.class_to_json(from_dict))
	var loaded_data: Dictionary = ForgeJSONGD.json_file_to_dict("user://saves/player_data.json")
	TestUtil.check(loaded_data.get("score") == 2000, "json_file_to_dict example")


func example_encryption() -> void:
	var player := PlayerData.new()
	player.name = "Secret"
	var saved: bool = ForgeJSONGD.store_json_file("user://saves/player_data.json", ForgeJSONGD.class_to_json(player), "my_secret_key")
	TestUtil.check(saved, "store_json_file with an encryption key")
	var loaded: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://saves/player_data.json", "my_secret_key")
	TestUtil.check(loaded.name == "Secret", "json_file_to_class with the same key")
	var plain: Dictionary = ForgeJSONGD.json_file_to_dict("user://saves/player_data.json")
	TestUtil.check(plain.is_empty(), "an encrypted file cannot be read without the key")


func example_inheritance() -> void:
	var rex := Dog.new()
	rex.name = "Rex"
	rex.tricks = ["sit", "roll"]
	var tom := Cat.new()
	tom.name = "Tom"
	var generic := Animal.new()
	generic.name = "Generic"

	var zoo := Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, tom, generic] # a Dog, a Cat and a plain Animal
	zoo.by_name = {"tom": tom}

	ForgeJSONGD.store_json_file("user://zoo.json", ForgeJSONGD.class_to_json(zoo))

	var loaded: Zoo = ForgeJSONGD.json_file_to_class(Zoo, "user://zoo.json")
	TestUtil.check(loaded.star is Dog, "zoo: star is a Dog")
	TestUtil.check(loaded.animals[1] is Cat, "zoo: animals[1] is a Cat")
	TestUtil.check(not loaded.animals[2] is Cat and not loaded.animals[2] is Dog, "zoo: a plain Animal stays an Animal")
	TestUtil.check((loaded.animals[0] as Dog).tricks == ["sit", "roll"], "zoo: the Dog keeps its tricks")
	TestUtil.check(loaded.by_name["tom"] is Cat, "zoo: a Cat in a typed dictionary")

	# The JSON shown in the guide.
	var expected_json: String = '{"animals":[{"name":"Rex","script_inheritance":"Dog","tricks":["sit","roll"]},{"lives":9,"name":"Tom","script_inheritance":"Cat"},{"name":"Generic"}],"by_name":{"tom":{"lives":9,"name":"Tom","script_inheritance":"Cat"}},"star":{"name":"Rex","script_inheritance":"Dog","tricks":["sit","roll"]}}'
	TestUtil.check(ForgeJSONGD.class_to_json_string(zoo) == expected_json, "zoo: the JSON matches the guide")


func example_loading_without_class() -> void:
	var rex := Dog.new()
	rex.name = "Rex"
	var json := ForgeJSONGD.class_to_json(rex, true) # also stores "script_inheritance": "Dog"
	var animal: Object = ForgeJSONGD.json_to_class(null, json)
	TestUtil.check(animal is Dog and animal.name == "Rex", "loading without knowing the class")


func example_account_and_weapon() -> void:
	var account := Account.new()
	account.user_name = "player"
	account.password = "hunter2"
	account.level = 3
	var json := ForgeJSONGD.class_to_json(account)
	TestUtil.check(json.has("user_name") and json.has("level") and not json.has("password"), "Account: the password is not saved")
	var loaded_account: Account = ForgeJSONGD.json_to_class(Account, {"user_name": "a", "password": "ignored"})
	TestUtil.check(loaded_account.password == "", "Account: the password is not loaded")

	var sword := Weapon.new(25, "Sword")
	var loaded_weapon: Weapon = ForgeJSONGD.json_string_to_class(Weapon, ForgeJSONGD.class_to_json_string(sword))
	TestUtil.check(loaded_weapon.damage == 25 and loaded_weapon.title == "Sword", "Weapon: _init arguments are saved and passed again")


func example_scoreboard() -> void:
	var board := Scoreboard.new()
	board.scores = [10, 20, 30]
	var json := ForgeJSONGD.class_to_json(board)
	TestUtil.check(json == {"scores": "10,20,30"}, "Scoreboard: _forge_serialize replaces the automatic JSON")
	var loaded: Scoreboard = ForgeJSONGD.json_to_class(Scoreboard, json)
	TestUtil.check(loaded.scores == [10, 20, 30], "Scoreboard: static _forge_deserialize builds the object")


func example_instance_hook() -> void:
	var model := InstanceHookModel.new()
	model.value = 4
	var json := ForgeJSONGD.class_to_json(model)
	TestUtil.check(json.size() == 1 and json["packed_value"] == 40, "instance hook: _forge_serialize is used")
	var loaded: InstanceHookModel = ForgeJSONGD.json_to_class(InstanceHookModel, json)
	TestUtil.check(loaded.value == 4, "instance hook: a non-static _forge_deserialize fills a new instance")


func example_registry() -> void:
	ForgeJSONGD.clear_registered_scripts()
	var rex := Dog.new()
	rex.name = "Rex"
	var tom := Cat.new()
	tom.name = "Tom"
	var zoo := Zoo.new()
	zoo.animals = [rex, tom]
	ForgeJSONGD.store_json_file("user://zoo.json", ForgeJSONGD.class_to_json(zoo))

	ForgeJSONGD.register_script(Dog)
	ForgeJSONGD.register_scripts([Cat, Animal])
	var allowed: Zoo = ForgeJSONGD.json_file_to_class(Zoo, "user://zoo.json")
	TestUtil.check(allowed.animals[0] is Dog and allowed.animals[1] is Cat, "registry: registered scripts load")

	ForgeJSONGD.clear_registered_scripts()
	ForgeJSONGD.register_script(Dog)
	var restricted: Zoo = ForgeJSONGD.json_file_to_class(Zoo, "user://zoo.json")
	TestUtil.check(restricted.animals[0] is Dog, "registry: the registered Dog loads")
	TestUtil.check(restricted.animals.size() == 2 and not restricted.animals[1] is Cat, "registry: the unregistered Cat does not load as a Cat")
	TestUtil.check(restricted.animals[1].name == "Tom", "registry: it loads as the declared type Animal, keeping the data that fits")
	ForgeJSONGD.clear_registered_scripts()


func example_equality_and_diff() -> void:
	var dict1 := {"name": "Alice", "score": 100}
	var dict2 := {"name": "Alice", "score": 100}
	var dict3 := {"name": "Bob", "score": 150}
	TestUtil.check(ForgeJSONGD.check_equal_jsons(dict1, dict2), "equality example: equal")
	TestUtil.check(not ForgeJSONGD.check_equal_jsons(dict1, dict3), "equality example: different")

	var old_data := {"name": "Player1", "level": 5, "items": ["sword"]}
	var new_data := {"name": "Player1", "level": 6, "items": ["sword", "shield"], "new_key": "value"}
	var diff := ForgeJSONGD.compare_jsons_diff(old_data, new_data)
	var expected := {
		"level": {"old": 5, "new": 6},
		"items": {"old": ["sword"], "new": ["sword", "shield"]},
		"new_key": {"old": null, "new": "value"},
	}
	TestUtil.check(diff == expected, "diff example matches the guide")
	TestUtil.check(ForgeJSONGD.compare_jsons_diff(dict1, dict2).is_empty(), "diff of equal data is empty")


func example_operations() -> void:
	var source_json := {"a": 1, "b": 2, "c": 3}
	var reference_json := {"b": 20, "c": 3, "d": 4}
	var expected := {
		ForgeJSONGD.Operation.Add: {"a": 1, "b": [2, 20], "c": [3, 3], "d": 4},
		ForgeJSONGD.Operation.AddDiffer: {"a": 1, "b": [2, 20], "c": 3, "d": 4},
		ForgeJSONGD.Operation.Replace: {"a": 1, "b": 20, "c": 3, "d": 4},
		ForgeJSONGD.Operation.Remove: {"a": 1},
		ForgeJSONGD.Operation.RemoveValue: {"a": 1, "b": 2},
	}
	for operation: ForgeJSONGD.Operation in expected:
		var result := ForgeJSONGD.json_operation(source_json, reference_json, operation)
		TestUtil.check(result == expected[operation], "operation %s matches the guide" % ForgeJSONGD.Operation.keys()[operation])
	TestUtil.check(source_json == {"a": 1, "b": 2, "c": 3}, "operations do not change the source")

	# Nested dictionaries and arrays.
	var base := {"player": {"hp": 10, "items": ["sword", "shield"]}}
	var ref := {"player": {"hp": 10, "items": ["shield"]}}
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Remove) == {"player": {"items": ["sword"]}}, "Remove works inside nested dictionaries and arrays")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Replace) == {"player": {"hp": 10, "items": ["shield"]}}, "Replace replaces arrays as a whole")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.AddDiffer) == {"player": {"hp": 10, "items": ["sword", "shield"]}}, "AddDiffer adds only new array items")
	TestUtil.check(ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Add)["player"]["items"] == ["sword", "shield", "shield"], "Add appends every array item")
