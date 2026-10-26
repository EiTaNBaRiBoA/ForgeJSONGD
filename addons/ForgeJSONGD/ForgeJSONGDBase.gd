## Shared constants and utilities used by every ForgeJSONGD class. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDBase

## Key written into a JSON dictionary to record which script an object was created from.
const SCRIPT_INHERITANCE = "script_inheritance"

## Key of the marker object that stores a resource file path in an untyped place (Variant, untyped Array/Dictionary).
const _RESOURCE_PATH = "forge_resource_path"

## Key written into a JSON dictionary with the arguments for the script's _init (see _forge_constructor_args).
const CONSTRUCTOR_ARGS = "script_constructor_args"

## Key written next to SCRIPT_INHERITANCE for scripts without a class_name: their uid, to find them again if the file moved.
const _SCRIPT_UID = "script_uid"

## Marker objects for numbers in untyped places. JSON has one number type, so a whole number is read back as an int:
## a whole-number float is stored as {_FLOAT_MARKER: 5.0}, an int too large for a double as {_INT_MARKER: "9007199254740993"}.
const _FLOAT_MARKER = "forge_float"
const _INT_MARKER = "forge_int"

## Prefix for text that would otherwise be read as something else ("Vector2(1, 2)"...).
const _TEXT_PREFIX = "forge_text:"

## Prefixes of dictionary keys that are not text, in a dictionary whose keys are not typed: ints, floats and bools.
## (JSON keys are always text. Text keys are written as they are, so ordinary dictionaries are not changed.)
const _KEY_INT = "forge_int:"
const _KEY_FLOAT = "forge_float:"
const _KEY_BOOL = "forge_bool:"

## Whole numbers up to this size (2^53) are exact in a JSON number.
const _MAX_SAFE_INT = 9007199254740992

## String prefixes (before the opening bracket) of types that str_to_var may safely parse.
const _SAFE_PREFIXES: Array[String] = [
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
	"Rect2", "Rect2i", "Plane", "Quaternion", "AABB", "Basis",
	"Transform2D", "Transform3D", "Projection", "Color",
	"PackedByteArray", "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array", "PackedFloat64Array",
	"PackedStringArray", "PackedVector2Array", "PackedVector3Array", "PackedVector4Array", "PackedColorArray"
]

## Built-in types that JSON can't represent. In untyped slots (Variant, untyped Array/Dictionary) they are
## stored as var_to_str text so their type survives. Vectors are handled separately.
const _TAGGED_TYPES: Array[int] = [
	TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_PLANE, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D,
	TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_COLOR, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY,
	TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY,
	TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY
]

## The part of _TAGGED_TYPES that JSON.stringify can only write as display text ("[P: (1.0, 2.0)...]"). A variable declared
## with one of these types is stored with var_to_str too. (The others, like PackedInt32Array, are fine as JSON arrays.)
const _TEXT_RENDERED_TYPES: Array[int] = [
	TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_PLANE, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D,
	TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY
]

## Defines the types of operations that can be performed on the data structures.
enum Operation {
	Add, # Adds values. If key exists, combines them into an array.
	AddDiffer, # Adds or merges values only if they are different.
	Replace, # Replaces values in the base structure with values from the reference.
	Remove, # Removes keys/values present in the reference structure from the base.
	RemoveValue # Removes keys/values only if their values match the reference.
}

## If true only exported values will be serialized or deserialized.
static var only_exported_values: bool = false

## Indentation of the files written by store_json_file. A tab by default, "" writes compact files.
static var json_indent: String = "\t"

## If true (default) keys are written in alphabetical order. If false they keep the order of the variables in the class.
static var sort_keys: bool = true

## True while a class that returns true from _forge_plain_json() (and everything inside it) is converted: plain, standard
## JSON with nothing Godot-specific added or interpreted (no class names, markers, prefixes or text forms of numbers and strings).
static var _plain: bool = false

