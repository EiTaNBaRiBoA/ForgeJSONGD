## validate_json and class_to_json_schema: the keywords, the ways to pass data and schemas, the problems reported,
## and the schemas of classes. The drift check makes sure every class's schema accepts what class_to_json writes.
## (The official JSON Schema Test Suite runs in Tests/schema_suite.tscn.)
extends Node

const TMP_DIR = "user://validation/"
## Scene scripts with class_name: they run tests in _ready, they are not data classes.
const NOT_DATA = ["Main", "TestUtil"]
## Classes whose defaults break their own _forge_schema rules on purpose (checked with filled data instead).
const RULES_NOT_MET_BY_DEFAULTS = ["SchemaUserDto", "SignupData", "SignupDto"]


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_check_keywords()
	_check_inputs()
	_check_reports()
	_check_registered()
	_check_class_schemas()
	_check_hook()
	_check_polymorphism()
	_check_drift()
	_check_speed()
	TestUtil.finish("Validation", get_tree())


func _check_speed() -> void:
	var users: Array = []
	for i: int in 2000:
		users.append({"id": i, "userName": "user%d" % i, "tags": ["a", "b"], "address": {"city": "Rome", "zip": "1"}, "position": {"x": 1, "y": 2}, "role": "Admin"})
	var schema: Dictionary = {"type": "array", "items": ForgeJSONGD.class_to_json_schema(UserDto)}
	var started: int = Time.get_ticks_msec()
	var errors: Array[Dictionary] = ForgeJSONGD.validate_json(users, schema)
	var elapsed: int = Time.get_ticks_msec() - started
	print("2000 UserDto objects validated in %d ms" % elapsed)
	TestUtil.check(errors.is_empty() and elapsed < 5000, "2000 objects are validated well under 5 seconds (%d ms)" % elapsed)


## The problems as "path keyword" text, for short checks.
func _found(data: Variant, schema: Variant) -> Array:
	return ForgeJSONGD.validate_json(data, schema).map(func(error: Dictionary) -> String: return "%s %s" % [error.path, error.keyword])


#region Keywords

