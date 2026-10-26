## JSON -> class conversion. Internal, use ForgeJSONGD instead.
@abstract class_name ForgeJSONGDDeserializer extends ForgeJSONGDBase


## Fills a class instance from a JSON dictionary.
## script_or_instance can be a Script (a new instance is created), an existing instance,
## or null (the script is read from the JSON, see SCRIPT_INHERITANCE).
static func json_to_class(script_or_instance: Variant, json: Dictionary) -> Object:
	var target: Object = null
	if script_or_instance == null:
		var script_type: Script = _script_from_json(json) # plain JSON from a server never chooses a class
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

	# A class that returns true from _forge_plain_json() is read as plain JSON, and so is everything inside it.
	var was_plain: bool = _plain
	if not _plain and _hook(target, "_forge_plain_json", false):
		_plain = true

	# Index the settable properties by name so each JSON key is a direct lookup.
	var excluded: Array = _hook(target, "_forge_excluded_properties", [])
	var extra: Array = _hook(target, "_forge_extra_properties", [])
	var settable: Dictionary = {}
	for property: Dictionary in target.get_property_list():
		var property_name: String = property.get("name")
		if property_name != "script" and not property_name in excluded and (_check_valid_property(property) or property_name in extra):
			settable[property_name] = property

	# Other keys a variable is read from: the key given by _forge_json_keys, and the old names in _forge_renamed_properties.
	var json_keys: Dictionary = _hook(target, "_forge_json_keys", {})
	var renamed: Dictionary = _hook(target, "_forge_renamed_properties", {})
	var shadowed: Dictionary = {} # keys that are ignored because the preferred key of the same variable is in the JSON
	for variable_name: String in json_keys:
		if settable.has(variable_name):
			settable[json_keys[variable_name]] = settable[variable_name]
			if json.has(json_keys[variable_name]):
				shadowed[variable_name] = true
	for old_name: String in renamed:
		var current_name: String = renamed[old_name]
		if settable.has(current_name) and not settable.has(old_name):
			settable[old_name] = settable[current_name]
			if json.has(json_keys.get(current_name, current_name)):
				shadowed[old_name] = true

	for key: Variant in json:
		if not key is String or not settable.has(key) or shadowed.has(key):
			continue
		var value: Variant = json.get(key)
		# Vector types and similar are stored as strings in JSON, except where the text could be plain data.
		if not _plain and value is String and settable[key].get("type") != TYPE_STRING and _is_safe_type(value):
			value = str_to_var(value)
		_assign_property(target, settable[key], value)
	_plain = was_plain
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
	# Stored arguments are only used by a class that gives its own (_forge_constructor_args), never for any class.
	if json.has(CONSTRUCTOR_ARGS) and json[CONSTRUCTOR_ARGS] is Array and not _plain and _script_has_method(script, "_forge_constructor_args"):
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
		if not value is Array:
			return # for example a null sent by a server: the variable keeps its default
		var element_type: Variant = current.get_typed_builtin()
		if current.is_typed() and current.get_typed_script():
			element_type = current.get_typed_script()
		current.assign(_convert_json_to_array(value, element_type, target))
		target.set(property_name, current) # C# arrays are copied when read, so set the filled array back
	elif current is Dictionary:
		if not value is Dictionary:
			return
		_convert_json_to_dictionary(current, value, target)
		target.set(property_name, current)
	else:
		_assign_simple(target, property, value)


## Assigns an Object property: rebuilds nested objects or loads referenced resources.
static func _assign_object(target: Object, property: Dictionary, current: Object, value: Variant) -> void:
	var property_name: String = property.get("name")
	if value is String and value.is_absolute_path() and not _plain: # plain JSON from a server never loads files
		target.set(property_name, _load_resource(value))
		return
	if not value is Dictionary:
		return # data that cannot be an object (a null, text, a number...): the variable keeps its value
	# Which class to build: the one the JSON names, else the class of the object the variable already holds,
	# else the class the variable is declared with (also used when the JSON names an unknown or unregistered one).
	var script_type: Script = _script_from_json(value, target)
	if script_type == null and current != null:
		script_type = current.get_script() as Script
	if script_type == null:
		script_type = _get_declared_script(target, property.get("class_name"))
	if script_type != null:
		target.set(property_name, json_to_class(script_type, value))


