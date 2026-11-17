## Class -> JSON Schema: describes the JSON that class_to_json writes for a class. Internal, use ForgeJSONGD instead.
## Every decision here mirrors ForgeJSONGDSerializer (_store_property and _serialize_variant), type by type.
@abstract class_name ForgeJSONGDSchema extends ForgeJSONGDBase

const _DIALECT = "https://json-schema.org/draft/2020-12/schema"

## Text that a whole number written as text (an int above 2^53 in a save file) matches.
const _INT_TEXT = "^-?[0-9]+$"

## Hex text that Color() reads: what the serializer writes (8 digits) and the shorter forms APIs send.
const _COLOR_TEXT = "^#?([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"

## Generated schemas by [script, only_exported_values]. Cleared when script aliases change (they appear in the schema).
static var _cache: Dictionary = {}


## The state of one generation: the class definitions made so far.
class _Generation:
	var definitions: Dictionary = {} # definition name -> schema
	var names: Dictionary = {} # [script, plain] -> definition name
	var instances: Array[Object] = [] # created to read the classes, freed at the end
	var instance_of: Dictionary = {} # script -> its instance (null if it cannot be created)
	var children: Dictionary = {} # global class name -> names of the global classes that extend it directly


## The JSON Schema of a class: what class_to_json(instance) writes, so validate_json(class_to_json(x), Class) passes.
static func class_to_json_schema(script: Script) -> Dictionary:
	var cache_key: Array = [script, only_exported_values]
	if not _cache.has(cache_key):
		var generation := _Generation.new()
		for class_info: Dictionary in ProjectSettings.get_global_class_list():
			if not generation.children.has(class_info.base):
				generation.children[class_info.base] = []
			generation.children[class_info.base].append(class_info.class)
		var root_ref: String = _class_ref(generation, script, false)
		for instance: Object in generation.instances:
			if not instance is RefCounted:
				instance.free()
		# The $id makes the "#/$defs/..." references work when this schema is put inside another one ("items": schema).
		var id: String = "urn:forgejsongd:" + root_ref.get_file()
		_cache[cache_key] = {"$schema": _DIALECT, "$id": id, "$ref": root_ref, "type": "object", "$defs": generation.definitions}
	return _cache[cache_key].duplicate(true)


## Forgets the generated schemas (called when script aliases change).
static func _clear_cache() -> void:
	_cache.clear()


#region Classes

## A "$ref" to the definition of a class, creating the definition the first time. plain is true inside a plain class.
static func _class_ref(generation: _Generation, script: Script, plain: bool) -> String:
	if not generation.instance_of.has(script):
		generation.instance_of[script] = _instance_of(generation, script)
	var instance: Object = generation.instance_of[script]
	plain = plain or (instance != null and _hook(instance, "_forge_plain_json", false))
	var key: Array = [script, plain]
	if not generation.names.has(key):
		var name: String = _definition_name(generation, script, plain)
		generation.names[key] = name
		generation.definitions[name] = {} # reserved first: a class can contain itself
		generation.definitions[name] = _class_schema(generation, instance, script, plain)
	return "#/$defs/" + generation.names[key]


## The schema of a class's JSON object. It has no "type": the places that use it say "object", or also "null".
static func _class_schema(generation: _Generation, instance: Object, script: Script, plain: bool) -> Dictionary:
	if instance == null or instance.has_method("_forge_serialize"):
		return {} # a class that writes itself (or cannot be created without arguments) can hold anything
	var schema: Dictionary = {}
	var title: String = String(script.get_global_name())
	if not title.is_empty():
		schema["title"] = title
	var properties: Dictionary = {}
	var key_of: Dictionary = {} # variable name -> JSON key
	var json_properties: Dictionary = _json_properties(instance)
	for json_key: String in json_properties:
		var property: Dictionary = json_properties[json_key]
		key_of[property.name] = json_key
		properties[json_key] = _property_schema(generation, property, instance.get(property.name), instance, plain)
	schema["properties"] = properties

	# The class's own rules (_forge_schema), in JSON Schema words, by variable name or JSON key.
	var rules: Variant = _hook(instance, "_forge_schema", {})
	if rules is Dictionary:
		for keyword: Variant in rules:
			var value: Variant = rules[keyword]
			if keyword == "properties" and value is Dictionary:
				for name: Variant in value:
					var json_key: String = key_of.get(name, name)
					if properties.get(json_key) is Dictionary and value[name] is Dictionary:
						properties[json_key].merge(value[name], true)
					else:
						properties[json_key] = value[name]
			elif keyword == "required" and value is Array:
				schema["required"] = value.map(func(name: Variant) -> Variant: return key_of.get(name, name))
			else:
				schema[keyword] = value

	if not plain:
		# A save file may name a child class: check the object against that class too (only classes with a class_name).
		var subclass_rules: Array = []
		for child: String in _descendants(generation, title):
			var child_script: Script = _get_gdscript(child)
			if child_script != null:
				subclass_rules.append({
					"if": {"properties": {SCRIPT_INHERITANCE: {"enum": _script_references(child_script)}}, "required": [SCRIPT_INHERITANCE]},
					"then": {"$ref": _class_ref(generation, child_script, false)},
				})
		if not subclass_rules.is_empty():
			schema["allOf"] = subclass_rules
		# A class that allows no other keys still allows the keys a save file adds to objects.
		if schema.get("additionalProperties") is bool and not schema["additionalProperties"]:
			for marker: String in [SCRIPT_INHERITANCE, _SCRIPT_UID]:
				properties[marker] = {"type": "string"}
			if instance.has_method("_forge_constructor_args"):
				properties[CONSTRUCTOR_ARGS] = {"type": "array"}
	return schema


