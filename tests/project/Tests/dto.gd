## JSON for HTTP APIs: a class that returns true from _forge_plain_json must write and read standard JSON, whatever the server sends.
extends Node


func _ready() -> void:
	test_request_body()
	test_response_body()
	test_server_cannot_choose_classes()
	test_untrusted_text_and_numbers()
	test_polymorphic_classes_stay_plain()
	test_vectors_and_hooks()
	test_normal_mode_is_unchanged()
	TestUtil.finish("Dto", get_tree())


func _user(script: Script = UserDto) -> UserDto:
	var user: UserDto = script.new()
	user.id = 7
	user.user_name = "ann"
	user.score = 2.0
	user.tags = ["a", "b"]
	user.address = AddressDto.new()
	user.address.city = "Tokyo"
	user.address.zip = "100"
	user.meta = {"count": 5, "ratio": 2.0, "1": "one", "true": "t", "text": "Vector2(1, 2)", "forge_text:x": "y", "list": [1, 2.0, "3"]}
	user.position = Vector2(1, 2)
	user.color = Color.RED
	user.role = UserDto.Role.ADMIN
	user.big_id = 9007199254740993
	user.secret = "never sent"
	return user


#region Request bodies

func test_request_body() -> void:
	var login: LoginDto = LoginDto.new()
	login.user_name = "ann"
	login.password = "pw"
	login.remember = true
	login.attempts = 2
	TestUtil.check(ForgeJSONGD.class_to_json_string(login) == '{"attempts":2,"password":"pw","remember":true,"userName":"ann"}', "a request body is exactly the expected JSON text")

	var text: String = ForgeJSONGD.class_to_json_string(_user())
	var json: Dictionary = JSON.parse_string(text)
	TestUtil.check(not text.contains("forge_float") and not text.contains("forge_int") and not text.contains("script_") and not text.contains("forge_resource"), "no marker or class name is written")
	TestUtil.check(json["userName"] == "ann" and json.has("bigId"), "variables are written under the keys of _forge_json_keys")
	TestUtil.check(not json.has("user_name") and not json.has("secret"), "the variable names and excluded variables are not written")
	TestUtil.check(text.contains('"bigId":9007199254740993'), "a large int is a plain JSON number with every digit")
	TestUtil.check(json["address"] == {"city": "Tokyo", "zip": "100"}, "a nested DTO is a plain object")
	TestUtil.check(json["tags"] == ["a", "b"] and json["score"] == 2.0 and text.contains('"score":2.0'), "arrays and floats are plain")
	TestUtil.check(json["position"] == {"x": 1.0, "y": 2.0}, "a Vector2 is {x, y}")
	TestUtil.check(json["color"] == "ff0000ff" and json["role"] == "Admin", "a Color is hex text and an enum is its name")
	var meta: Dictionary = json["meta"]
	TestUtil.check(meta["count"] == 5.0 and text.contains('"count":5,') and text.contains('"ratio":2.0'), "numbers in a free-form dictionary are plain: 5 stays 5 and 2.0 stays 2.0")
	TestUtil.check(meta.has("1") and meta.has("true") and meta.has("forge_text:x") and meta["text"] == "Vector2(1, 2)", "keys and text in a free-form dictionary are written as they are")
	TestUtil.check(text.contains('"list":[1,2.0,"3"]'), "an untyped array is plain")
	TestUtil.check(ForgeJSONGD.class_to_json(_user()) == ForgeJSONGD.class_to_json(_user()), "a plain class gives the same dictionary every time")

	var keyed: UserDto = UserDto.new()
	keyed.meta = {1: "a", 2.5: "b", true: "c", "text": "d"}
	var keyed_meta: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(keyed))["meta"]
	TestUtil.check(keyed_meta == {"1": "a", "2.5": "b", "true": "c", "text": "d"}, "number and bool keys of a free-form dictionary are written as their text")

	var unsorted: LoginDto = LoginDto.new()
	ForgeJSONGD.sort_keys = false
	var declared_order: String = ForgeJSONGD.class_to_json_string(unsorted)
	ForgeJSONGD.sort_keys = true
	TestUtil.check(declared_order == '{"userName":"","password":"","remember":false,"attempts":0}', "with sort_keys off the keys keep the order of the variables")

