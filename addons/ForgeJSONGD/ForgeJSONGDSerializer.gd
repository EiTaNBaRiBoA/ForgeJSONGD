## Class -> JSON conversion. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDSerializer extends ForgeJSONGDBase


## Converts an object into a JSON dictionary. specify_class stores the script so the
## object can be rebuilt without a type hint (needed under inheritance).
static func class_to_json(_class: Object, specify_class: bool = false) -> Dictionary:
	var dictionary: Dictionary = {}
	if specify_class:
		dictionary.set(SCRIPT_INHERITANCE, _get_script_reference(_class.get_script()))

	# A class can take over its own serialization.
	if _class.has_method("_forge_serialize"):
		dictionary.merge(convert_dictionary_to_json(_class._forge_serialize()), true)
		return dictionary

	var excluded: Array = _get_excluded_properties(_class)
	for property: Dictionary in _class.get_property_list():
		var property_name: String = property.get("name")
		if property_name == "script" or property_name.is_empty() or property_name in excluded:
			continue
		if _check_valid_property(property):
			_store_property(dictionary, property, _class.get(property_name))

	if _class.has_method("_forge_constructor_args"):
		dictionary.set(CONSTRUCTOR_ARGS, convert_array_to_json(_class._forge_constructor_args()))
	return dictionary


## Recursively converts an Array into a JSON-compatible Array.
static func convert_array_to_json(array: Array) -> Array:
	var json_array: Array = []
	for element: Variant in array:
		json_array.append(_serialize_variant(element, array.get_typed_builtin(), array.get_typed_script()))
	return json_array


## Recursively converts a Dictionary into a JSON-compatible Dictionary.
static func convert_dictionary_to_json(dictionary: Dictionary) -> Dictionary:
	var json_dictionary: Dictionary = {}
	for key: Variant in dictionary:
		# Keys stay plain so files keep readable keys, only values get their type tagged.
		var parsed_key: Variant = _serialize_variant(key, dictionary.get_typed_key_builtin(), dictionary.get_typed_key_script(), false)
		var parsed_value: Variant = _serialize_variant(dictionary.get(key), dictionary.get_typed_value_builtin(), dictionary.get_typed_value_script())
		if typeof(parsed_value) == TYPE_INT: # JSON parsing in Godot always yields floats
			parsed_value = float(parsed_value)
		json_dictionary.set(parsed_key, parsed_value)
	return json_dictionary


#region Internals

## Built-in property types that JSON.stringify can only write as display text. They are stored with var_to_str instead.
const _TEXT_RENDERED_TYPES: Array[int] = [
	TYPE_RECT2, TYPE_RECT2I, TYPE_AABB, TYPE_PLANE, TYPE_QUATERNION, TYPE_BASIS, TYPE_TRANSFORM2D,
	TYPE_TRANSFORM3D, TYPE_PROJECTION, TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_VECTOR2_ARRAY,
	TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY
]

## The name stored for a script: its global class name, or its path for classes without one.
static func _get_script_reference(script: Script) -> String:
	if script == null:
		return ""
	var script_name: String = script.get_global_name()
	return script_name if not script_name.is_empty() else script.resource_path


## Serializes one property value into the dictionary, depending on its type.
static func _store_property(dictionary: Dictionary, property: Dictionary, value: Variant) -> void:
	var property_name: String = property.get("name")
	var property_type: Variant = property.get("type")

	if value is Array:
		dictionary.set(property_name, convert_array_to_json(value))
	elif value is Dictionary:
		dictionary.set(property_name, convert_dictionary_to_json(value))
	elif property_type == TYPE_OBJECT and value != null and value.get_property_list():
		dictionary.set(property_name, _serialize_object_property(property, value))
	elif property_type == TYPE_NIL and not value is int:
		# Variant property: nothing tells the type on load, so it has to be stored with the value.
		dictionary.set(property_name, _serialize_variant(value))
	elif property_type in _TEXT_RENDERED_TYPES:
		# JSON would turn these into display text ("[P: (1.0, 2.0)...]") that C# cannot convert back.
		dictionary.set(property_name, _serialize_variant(value))
	elif _is_vector(value):
		dictionary.set(property_name, var_to_str(value))
	elif property_type == TYPE_COLOR:
		dictionary.set(property_name, value.to_html())
	elif property_type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
		var enum_name: Variant = _enum_to_string(value, property.get("hint_string"))
		if enum_name != null:
			dictionary.set(property_name, enum_name)
	else:
		dictionary.set(property_name, value)


