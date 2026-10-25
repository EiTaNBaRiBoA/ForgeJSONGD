## JSON -> class conversion. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDDeserializer extends ForgeJSONGDBase


## Fills a class instance from a JSON dictionary.
## script_or_instance can be a Script (a new instance is created), an existing instance,
## or null (the script is read from the JSON, see SCRIPT_INHERITANCE).
static func json_to_class(script_or_instance: Variant, json: Dictionary) -> Object:
	var target: Object = null
	if script_or_instance == null:
		var script_name: Variant = json.get(SCRIPT_INHERITANCE, null)
		if script_name != null:
			var script_type: Script = _get_json_script(script_name)
			if script_type != null:
				var created: Array = _create_from_script(script_type, json)
				if created[1]:
					return created[0]
				target = created[0]
	elif script_or_instance is Script:
		var created: Array = _create_from_script(script_or_instance, json)
		if created[1]:
			return created[0]
		target = created[0]
	elif script_or_instance is Object:
		target = script_or_instance
	if target == null:
		return Object.new()

	# Index the settable properties by name so each JSON key is a direct lookup.
	var excluded: Array = _get_excluded_properties(target)
	var settable: Dictionary = {}
	for property: Dictionary in target.get_property_list():
		var property_name: String = property.get("name")
		if property_name != "script" and not property_name in excluded and _check_valid_property(property):
			settable[property_name] = property

	for key: String in json:
		if not settable.has(key):
			continue
		var value: Variant = json.get(key)
		# Vector types and similar are stored as strings in JSON.
		if value is String and _is_safe_type(value):
			value = str_to_var(value)
		_assign_property(target, settable[key], value)
	return target


#region Internals

## Creates the object for a script. The second item is true when the class built itself from the JSON
## with _forge_deserialize: a static method (GDScript) or, for C#, a method of the new instance.
static func _create_from_script(script: Script, json: Dictionary) -> Array:
	if script.has_method("_forge_deserialize"):
		return [script._forge_deserialize(json), true]
	var instance: Object = _create_instance(script, json)
	if instance != null and instance.has_method("_forge_deserialize"):
		return [instance._forge_deserialize(json), true]
	return [instance, false]


## Creates an instance of the script, passing the constructor arguments stored in the JSON (if any).
static func _create_instance(script: Script, json: Dictionary) -> Object:
	if json.has(CONSTRUCTOR_ARGS) and json[CONSTRUCTOR_ARGS] is Array:
		return script.new.callv(_convert_json_to_array(json[CONSTRUCTOR_ARGS])) as Object
	return script.new() as Object


## Assigns one JSON value to a property, depending on the property's type.
static func _assign_property(target: Object, property: Dictionary, value: Variant) -> void:
	var property_name: String = property.get("name")
	var property_type: Variant = property.get("type")
	var current: Variant = target.get(property_name)

	if not current is Array and property_type == TYPE_OBJECT:
		_assign_object(target, property, current, value)
	elif current is Array:
		var element_type: Variant = current.get_typed_builtin()
		if current.is_typed() and current.get_typed_script():
			element_type = load(current.get_typed_script().get_path())
		current.assign(_convert_json_to_array(value, element_type))
		target.set(property_name, current) # C# arrays are copied when read, so set the filled array back
	elif current is Dictionary:
		_convert_json_to_dictionary(current, value)
		target.set(property_name, current)
	else:
		_assign_simple(target, property, value)


## Assigns an Object property: rebuilds nested objects or loads referenced resources.
static func _assign_object(target: Object, property: Dictionary, current: Object, value: Variant) -> void:
	var property_name: String = property.get("name")
	if current:
		# The property already holds an object, so reuse its script for the nested data.
		var inner_class_path: String = ""
		for inner_property: Dictionary in current.get_property_list():
			if inner_property.has("hint_string") and inner_property.get("hint_string").contains(".gd"):
				inner_class_path = inner_property.get("hint_string")
		target.set(property_name, json_to_class(load(inner_class_path), value))
	elif value:
		if value is String and value.is_absolute_path():
			target.set(property_name, _load_resource(value))
			return
		var script_type: Script = null
		if value is Dictionary and value.has(SCRIPT_INHERITANCE):
			script_type = _get_json_script(value.get(SCRIPT_INHERITANCE))
		if script_type == null:
			# No script in the JSON, or an unknown/unregistered one: use the type the variable is declared with.
			script_type = _get_gdscript(property.get("class_name"))
		if script_type == null:
			return
		target.set(property_name, json_to_class(script_type, value))


## Assigns a Variant, Color, enum, int or other basic property.
static func _assign_simple(target: Object, property: Dictionary, value: Variant) -> void:
	var property_name: String = property.get("name")
	var property_type: Variant = property.get("type")
	if property_type == TYPE_NIL:
		# Variant property: nested objects and tagged built-in types are restored from the value itself.
		target.set(property_name, _convert_plain_value(value))
		return
	if property_type == TYPE_COLOR:
		value = Color(value)
	if property_type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
		target.set(property_name, _string_to_enum(value, property.hint_string))
	elif property_type == TYPE_INT:
		target.set(property_name, int(value))
	else:
		target.set(property_name, value)


