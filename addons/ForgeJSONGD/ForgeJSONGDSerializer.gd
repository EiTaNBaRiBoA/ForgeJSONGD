## Class -> JSON conversion. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDSerializer extends ForgeJSONGDBase


## Converts an object into a JSON dictionary. specify_class stores the script so the
## object can be rebuilt without a type hint (needed under inheritance).
## owner is the object this one is a variable of: a class declared inside the owner's script is named through it.
## A class whose _forge_plain_json() returns true is written as plain JSON, and so is everything inside it.
static func class_to_json(_class: Object, specify_class: bool = false, owner: Object = null) -> Dictionary:
	if _plain or not _hook(_class, "_forge_plain_json", false):
		return _object_to_dictionary(_class, specify_class, owner)
	_plain = true
	var result: Dictionary = _object_to_dictionary(_class, specify_class, owner)
	_plain = false
	return result


## The variables of an object as a dictionary (see class_to_json).
static func _object_to_dictionary(_class: Object, specify_class: bool, owner: Object) -> Dictionary:
	var dictionary: Dictionary = {}
	if specify_class and not _plain: # plain JSON never carries class names
		dictionary.set(SCRIPT_INHERITANCE, _get_script_reference(_class.get_script(), owner))
		_add_script_uid(dictionary, _class.get_script())

	# A class can take over its own serialization.
	if _class.has_method("_forge_serialize"):
		dictionary.merge(convert_dictionary_to_json(_class._forge_serialize(), _class), true)
		return dictionary

	var excluded: Array = _hook(_class, "_forge_excluded_properties", [])
	var extra: Array = _hook(_class, "_forge_extra_properties", [])
	for property: Dictionary in _class.get_property_list():
		var property_name: String = property.get("name")
		if property_name == "script" or property_name.is_empty() or property_name in excluded:
			continue
		if _check_valid_property(property) or property_name in extra:
			_store_property(dictionary, property, _class.get(property_name), _class)

	# Variables can be written under another key (camelCase names of an API, for example).
	var json_keys: Dictionary = _hook(_class, "_forge_json_keys", {})
	if not json_keys.is_empty():
		var renamed: Dictionary = {} # rebuilt in the same order, so sort_keys = false still follows the variables
		for key: Variant in dictionary:
			renamed.set(json_keys.get(key, key), dictionary[key])
		dictionary = renamed

	if _class.has_method("_forge_constructor_args") and not _plain:
		dictionary.set(CONSTRUCTOR_ARGS, convert_array_to_json(_class._forge_constructor_args(), _class))
	return dictionary


## Recursively converts an Array into a JSON-compatible Array.
## owner is the object the array is a variable of (see class_to_json).
static func convert_array_to_json(array: Array, owner: Object = null) -> Array:
	var json_array: Array = []
	for element: Variant in array:
		json_array.append(_serialize_variant(element, array.get_typed_builtin(), array.get_typed_script(), true, owner))
	return json_array


## Recursively converts a Dictionary into a JSON-compatible Dictionary.
## owner is the object the dictionary is a variable of (see class_to_json).
static func convert_dictionary_to_json(dictionary: Dictionary, owner: Object = null) -> Dictionary:
	var json_dictionary: Dictionary = {}
	var key_builtin: int = dictionary.get_typed_key_builtin()
	var key_script: Script = dictionary.get_typed_key_script()
	for key: Variant in dictionary:
		# JSON keys are text. Text keys are written as they are (only text that could be mistaken for a tagged key
		# or a Godot value is escaped). In an untyped dictionary a number or bool key gets a tag that says its type;
		# in a typed dictionary the key type is known, so its text is enough.
		var parsed_key: Variant
		var untyped_keys: bool = key_builtin == TYPE_NIL and key_script == null
		match typeof(key):
			TYPE_STRING:
				parsed_key = key if _plain else _escape_text(key, true)
			TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
				parsed_key = _tag_key(key) if untyped_keys and not _plain else key
			_:
				parsed_key = _serialize_variant(key, key_builtin, key_script, false)
		var parsed_value: Variant = _serialize_variant(dictionary.get(key), dictionary.get_typed_value_builtin(), dictionary.get_typed_value_script(), true, owner)
		json_dictionary.set(parsed_key, parsed_value)
	return json_dictionary


#region Internals

## Stores the uid of a script without a class_name, so it can be found again if its file is moved.
static func _add_script_uid(dictionary: Dictionary, script: Script) -> void:
	if script == null or not script.get_global_name().is_empty() or script.resource_path.is_empty() or _alias_of.has(script):
		return
	var uid: int = ResourceLoader.get_resource_uid(script.resource_path)
	if uid != ResourceUID.INVALID_ID:
		dictionary.set(_SCRIPT_UID, ResourceUID.id_to_text(uid))


## True when a packed array holds a value a JSON number cannot keep exactly.
static func _has_unsafe_int(values: PackedInt64Array) -> bool:
	for number: int in values:
		if _is_unsafe_int(number):
			return true
	return false


## The name stored for a script: its global class name, its path for classes without one, or "::Name" for a class
## declared inside the script of the owner object (those have no name or path of their own).
static func _get_script_reference(script: Script, owner: Object = null) -> String:
	if script == null:
		return ""
	if _alias_of.has(script):
		return _alias_of[script] # the stable name chosen with register_script_alias
	var script_name: String = script.get_global_name()
	if not script_name.is_empty():
		return script_name
	if not script.resource_path.is_empty():
		return script.resource_path
	var owner_script: Script = owner.get_script() if owner != null else null
	while owner_script != null:
		var constants: Dictionary = owner_script.get_script_constant_map()
		for constant_name: Variant in constants:
			if constants[constant_name] == script:
				return "::" + str(constant_name)
		owner_script = owner_script.get_base_script()
	return ""