## Serializes an Object property: external resources by path, everything else as a nested dictionary.
static func _serialize_object_property(property: Dictionary, value: Object) -> Variant:
	if value is Resource and ResourceLoader.exists(value.resource_path):
		# Resources stored in a file that isn't a .tres are referenced by path only.
		if _get_main_tres_path(value.resource_path).get_extension() != "tres":
			return value.resource_path
		return class_to_json(value)
	if value.get_script() == null:
		return null # objects without a script cannot be rebuilt
	return class_to_json(value, property.get("class_name") != value.get_script().get_global_name())


## Serializes an Object inside a container: a resource from a file by its path, an object without a script as null.
## In an untyped place (mark_resource) the path is wrapped in a marker object, so loading knows it is a resource.
static func _object_to_json(value: Object, specify_script: bool, mark_resource: bool = false) -> Variant:
	if value is Resource and ResourceLoader.exists(value.resource_path):
		if _get_main_tres_path(value.resource_path).get_extension() != "tres":
			return {RESOURCE_PATH: value.resource_path} if mark_resource else value.resource_path
	elif value.get_script() == null:
		return null
	return class_to_json(value, specify_script)


## Returns the enum key matching the value from a property hint string ("A:0,B:1"), or null if none matches.
static func _enum_to_string(value: int, hint_string: String) -> Variant:
	var result: Variant = null
	for entry: String in hint_string.split(","):
		entry = entry.replace(" ", "_")
		if entry.contains(":"):
			var parts: PackedStringArray = entry.split(":")
			if value == parts[1].to_int():
				result = parts[0]
		else:
			result = entry
	return result


## Converts a single Variant into a JSON-compatible Variant.
## typed_builtin / typed_script describe how the parent container is typed (TYPE_NIL and null when it is untyped).
## tag_builtins stores types JSON can't represent (Rect2, Transform3D, Packed arrays...) as var_to_str text.
static func _serialize_variant(variant_value: Variant, typed_builtin: int = TYPE_NIL, typed_script: Script = null, tag_builtins: bool = true) -> Variant:
	var is_typed: bool = typed_builtin != TYPE_NIL or typed_script != null
	if variant_value is Object:
		# The script is only needed when the container doesn't already tell the class:
		# untyped containers, or elements that are a subclass of the container's type.
		var specify_script: bool = not is_typed or (typed_script != null and variant_value.get_script() != typed_script)
		return _object_to_json(variant_value, specify_script, not is_typed)
	if variant_value is Array:
		return convert_array_to_json(variant_value)
	if variant_value is Dictionary:
		return convert_dictionary_to_json(variant_value)
	if _is_vector(variant_value):
		return var_to_str(variant_value)
	if variant_value is int and not is_typed:
		# JSON.parse_string yields floats only, so ints are cast to keep types consistent.
		return float(variant_value)
	if tag_builtins and typeof(variant_value) == TYPE_PACKED_BYTE_ARRAY:
		# base64 is much shorter than a list of numbers, and str_to_var reads both forms.
		return 'PackedByteArray("%s")' % (Marshalls.raw_to_base64(variant_value) if not variant_value.is_empty() else "")
	if tag_builtins and typeof(variant_value) in _TAGGED_TYPES and (not is_typed or typeof(variant_value) != TYPE_COLOR):
		return var_to_str(variant_value) # typed Color containers keep the hex format
	if typeof(variant_value) == TYPE_COLOR:
		return variant_value.to_html()
	return variant_value

#endregion