func _check_keywords() -> void:
	var person: Dictionary = {
		"type": "object",
		"required": ["name"],
		"additionalProperties": false,
		"properties": {
			"name": {"type": "string", "minLength": 2, "maxLength": 10, "pattern": "^[A-Z]"},
			"age": {"type": "integer", "minimum": 0, "exclusiveMaximum": 150, "multipleOf": 1},
			"email": {"type": ["string", "null"]},
			"role": {"enum": ["guest", "admin"]},
			"kind": {"const": "person"},
			"tags": {"type": "array", "items": {"type": "string"}, "minItems": 1, "maxItems": 3, "uniqueItems": true},
			"point": {"type": "array", "prefixItems": [{"type": "number"}, {"type": "number"}], "items": false},
			"scores": {"type": "array", "contains": {"minimum": 90}, "minContains": 1, "maxContains": 2},
			"extra": {"type": "object", "patternProperties": {"^x_": {"type": "integer"}}, "propertyNames": {"maxLength": 5}, "minProperties": 1, "maxProperties": 2},
		},
		"dependentRequired": {"email": ["role"]},
	}
	var good: Dictionary = {"name": "Ann", "age": 30, "email": null, "role": "admin", "kind": "person", "tags": ["a", "b"], "point": [1, 2.5], "scores": [95, 10], "extra": {"x_a": 1}}
	TestUtil.check(_found(good, person).is_empty(), "valid data has no problems")
	TestUtil.check(_found({"age": 30}, person) == [" required"], "required: a missing property is reported at the object")
	TestUtil.check(_found({"name": 5}, person) == ["/name type"], "type: wrong type at its path")
	TestUtil.check(_found({"name": "A"}, person) == ["/name minLength"], "minLength")
	TestUtil.check(_found({"name": "Abcdefghijk"}, person) == ["/name maxLength"], "maxLength")
	TestUtil.check(_found({"name": "ann"}, person) == ["/name pattern"], "pattern")
	TestUtil.check(_found({"name": "Ann", "age": -1}, person) == ["/age minimum"], "minimum")
	TestUtil.check(_found({"name": "Ann", "age": 150}, person) == ["/age exclusiveMaximum"], "exclusiveMaximum")
	TestUtil.check(_found({"name": "Ann", "age": 2.5}, person) == ["/age type", "/age multipleOf"], "integer type and multipleOf")
	TestUtil.check(_found({"name": "Ann", "age": 30.0}, person).is_empty(), "30.0 is an integer (JSON has one number type)")
	TestUtil.check(_found({"name": "Ann", "role": "boss", "email": "a@b"}, person) == ["/role enum"], "enum")
	TestUtil.check(_found({"name": "Ann", "kind": "robot"}, person) == ["/kind const"], "const")
	TestUtil.check(_found({"name": "Ann", "email": "a@b"}, person) == [" dependentRequired"], "dependentRequired")
	TestUtil.check(_found({"name": "Ann", "tags": []}, person) == ["/tags minItems"], "minItems")
	TestUtil.check(_found({"name": "Ann", "tags": ["a", "b", "c", "d"]}, person) == ["/tags maxItems"], "maxItems")
	TestUtil.check(_found({"name": "Ann", "tags": ["a", "a"]}, person) == ["/tags uniqueItems"], "uniqueItems")
	TestUtil.check(_found({"name": "Ann", "tags": ["a", 2]}, person) == ["/tags/1 type"], "items: the path names the item")
	TestUtil.check(_found({"name": "Ann", "point": [1, "2"]}, person) == ["/point/1 type"], "prefixItems")
	TestUtil.check(_found({"name": "Ann", "point": [1, 2, 3]}, person) == ["/point/2 false"], "items: false after prefixItems")
	TestUtil.check(_found({"name": "Ann", "scores": [1, 2]}, person) == ["/scores contains"], "contains")
	TestUtil.check(_found({"name": "Ann", "scores": [91, 92, 93]}, person) == ["/scores maxContains"], "maxContains")
	TestUtil.check(_found({"name": "Ann", "extra": {"x_a": "1"}}, person) == ["/extra/x_a type"], "patternProperties")
	TestUtil.check(_found({"name": "Ann", "extra": {"longname": 1}}, person) == ["/extra/longname propertyNames"], "propertyNames")
	TestUtil.check(_found({"name": "Ann", "extra": {}}, person) == ["/extra minProperties"], "minProperties")
	TestUtil.check(_found({"name": "Ann", "extra": {"a": 1, "b": 2, "c": 3}}, person) == ["/extra maxProperties"], "maxProperties")
	TestUtil.check(_found({"name": "Ann", "nick": "x"}, person) == ["/nick additionalProperties"], "additionalProperties: false")
	TestUtil.check(_found({"name": "Ann", "age": "30", "tags": [1]}, person).size() == 2, "every problem is reported, not only the first")

	var combined: Dictionary = {
		"$defs": {"positive": {"type": "number", "exclusiveMinimum": 0}, "node": {"type": "object", "properties": {"next": {"$ref": "#/$defs/node"}, "value": {"$ref": "#/$defs/positive"}}}},
		"type": "object",
		"properties": {
			"all": {"allOf": [{"type": "integer"}, {"minimum": 10}]},
			"any": {"anyOf": [{"type": "string"}, {"type": "boolean"}]},
			"one": {"oneOf": [{"type": "integer"}, {"minimum": 5}]},
			"not": {"not": {"type": "null"}},
			"conditional": {"if": {"type": "string"}, "then": {"minLength": 2}, "else": {"type": "integer"}},
			"chain": {"$ref": "#/$defs/node"},
			"shape": {"dependentSchemas": {"radius": {"required": ["center"]}}},
		},
	}
	TestUtil.check(_found({"all": 12, "any": true, "one": 2, "not": 1, "conditional": "ab", "chain": {"value": 1, "next": {"value": 2}}, "shape": {"radius": 1, "center": 0}}, combined).is_empty(), "allOf, anyOf, oneOf, not, if, $ref and dependentSchemas pass")
	TestUtil.check(_found({"all": 5}, combined) == ["/all allOf"] or _found({"all": 5}, combined) == ["/all minimum"], "allOf reports the failing part")
	TestUtil.check(_found({"any": 1}, combined) == ["/any anyOf"], "anyOf")
	TestUtil.check(_found({"one": 7}, combined) == ["/one oneOf"], "oneOf: two schemas match")
	TestUtil.check(_found({"not": null}, combined) == ["/not not"], "not")
	TestUtil.check(_found({"conditional": "a"}, combined) == ["/conditional minLength"] and _found({"conditional": 1.5}, combined) == ["/conditional type"], "if / then / else")
	TestUtil.check(_found({"chain": {"next": {"next": {"value": -1}}}}, combined) == ["/chain/next/next/value exclusiveMinimum"], "a recursive $ref checks every level, with the full path")
	TestUtil.check(_found({"shape": {"radius": 1}}, combined) == ["/shape required"], "dependentSchemas")
	TestUtil.check(_found({"a/b": 1}, {"properties": {"a/b": {"type": "string"}}}) == ["/a~1b type"], "a key with / is escaped in the path (JSON Pointer)")
	TestUtil.check(_found("x", true).size() == 1 and _found("1", true).is_empty() and _found("1", false) == [" false"], "true and false schemas")
	TestUtil.check(_found("\"\\u00e9t\\u00e9\"", {"pattern": "^\\p{Letter}+$", "maxLength": 4}).is_empty(), "patterns use Unicode categories; lengths count characters")

	# The forms of older drafts.
	var legacy: Dictionary = {
		"definitions": {"small": {"maximum": 10}},
		"properties": {
			"n": {"$ref": "#/definitions/small"},
			"tuple": {"items": [{"type": "integer"}, {"type": "string"}], "additionalItems": false},
			"below": {"maximum": 5, "exclusiveMaximum": true},
			"above": {"minimum": 5, "exclusiveMinimum": true},
			"pair": {"dependencies": {"a": ["b"], "c": {"required": ["d"]}}},
		},
	}
	TestUtil.check(_found({"n": 3, "tuple": [1, "x"], "below": 4, "above": 6, "pair": {"a": 1, "b": 2, "c": 3, "d": 4}}, legacy).is_empty(), "older drafts: definitions, items as a list, boolean exclusive limits, dependencies")
	var legacy_found: Array = _found({"n": 11, "tuple": [1, "x", 3], "below": 5, "above": 5, "pair": {"a": 1, "c": 3}}, legacy)
	TestUtil.check(legacy_found == ["/n maximum", "/tuple/2 false", "/below exclusiveMaximum", "/above exclusiveMinimum", "/pair dependencies", "/pair required"], "and each of them reports (%s)" % str(legacy_found))
	TestUtil.check(_found({"a~b": 1}, {"properties": {"a~b": {"type": "string"}}}) == ["/a~0b type"], "a key with ~ is escaped in the path")
	TestUtil.check(_found("\"caf\\u00e9\"", {"pattern": "^caf\\u00e9$"}).is_empty() and _found("\"cafe\"", {"pattern": "^caf\\u00e9$"}) == [" pattern"], "\\u escapes in a pattern")
	TestUtil.check(_found("\"a\\u00a0b\"", {"pattern": "^a\\sb$"}).is_empty() and _found("\"a\\u2003b\"", {"pattern": "^a\\Sb$"}) == [" pattern"], "\\s and \\S cover Unicode spaces")

	var message: String = ForgeJSONGD.validate_json({"zip": 12345}, {"properties": {"zip": {"type": "string"}}})[0].message
	TestUtil.check(message == "expected string, got integer", "the message says what was expected and what came (%s)" % message)

