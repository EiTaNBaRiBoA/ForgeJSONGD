@abstract class_name ForgeJSONGDBase

const SCRIPT_INHERITANCE = "script_inheritance"

## If ture only exported values will be serialized or deserialized.
static var only_exported_values: bool = false

#region Checks and Gets

## Checks if the directory for the given file path exists, creating it if necessary.
static func _check_dir(file_path: String) -> void:
	if !DirAccess.dir_exists_absolute(file_path.get_base_dir()):
		DirAccess.make_dir_absolute(file_path.get_base_dir())

## Checks if the provided class is valid (not null)
static func _check_cast_class(gdscript_or_instace: Variant) -> bool:
	if typeof(gdscript_or_instace) == Variant.Type.TYPE_NIL:
		printerr("The provided class or object is null.")
		return false
	return true

## Checks if a property should be included during serialization or deserialization. if script_type is not gdscript , then it is called from other languages
static func _check_valid_property(property: Variant) -> bool:
	return property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and (!only_exported_values or property.usage & PROPERTY_USAGE_STORAGE)

## Helper function to find a GDScript by its class name.
static func _get_gdscript(hint_class: String) -> GDScript:
	for className: Dictionary in ProjectSettings.get_global_class_list():
		if className.class == hint_class:
			return load(className.path)
	return null

## Extracts the main path from a resource path (removes node path if present).
static func _get_main_tres_path(path: String) -> String:
	var path_parts: PackedStringArray = path.split("::", true, 1)
	if path_parts.size() > 0:
		return path_parts[0]
	else:
		return path

## Get's a dictionary from a given string or dictionary if it is a path or dictionary or string
static func _get_dict_from_type(json: Variant) -> Dictionary:
	var dict: Dictionary = {}
	if json is Dictionary:
		dict = json
	elif json is Object:
		dict = ForgeJSONGD.class_to_json(json)
	else:
		var result = JSON.parse_string(json)
		if result == null:
			#first_json is not a file json string , loading it from path
			dict = ForgeJSONGD.json_file_to_dict(json)
		else:
			dict = result
	return dict

#endregion

#region Converters

#region Class to Json

## Helper function to recursively convert Godot arrays to JSON arrays.
static func convert_array_to_json(array: Array) -> Array:
	var json_array: Array = []
	for element: Variant in array:
		json_array.append(_serialize_variant(element, array.is_typed()))
	return json_array

## Helper function to recursively convert Godot dictionaries to JSON dictionaries.
static func convert_dictionary_to_json(dictionary: Dictionary) -> Dictionary:
	var json_dictionary: Dictionary = {}
	for key: Variant in dictionary.keys():
		var parsed_key: Variant = _serialize_variant(key, dictionary.is_typed())
		var parsed_value: Variant = _serialize_variant(dictionary.get(key), dictionary.is_typed())
		if typeof(parsed_value) == TYPE_INT: # casting to float due to json parse in godot will always parse int and enum as float
			json_dictionary.set(parsed_key, float(parsed_value))
		else:
			json_dictionary.set(parsed_key, parsed_value)
	return json_dictionary

# Converts a Godot Variant into a JSON-compatible Variant.
static func _serialize_variant(variant_value: Variant, is_parent_typed: bool = false) -> Variant:
	if variant_value is Object:
		# If the parent is typed, the script path isn't needed. If untyped, it is.
		var specify_script = not is_parent_typed
		return ForgeJSONGD.class_to_json(variant_value, specify_script)
	elif variant_value is Array:
		return convert_array_to_json(variant_value)
	elif variant_value is Dictionary:
		return convert_dictionary_to_json(variant_value)
	elif type_string(typeof(variant_value)).begins_with("Vector"):
		return var_to_str(variant_value)
	elif variant_value is int and not is_parent_typed:
		# Godot's JSON.parse_string treats all numbers as floats.
		# To ensure type consistency on deserialization, we cast all ints to floats here.
		return float(variant_value)
	else:
		if typeof(variant_value) == TYPE_COLOR:
			return variant_value.to_html()
		# For all other primitive types (float, string, bool), return as is.
		return variant_value

#endregion

#region Json to Class

## Helper function to recursively convert a JSON dictionary into a target dictionary.
static func _convert_json_to_dictionary(property_dict: Dictionary, json_dict: Dictionary) -> void:
	var key_type_script: GDScript = property_dict.get_typed_key_script()
	var value_type_script: GDScript = property_dict.get_typed_value_script()
	for json_key: Variant in json_dict:
		var json_value: Variant = json_dict.get(json_key)
		var converted_key: Variant = _convert_variant(json_key, key_type_script)
		var converted_value: Variant = _convert_variant(json_value, value_type_script)
		property_dict.set(converted_key, converted_value)

## Helper function to recursively convert a JSON array to a Godot array.
static func _convert_json_to_array(json_array: Array, type: Variant = null) -> Array:
	var godot_array: Array = []
	for element: Variant in json_array:
		godot_array.append(_convert_variant(element, type))
	return godot_array

## Converts a single Variant from JSON into its target Godot type.
static func _convert_variant(json_variant: Variant, type: Variant = null) -> Variant:
	var processed_variant: Variant = json_variant
	# Process the variant based on its actual type.
	if processed_variant is Dictionary or type is Object:
		var script: GDScript = null
		if SCRIPT_INHERITANCE in processed_variant:
			# Prioritize script path embedded in the JSON data.
			script = _get_gdscript(processed_variant.get(SCRIPT_INHERITANCE))
		elif type is GDScript:
			# Fallback to the type hint from the parent array/dictionary.
			script = load(type.get_path())
		
		if script != null:
			if processed_variant is String:
				return ForgeJSONGD.json_to_class(script, JSON.parse_string(processed_variant))
			return ForgeJSONGD.json_to_class(script, processed_variant)
		else:
			return processed_variant
	elif processed_variant is Array:
		# Recursively call the array converter for nested arrays.
		return _convert_json_to_array(processed_variant)
	elif processed_variant is String and not processed_variant.is_empty():
		# Try to convert string to a built-in Godot type (e.g., Vector2).
		if type != null and type is int and type == TYPE_COLOR:
			return Color(processed_variant)
		var str_var: Variant = str_to_var(processed_variant)
		if str_var == null:
			var json := JSON.new()
			# Handle cases where a value is a stringified JSON object/array.
			var error = json.parse(processed_variant)
			if error == OK:
				return json.get_data()
		else:
			return str_var
	# primitive types (int, float, bool, null)
	return processed_variant

#endregion

#endregion


#region Json Utilties
## Defines the types of operations that can be performed on the data structures.
enum Operation {
	Add, # Adds values. If key exists, combines them into an array.
	AddDiffer, # Adds or merges values only if they are different.
	Replace, # Replaces values in the base structure with values from the reference.
	Remove, # Removes keys/values present in the reference structure from the base.
	RemoveValue # Removes keys/values only if their values match the reference.
}
#endregion