## Stable names for scripts, so saves survive a rename or a move. Alias -> Script, and Script -> the alias it is saved with.
static var _script_aliases: Dictionary = {}
static var _alias_of: Dictionary = {}

## Global class name -> script path, read once from ProjectSettings.
static var _global_class_paths: Dictionary = {}

## Scripts allowed to be created from names/paths found in JSON. Empty means any script is allowed.
static var _registered_scripts: Array[Script] = []


#region Files

## Creates the directory of the given file path if it doesn't exist.
static func _check_dir(file_path: String) -> void:
	if not DirAccess.dir_exists_absolute(file_path.get_base_dir()):
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())


## Opens a file for reading or writing, encrypted when a security key is given. Returns null on failure.
static func _open_file(file_path: String, mode: FileAccess.ModeFlags, security_key: String = "") -> FileAccess:
	if security_key.is_empty():
		return FileAccess.open(file_path, mode)
	return FileAccess.open_encrypted_with_pass(file_path, mode, security_key)


## Writes a dictionary as JSON to a file (indented with json_indent). Returns false on failure.
static func _write_json_file(file_path: String, data: Dictionary, security_key: String = "") -> bool:
	_check_dir(file_path)
	var file: FileAccess = _open_file(file_path, FileAccess.WRITE, security_key)
	if not file:
		printerr("Error writing to a file")
		return false
	file.store_string(JSON.stringify(data, json_indent, sort_keys, true)) # full_precision: floats keep every digit
	file.close()
	return true


## Reads a JSON file into a Dictionary. Returns an empty Dictionary on any failure.
static func _read_json_file(file_path: String, security_key: String = "") -> Dictionary:
	if not FileAccess.file_exists(file_path):
		return {}
	var file: FileAccess = _open_file(file_path, FileAccess.READ, security_key)
	if not file:
		printerr("Error opening file: ", file_path)
		return {}
	var text: String = file.get_as_text()
	file.close()
	if text.strip_edges().is_empty():
		return {}
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK:
		printerr("ForgeJSONGD: invalid JSON in %s (line %d): %s" % [file_path, parser.get_error_line(), parser.get_error_message()])
		return {}
	if not parser.data is Dictionary:
		printerr("ForgeJSONGD: %s does not contain a JSON object." % file_path)
		return {}
	return parser.data

#endregion


#region Checks and Gets

## Checks if a property should be included during serialization or deserialization.
static func _check_valid_property(property: Dictionary) -> bool:
	return property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (not only_exported_values or property.usage & PROPERTY_USAGE_STORAGE)


## Returns true if the value is one of the six vector types.
static func _is_vector(value: Variant) -> bool:
	return _is_vector_type(typeof(value))


## Calls an optional _forge_ method of a class (see the list in ForgeJSONGD.gd), or returns the fallback if it has none.
static func _hook(object: Object, hook_name: String, fallback: Variant) -> Variant:
	return object.call(hook_name) if object.has_method(hook_name) else fallback


## True for the six vector types.
static func _is_vector_type(type: Variant) -> bool:
	return type is int and type in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]


## A vector as the standard JSON object {"x": 1, "y": 2}.
static func _vector_to_dict(vector: Variant) -> Dictionary:
	var result: Dictionary = {"x": vector.x, "y": vector.y}
	if typeof(vector) in [TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
		result["z"] = vector.z
	if typeof(vector) in [TYPE_VECTOR4, TYPE_VECTOR4I]:
		result["w"] = vector.w
	return result


## Builds a vector of the given type from {"x": 1, "y": 2}. Returns null if a component is missing or is not a number.
static func _vector_from_dict(type: int, data: Dictionary) -> Variant:
	var names: Array = ["x", "y"]
	if type in [TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
		names.append("z")
	if type in [TYPE_VECTOR4, TYPE_VECTOR4I]:
		names.append("w")
	var numbers: Array = []
	for component: String in names:
		var number: Variant = data.get(component)
		if not (number is float or number is int):
			return null
		numbers.append(number)
	match type:
		TYPE_VECTOR2:
			return Vector2(numbers[0], numbers[1])
		TYPE_VECTOR2I:
			return Vector2i(int(numbers[0]), int(numbers[1]))
		TYPE_VECTOR3:
			return Vector3(numbers[0], numbers[1], numbers[2])
		TYPE_VECTOR3I:
			return Vector3i(int(numbers[0]), int(numbers[1]), int(numbers[2]))
		TYPE_VECTOR4:
			return Vector4(numbers[0], numbers[1], numbers[2], numbers[3])
		TYPE_VECTOR4I:
			return Vector4i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3]))
	return null