#endregion


#region Response bodies

func test_response_body() -> void:
	var response: String = JSON.stringify({
		"id": 9, "userName": "bob", "score": null, "tags": null, "unknown": 1, "bigId": "9007199254740993",
		"address": {"city": "Osaka", "zip": 54321},
		"friends": [{"id": 1, "userName": "x"}, {"id": 2, "tags": ["t"]}, null],
		"meta": {"forge_float": 3, "a": "forge_text:x", "k": [1, 2.5, {"deep": true}], "n": null},
		"position": {"x": 3, "y": 4}, "color": "00ff00ff", "role": "Admin", "nickname": null,
	})
	var user: UserDto = ForgeJSONGD.json_string_to_class(UserDto, response)
	TestUtil.check(user != null and user.id == 9 and user.user_name == "bob", "fields are read, also under their API keys")
	TestUtil.check(user.score == 1.5 and user.tags.is_empty() and user.nickname == "none", "a null from the server keeps the default")
	TestUtil.check(user.big_id == 9007199254740993, "a large id sent as text is read exactly")
	TestUtil.check(user.address.city == "Osaka" and user.address.zip == "54321", "a nested DTO is read, and a number where text is expected becomes text")
	TestUtil.check(user.friends.size() == 3 and user.friends[0].user_name == "x" and user.friends[1].tags == ["t"] and user.friends[2] == null, "an array of DTOs is read (a null element stays null)")
	TestUtil.check(user.meta["forge_float"] == 3 and user.meta["a"] == "forge_text:x", "a free-form dictionary is read exactly as the server sent it")
	TestUtil.check(user.meta["k"] == [1, 2.5, {"deep": true}] and user.meta["n"] == null, "nested data and nulls in a free-form dictionary are kept")
	TestUtil.check(user.position == Vector2(3, 4) and user.color == Color.GREEN and user.role == UserDto.Role.ADMIN, "Vector2, Color and enum are read")
	TestUtil.check(ForgeJSONGD.json_string_to_class(UserDto, "{ broken") == null and ForgeJSONGD.json_string_to_class(UserDto, "[1, 2]") == null, "text that is not a JSON object gives null")
	TestUtil.check(ForgeJSONGD.json_string_to_class(UserDto, "{}") is UserDto, "an empty object gives a DTO with defaults")

	var original: UserDto = _user()
	var returned: UserDto = ForgeJSONGD.json_string_to_class(UserDto, ForgeJSONGD.class_to_json_string(original))
	TestUtil.check(returned.id == 7 and returned.user_name == "ann" and returned.score == 2.0 and returned.tags == original.tags, "a DTO returned-trips: plain fields")
	TestUtil.check(returned.address.city == "Tokyo" and returned.position == Vector2(1, 2) and returned.color == Color.RED and returned.role == UserDto.Role.ADMIN, "a DTO returned-trips: nested, vector, color, enum")
	TestUtil.check(returned.meta["count"] == 5 and typeof(returned.meta["count"]) == TYPE_INT and returned.meta["text"] == "Vector2(1, 2)", "a DTO returned-trips: free-form dictionary")

	var existing: UserDto = UserDto.new()
	existing.nickname = "keep"
	ForgeJSONGD.json_to_class(existing, {"id": 3})
	TestUtil.check(existing.id == 3 and existing.nickname == "keep", "a plain class can be filled as an existing instance")

#endregion


#region A server cannot choose what gets created or loaded