#endregion


#region Inputs

func _check_inputs() -> void:
	var schema: Dictionary = {"type": "object", "properties": {"score": {"type": "integer"}}, "required": ["score"]}
	var good_text: String = '{"score": 5}'
	var bad_text: String = '{"score": "five"}'
	FileAccess.open(TMP_DIR + "good.json", FileAccess.WRITE).store_string(good_text)
	FileAccess.open(TMP_DIR + "bad.json", FileAccess.WRITE).store_string(bad_text)
	FileAccess.open(TMP_DIR + "schema.json", FileAccess.WRITE).store_string(JSON.stringify(schema))
	for data: Variant in [{"score": 5}, good_text, TMP_DIR + "good.json"]:
		for schema_form: Variant in [schema, JSON.stringify(schema), TMP_DIR + "schema.json"]:
			TestUtil.check(_found(data, schema_form).is_empty(), "valid: data as %s, schema as %s" % [type_string(typeof(data)), type_string(typeof(schema_form))])
	for data: Variant in [{"score": "five"}, bad_text, TMP_DIR + "bad.json"]:
		TestUtil.check(_found(data, TMP_DIR + "schema.json") == ["/score type"], "invalid: data as %s" % type_string(typeof(data)))
	TestUtil.check(_found("[1, 2]", {"type": "array", "items": {"type": "integer"}}).is_empty() and _found("3", {"type": "integer"}).is_empty(), "the data can be any JSON value, not only an object")
	TestUtil.check(_found([1, "x"], {"items": {"type": "integer"}}) == ["/1 type"], "an Array is checked as it is")

	# An object is checked as its class_to_json: what would be saved or sent.
	var player: PlayerData = PlayerData.new()
	player.name = "Bob"
	TestUtil.check(_found(player, {"properties": {"name": {"const": "Bob"}, "score": {"type": "integer"}}}).is_empty(), "an object is checked as its JSON")
	TestUtil.check(_found(player, PlayerData).is_empty(), "an object against its own class")
	TestUtil.check(_found({"name": 5}, player) == ["/name type"], "an object as the schema stands for its class")

	# Encrypted files are read with json_file_to_dict, then checked.
	ForgeJSONGD.store_json_file(TMP_DIR + "secret.json", {"score": "five"}, "key")
	TestUtil.check(_found(ForgeJSONGD.json_file_to_dict(TMP_DIR + "secret.json", "key"), schema) == ["/score type"], "an encrypted file, read first")

	# Values that are not JSON become what JSON makes of them.
	TestUtil.check(_found({"path": NodePath("a/b"), "name": &"n", "ints": PackedInt32Array([1, 2])}, {"properties": {"path": {"type": "string"}, "name": {"type": "string"}, "ints": {"type": "array", "items": {"type": "integer"}}}}).is_empty(), "NodePath, StringName and packed arrays are checked as JSON text and arrays")

