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
			var script_type: Script = _get_json_script(script_name, json)
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
			element_type = current.get_typed_script()
		current.assign(_convert_json_to_array(value, element_type, target))
		target.set(property_name, current) # C# arrays are copied when read, so set the filled array back
	elif current is Dictionary:
		_convert_json_to_dictionary(current, value, target)
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
			var script_name: String = str(value.get(SCRIPT_INHERITANCE))
			if script_name.begins_with("::"):
				# A class declared inside the script of the object that owns this variable.
				script_type = _get_declared_script(target, script_name.substr(2))
			else:
				script_type = _get_json_script(script_name, value)
		if script_type == null:
			# No script in the JSON, or an unknown/unregistered one: use the type the variable is declared with.
			script_type = _get_declared_script(target, property.get("class_name"))
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
	if value is String:
		if property_type == TYPE_STRING:
			value = _unescape_text(value)
		elif property_type is int:
			# Files from older versions wrote Rect2, packed arrays... as display text, e.g. "[P: (1.0, 2.0), S: (3.0, 4.0)]".
			var from_text: Variant = _from_display_text(value, property_type)
			if from_text != null:
				value = from_text
	if property_type == TYPE_COLOR:
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
	if is_finite(number) and number == floor(number) and abs(number) < MAX_SAFE_INT:
		return int(number)
	return number


## Converts a single Variant from JSON into its target Godot type.
## is_key is true for the key of a dictionary, which JSON always writes as text.
static func _convert_variant(json_variant: Variant, type: Variant = null, is_key: bool = false, owner: Object = null) -> Variant:
	# A resource stored by its path, in a container declared with an object type (Array[Texture2D]...).
	if json_variant is String and json_variant.is_absolute_path() and (type is Script or (type is int and type == TYPE_OBJECT)):
		return _load_resource(json_variant)
	if json_variant is Dictionary or type is Object:
		var script: Script = null
		if SCRIPT_INHERITANCE in json_variant:
			# Prioritize the script embedded in the JSON data.
			var script_name: String = str(json_variant.get(SCRIPT_INHERITANCE))
			if script_name.begins_with("::"):
				script = _get_declared_script(owner, script_name.substr(2)) # a class declared inside the owner's script
			else:
				script = _get_json_script(script_name, json_variant)
			if script == null and type is Script:
				# Unknown or unregistered script: use the type the container is declared with.
				script = type
		elif type is Script:
			# Fall back to the type hint from the parent array/dictionary.
			script = type
		if script == null:
			return _convert_plain_value(json_variant) if json_variant is Dictionary else json_variant
		if json_variant is String:
			return json_to_class(script, JSON.parse_string(json_variant)) # an object used as a dictionary key
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
		if value.size() == 1:
			if value.get(RESOURCE_PATH) is String:
				return _load_resource(value[RESOURCE_PATH])
			if value.get(FLOAT_MARKER) is float:
				return float(value[FLOAT_MARKER])
			if value.get(INT_MARKER) is String:
				return String(value[INT_MARKER]).to_int()
		if value.has(SCRIPT_INHERITANCE):
			var script: Script = _get_json_script(value.get(SCRIPT_INHERITANCE), value)
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
	if text.begins_with(TEXT_PREFIX):
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
		if text.is_valid_int():
			return text.to_int()
		if text.is_valid_float():
			return text.to_float()
		if text == "true" or text == "false":
			return text == "true"
	return text

#endregion