func test_server_cannot_choose_classes() -> void:
	var hostile: Dictionary = {
		"id": 1,
		"script_inheritance": "res://Tests/Models/PlainScript.gd",
		"script_constructor_args": [1, 2],
		"address": {"city": "Z", "script_inheritance": "res://Tests/Models/PlainScript.gd", "script_uid": "uid://nothing"},
		"friends": [{"id": 5, "script_inheritance": "Dog"}],
		"meta": {"o": {"script_inheritance": "Dog", "name": "x"}, "r": {"forge_resource_path": "res://icon.svg"}, "p": "res://icon.svg"},
	}
	var user: UserDto = ForgeJSONGD.json_to_class(UserDto, hostile)
	TestUtil.check(user is UserDto and user.id == 1, "a class name at the top is ignored")
	TestUtil.check(user.address is AddressDto and user.address.city == "Z", "a class name in a nested object is ignored: the declared class is used")
	TestUtil.check(user.friends.size() == 1 and user.friends[0] is UserDto and user.friends[0].id == 5, "a class name in an array element is ignored")
	TestUtil.check(user.meta["o"] is Dictionary and user.meta["o"]["script_inheritance"] == "Dog", "a class name in a free-form dictionary stays plain data")
	TestUtil.check(user.meta["r"] is Dictionary and user.meta["p"] == "res://icon.svg", "a resource marker and a resource path stay plain data")
	var holder: ApiTexHolder = ForgeJSONGD.json_to_class(ApiTexHolder, {"single": "res://icon.svg", "textures": ["res://icon.svg"]})
	TestUtil.check(holder.single == null and holder.textures.size() == 1 and holder.textures[0] == null, "a path sent by a server is not loaded as a resource")
	var normal: TexHolder = ForgeJSONGD.json_to_class(TexHolder, {"single": "res://icon.svg"})
	TestUtil.check(normal.single != null, "the normal functions still load resources by path")

#endregion


#region Text and numbers are not interpreted

func test_untrusted_text_and_numbers() -> void:
	var texts: Array[String] = ["Vector2(1, 2)", "Rect2(1, 2, 3, 4)", "Color(1, 0, 0, 1)", "PackedByteArray(1)", "forge_text:abc", "123", "true", "[1, 2]", "{\"a\": 1}", "null", "", "Object(Node)", "&\"name\"", "@\"path\"", "res://icon.svg"]
	for text: String in texts:
		var user: UserDto = ForgeJSONGD.json_to_class(UserDto, {"userName": text, "nickname": text, "meta": {text: text, "list": [text]}, "tags": [text]})
		var shown: String = text.replace("\n", " ")
		TestUtil.check(user.user_name == text and user.nickname == text, "text variable keeps '%s'" % shown)
		TestUtil.check(user.meta.get(text) is String and user.meta[text] == text and user.meta["list"] == [text], "free-form dictionary keeps key and value '%s'" % shown)
		TestUtil.check(user.tags == [text], "Array[String] keeps '%s'" % shown)
		var sent: Dictionary = JSON.parse_string(ForgeJSONGD.class_to_json_string(user))
		TestUtil.check(sent["userName"] == text and sent["meta"].has(text) and sent["meta"][text] == text, "'%s' is sent back unchanged" % shown)
	# Numbers in free-form data: JSON has no int type, so a whole number is read as an int.
	var numbers: UserDto = ForgeJSONGD.json_to_class(UserDto, {"meta": {"a": 5, "b": 2.5, "c": 5.0, "d": -3, "e": 1e20, "f": 0}})
	TestUtil.check(typeof(numbers.meta["a"]) == TYPE_INT and typeof(numbers.meta["b"]) == TYPE_FLOAT and numbers.meta["d"] == -3 and numbers.meta["f"] == 0, "whole numbers in free-form data are ints, others are floats")
	TestUtil.check(numbers.meta["e"] == 1e20, "a huge number is kept")
	var typed: UserDto = ForgeJSONGD.json_to_class(UserDto, {"id": 5.0, "score": 3, "bigId": 12})
	TestUtil.check(typeof(typed.id) == TYPE_INT and typed.id == 5 and typeof(typed.score) == TYPE_FLOAT and typed.score == 3.0 and typed.big_id == 12, "typed fields get their own type whatever number the server sends")
	var wrong: UserDto = ForgeJSONGD.json_to_class(UserDto, {"id": "x", "tags": "not a list", "address": "nope", "meta": [1], "position": [1, 2], "role": "SomethingElse"})
	TestUtil.check(wrong is UserDto and wrong.tags.is_empty() and wrong.meta.is_empty() and wrong.address == null, "data of the wrong shape does not break loading")
	TestUtil.check(wrong.role == UserDto.Role.GUEST, "an unknown enum name gives the first value")

#endregion


#region Child classes: no class names on the wire

