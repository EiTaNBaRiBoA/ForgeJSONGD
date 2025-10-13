@abstract class_name ForgeJSONGD extends ForgeJSONGDBase


#region Class to Json


## Stores a JSON dictionary to a file, optionally with encryption.
static func store_json_file(file_path: String, data: Dictionary, security_key: String = "") -> bool:
	_check_dir(file_path)
	var file: FileAccess
	if security_key.length() == 0:
		file = FileAccess.open(file_path, FileAccess.WRITE)
	else:
		file = FileAccess.open_encrypted_with_pass(file_path, FileAccess.WRITE, security_key)
	if not file:
		printerr("Error writing to a file")
		return false
	var json_string: String = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	return true


## Converts a Godot class instance into a JSON string.
static func class_to_json_string(_class: Object, specify_class: bool = false) -> String:
	return JSON.stringify(class_to_json(_class, specify_class))


## Converts a Godot class instance into a JSON dictionary, specify_class for manual class specifying (true under inheritance).
## This is the core serialization function.
static func class_to_json(_class: Object, specify_class: bool = false) -> Dictionary:
	var dictionary: Dictionary = {}
	# Store the script name for reference during deserialization if inheritance exists
	if specify_class:
		dictionary.set(SCRIPT_INHERITANCE, _class.get_script().get_global_name())
	var script_language: Variant = _class.get_script()
	var properties: Array = []
	properties = _class.get_property_list()

	# Iterate through each property of the class
	for property: Dictionary in properties:
		var property_name: String = property.get("name")
		var property_type: Variant = property.get("type")
		
		# Skip the built-in 'script' property
		if property_name == "script":
			continue
		var property_value: Variant = _class.get(property_name)
		# Only serialize properties that are exported or marked for storage
		if not property_name.is_empty() and _check_valid_property(property):
			if property_value is Array:
				# Recursively convert arrays to JSON
				dictionary.set(property_name, convert_array_to_json(property_value))
			elif property_value is Dictionary:
				# Recursively convert dictionaries to JSON
				dictionary.set(property_name, convert_dictionary_to_json(property_value))
			# If the property is a Resource:
			elif property_type == TYPE_OBJECT and property_value != null and property_value.get_property_list():
				if property_value is Resource and ResourceLoader.exists(property_value.resource_path):
					var main_src: String = _get_main_tres_path(property_value.resource_path)
					if main_src.get_extension() != "tres":
						# Store the resource path if it's not a .tres file
						dictionary.set(property_name, property_value.resource_path)
					else:
						# Recursively serialize the nested resource
						dictionary.set(property_name, class_to_json(property_value))
				else:
					dictionary.set(property_name, class_to_json(property_value, property.class_name != property_value.get_script().get_global_name()))
			# Special handling for Vector types (store as strings)
			elif type_string(typeof(property_value)).begins_with("Vector"):
				dictionary[property_name] = var_to_str(property_value)
			elif property_type == TYPE_COLOR:
				# Store Color as a hex string
				dictionary.set(property_name, property_value.to_html())
			else:
				# Store other basic types directly
				if property_type == TYPE_INT and property.hint == PROPERTY_HINT_ENUM:
					var enum_params: String = property.hint_string
					for enum_value: String in enum_params.split(","):
						if enum_value.contains(":"):
							if property_value == str_to_var(enum_value.split(":")[1]):
								dictionary.set(property_name, enum_value.split(":")[0])
						else:
							dictionary.set(property_name, enum_value)
				else:
					dictionary.set(property_name, property_value)
	return dictionary

#endregion


#region Json to Class


## Loads a JSON file and converts its contents into a Godot class instance.
## Uses the provided GDScript (castClass) as a template for the class.
static func json_file_to_class(gdscript_or_instace: Variant, file_path: String, security_key: String = "") -> Object:
	if not _check_cast_class(gdscript_or_instace):
		printerr("The provided class is null.")
		return null
	var parsed_results = json_file_to_dict(file_path, security_key)
	if parsed_results.is_empty() and gdscript_or_instace is GDScript:
		return gdscript_or_instace.new()
	return json_to_class(gdscript_or_instace, parsed_results)


## Converts a JSON string into a Godot class instance.
static func json_string_to_class(gdscript_or_instace: Variant, json_string: String) -> Object:
	if not _check_cast_class(gdscript_or_instace):
		printerr("The provided class is null.")
		return null
	var json: JSON = JSON.new()
	var parse_result: Error = json.parse(json_string)
	if parse_result == Error.OK:
		return json_to_class(gdscript_or_instace, json.data)
	return null


## Loads a JSON file and parses it into a Dictionary.
## Supports optional decryption using a security key.
static func json_file_to_dict(file_path: String, security_key: String = "") -> Dictionary:
	var file: FileAccess
	if FileAccess.file_exists(file_path):
		if security_key.length() == 0:
			file = FileAccess.open(file_path, FileAccess.READ)
		else:
			file = FileAccess.open_encrypted_with_pass(file_path, FileAccess.READ, security_key)
		if not file:
			printerr("Error opening file: ", file_path)
			return {}
		var parsed_results: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if parsed_results is Dictionary or parsed_results is Array:
			return parsed_results
	return {}