## True if the script defines a method with this name (its own or inherited from a script).
static func _script_has_method(script: Script, method_name: String) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if method.name == method_name:
			return true
	return false


## True for a resource from a file whose class asks to be saved as its path with _forge_save_by_path().
static func _is_saved_by_path(resource: Resource) -> bool:
	return _hook(resource, "_forge_save_by_path", false)


## Returns true if the script may be created from JSON data (always true when nothing is registered).
static func _is_script_allowed(script: Script) -> bool:
	return _registered_scripts.is_empty() or script in _registered_scripts


## Finds the script a JSON object names with "script_inheritance": an alias, a class name, a path, the uid stored
## next to it (the file may have moved), or "::Name" for a class declared inside the script of owner.
## Returns null if there is none, it is unknown or not registered. Plain JSON never names a script.
static func _script_from_json(json: Dictionary, owner: Object = null) -> Script:
	if _plain or not json.get(SCRIPT_INHERITANCE) is String:
		return null
	var script_name: String = json[SCRIPT_INHERITANCE]
	if script_name.begins_with("::"):
		return _find_inner_script(owner, script_name.substr(2)) # the owner's own code, so the allow-list does not apply
	var script: Script = _script_aliases.get(script_name)
	if script == null:
		script = _get_gdscript(script_name)
	if script == null and json.get(_SCRIPT_UID) is String:
		var uid: int = ResourceUID.text_to_id(json[_SCRIPT_UID])
		if ResourceUID.has_id(uid):
			script = load(ResourceUID.get_id_path(uid)) as Script
	if script != null and not _is_script_allowed(script):
		push_warning("ForgeJSONGD: script '%s' is not registered, ignoring it." % script_name)
		return null
	return script


## Finds a class declared inside the script of owner (or of one of its base scripts).
static func _find_inner_script(owner: Object, class_name_text: String) -> Script:
	var owner_script: Script = owner.get_script() if owner != null else null
	while owner_script != null:
		var constants: Dictionary = owner_script.get_script_constant_map()
		if constants.get(class_name_text) is Script:
			return constants[class_name_text]
		owner_script = owner_script.get_base_script()
	return null


## Finds the script of a variable's declared class: a global class, or a class declared inside the owner's script.
static func _get_declared_script(owner: Object, hint_class: String) -> Script:
	var script: Script = _get_gdscript(hint_class)
	return script if script != null else _find_inner_script(owner, hint_class)


## True for an int that a JSON number cannot hold exactly (2^53 and above, in either direction).
static func _is_unsafe_int(number: int) -> bool:
	return number >= _MAX_SAFE_INT or number <= -_MAX_SAFE_INT


## True when a container is not typed, so nothing tells the type of its values when loading.
static func _is_untyped(type: Variant) -> bool:
	return type == null or (type is int and type == TYPE_NIL)


## Text that would be read as something else gets _TEXT_PREFIX: a Godot value ("Vector2(1, 2)") and text starting
## with the prefix itself. A dictionary key is also escaped when it starts like a tagged number or bool key.
static func _escape_text(text: String, is_key: bool = false) -> String:
	if text.begins_with(_TEXT_PREFIX) or _is_safe_type(text):
		return _TEXT_PREFIX + text
	if is_key and (text.begins_with(_KEY_INT) or text.begins_with(_KEY_FLOAT) or text.begins_with(_KEY_BOOL)):
		return _TEXT_PREFIX + text
	return text