## Serializes one property value into the dictionary, depending on its type.
static func _store_property(dictionary: Dictionary, property: Dictionary, value: Variant, owner: Object) -> void:
	var property_name: String = property.get("name")
	var property_type: Variant = property.get("type")

	if value is Array:
		dictionary.set(property_name, convert_array_to_json(value, owner))
	elif value is Dictionary:
		dictionary.set(property_name, convert_dictionary_to_json(value, owner))
	elif property_type == TYPE_OBJECT and value != null and value.get_property_list():
		dictionary.set(property_name, _serialize_object_property(property, value, owner))
	elif property_type == TYPE_NIL:
		# Variant property: nothing tells the type on load, so it has to be stored with the value.
		dictionary.set(property_name, _serialize_variant(value, TYPE_NIL, null, true, owner))
	elif property_type in _TEXT_RENDERED_TYPES or (property_type == TYPE_PACKED_INT64_ARRAY and _has_unsafe_int(value) and not _plain):
		# JSON would turn these into display text ("[P: (1.0, 2.0)...]") that C# cannot convert back.
		dictionary.set(property_name, _serialize_variant(value))
	elif _is_vector(value):
		dictionary.set(property_name, _vector_to_dict(value) if _plain else var_to_str(value))
	elif property_type == TYPE_COLOR:
		dictionary.set(property_name, value.to_html())
	elif property_type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
		var enum_name: Variant = _enum_to_string(value, property.get("hint_string"))
		if enum_name != null:
			dictionary.set(property_name, enum_name)
	elif value is int and _is_unsafe_int(value) and not _plain:
		dictionary.set(property_name, str(value)) # a JSON number would lose digits
	elif typeof(value) == TYPE_STRING:
		dictionary.set(property_name, value if _plain else _escape_text(value))
	else:
		dictionary.set(property_name, value)


## Serializes an Object property: external resources by path, everything else as a nested dictionary.
static func _serialize_object_property(property: Dictionary, value: Object, owner: Object) -> Variant:
	if value is Resource and ResourceLoader.exists(value.resource_path):
		# Resources stored in a file that isn't a .tres are referenced by path only, and so are classes that ask for it.
		if _get_main_tres_path(value.resource_path).get_extension() != "tres" or _is_saved_by_path(value):
			return value.resource_path
		return class_to_json(value)
	if value.get_script() == null:
		return null # objects without a script cannot be rebuilt
	return class_to_json(value, property.get("class_name") != value.get_script().get_global_name(), owner)


## Serializes an Object inside a container: a resource from a file by its path, an object without a script as null.
## In an untyped place (mark_resource) the path is wrapped in a marker object, so loading knows it is a resource.
static func _object_to_json(value: Object, specify_script: bool, mark_resource: bool = false, owner: Object = null) -> Variant:
	if value is Resource and ResourceLoader.exists(value.resource_path):
		if _get_main_tres_path(value.resource_path).get_extension() != "tres" or _is_saved_by_path(value):
			return {_RESOURCE_PATH: value.resource_path} if mark_resource else value.resource_path
	elif value.get_script() == null:
		return null
	return class_to_json(value, specify_script, owner)


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
static func _serialize_variant(variant_value: Variant, typed_builtin: int = TYPE_NIL, typed_script: Script = null, tag_builtins: bool = true, owner: Object = null) -> Variant:
	var is_typed: bool = typed_builtin != TYPE_NIL or typed_script != null
	if variant_value is Object:
		# The script is only needed when the container doesn't already tell the class:
		# untyped containers, or elements that are a subclass of the container's type.
		var specify_script: bool = not is_typed or (typed_script != null and variant_value.get_script() != typed_script)
		return _object_to_json(variant_value, specify_script, not is_typed and not _plain, owner)
	if variant_value is Array:
		return convert_array_to_json(variant_value, owner)
	if variant_value is Dictionary:
		return convert_dictionary_to_json(variant_value, owner)
	if _is_vector(variant_value):
		return _vector_to_dict(variant_value) if _plain else var_to_str(variant_value)
	if variant_value is int:
		if _is_unsafe_int(variant_value) and not _plain: # a JSON number would lose digits
			return str(variant_value) if is_typed else {_INT_MARKER: str(variant_value)}
		return variant_value
	if variant_value is float:
		# Godot reads every JSON number as a float, so in an untyped place a whole number is read back as an int.
		# A float with a whole value gets a marker to stay a float.
		if not is_typed and not _plain and is_finite(variant_value) and variant_value == floor(variant_value) and abs(variant_value) < _MAX_SAFE_INT:
			return {_FLOAT_MARKER: variant_value}
		return variant_value
	if typeof(variant_value) == TYPE_STRING:
		return variant_value if _plain else _escape_text(variant_value)
	if typeof(variant_value) == TYPE_COLOR:
		# Hex text in typed containers, in plain JSON and for keys. In an untyped place Color(1, 0, 0, 1) keeps the type.
		return variant_value.to_html() if (is_typed or _plain or not tag_builtins) else var_to_str(variant_value)
	if tag_builtins and typeof(variant_value) == TYPE_PACKED_BYTE_ARRAY:
		# base64 is much shorter than a list of numbers, and str_to_var reads both forms.
		return 'PackedByteArray("%s")' % (Marshalls.raw_to_base64(variant_value) if not variant_value.is_empty() else "")
	if tag_builtins and typeof(variant_value) in _TAGGED_TYPES:
		return var_to_str(variant_value)
	return variant_value

#endregion