## Returns the enum value matching a key from a property hint string ("A:0,B:1"), or 0 if none matches.
## Numeric JSON values are passed through unchanged.
static func _string_to_enum(value: Variant, hint_string: String) -> int:
	if not value is String:
		return int(value)
	var wanted: String = value.to_lower().replace("_", " ")
	for entry: String in hint_string.split(","):
		if entry.contains(":"):
			var keys: PackedStringArray = entry.split(":")
			if keys[0].to_lower() == wanted:
				return keys[1].to_int()
	return 0


## Fills a (possibly typed) dictionary from a JSON dictionary.
static func _convert_json_to_dictionary(property_dict: Dictionary, json_dict: Dictionary) -> void:
	var key_type: Variant = property_dict.get_typed_key_script()
	if key_type == null:
		key_type = property_dict.get_typed_key_builtin()

	var value_type: Variant = property_dict.get_typed_value_script()
	if value_type == null:
		value_type = property_dict.get_typed_value_builtin()

	for json_key: Variant in json_dict:
		property_dict.set(_convert_variant(json_key, key_type), _convert_variant(json_dict.get(json_key), value_type))


## Converts a JSON array to a Godot array, converting each element to the given type.
static func _convert_json_to_array(json_array: Array, type: Variant = null) -> Array:
	var godot_array: Array = []
	for element: Variant in json_array:
		godot_array.append(_convert_variant(element, type))
	return godot_array


## Loads a resource named by a path in the JSON. Returns null if it uses a script that is not registered.
static func _load_resource(path: String) -> Resource:
	var resource: Resource = ResourceLoader.load(_get_main_tres_path(path))
	if resource != null and resource.get_script() != null and not _is_script_allowed(resource.get_script()):
		push_warning("ForgeJSONGD: resource '%s' uses a script that is not registered, ignoring it." % path)
		return null
	return resource


## Converts a single Variant from JSON into its target Godot type.
static func _convert_variant(json_variant: Variant, type: Variant = null) -> Variant:
	# A resource stored by its path, in a container declared with an object type (Array[Texture2D]...).
	if json_variant is String and json_variant.is_absolute_path() and (type is Script or (type is int and type == TYPE_OBJECT)):
		return _load_resource(json_variant)
	if json_variant is Dictionary or type is Object:
		var script: Script = null
		if SCRIPT_INHERITANCE in json_variant:
			# Prioritize the script embedded in the JSON data.
			script = _get_json_script(json_variant.get(SCRIPT_INHERITANCE))
			if script == null and type is Script:
				# Unknown or unregistered script: use the type the container is declared with.
				script = load(type.get_path())
		elif type is Script:
			# Fall back to the type hint from the parent array/dictionary.
			script = load(type.get_path())
		if script == null:
			return _convert_plain_value(json_variant) if json_variant is Dictionary else json_variant
		if json_variant is String:
			return json_to_class(script, JSON.parse_string(json_variant))
		return json_to_class(script, json_variant)
	if json_variant is Array:
		return _convert_json_to_array(json_variant)
	if json_variant is String and not json_variant.is_empty():
		return _convert_string(json_variant, type)
	# primitive types (int, float, bool, null)
	return json_variant


## Restores what a value says about itself, without a type hint: objects stored with their script
## and built-in types stored as text (Rect2, Transform3D, Packed arrays...). Other values are kept as they are.
static func _convert_plain_value(value: Variant) -> Variant:
	if value is Dictionary:
		if value.size() == 1 and value.get(RESOURCE_PATH) is String:
			return _load_resource(value[RESOURCE_PATH])
		if value.has(SCRIPT_INHERITANCE):
			var script: Script = _get_json_script(value.get(SCRIPT_INHERITANCE))
			if script != null:
				return json_to_class(script, value)
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _convert_plain_value(value[key])
		return result
	if value is Array:
		return value.map(_convert_plain_value)
	if value is String and _is_safe_type(value):
		var parsed: Variant = str_to_var(value)
		if parsed != null:
			return parsed
	return value


## Converts a string into a built-in type (Vector2, Color...) or a parsed JSON structure when possible.
static func _convert_string(text: String, type: Variant) -> Variant:
	if type is int:
		if type == TYPE_STRING:
			return text
		if type == TYPE_COLOR and not _is_safe_type(text):
			return Color(text)
	if _is_safe_type(text):
		var parsed: Variant = str_to_var(text)
		if parsed != null:
			return parsed
	# A value can also be a stringified JSON object/array.
	var json := JSON.new()
	if json.parse(text) == OK:
		return json.get_data()
	return text

#endregion
