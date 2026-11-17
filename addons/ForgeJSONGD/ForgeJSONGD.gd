## Public API of the ForgeJSONGD addon. Every method here is static and a thin wrapper:
## the actual work lives in ForgeJSONGDSerializer, ForgeJSONGDDeserializer, ForgeJSONGDHelper, ForgeJSONGDValidator
## and ForgeJSONGDSchema.
##
## Settings (inherited from ForgeJSONGDBase):
##   ForgeJSONGD.only_exported_values - serialize only @export variables when true.
##   ForgeJSONGD.json_indent          - indentation of the files store_json_file writes ("\t" by default, "" for compact files).
##   ForgeJSONGD.sort_keys            - alphabetical keys when true (default), the order of the class's variables when false.
## Types:
##   ForgeJSONGD.Operation - operations accepted by json_operation().
##
## Optional methods a class can define to customize its own JSON (all start with _forge_):
##   func _forge_excluded_properties() -> Array   - names of variables to skip when saving and loading.
##   func _forge_extra_properties() -> Array      - names of built-in properties (position, rotation...) to save and load too.
##   func _forge_renamed_properties() -> Dictionary - {"old_name": "new_name"}: old saves still load into the renamed variable.
##   func _forge_json_keys() -> Dictionary        - {"variable_name": "jsonKey"}: the key a variable uses in the JSON (API field names).
##   func _forge_save_by_path() -> bool           - Resource classes: save a resource that comes from a file as its path.
##   func _forge_plain_json() -> bool             - return true for a class that talks to a web API: it is written and read as
##                                                  standard JSON (no class names, markers or prefixes; nothing in the data is interpreted).
##   func _forge_constructor_args() -> Array      - arguments for _init, stored and passed again on load.
##   func _forge_schema() -> Dictionary           - JSON Schema rules for validate_json and class_to_json_schema, added to
##                                                  what the variable types already say: {"required": [...], "properties": {"age": {"minimum": 0}}}.
##   func _forge_serialize() -> Dictionary        - replaces the automatic serialization of the class.
##   static func _forge_deserialize(json: Dictionary) -> Object - builds the instance from that dictionary.
@abstract class_name ForgeJSONGD extends ForgeJSONGDBase


#region Class to JSON

## Converts a class instance into a JSON dictionary.
## Set specify_class to true when the instance is a subclass (stores its script for loading later).
static func class_to_json(_class: Object, specify_class: bool = false) -> Dictionary:
	return ForgeJSONGDSerializer.class_to_json(_class, specify_class)


## Converts a class instance into a JSON string.
static func class_to_json_string(_class: Object, specify_class: bool = false) -> String:
	return _stringify(class_to_json(_class, specify_class), "", sort_keys)


## Stores a JSON dictionary to a file, encrypted when a security_key is given. Returns false on failure.
static func store_json_file(file_path: String, data: Dictionary, security_key: String = "") -> bool:
	return _write_json_file(file_path, data, security_key)

#endregion


#region JSON to Class

## Converts a JSON dictionary into an instance of the given script (or fills the given instance).
## Pass null as the script to use the script stored in the JSON.
static func json_to_class(gdscript_or_instance: Variant, json: Dictionary) -> Object:
	return ForgeJSONGDDeserializer.json_to_class(gdscript_or_instance, json)


## Converts a JSON string into a class instance. Returns null if the string is not a JSON object.
static func json_string_to_class(gdscript_or_instance: Variant, json_string: String) -> Object:
	var json: Variant = _parse_json_object(json_string)
	return json_to_class(gdscript_or_instance, json) if json != null else null


## Loads a JSON file into a class instance. If the file is missing or empty and a Script was given,
## returns a fresh instance of it.
static func json_file_to_class(gdscript_or_instance: Variant, file_path: String, security_key: String = "") -> Object:
	var parsed_results: Dictionary = json_file_to_dict(file_path, security_key)
	if parsed_results.is_empty() and gdscript_or_instance is Script:
		return gdscript_or_instance.new()
	return json_to_class(gdscript_or_instance, parsed_results)


## Loads a JSON file into a Dictionary, decrypting when a security_key is given. Returns {} on failure.
static func json_file_to_dict(file_path: String, security_key: String = "") -> Dictionary:
	return _read_json_file(file_path, security_key)

#endregion


#region JSON utilities
## The json arguments below accept a Dictionary, a JSON string, a JSON file path or an Object.

## Returns true if both JSONs are equal.
static func check_equal_jsons(first_json: Variant, second_json: Variant) -> bool:
	return _jsons_equal(_get_dict_from_type(first_json), _get_dict_from_type(second_json))