#endregion


#region Problems with the input or the schema

func _check_reports() -> void:
	TestUtil.check(_found("res://no/such/file.json", true) == [" json"], "data that is neither JSON nor a file is reported")
	TestUtil.check(_found("1", "res://no/such/schema.json") == [" json"], "a schema that cannot be read is reported")
	TestUtil.check(_found("1", "[1, 2]") == [" schema"], "a schema must be an object or a boolean")
	TestUtil.check(_found("1", {"minimum": "5"}) == [" minimum"], "a keyword with a wrong value is reported, not ignored")
	TestUtil.check(_found("1", {"type": 5}) == [" type"], "a type that is not text is reported")
	TestUtil.check(_found("\"a\"", {"pattern": "("}) == [" pattern"], "a pattern that is not a regular expression is reported")
	TestUtil.check(_found("1", {"unevaluatedProperties": false}) == [" unevaluatedProperties"], "an unsupported keyword is reported, so nothing passes unchecked")
	TestUtil.check(_found("1", {"$ref": "https://example.com/other.json"}) == [" $ref"], "a $ref to another file or URL is reported, never loaded")
	TestUtil.check(_found("1", {"$ref": "#/$defs/missing"}) == [" $ref"], "a $ref to a missing place is reported")
	TestUtil.check(_found("1", {"$defs": {"a": {"$ref": "#/$defs/b"}, "b": {"$ref": "#/$defs/a"}}, "$ref": "#/$defs/a"}) == [" $ref"], "a $ref that loops is reported instead of hanging")
	TestUtil.check(_found("1", {"x-custom": 1, "title": "t", "description": "d", "examples": [1], "default": 0, "format": "email", "$comment": "c", "deprecated": false, "readOnly": true, "writeOnly": false, "contentMediaType": "text/plain", "contentEncoding": "base64"}).is_empty(), "annotations and unknown keywords are allowed (as the standard says)")
	var deep: String = "[".repeat(300) + "]".repeat(300)
	var schema: Dictionary = {"$defs": {"any": {"items": {"$ref": "#/$defs/any"}}}, "$ref": "#/$defs/any"}
	TestUtil.check(_found(deep, schema).has(" depth") or not _found(deep, schema).is_empty(), "very deep data is reported instead of checked forever")
	var with_id: Dictionary = {"$id": "https://example.com/root.json", "$defs": {"name": {"$id": "name.json", "type": "string"}, "tag": {"$anchor": "tag", "maxLength": 3}}, "properties": {"a": {"$ref": "name.json"}, "b": {"$ref": "https://example.com/root.json#tag"}}}
	TestUtil.check(_found({"a": "x", "b": "abc"}, with_id).is_empty() and _found({"a": 1, "b": "abcd"}, with_id) == ["/a type", "/b maxLength"], "$id and $anchor inside the schema are found")