func test_polymorphic_classes_stay_plain() -> void:
	var rex: Dog = Dog.new()
	rex.name = "Rex"
	rex.tricks = ["sit"]
	var zoo: ApiZoo = ApiZoo.new()
	zoo.star = rex
	zoo.animals = [rex, Cat.new()]
	zoo.by_name = {"rex": rex}
	var text: String = ForgeJSONGD.class_to_json_string(zoo)
	TestUtil.check(not text.contains("script_inheritance") and not text.contains("script_uid"), "child classes are written without class names")
	TestUtil.check(text.contains('"tricks":["sit"]') and text.contains('"lives":9'), "child variables are still written")
	var loaded: ApiZoo = ForgeJSONGD.json_string_to_class(ApiZoo, text)
	TestUtil.check(loaded.star is Animal and loaded.star.name == "Rex" and loaded.animals.size() == 2, "they load as the declared class")
	TestUtil.check(ForgeJSONGD.class_to_json(zoo, true).has("animals") and not ForgeJSONGD.class_to_json(zoo, true).has("script_inheritance"), "a plain class never adds script_inheritance, even with specify_class")

#endregion


#region Vectors, types without a standard form, and hooks

func test_vectors_and_hooks() -> void:
	var vectors: VectorsDto = VectorsDto.new()
	var text: String = ForgeJSONGD.class_to_json_string(vectors)
	var json: Dictionary = JSON.parse_string(text)
	TestUtil.check(json["v2"] == {"x": 1.5, "y": 2.5} and json["v2i"] == {"x": 1.0, "y": 2.0}, "Vector2 and Vector2i are {x, y}")
	TestUtil.check(json["v3"] == {"x": 1.0, "y": 2.0, "z": 3.0} and json["v3i"] == {"x": 4.0, "y": 5.0, "z": 6.0}, "Vector3 and Vector3i are {x, y, z}")
	TestUtil.check(json["v4"] == {"x": 1.0, "y": 2.0, "z": 3.0, "w": 4.0} and json["v4i"] == {"x": 5.0, "y": 6.0, "z": 7.0, "w": 8.0}, "Vector4 and Vector4i are {x, y, z, w}")
	TestUtil.check(text.contains('"v2i":{"x":1,"y":2}'), "the integer vectors have whole numbers")
	TestUtil.check(json["points"] == [{"x": 1.0, "y": 2.0}, {"x": 3.0, "y": 4.0}] and json["by_name"] == {"a": {"x": 1.0, "y": 2.0, "z": 3.0}}, "vectors in typed arrays and dictionaries are {x, y}")
	TestUtil.check(json["rect"] == "Rect2(1, 2, 3, 4)", "a type without a standard JSON form keeps its text form")

	var loaded: VectorsDto = VectorsDto.new()
	loaded.v2 = Vector2.ZERO
	loaded.v2i = Vector2i.ZERO
	loaded.v3 = Vector3.ZERO
	loaded.v3i = Vector3i.ZERO
	loaded.v4 = Vector4.ZERO
	loaded.v4i = Vector4i.ZERO
	loaded.rect = Rect2()
	loaded.points = []
	loaded.by_name = {}
	ForgeJSONGD.json_to_class(loaded, json)
	TestUtil.check(loaded.v2 == Vector2(1.5, 2.5) and loaded.v2i == Vector2i(1, 2) and loaded.v3 == Vector3(1, 2, 3) and loaded.v3i == Vector3i(4, 5, 6), "vectors are read back")
	TestUtil.check(loaded.v4 == Vector4(1, 2, 3, 4) and loaded.v4i == Vector4i(5, 6, 7, 8) and loaded.rect == Rect2(1, 2, 3, 4), "larger vectors and the text form are read back")
	TestUtil.check(loaded.points == [Vector2(1, 2), Vector2(3, 4)] and loaded.by_name == {"a": Vector3(1, 2, 3)}, "vectors in typed containers are read back")
	var partial: VectorsDto = ForgeJSONGD.json_to_class(VectorsDto, {"v2": {"x": 9}, "v3": [1, 2, 3], "v4": "nope"})
	TestUtil.check(partial.v2 == Vector2(1.5, 2.5) and partial.v3 == Vector3(1, 2, 3) and partial.v4 == Vector4(1, 2, 3, 4), "an incomplete or wrongly shaped vector keeps the default")

	# Enums by name or by number.
	TestUtil.check(ForgeJSONGD.json_to_class(UserDto, {"role": 5}).role == UserDto.Role.ADMIN and ForgeJSONGD.json_to_class(UserDto, {"role": "admin"}).role == UserDto.Role.ADMIN, "an enum is read from its name (any case) or its number")

	# A class that takes over its own JSON still works in plain mode.
	var board: ApiScoreboard = ApiScoreboard.new()
	board.scores = [10, 20, 30]
	TestUtil.check(ForgeJSONGD.class_to_json(board) == {"scores": "10,20,30"} and ForgeJSONGD.class_to_json_string(board) == '{"scores":"10,20,30"}', "_forge_serialize is used by a plain class")
	TestUtil.check(ForgeJSONGD.json_to_class(ApiScoreboard, {"scores": "1,2"}).scores == [1, 2], "_forge_deserialize is used by a plain class")

	# Variable keys also apply to a class that is not plain.
	var saved: SavedUserDto = SavedUserDto.new()
	saved.user_name = "ann"
	var exact: Dictionary = ForgeJSONGD.class_to_json(saved)
	TestUtil.check(exact.has("userName") and not exact.has("user_name"), "_forge_json_keys also applies to a class that is not plain")
	TestUtil.check(ForgeJSONGD.json_to_class(SavedUserDto, {"userName": "bob"}).user_name == "bob", "and when loading it")