## The text of a number or bool dictionary key in an untyped dictionary, with a tag that says its type.
static func _tag_key(key: Variant) -> String:
	match typeof(key):
		TYPE_INT:
			return _KEY_INT + str(key)
		TYPE_FLOAT:
			return _KEY_FLOAT + JSON.stringify(key, "", true, true)
		_:
			return _KEY_BOOL + ("true" if key else "false")


## Reads a key written by _tag_key. Returns null if the text is not a tagged key.
static func _untag_key(text: String) -> Variant:
	if text.begins_with(_KEY_INT) and text.substr(_KEY_INT.length()).is_valid_int():
		return text.substr(_KEY_INT.length()).to_int()
	if text.begins_with(_KEY_FLOAT) and text.substr(_KEY_FLOAT.length()).is_valid_float():
		return text.substr(_KEY_FLOAT.length()).to_float()
	if text.begins_with(_KEY_BOOL):
		var value: String = text.substr(_KEY_BOOL.length())
		if value == "true" or value == "false":
			return value == "true"
	return null


## Removes _TEXT_PREFIX from text written by _escape_text.
static func _unescape_text(text: String) -> String:
	return text.substr(_TEXT_PREFIX.length()) if text.begins_with(_TEXT_PREFIX) else text


## Finds a Script by its global class name or resource path.
static func _get_gdscript(hint_class: String) -> Script:
	if _global_class_paths.is_empty():
		for class_info: Dictionary in ProjectSettings.get_global_class_list(): # the list is built once, not for every object
			_global_class_paths[class_info.class] = class_info.path
	if _global_class_paths.has(hint_class):
		return load(_global_class_paths[hint_class])
	if ResourceLoader.exists(hint_class):
		return load(hint_class)
	return null


## Extracts the main path from a resource path (removes the sub-resource part if present).
static func _get_main_tres_path(path: String) -> String:
	return path.split("::", true, 1)[0]


## Parses JSON text. Returns the Dictionary, or null if the text is not valid JSON or not a JSON object.
static func _parse_json_object(text: String) -> Variant:
	var parser: JSON = JSON.new()
	if parser.parse(text) == OK and parser.data is Dictionary:
		return parser.data
	return null


## Gets a dictionary from an object, a dictionary, a JSON string or a JSON file path.
static func _get_dict_from_type(json: Variant) -> Dictionary:
	if json is Dictionary:
		return json
	if json is Object:
		return ForgeJSONGDSerializer.class_to_json(json)
	if not json is String:
		return {}
	var parsed: Variant = _parse_json_object(json)
	if parsed != null:
		return parsed
	# Not a JSON string, so treat it as a file path.
	return _read_json_file(json)


## Converts data to what it would be after being saved and loaded again: numbers become floats,
## keys are sorted and text-like values become strings. Makes data from files and classes comparable.
static func _normalize_json(data: Variant) -> Variant:
	return JSON.parse_string(JSON.stringify(data))


## Checks if two dictionaries hold the same JSON data, ignoring key order and int/float differences.
static func _jsons_equal(first: Dictionary, second: Dictionary) -> bool:
	return _normalize_json(first) == _normalize_json(second)


## Checks if a string is safe to be processed by str_to_var.
static func _is_safe_type(p_str: String) -> bool:
	if p_str.is_empty():
		return false

	var is_safe := false
	for prefix: String in _SAFE_PREFIXES:
		if p_str.begins_with(prefix + "(") and p_str.ends_with(")"):
			is_safe = true
			break
	# Also allow NodePath and StringName literals
	if not is_safe:
		is_safe = (p_str.begins_with("@\"") or p_str.begins_with("&\"")) and p_str.ends_with("\"")

	# Even a safe-looking string must not contain dangerous instantiations
	return is_safe and not ("Object(" in p_str or "Callable(" in p_str or "Signal(" in p_str)

#endregion