#endregion


#region Schemas that refer to other schemas

func _check_registered() -> void:
	var common: Dictionary = {"$defs": {"id": {"type": "integer", "minimum": 1}, "name": {"type": "string", "minLength": 2}}}
	var user: Dictionary = {"type": "object", "properties": {"id": {"$ref": "common.schema.json#/$defs/id"}, "name": {"$ref": "common.schema.json#/$defs/name"}}}
	TestUtil.check(_found({"id": 1}, user) == ["/id $ref"], "before registering, the $ref is reported (nothing is loaded)")
	TestUtil.check(ForgeJSONGD.validate_json({"id": 1}, user)[0].message.contains("register_schema"), "and the message says how to make it available")

	# Under a name given in the call.
	TestUtil.check(ForgeJSONGD.register_schema(common, "common.schema.json"), "register a dictionary under a name")
	TestUtil.check(_found({"id": 1, "name": "ann"}, user).is_empty() and _found({"id": 0, "name": "a"}, user) == ["/id minimum", "/name minLength"], "a $ref finds it by the name it is written with")
	ForgeJSONGD.clear_registered_schemas()
	TestUtil.check(_found({"id": 1}, user) == ["/id $ref"], "clear_registered_schemas forgets it")

	# From a file: registered under its file name.
	FileAccess.open(TMP_DIR + "common.schema.json", FileAccess.WRITE).store_string(JSON.stringify(common))
	TestUtil.check(ForgeJSONGD.register_schema(TMP_DIR + "common.schema.json"), "register a file")
	TestUtil.check(_found({"id": 0}, user) == ["/id minimum"], "a file is registered under its file name")
	TestUtil.check(ForgeJSONGD.register_schema(TMP_DIR + "common.schema.json", "shared/common.json") and _found({"id": 0}, {"properties": {"id": {"$ref": "shared/common.json#/$defs/id"}}}) == ["/id minimum"], "or under a name given in the call, with folders")
	ForgeJSONGD.clear_registered_schemas()

	# Under its $id, by full URL: also from a schema whose own $id makes the $ref relative.
	var with_url: Dictionary = common.duplicate(true)
	with_url["$id"] = "https://example.com/schemas/common.schema.json"
	TestUtil.check(ForgeJSONGD.register_schema(with_url), "register a schema that has an $id")
	TestUtil.check(_found({"id": 0}, {"properties": {"id": {"$ref": "https://example.com/schemas/common.schema.json#/$defs/id"}}}) == ["/id minimum"], "a $ref finds it by its full URL, without fetching anything")
	var api_user: Dictionary = {"$id": "https://example.com/schemas/user.schema.json", "properties": {"id": {"$ref": "common.schema.json#/$defs/id"}}}
	TestUtil.check(_found({"id": 0}, api_user) == ["/id minimum"], "a relative $ref from a schema with an $id resolves to the registered URL")

	# JSON text, a class, a registered schema that refers to another registered schema, and loops between them.
	TestUtil.check(ForgeJSONGD.register_schema('{"type": "string", "maxLength": 3}', "short.json") and _found("\"abcd\"", {"$ref": "short.json"}) == [" maxLength"], "register JSON text")
	TestUtil.check(ForgeJSONGD.register_schema(UserDto) and _found({"users": [{"id": "x"}]}, {"properties": {"users": {"items": {"$ref": "urn:forgejsongd:UserDto"}}}}) == ["/users/0/id type"], "register a class: it is found by its $id")
	ForgeJSONGD.register_schema({"$ref": "short.json", "minLength": 2}, "code.json")
	TestUtil.check(_found("\"a\"", {"$ref": "code.json"}) == [" minLength"] and _found("\"abcd\"", {"$ref": "code.json"}) == [" maxLength"], "a registered schema can refer to another registered one")
	ForgeJSONGD.register_schema({"$ref": "loop_b.json"}, "loop_a.json")
	ForgeJSONGD.register_schema({"$ref": "loop_a.json"}, "loop_b.json")
	TestUtil.check(_found("1", {"$ref": "loop_a.json"}) == [" $ref"], "registered schemas that refer to each other in a loop are reported, not followed forever")
	TestUtil.check(_found("1", {"$ref": "common.schema.json"}) == [" $ref"], "only registered names are found (common.schema.json is not registered under that name now)")

	# Registering fails clearly.
	TestUtil.check(not ForgeJSONGD.register_schema({"type": "string"}), "a schema without a name or $id is refused")
	TestUtil.check(not ForgeJSONGD.register_schema("res://no/such/schema.json"), "a file that cannot be read is refused")
	TestUtil.check(not ForgeJSONGD.register_schema("[1, 2]", "list.json"), "a schema that is not an object or a boolean is refused")
	ForgeJSONGD.clear_registered_schemas()