## The names a save file may use for a script: its class_name, its aliases and its path.
static func _script_references(script: Script) -> Array:
	var references: Array = [String(script.get_global_name())]
	for alias: String in _script_aliases:
		if _script_aliases[alias] == script:
			references.append(alias)
	if not script.resource_path.is_empty():
		references.append(script.resource_path)
	return references


## Every global class that extends the given one, directly or not.
static func _descendants(generation: _Generation, global_name: String) -> Array:
	var result: Array = []
	if global_name.is_empty():
		return result
	for child: String in generation.children.get(global_name, []):
		result.append(child)
		result.append_array(_descendants(generation, child))
	return result


## An instance of the script, to read its variables, their default values and its hooks. null if it cannot be created.
static func _instance_of(generation: _Generation, script: Script) -> Object:
	if not script.can_instantiate():
		return null
	# A class whose _init needs arguments gets empty ones (0, "", null...): only its variables and hooks are read.
	var arguments: Array = []
	for method: Dictionary in script.get_script_method_list():
		if method.name == "_init":
			for i: int in method.args.size() - method.default_args.size():
				arguments.append(type_convert(null, method.args[i].type))
			break
	var instance: Object = script.new.callv(arguments)
	if instance != null:
		generation.instances.append(instance)
	return instance


## A readable, unique name for the definition of a class. A class used both in a save file and inside a plain class
## has two definitions: the second one is named Name_plain or Name_save.
static func _definition_name(generation: _Generation, script: Script, plain: bool) -> String:
	var name: String = script.get_global_name()
	if name.is_empty():
		name = script.resource_path.get_file().get_basename() if not script.resource_path.is_empty() else "Class"
		name = name.validate_filename().replace(" ", "_").replace("#", "_")
	if generation.names.has([script, not plain]):
		name += "_plain" if plain else "_save"
	var unique: String = name
	var number: int = 2
	while generation.definitions.has(unique):
		unique = "%s_%d" % [name, number]
		number += 1
	return unique

#endregion


#region Properties and values

## The schema of one variable (mirrors ForgeJSONGDSerializer._store_property).
static func _property_schema(generation: _Generation, property: Dictionary, value: Variant, owner: Object, plain: bool) -> Dictionary:
	var type: int = property.get("type")
	if value is Array:
		return _array_schema(generation, value, owner, plain)
	if value is Dictionary:
		return _dictionary_schema(generation, value, owner, plain)
	if type == TYPE_OBJECT:
		# The class of the object the variable already holds, else the declared class (as loading does). C# members
		# often only name their class in the hint.
		var declared: String = property.get("class_name")
		if declared.is_empty() and property.get("hint") in [PROPERTY_HINT_RESOURCE_TYPE, PROPERTY_HINT_NODE_TYPE]:
			declared = property.get("hint_string")
		var script: Script = value.get_script() as Script if value is Object and value != null else null
		if script == null:
			script = _get_declared_script(owner, declared)
		return _object_schema(generation, script, declared, plain)
	if type == TYPE_NIL:
		return {} # a Variant can hold anything
	if type in _TEXT_RENDERED_TYPES:
		return _text_schema(type)
	if type == TYPE_PACKED_INT64_ARRAY:
		if plain:
			return {"type": "array", "items": {"type": "integer"}}
		# Numbers too large for JSON make a save file write the whole array as text.
		return {"type": ["array", "string"], "items": {"type": "integer"}, "pattern": "^PackedInt64Array\\("}
	if _is_vector_type(type):
		return _vector_schema(type, plain)
	if type == TYPE_COLOR:
		return {"type": "string", "pattern": _COLOR_TEXT}
	if type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
		return {"enum": _enum_names(property.get("hint_string"))}
	return _builtin_schema(type, plain)