## Assigns a Variant, Color, enum, int or other basic property.
static func _assign_simple(target: Object, property: Dictionary, value: Variant) -> void:
	var property_name: String = property.get("name")
	var property_type: Variant = property.get("type")
	if property_type == TYPE_NIL:
		# Variant property: nested objects and tagged built-in types are restored from the value itself.
		target.set(property_name, _convert_plain_value(value))
		return
	if value == null:
		return # for example a null sent by a server: the variable keeps its default
	if property_type == TYPE_STRING and not value is String:
		# A server may send a number or a bool where the variable is text.
		if value is Dictionary or value is Array:
			return
		value = str(int(value)) if value is float and value == floor(value) else str(value)
	if value is String:
		if property_type == TYPE_STRING:
			value = value if _plain else _unescape_text(value)
		elif property_type is int:
			# The text form of a built-in type ("Rect2(1, 2, 3, 4)"): the normal functions already read it, plain JSON
			# reads it only for a variable declared with that very type.
			if _plain and _is_safe_type(value):
				var parsed: Variant = str_to_var(value)
				if typeof(parsed) == property_type:
					value = parsed
			if value is String:
				# Files from older versions wrote Rect2, packed arrays... as display text, e.g. "[P: (1.0, 2.0), S: (3.0, 4.0)]".
				var from_text: Variant = _from_display_text(value, property_type)
				if from_text != null:
					value = from_text
	elif value is Dictionary and _is_vector_type(property_type):
		value = _vector_from_dict(property_type, value) # {"x": 1, "y": 2}
		if value == null:
			return
	if property_type == TYPE_COLOR and value is String:
		value = Color(value)
	if property_type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
		target.set(property_name, _string_to_enum(value, property.hint_string))
	elif property_type == TYPE_INT:
		target.set(property_name, int(value)) # also reads big numbers saved as text
	else:
		target.set(property_name, value)