#endregion


#region Schemas of classes

func _check_class_schemas() -> void:
	var schema: Dictionary = ForgeJSONGD.class_to_json_schema(UserDto)
	TestUtil.check(schema.get("$schema") == "https://json-schema.org/draft/2020-12/schema" and schema.get("type") == "object" and schema.get("$ref") == "#/$defs/UserDto", "a class schema names the standard and its class")
	var user_def: Dictionary = schema["$defs"]["UserDto"]
	var properties: Dictionary = user_def.properties
	TestUtil.check(properties.has("userName") and not properties.has("user_name"), "properties use the JSON keys (_forge_json_keys)")
	TestUtil.check(not properties.has("secret"), "excluded variables are not in the schema")
	TestUtil.check(properties.id == {"type": "integer"} and properties.score == {"type": "number"} and properties.nickname == {"type": "string"}, "int, float and String (plain JSON)")
	TestUtil.check(properties.position.type == "object" and properties.position.required == ["x", "y"], "a Vector2 is {x, y} in plain JSON")
	TestUtil.check(properties.role.enum == ["Guest", "GUEST", "Admin", "ADMIN"], "an enum lists the names it is written with, and the names in the code (%s)" % str(properties.role.enum))
	TestUtil.check(properties.tags == {"type": "array", "items": {"type": "string"}}, "Array[String]")
	TestUtil.check(properties.friends.items.get("$ref") == "#/$defs/UserDto", "a class that contains itself refers to its own definition")
	TestUtil.check(properties.address.get("$ref") == "#/$defs/AddressDto" and "null" in properties.address.type, "an object variable: its class, or null (%s)" % str(properties.address))
	TestUtil.check(JSON.parse_string(JSON.stringify(schema)) is Dictionary, "the schema is plain JSON (it can be saved or sent)")
	TestUtil.check(schema.get("$id") == "urn:forgejsongd:UserDto", "the schema has an $id, so it can be put inside another schema")
	var list_schema: Dictionary = {"type": "array", "items": ForgeJSONGD.class_to_json_schema(UserDto)}
	TestUtil.check(_found([{"id": 1}, {"id": "x", "address": {"city": 2}}], list_schema) == ["/1/id type", "/1/address/city type"], "a list of objects of a class (%s)" % str(_found([{"id": 1}, {"id": "x", "address": {"city": 2}}], list_schema)))
	var both: Dictionary = {"type": "object", "properties": {"user": ForgeJSONGD.class_to_json_schema(UserDto), "login": ForgeJSONGD.class_to_json_schema(LoginDto)}}
	TestUtil.check(_found({"user": {"id": 1}, "login": {}}, both).is_empty() and _found({"user": {"id": "x"}}, both) == ["/user/id type"], "two class schemas inside one schema")
	TestUtil.check(ForgeJSONGD.class_to_json_schema(UserDto) == schema and ForgeJSONGD.class_to_json_schema(UserDto) != null, "the same schema every time")
	schema["$defs"].clear()
	TestUtil.check(not ForgeJSONGD.class_to_json_schema(UserDto)["$defs"].is_empty(), "changing a returned schema does not change the next one")

	# The same values in a save file (exact format): vectors as text, big ints may be text.
	var saved: Dictionary = ForgeJSONGD.class_to_json_schema(SavedUserDto)["$defs"]["SavedUserDto"].properties
	TestUtil.check(saved.position == {"type": "string", "pattern": "^Vector2\\("}, "a Vector2 is text in a save file")
	TestUtil.check(saved.bigId.type == ["integer", "string"], "an int may be text in a save file (above 2^53)")

	# Wrong data from a server is reported where it is.
	var bad_user: Dictionary = {"id": "7", "userName": 5, "address": {"city": 3}, "tags": ["a", 1], "position": {"x": 1}, "role": "BOSS", "color": "red!", "friends": [{"id": 1.5}]}
	var found: Array = _found(bad_user, UserDto)
	for expected: String in ["/id type", "/userName type", "/address/city type", "/tags/1 type", "/position required", "/role enum", "/color pattern", "/friends/0/id type"]:
		TestUtil.check(expected in found, "UserDto reports %s" % expected)
	TestUtil.check(found.size() == 8, "and nothing else (%s)" % str(found))
	TestUtil.check(_found({"id": 7, "address": null, "friends": [], "unknown_field": true}, UserDto).is_empty(), "null objects, missing fields and extra fields are allowed by default")

	# Loading stays forgiving; validation says what is wrong.
	var loaded: UserDto = ForgeJSONGD.json_to_class(UserDto, {"id": "7"})
	TestUtil.check(loaded.id == 7 and _found({"id": "7"}, UserDto) == ["/id type"], "json_to_class still reads \"7\" into an int; validate_json reports it")

	# only_exported_values changes what is saved, and so the schema.
	ForgeJSONGD.only_exported_values = true
	var exported_only: Dictionary = ForgeJSONGD.class_to_json_schema(PlayerData)["$defs"]["PlayerData"].properties
	ForgeJSONGD.only_exported_values = false
	var all_variables: Dictionary = ForgeJSONGD.class_to_json_schema(PlayerData)["$defs"]["PlayerData"].properties
	TestUtil.check(not exported_only.has("internal_variable") and all_variables.has("internal_variable"), "only_exported_values is followed")

	# A class that needs arguments in _init still gets its schema.
	var args_schema: Dictionary = ForgeJSONGD.class_to_json_schema(ArgsModel)["$defs"]["ArgsModel"]
	TestUtil.check(args_schema.properties.count == {"type": ["integer", "string"], "pattern": "^-?[0-9]+$"} and args_schema.properties.label == {"type": "string"}, "a class with _init arguments")
	TestUtil.check(_found(ForgeJSONGD.class_to_json(ArgsModel.new(3, "x")), ArgsModel).is_empty(), "and its JSON passes")

	# A class that writes itself (_forge_serialize) can hold anything.
	TestUtil.check(ForgeJSONGD.class_to_json_schema(CustomModel)["$defs"]["CustomModel"] == {}, "a class with _forge_serialize has an open schema")