## Returns the differences as {key: {"old": ..., "new": ...}}, or {} if they are equal.
static func compare_jsons_diff(first_json: Variant, second_json: Variant) -> Dictionary:
	var first_dict: Dictionary = _get_dict_from_type(first_json)
	var second_dict: Dictionary = _get_dict_from_type(second_json)
	if _jsons_equal(first_dict, second_dict):
		return {}
	return ForgeJSONGDHelper.compare_recursive(first_dict, second_dict)


## Applies an Operation to base_json using ref_json as the reference and returns the result.
## The inputs are not modified.
static func json_operation(base_json: Variant, ref_json: Variant, operation_type: Operation) -> Dictionary:
	var base_dict: Dictionary = _get_dict_from_type(base_json).duplicate(true)
	var ref_dict: Dictionary = _get_dict_from_type(ref_json)

	# Identical inputs short-circuit.
	if _jsons_equal(base_dict, ref_dict):
		if operation_type == Operation.Replace:
			return base_dict
		if operation_type == Operation.Remove or operation_type == Operation.RemoveValue:
			return {}
	return ForgeJSONGDHelper.apply_operation_recursively(base_dict, ref_dict, operation_type)

#endregion


#region Validation

## Checks JSON data against a schema and returns the problems found; an empty array means the data is valid.
## Each problem is {"path": "/address/zip", "message": "expected string, got integer", "keyword": "type", "schema_path": "..."}.
## json: a Dictionary, Array or other JSON value, JSON text, a JSON file path, or an object (checked as its class_to_json).
## schema: a Script (the class is the schema, see class_to_json_schema), or a JSON Schema as a Dictionary, JSON text or file path.
static func validate_json(json: Variant, schema: Variant) -> Array[Dictionary]:
	return ForgeJSONGDValidator.validate(json, schema)


## The JSON Schema (draft 2020-12) of the JSON that class_to_json writes for the class: its variable types,
## plus the rules from its _forge_schema(). Give it to a server, to API docs, or to validate_json.
static func class_to_json_schema(script: Script) -> Dictionary:
	return ForgeJSONGDSchema.class_to_json_schema(script)


## Makes a schema available to "$ref" in other schemas ("$ref": "common.schema.json#/$defs/id"). A $ref never loads
## files or URLs by itself: it finds only schemas registered here. The schema is a Dictionary, JSON text, a file path
## or a Script; it is registered under uri, else its "$id", else (for a file) its file name. Returns false on failure.
static func register_schema(schema: Variant, uri: String = "") -> bool:
	return ForgeJSONGDValidator.register_schema(schema, uri)


## Forgets every schema registered with register_schema.
static func clear_registered_schemas() -> void:
	ForgeJSONGDValidator.clear_registered_schemas()

#endregion


#region Script registry (optional safety)
## By default any script can be created from the script name/path stored in a JSON file.
## Once at least one script is registered, only registered scripts are created from JSON data
## (scripts you pass yourself, like json_to_class(PlayerData, json), are always allowed).

## Allows a script to be created from JSON data. Register every class that can appear, including child classes.
static func register_script(script: Script) -> void:
	if not script in _registered_scripts:
		_registered_scripts.append(script)


## Allows several scripts to be created from JSON data. See register_script().
static func register_scripts(scripts: Array[Script]) -> void:
	for script: Script in scripts:
		register_script(script)


## Removes every registered script, so any script is allowed again.
static func clear_registered_scripts() -> void:
	_registered_scripts.clear()

#endregion


#region Script aliases (stable names)
## A script is saved under its class_name. An alias is a name you choose and keep, so renaming the class
## (or moving a script without a class_name) does not break saves that already exist.

## Saves and loads the script under the given alias. With save_as = false the alias is only used when loading:
## use it for the old name of a class you renamed.
static func register_script_alias(script: Script, alias: String, save_as: bool = true) -> void:
	if _script_aliases.has(alias) and _script_aliases[alias] != script:
		push_warning("ForgeJSONGD: the alias '%s' now names another script." % alias)
	_script_aliases[alias] = script
	if save_as:
		_alias_of[script] = alias
	ForgeJSONGDSchema._clear_cache() # aliases are part of generated schemas


## Removes every alias.
static func clear_script_aliases() -> void:
	_script_aliases.clear()
	_alias_of.clear()
	ForgeJSONGDSchema._clear_cache()

#endregion


#region Advanced

## Recursively converts an Array into a JSON-compatible Array.
static func convert_array_to_json(array: Array) -> Array:
	return ForgeJSONGDSerializer.convert_array_to_json(array)


## Recursively converts a Dictionary into a JSON-compatible Dictionary.
static func convert_dictionary_to_json(dictionary: Dictionary) -> Dictionary:
	return ForgeJSONGDSerializer.convert_dictionary_to_json(dictionary)

#endregion