## Reads the display text older versions wrote for a few built-in types. Returns null if the text is not understood.
static func _from_display_text(text: String, type: int) -> Variant:
	var regex := RegEx.new()
	regex.compile("-?\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?")
	var n: PackedFloat64Array = []
	for found: RegExMatch in regex.search_all(text):
		n.append(found.get_string().to_float())
	match type:
		TYPE_RECT2:
			return Rect2(n[0], n[1], n[2], n[3]) if n.size() == 4 else null
		TYPE_RECT2I:
			return Rect2i(int(n[0]), int(n[1]), int(n[2]), int(n[3])) if n.size() == 4 else null
		TYPE_AABB:
			return AABB(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5])) if n.size() == 6 else null
		TYPE_PLANE:
			return Plane(Vector3(n[0], n[1], n[2]), n[3]) if n.size() == 4 else null
		TYPE_QUATERNION:
			return Quaternion(n[0], n[1], n[2], n[3]) if n.size() == 4 else null
		TYPE_BASIS:
			return Basis(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5]), Vector3(n[6], n[7], n[8])) if n.size() == 9 else null
		TYPE_TRANSFORM2D:
			return Transform2D(Vector2(n[0], n[1]), Vector2(n[2], n[3]), Vector2(n[4], n[5])) if n.size() == 6 else null
		TYPE_TRANSFORM3D:
			if n.size() != 12:
				return null
			return Transform3D(Basis(Vector3(n[0], n[1], n[2]), Vector3(n[3], n[4], n[5]), Vector3(n[6], n[7], n[8])), Vector3(n[9], n[10], n[11]))
		TYPE_PROJECTION:
			if n.size() != 16:
				return null
			return Projection(Vector4(n[0], n[1], n[2], n[3]), Vector4(n[4], n[5], n[6], n[7]), Vector4(n[8], n[9], n[10], n[11]), Vector4(n[12], n[13], n[14], n[15]))
		TYPE_PACKED_BYTE_ARRAY:
			var bytes := PackedByteArray()
			for number: float in n:
				bytes.append(int(number))
			return bytes
		TYPE_PACKED_VECTOR2_ARRAY:
			var vectors2 := PackedVector2Array()
			for i: int in range(0, n.size() - 1, 2):
				vectors2.append(Vector2(n[i], n[i + 1]))
			return vectors2
		TYPE_PACKED_VECTOR3_ARRAY:
			var vectors3 := PackedVector3Array()
			for i: int in range(0, n.size() - 2, 3):
				vectors3.append(Vector3(n[i], n[i + 1], n[i + 2]))
			return vectors3
		TYPE_PACKED_VECTOR4_ARRAY:
			var vectors4 := PackedVector4Array()
			for i: int in range(0, n.size() - 3, 4):
				vectors4.append(Vector4(n[i], n[i + 1], n[i + 2], n[i + 3]))
			return vectors4
		TYPE_PACKED_COLOR_ARRAY:
			var colors := PackedColorArray()
			for i: int in range(0, n.size() - 3, 4):
				colors.append(Color(n[i], n[i + 1], n[i + 2], n[i + 3]))
			return colors
	return null


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
static func _convert_json_to_dictionary(property_dict: Dictionary, json_dict: Dictionary, owner: Object = null) -> void:
	var key_type: Variant = property_dict.get_typed_key_script()
	if key_type == null:
		key_type = property_dict.get_typed_key_builtin()

	var value_type: Variant = property_dict.get_typed_value_script()
	if value_type == null:
		value_type = property_dict.get_typed_value_builtin()

	for json_key: Variant in json_dict:
		property_dict.set(_convert_variant(json_key, key_type, true, owner), _convert_variant(json_dict.get(json_key), value_type, false, owner))


## Converts a JSON array to a Godot array, converting each element to the given type.
static func _convert_json_to_array(json_array: Array, type: Variant = null, owner: Object = null) -> Array:
	var godot_array: Array = []
	for element: Variant in json_array:
		godot_array.append(_convert_variant(element, type, false, owner))
	return godot_array


## Loads a resource named by a path in the JSON. Returns null if it uses a script that is not registered.
static func _load_resource(path: String) -> Resource:
	var resource: Resource = ResourceLoader.load(_get_main_tres_path(path))
	if resource != null and resource.get_script() != null and not _is_script_allowed(resource.get_script()):
		push_warning("ForgeJSONGD: resource '%s' uses a script that is not registered, ignoring it." % path)
		return null
	return resource


## A number read from JSON in an untyped place: JSON (and Godot's parser) has one number type, so whole numbers become ints.
static func _plain_number(number: float) -> Variant:
	if is_finite(number) and number == floor(number) and abs(number) < _MAX_SAFE_INT:
		return int(number)
	return number


