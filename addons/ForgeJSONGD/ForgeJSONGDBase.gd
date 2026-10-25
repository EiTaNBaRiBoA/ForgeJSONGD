## Shared constants and utilities used by every ForgeJSONGD class. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDBase

## Key written into a JSON dictionary to record which script an object was created from.
const SCRIPT_INHERITANCE = "script_inheritance"

## Key of the marker object that stores a resource file path in an untyped place (Variant, untyped Array/Dictionary).
const RESOURCE_PATH = "forge_resource_path"

## Key written into a JSON dictionary with the arguments for the script's _init (see _forge_constructor_args).
const CONSTRUCTOR_ARGS = "script_constructor_args"

## Key written next to SCRIPT_INHERITANCE for scripts without a class_name: their uid, to find them again if the file moved.
const SCRIPT_UID = "script_uid"

## Marker objects for numbers in untyped places. JSON has one number type, so a whole number is read back as an int:
## a whole-number float is stored as {FLOAT_MARKER: 5.0}, an int too large for a double as {INT_MARKER: "9007199254740993"}.
const FLOAT_MARKER = "forge_float"
const INT_MARKER = "forge_int"

## Prefix for text that would otherwise be read as something else (a number as a dictionary key, "Vector2(1, 2)"...).
const TEXT_PREFIX = "forge_text:"

## Whole numbers up to this size (2^53) are exact in a JSON number.
const MAX_SAFE_INT = 9007199254740992

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


## Writes a dictionary as tab-indented JSON to a file. Returns false on failure.
static func _write_json_file(file_path: String, data: Dictionary, security_key: String = "") -> bool:
	_check_dir(file_path)
	var file: FileAccess = _open_file(file_path, FileAccess.WRITE, security_key)
	if not file:
		printerr("Error writing to a file")
		return false
	file.store_string(JSON.stringify(data, "\t", true, true)) # full_precision: floats keep every digit
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


## Returns true if the value's type is one of the Vector types.
static func _is_vector(value: Variant) -> bool:
	return type_string(typeof(value)).begins_with("Vector")


## Returns the property names a class asks to skip with _forge_excluded_properties().
static func _get_excluded_properties(object: Object) -> Array:
	if object.has_method("_forge_excluded_properties"):
		return object._forge_excluded_properties()
	return []


## Returns true if the script may be created from JSON data (always true when nothing is registered).
static func _is_script_allowed(script: Script) -> bool:
	return _registered_scripts.is_empty() or script in _registered_scripts


## Finds a Script named inside JSON data. Returns null if it is unknown or not registered.
## json is the dictionary holding the name: it can carry the script's uid, used when the file was moved.
static func _get_json_script(hint_class: String, json: Dictionary = {}) -> Script:
	var script: Script = _get_gdscript(hint_class)
	if script == null and json.get(SCRIPT_UID) is String:
		var uid: int = ResourceUID.text_to_id(json[SCRIPT_UID])
		if ResourceUID.has_id(uid):
			script = load(ResourceUID.get_id_path(uid)) as Script
	if script != null and not _is_script_allowed(script):
		push_warning("ForgeJSONGD: script '%s' is not registered, ignoring it." % hint_class)
		return null
	return script


## Finds the script of a variable's declared class: a global class, or a class declared inside the owner's script.
static func _get_declared_script(owner: Object, hint_class: String) -> Script:
	var script: Script = _get_gdscript(hint_class)
	if script != null:
		return script
	var owner_script: Script = owner.get_script() if owner != null else null
	while owner_script != null:
		var constants: Dictionary = owner_script.get_script_constant_map()
		if constants.get(hint_class) is Script:
			return constants[hint_class]
		owner_script = owner_script.get_base_script()
	return null


## True for an int that a JSON number cannot hold exactly (2^53 and above, in either direction).
static func _is_unsafe_int(number: int) -> bool:
	return number >= MAX_SAFE_INT or number <= -MAX_SAFE_INT


## True when a container is not typed, so nothing tells the type of its values when loading.
static func _is_untyped(type: Variant) -> bool:
	return type == null or (type is int and type == TYPE_NIL)


## Text that would be read as something else gets TEXT_PREFIX: a Godot value ("Vector2(1, 2)"), text starting with the
## prefix itself, and, for keys of untyped dictionaries, text that looks like a number or a bool.
static func _escape_text(text: String, is_untyped_key: bool = false) -> String:
	if text.begins_with(TEXT_PREFIX) or _is_safe_type(text):
		return TEXT_PREFIX + text
	if is_untyped_key and (text.is_valid_int() or text.is_valid_float() or text == "true" or text == "false"):
		return TEXT_PREFIX + text
	return text


## Removes TEXT_PREFIX from text written by _escape_text.
static func _unescape_text(text: String) -> String:
	return text.substr(TEXT_PREFIX.length()) if text.begins_with(TEXT_PREFIX) else text


## Finds a Script by its global class name or resource path.
static func _get_gdscript(hint_class: String) -> Script:
	for class_info: Dictionary in ProjectSettings.get_global_class_list():
		if class_info.class == hint_class:
			return load(class_info.path)
	if ResourceLoader.exists(hint_class):
		return load(hint_class)
	return null


## Extracts the main path from a resource path (removes the sub-resource part if present).
static func _get_main_tres_path(path: String) -> String:
	return path.split("::", true, 1)[0]


## Gets a dictionary from an object, a dictionary, a JSON string or a JSON file path.
static func _get_dict_from_type(json: Variant) -> Dictionary:
	if json is Dictionary:
		return json
	if json is Object:
		return ForgeJSONGDSerializer.class_to_json(json)
	var parser: JSON = JSON.new()
	if parser.parse(json) == OK and parser.data is Dictionary:
		return parser.data
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