## The schema of a value inside a typed array or dictionary (mirrors ForgeJSONGDSerializer._serialize_variant).
static func _element_schema(generation: _Generation, builtin: int, script: Script, native_class: StringName, plain: bool) -> Dictionary:
	if script != null:
		return _object_schema(generation, script, native_class, plain)
	match builtin:
		TYPE_NIL:
			return {}
		TYPE_OBJECT:
			return _object_schema(generation, null, native_class, plain)
		TYPE_ARRAY:
			return {"type": "array"}
		TYPE_DICTIONARY:
			return {"type": "object"}
		TYPE_COLOR:
			return {"type": "string", "pattern": _COLOR_TEXT}
	if _is_vector_type(builtin):
		return _vector_schema(builtin, plain)
	if builtin in _TAGGED_TYPES:
		return _text_schema(builtin) # Rect2, packed arrays... are written as text inside containers
	return _builtin_schema(builtin, plain)


static func _builtin_schema(type: int, plain: bool) -> Dictionary:
	match type:
		TYPE_BOOL:
			return {"type": "boolean"}
		TYPE_INT:
			# A save file writes an int above 2^53 as text, so no digit is lost.
			return {"type": "integer"} if plain else {"type": ["integer", "string"], "pattern": _INT_TEXT}
		TYPE_FLOAT:
			return {"type": "number"}
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return {"type": "string"}
		TYPE_PACKED_INT32_ARRAY:
			return {"type": "array", "items": {"type": "integer"}}
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			return {"type": "array", "items": {"type": "number"}}
		TYPE_PACKED_STRING_ARRAY:
			return {"type": "array", "items": {"type": "string"}}
	return {}


## An object variable or element: the class's object, null, or (for resources) the path of a resource file.
static func _object_schema(generation: _Generation, script: Script, native_class: StringName, plain: bool) -> Dictionary:
	var base_class: StringName = script.get_instance_base_type() if script != null else native_class
	var types: Array = ["object", "null"]
	if base_class.is_empty() or base_class == &"Object" or ClassDB.is_parent_class(base_class, &"Resource"):
		types.append("string")
	if script == null:
		return {"type": types}
	return {"type": types, "$ref": _class_ref(generation, script, plain)}


static func _array_schema(generation: _Generation, array: Array, owner: Object, plain: bool) -> Dictionary:
	if not array.is_typed():
		return {"type": "array"}
	var script: Script = array.get_typed_script()
	return {"type": "array", "items": _element_schema(generation, array.get_typed_builtin(), script, array.get_typed_class_name(), plain)}


static func _dictionary_schema(generation: _Generation, dictionary: Dictionary, owner: Object, plain: bool) -> Dictionary:
	var schema: Dictionary = {"type": "object"}
	if dictionary.is_typed_value():
		schema["additionalProperties"] = _element_schema(generation, dictionary.get_typed_value_builtin(), dictionary.get_typed_value_script(), dictionary.get_typed_value_class_name(), plain)
	# JSON keys are text. A typed key says what that text looks like.
	match dictionary.get_typed_key_builtin():
		TYPE_INT:
			schema["propertyNames"] = {"pattern": _INT_TEXT}
		TYPE_BOOL:
			schema["propertyNames"] = {"enum": ["true", "false"]}
	return schema


## A vector: {"x": 1, "y": 2} in plain JSON, "Vector2(1, 2)" in a save file.
static func _vector_schema(type: int, plain: bool) -> Dictionary:
	if not plain:
		return _text_schema(type)
	var component: Dictionary = {"type": "integer" if type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else "number"}
	var names: Array = ["x", "y"]
	if type in [TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
		names.append("z")
	if type in [TYPE_VECTOR4, TYPE_VECTOR4I]:
		names.append("w")
	var properties: Dictionary = {}
	for name: String in names:
		properties[name] = component.duplicate()
	return {"type": "object", "properties": properties, "required": names}


## A built-in type written as Godot text: "Rect2(1, 2, 3, 4)", 'PackedByteArray("AQI=")'...
static func _text_schema(type: int) -> Dictionary:
	return {"type": "string", "pattern": "^%s\\(" % type_string(type)}


## The names an enum variable is written with (the names ForgeJSONGDSerializer._enum_to_string writes: Godot shows
## VERY_SLOW as "Very Slow", written "Very_Slow"), and the same in capitals, as in the code (VERY_SLOW). Loading reads both.
static func _enum_names(hint_string: String) -> Array:
	var names: Array = []
	for entry: String in hint_string.split(","):
		var name: String = entry.replace(" ", "_").split(":")[0]
		for form: String in [name, name.to_upper()]:
			if not form in names:
				names.append(form)
	return names

#endregion