#endregion


#region _forge_schema

func _check_hook() -> void:
	var schema: Dictionary = ForgeJSONGD.class_to_json_schema(SchemaUserDto)
	var definition: Dictionary = schema["$defs"]["SchemaUserDto"]
	TestUtil.check(definition.required == ["id", "userName"], "required names are mapped to JSON keys")
	TestUtil.check(definition.properties.userName == {"type": "string", "minLength": 3, "maxLength": 20}, "rules are added to the generated type")
	TestUtil.check(definition.properties.address.type == "object" and definition.properties.address.has("$ref"), "a rule can replace a generated keyword (address may not be null)")
	TestUtil.check(definition.additionalProperties == false, "a class can refuse unknown keys")

	var good: Dictionary = {"id": 1, "userName": "ann", "email": "a@b.c", "age": 30, "role": "ADMIN", "tags": ["x"], "address": {"city": "Rome", "zip": "1"}}
	TestUtil.check(_found(good, SchemaUserDto).is_empty(), "valid data passes the class rules (%s)" % str(_found(good, SchemaUserDto)))
	var bad: Dictionary = {"id": 0, "userName": "an", "email": "no-at", "age": 200, "tags": ["x", "x", "y", "z"], "address": null, "nick": "?"}
	var found: Array = _found(bad, SchemaUserDto)
	for expected: String in ["/id minimum", "/userName minLength", "/email pattern", "/age maximum", "/tags maxItems", "/tags uniqueItems", "/address type", "/nick additionalProperties"]:
		TestUtil.check(expected in found, "SchemaUserDto reports %s" % expected)
	TestUtil.check(_found({"userName": "ann"}, SchemaUserDto) == [" required"], "a missing required field")

	# The rules do not change saving or loading.
	var user: SchemaUserDto = ForgeJSONGD.json_to_class(SchemaUserDto, bad)
	TestUtil.check(user.user_name == "an" and user.age == 200, "loading ignores the rules (validate first when it matters)")

	# Validate, then load: the pattern the guide shows.
	var errors: Array[Dictionary] = ForgeJSONGD.validate_json(good, SchemaUserDto)
	var loaded: SchemaUserDto = ForgeJSONGD.json_to_class(SchemaUserDto, good) if errors.is_empty() else null
	TestUtil.check(loaded != null and loaded.address.city == "Rome", "validate, then load")