## Converts a JSON dictionary into a Godot class instance.
## This is the core deserialization function.
static func json_to_class(script_or_instace: Variant, json: Dictionary) -> Object:
	# Create an instance of the target class
	var _class: Variant = null
	var properties: Array = []
	## Passing null as a casted class
	if script_or_instace == null:
		var script_name: String = json.get(SCRIPT_INHERITANCE, null)
		# Looking for the script
		if script_name != null:
			var script_type: GDScript = _get_gdscript(script_name)
			if script_type != null:
				_class = script_type.new() as Object
		# creating an empty object
		elif typeof(script_or_instace) == TYPE_OBJECT:
			_class = script_or_instace
	# Creating an class object
	elif script_or_instace is GDScript or script_or_instace is Script:
		_class = script_or_instace.new() as Object
	elif script_or_instace is Object:
		_class = script_or_instace
		properties = script_or_instace.get_script().get_script_property_list()
	if properties.is_empty():
		if _class == null:
			return Object.new()
		properties = _class.get_property_list()
	# Iterate through each key-value pair in the JSON dictionary
	for key: String in json.keys():
		var value: Variant = json.get(key)
		
		# Special handling for Vector types (stored as strings in JSON)
		if type_string(typeof(value)) == "String" and value.begins_with("Vector"):
			value = str_to_var(value)
			
		# Find the matching property in the target class
		var script_language = _class.get_script()
		for property: Dictionary in properties:
			var property_name: String = property.get("name")
			var property_type: Variant = property.get("type")
			# Skip the 'script' property (built-in)
			if property_name == "script":
				continue
				
			# Get the current value of the property in the class instance
			var property_value: Variant = _class.get(property_name)
			
			# If the property name matches the JSON key and is a script variable:
			if property_name == key and _check_valid_property(property):
				# Case 1: Property is an Object (not an array)
				if not property_value is Array and property_type == TYPE_OBJECT:
					var inner_class_path: String = ""
					if property_value:
						# If the property already holds an object, try to get its script path
						for inner_property: Dictionary in property_value.get_property_list():
							if inner_property.has("hint_string") and inner_property.get("hint_string").contains(".gd"):
								inner_class_path = inner_property.get("hint_string")
						# Recursively deserialize nested objects
						_class.set(property_name, json_to_class(load(inner_class_path), value))
					elif value:
						var script_type: GDScript = null
						# Determine the script type for the nested object
						if value is Dictionary and value.has(SCRIPT_INHERITANCE):
							script_type = _get_gdscript(value.get(SCRIPT_INHERITANCE))
						else:
							script_type = _get_gdscript(property.class_name )
							
						# If the value is a resource path, load the resource
						if value is String and value.is_absolute_path():
							_class.set(property_name, ResourceLoader.load(_get_main_tres_path(value)))
						else:
							# Recursively deserialize nested objects
							_class.set(property_name, json_to_class(script_type, value))
							
				# Case 2: Property is an Array
				elif property_value is Array:
					var arr_script: GDScript = null
					if property_value.is_typed() and property_value.get_typed_script():
						arr_script = load(property_value.get_typed_script().get_path())
						# Recursively convert the JSON array to a Godot array
					if arr_script == null:
						_class.get(property_name).assign(_convert_json_to_array(value, property_value.get_typed_builtin()))
					else:
						_class.get(property_name).assign(_convert_json_to_array(value, arr_script))
				# Case 3: Property is a Typed Dictionary
				elif property_value is Dictionary:
					_convert_json_to_dictionary(property_value, value)
				# Case 4: Property is a simple type (not an object or array)
				else:
					# Special handling for Color type (stored as a hex string)
					if property_type == TYPE_COLOR:
						value = Color(value)
					if property_type == TYPE_INT and property.get("hint") == PROPERTY_HINT_ENUM:
						var enum_strs: Array = property.hint_string.split(",")
						var enum_value: int = 0
						for enum_str: String in enum_strs:
							if enum_str.contains(":"):
								var enum_keys: Array = enum_str.split(":")
								for i: int in enum_keys.size():
									if enum_keys[i].to_lower() == value.to_lower():
										enum_value = int(enum_keys[i + 1])
						_class.set(property_name, int(enum_value))
					elif property_type == TYPE_INT:
						_class.set(property_name, int(value))
					else:
						_class.set(property_name, value)
	# Return the fully deserialized class instance
	return _class

#endregion


#region Json Utilties

## Checks if two jsons are equal, can recieve json string, file path , dictionary
static func check_equal_jsons(first_json: Variant, second_json: Variant) -> bool:
	if _get_dict_from_type(first_json).hash() == _get_dict_from_type(second_json).hash():
		return true
	return false


## Finds the differences between two JSON-like structures.
## Returns a dictionary showing the old and new values for each changed key.
static func compare_jsons_diff(first_json: Variant, second_json: Variant) -> Dictionary:
	var first_dict := _get_dict_from_type(first_json)
	var second_dict := _get_dict_from_type(second_json)
	if first_dict.hash() == second_dict.hash():
		return {}
	return ForgeJSONGDHelper.compare_recursive(first_dict, second_dict)


## Performs a specified operation on a JSON structure ('base_json') using another
## ('ref_json') as a reference.
## Returns the modified dictionary.
static func json_operation(base_json: Variant, ref_json: Variant, operation_type: Operation) -> Dictionary:
	# Ensure we are working with deep copies to avoid modifying original inputs.
	var base_dict: Dictionary = _get_dict_from_type(base_json).duplicate(true)
	var ref_dict: Dictionary = _get_dict_from_type(ref_json)

	if base_dict.hash() == ref_dict.hash():
		if operation_type == Operation.Replace:
			return base_dict
		if operation_type == Operation.Remove || operation_type == Operation.RemoveValue:
			return {}
	return ForgeJSONGDHelper.apply_operation_recursively(base_dict, ref_dict, operation_type)

#endregion