## Converts a single Variant from JSON into its target Godot type.
## is_key is true for the key of a dictionary, which JSON always writes as text.
static func _convert_variant(json_variant: Variant, type: Variant = null, is_key: bool = false, owner: Object = null) -> Variant:
	# A resource stored by its path, in a container declared with an object type (Array[Texture2D]...).
	if json_variant is String and json_variant.is_absolute_path() and not _plain and (type is Script or (type is int and type == TYPE_OBJECT)):
		return _load_resource(json_variant)
	if json_variant is Dictionary and _is_vector_type(type):
		var vector: Variant = _vector_from_dict(type, json_variant) # {"x": 1, "y": 2}
		if vector != null:
			return vector
	var is_object_slot: bool = type is Object or (type is int and type == TYPE_OBJECT) # a script, or a built-in class like Texture2D
	if json_variant is Dictionary or is_object_slot:
		if not json_variant is Dictionary and not (json_variant is String and is_key):
			return null # data that cannot be an object (a null, a number, text...) where an object is declared
		# The class the JSON names comes first; else (or if it is unknown or unregistered) the type the container is declared with.
		var script: Script = _script_from_json(json_variant, owner) if json_variant is Dictionary else null
		if script == null and type is Script:
			script = type
		if script == null:
			if is_object_slot:
				return null # an object of a built-in class cannot be built from data
			return _convert_plain_value(json_variant) if json_variant is Dictionary else json_variant
		if json_variant is String:
			var key_data: Variant = JSON.parse_string(json_variant) # an object used as a dictionary key
			return json_to_class(script, key_data) if key_data is Dictionary else null
		return json_to_class(script, json_variant)
	if json_variant is Array:
		return _convert_json_to_array(json_variant, null, owner)
	if json_variant is String and not json_variant.is_empty():
		return _convert_string(json_variant, type, is_key)
	if json_variant is float and _is_untyped(type):
		return _plain_number(json_variant)
	# primitive types (int, float, bool, null)
	return json_variant


## Restores what a value says about itself, without a type hint: objects stored with their script,
## built-in types stored as text (Rect2, Transform3D, Packed arrays...), resources, and the number markers.
## Other values are kept as they are, except that whole numbers become ints.
static func _convert_plain_value(value: Variant) -> Variant:
	if value is Dictionary:
		if _plain:
			# Plain JSON from a server: nothing in it is a marker, a class name or a path.
			var plain_result: Dictionary = {}
			for plain_key: Variant in value:
				plain_result[plain_key] = _convert_plain_value(value[plain_key])
			return plain_result
		if value.size() == 1:
			if value.get(_RESOURCE_PATH) is String:
				return _load_resource(value[_RESOURCE_PATH])
			if value.get(_FLOAT_MARKER) is float:
				return float(value[_FLOAT_MARKER])
			if value.get(_INT_MARKER) is String:
				return String(value[_INT_MARKER]).to_int()
		var script: Script = _script_from_json(value)
		if script != null:
			return json_to_class(script, value)
		var result: Dictionary = {}
		for key: Variant in value:
			var converted_key: Variant = _convert_string(key, null, true) if key is String else key
			result[converted_key] = _convert_plain_value(value[key])
		return result
	if value is Array:
		return value.map(_convert_plain_value)
	if value is String:
		return _convert_string(value, null)
	if value is float:
		return _plain_number(value)
	return value


## Converts text into the type it stands for: escaped text, a number or bool where the target type asks for it
## (or for dictionary keys), or a Godot value (Vector2, Color...) written as text.
static func _convert_string(text: String, type: Variant, is_key: bool = false) -> Variant:
	if _plain and (type == null or type is Object or (type is int and (type == TYPE_NIL or type == TYPE_STRING))):
		return text # plain JSON: text is text
	if text.begins_with(_TEXT_PREFIX):
		return _unescape_text(text)
	if type is int:
		match type:
			TYPE_STRING:
				return text
			TYPE_INT:
				if text.is_valid_int():
					return text.to_int()
			TYPE_FLOAT:
				if text.is_valid_float():
					return text.to_float()
			TYPE_BOOL:
				if text == "true" or text == "false":
					return text == "true"
			TYPE_COLOR:
				if not _is_safe_type(text):
					return Color(text)
	if _is_safe_type(text):
		var parsed: Variant = str_to_var(text)
		if parsed != null:
			return parsed
	if is_key and _is_untyped(type):
		var tagged: Variant = _untag_key(text) # an int, float or bool key of an untyped dictionary
		if tagged != null:
			return tagged
	return text

#endregion