#endregion


#region A class that is not plain is unchanged

func test_normal_mode_is_unchanged() -> void:
	var user: UserDto = _user(SavedUserDto)
	var normal: String = ForgeJSONGD.class_to_json_string(user)
	var json: Dictionary = JSON.parse_string(normal)
	TestUtil.check(json["userName"] == "ann" and json["position"] == "Vector2(1, 2)", "a class that is not plain still uses the exact format (vectors as text)")
	TestUtil.check(json["bigId"] == "9007199254740993" and json["meta"]["ratio"] == {"forge_float": 2.0}, "and still protects large numbers and whole floats")
	var back: UserDto = ForgeJSONGD.json_string_to_class(SavedUserDto, normal)
	TestUtil.check(back.big_id == 9007199254740993 and back.meta["forge_text:x"] == "y" and back.position == Vector2(1, 2), "and still round-trips exactly")
	# A plain class is plain wherever it appears, also inside a class that is not plain.
	var mixed: MixedHolder = MixedHolder.new()
	mixed.api.user_name = "ann"
	var mixed_text: String = ForgeJSONGD.class_to_json_string(mixed)
	var mixed_json: Dictionary = JSON.parse_string(mixed_text)
	TestUtil.check(mixed_json["data"]["ratio"] == {"forge_float": 2.0} and mixed_json["big"] == "9007199254740993", "the class that is not plain is exact")
	TestUtil.check(mixed_json["api"] == {"attempts": 0.0, "password": "", "remember": false, "userName": "ann"}, "the plain class inside it is plain, with its API keys")
	var mixed_loaded: MixedHolder = ForgeJSONGD.json_string_to_class(MixedHolder, mixed_text)
	TestUtil.check(mixed_loaded.api.user_name == "ann" and typeof(mixed_loaded.data["ratio"]) == TYPE_FLOAT and mixed_loaded.big == 9007199254740993, "and both are read back by their own format")
	# Converting a plain class does not leave plain mode switched on.
	ForgeJSONGD.class_to_json_string(_user())
	TestUtil.check(ForgeJSONGD.class_to_json_string(user) == normal, "the exact format is back right after a plain class was converted")
	# A plain class holding a class that is not plain writes it as plain too, and a class that is not plain holding a plain class does not.
	var holder: ApiZoo = ApiZoo.new()
	holder.animals = [Dog.new()]
	TestUtil.check(not ForgeJSONGD.class_to_json_string(holder).contains("script_inheritance"), "everything inside a plain class is plain")
	var exact_holder: Zoo = Zoo.new()
	exact_holder.animals = [Dog.new()]
	TestUtil.check(ForgeJSONGD.class_to_json_string(exact_holder).contains("script_inheritance"), "everything inside a class that is not plain is exact")

#endregion