#endregion


#region Child classes in save files

func _check_polymorphism() -> void:
	var rex: Dog = Dog.new()
	rex.name = "Rex"
	rex.tricks = ["sit"]
	var zoo: Zoo = Zoo.new()
	zoo.star = rex
	zoo.animals = [rex, Cat.new(), Animal.new()]
	var json: Dictionary = ForgeJSONGD.class_to_json(zoo)
	TestUtil.check(_found(json, Zoo).is_empty(), "a save with child classes passes")
	var animal_def: Dictionary = ForgeJSONGD.class_to_json_schema(Zoo)["$defs"]["Animal"]
	TestUtil.check(animal_def.has("allOf") and str(animal_def.allOf).contains("Dog") and str(animal_def.allOf).contains("Cat"), "the parent class lists its child classes")
	json.star.tricks = "sit"
	json.animals[0].tricks = [5]
	TestUtil.check(_found(json, Zoo) == ["/animals/0/tricks/0 type", "/star/tricks type"] or _found(json, Zoo) == ["/star/tricks type", "/animals/0/tricks/0 type"], "a child class's own fields are checked by its class (%s)" % str(_found(json, Zoo)))

	ForgeJSONGD.register_script_alias(Dog, "dog_v1")
	var with_alias: Dictionary = ForgeJSONGD.class_to_json(zoo)
	with_alias.star.tricks = 1
	TestUtil.check(with_alias.star.script_inheritance == "dog_v1" and _found(with_alias, Zoo) == ["/star/tricks type"], "a child class saved under an alias is found too")
	ForgeJSONGD.clear_script_aliases()

	# Plain JSON names no classes: the declared class is checked, child fields are extra fields.
	var api_zoo: ApiZoo = ApiZoo.new()
	api_zoo.star = rex
	TestUtil.check(_found(api_zoo, ApiZoo).is_empty(), "a plain class with a child object passes")

#endregion


#region Every class accepts its own JSON

func _check_drift() -> void:
	var checked: int = 0
	for class_info: Dictionary in ProjectSettings.get_global_class_list():
		if class_info.path.begins_with("res://addons/") or class_info.class in NOT_DATA or class_info.class in RULES_NOT_MET_BY_DEFAULTS:
			continue
		var script: Script = load(class_info.path)
		var instance: Object = ForgeJSONGDSchema._instance_of(ForgeJSONGDSchema._Generation.new(), script)
		if instance == null:
			continue
		_check_own_json(class_info.class, script, instance)
		checked += 1
		TestUtil.free_object(instance)
	TestUtil.check(checked > 70, "every data class of the project was checked (%d)" % checked)

	# The filled objects of the fidelity test: every kind of data.
	var user: SchemaUserDto = ForgeJSONGD.json_to_class(SchemaUserDto, {"id": 1, "userName": "ann", "email": "ann@site.com", "address": {}})
	_check_own_json("SchemaUserDto (filled)", SchemaUserDto, user)
	var fidelity: Node = load("res://Tests/fidelity.gd").new()
	for sample: Dictionary in fidelity._samples():
		_check_own_json(sample.name, sample.script, sample.object)
	fidelity.free()


## The class's JSON, as a dictionary and as a file, passes the class's schema.
func _check_own_json(label: String, script: Script, instance: Object) -> void:
	var json: Dictionary = ForgeJSONGD.class_to_json(instance)
	var problems: Array = _found(json, script)
	TestUtil.check(problems.is_empty(), "[%s] its JSON passes its schema %s" % [label, "" if problems.is_empty() else str(ForgeJSONGD.validate_json(json, script))])
	var file: String = TMP_DIR + label.get_slice(" ", 0) + ".json"
	ForgeJSONGD.store_json_file(file, json)
	TestUtil.check(_found(file, script).is_empty(), "[%s] and so does its file" % label)
	TestUtil.check(_found(ForgeJSONGD.class_to_json(instance, true), script).is_empty(), "[%s] also with its class name stored" % label)

#endregion
