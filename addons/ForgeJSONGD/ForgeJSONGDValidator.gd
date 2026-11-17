## Checks JSON data against a JSON Schema (the keywords of draft 2020-12 listed in the guide). Internal, use ForgeJSONGD instead.
## Each problem is reported as {"path": "/address/zip", "message": "...", "keyword": "type", "schema_path": "/properties/..."}.
@abstract class_name ForgeJSONGDValidator extends ForgeJSONGDBase

## Keywords whose value is one schema, a list of schemas, or a dictionary of schemas (used to find $id and $anchor).
const _SCHEMA_KEYWORDS: Array[String] = ["additionalProperties", "additionalItems", "items", "contains", "propertyNames", "not", "if", "then", "else"]
const _SCHEMA_LIST_KEYWORDS: Array[String] = ["allOf", "anyOf", "oneOf", "prefixItems", "items"]
const _SCHEMA_MAP_KEYWORDS: Array[String] = ["properties", "patternProperties", "$defs", "definitions", "dependentSchemas"]

## Keywords of the standard that are not supported. A schema that uses one is reported, so nothing is silently unchecked.
const _UNSUPPORTED: Array[String] = ["unevaluatedProperties", "unevaluatedItems", "$dynamicRef", "$dynamicAnchor", "$recursiveRef", "$recursiveAnchor"]

## Data nested deeper than this (or a $ref chain this long) is reported instead of checked.
const _MAX_DEPTH = 256

## Base URI of a schema without an $id. It has a path, so a relative name ("common.schema.json") resolves to
## "forge:///common.schema.json", the same URI a schema registered under that name gets.
const _ROOT_URI = "forge:///schema.json"

## Compiled patterns, by pattern text (null for a pattern that does not compile).
static var _regex_cache: Dictionary = {}

## Schemas registered with register_schema, by absolute URI (no fragment). A $ref to another file or URL can only
## reach these: nothing is ever loaded or fetched by a $ref.
static var _registered_schemas: Dictionary = {}

## What \s matches in the regular expressions of JSON Schema (ECMA-262): also the Unicode spaces.
const _ECMA_SPACE = "\\t\\n\\x{0B}\\f\\r \\x{A0}\\x{1680}\\x{2000}-\\x{200A}\\x{2028}\\x{2029}\\x{202F}\\x{205F}\\x{3000}\\x{FEFF}"

## Long Unicode category names of ECMA-262 (\p{Letter}) -> the short names Godot's regular expressions know (\p{L}).
const _UNICODE_CATEGORIES = {
	"letter": "L", "cased_letter": "L&", "uppercase_letter": "Lu", "lowercase_letter": "Ll", "titlecase_letter": "Lt",
	"modifier_letter": "Lm", "other_letter": "Lo", "mark": "M", "combining_mark": "M", "nonspacing_mark": "Mn",
	"spacing_mark": "Mc", "enclosing_mark": "Me", "number": "N", "decimal_number": "Nd", "digit": "Nd",
	"letter_number": "Nl", "other_number": "No", "punctuation": "P", "punct": "P", "connector_punctuation": "Pc",
	"dash_punctuation": "Pd", "open_punctuation": "Ps", "close_punctuation": "Pe", "initial_punctuation": "Pi",
	"final_punctuation": "Pf", "other_punctuation": "Po", "symbol": "S", "math_symbol": "Sm", "currency_symbol": "Sc",
	"modifier_symbol": "Sk", "other_symbol": "So", "separator": "Z", "space_separator": "Zs", "line_separator": "Zl",
	"paragraph_separator": "Zp", "other": "C", "control": "Cc", "cntrl": "Cc", "format": "Cf", "surrogate": "Cs",
	"private_use": "Co", "unassigned": "Cn",
}


## The state of one validation: the errors found so far and where each $id and $anchor of the schema is.
class _Context:
	var errors: Array[Dictionary] = []
	var resources: Dictionary = {} # absolute URI (no fragment) -> [schema, base URI]
	var anchors: Dictionary = {} # URI#anchor -> [schema, base URI]
	# (The base URI stored with a schema is the one around it: the schema applies its own $id when it is checked.)
	var active_refs: Dictionary = {} # "$ref target|data path" being followed, to catch a $ref that loops


## Checks data against a schema. data: a Dictionary, Array or other JSON value, JSON text, a JSON file path, or an object
## (checked as its class_to_json). schema: a Dictionary or bool (JSON Schema), JSON text, a JSON file path, or a Script
## (its class_to_json_schema). Returns the problems found; an empty array means the data is valid.
static func validate(data: Variant, schema: Variant) -> Array[Dictionary]:
	var context := _Context.new()
	if schema is Object and not schema is Script and schema.get_script() != null:
		schema = schema.get_script() # an object stands for its class
	var read_data: Array = _read_json_value(data, "data")
	var read_schema: Array = [true, ForgeJSONGDSchema.class_to_json_schema(schema)] if schema is Script else _read_json_value(schema, "schema")
	if not read_data[0] or not read_schema[0]:
		for result: Array in [read_data, read_schema]:
			if not result[0]:
				_fail(context, "", "", "json", result[1])
		return context.errors
	var root: Variant = read_schema[1]
	if not (root is Dictionary or root is bool):
		_fail(context, "", "", "schema", "the schema must be a JSON object or a boolean")
		return context.errors
	context.resources[_ROOT_URI] = [root, _ROOT_URI]
	_index_schema(context, root, _ROOT_URI)
	_validate(context, _to_json(read_data[1]), root, _ROOT_URI, "", "", 0)
	return context.errors


## Makes a schema available to $ref under a URI: the given one, else the schema's $id, else (for a file) its file name.
## schema: a Dictionary or bool, JSON text, a JSON file path, or a Script (its class_to_json_schema).
## Returns false (with an error printed) if the schema cannot be read or has no name.
static func register_schema(schema: Variant, uri: String = "") -> bool:
	var read: Array = [true, ForgeJSONGDSchema.class_to_json_schema(schema)] if schema is Script else _read_json_value(schema, "schema")
	if not read[0] or not (read[1] is Dictionary or read[1] is bool):
		printerr("ForgeJSONGD: register_schema: ", read[1] if not read[0] else "a schema must be a JSON object or a boolean")
		return false
	if uri.is_empty() and read[1] is Dictionary and read[1].get("$id") is String:
		uri = read[1]["$id"]
	if uri.is_empty() and (schema is String or schema is StringName) and _parse_json_object(schema) == null:
		uri = String(schema).get_file() # a file: its name, as a $ref next to it would write it
	if uri.is_empty():
		printerr("ForgeJSONGD: register_schema: give the schema a name (uri), or an $id")
		return false
	_registered_schemas[_without_fragment(_resolve_uri(_ROOT_URI, uri))] = read[1]
	return true


## Forgets every schema registered with register_schema.
static func clear_registered_schemas() -> void:
	_registered_schemas.clear()


#region Reading

## Reads data or a schema given in any of the accepted forms. Returns [true, value] or [false, problem].
static func _read_json_value(value: Variant, what: String) -> Array:
	if value is Object:
		return [true, ForgeJSONGDSerializer.class_to_json(value)]
	if not (value is String or value is StringName):
		return [true, value]
	var text: String = value
	var parser := JSON.new()
	if parser.parse(text) == OK:
		return [true, parser.data]
	if not text.contains("\n") and FileAccess.file_exists(text):
		var file: FileAccess = _open_file(text, FileAccess.READ)
		if file == null:
			return [false, "the %s file %s cannot be opened" % [what, text]]
		var content: String = file.get_as_text()
		file.close()
		if parser.parse(content) == OK:
			return [true, parser.data]
		return [false, "the %s file %s is not valid JSON (line %d): %s" % [what, text, parser.get_error_line(), parser.get_error_message()]]
	return [false, "the %s is neither valid JSON text nor an existing file (line %d: %s)" % [what, parser.get_error_line(), parser.get_error_message()]]


## The data as JSON sees it: what it becomes once written and parsed again (NodePath and StringName become text,
## packed arrays become arrays, numbers become floats).
static func _to_json(data: Variant) -> Variant:
	return JSON.parse_string(_stringify(data, "", false)) if data != null else null

#endregion


#region Schema references

## Records every $id and $anchor of a schema, so $ref can find them.
static func _index_schema(context: _Context, schema: Variant, base: String) -> void:
	if not schema is Dictionary:
		return
	var outer_base: String = base
	if schema.get("$id") is String:
		base = _without_fragment(_resolve_uri(base, schema["$id"]))
		context.resources[base] = [schema, outer_base]
	if schema.get("$anchor") is String:
		context.anchors[base + "#" + schema["$anchor"]] = [schema, outer_base]
	for keyword: String in _SCHEMA_KEYWORDS:
		if schema.get(keyword) is Dictionary:
			_index_schema(context, schema[keyword], base)
	for keyword: String in _SCHEMA_LIST_KEYWORDS:
		if schema.get(keyword) is Array:
			for item: Variant in schema[keyword]:
				_index_schema(context, item, base)
	for keyword: String in _SCHEMA_MAP_KEYWORDS:
		if schema.get(keyword) is Dictionary:
			for item: Variant in schema[keyword].values():
				_index_schema(context, item, base)


## Finds the schema a $ref points to. Returns [schema, base URI], or [] if it is not part of this schema.
static func _resolve_ref(context: _Context, base: String, ref: String) -> Array:
	var uri: String = _resolve_uri(base, ref)
	var hash: int = uri.find("#")
	var document: String = uri if hash < 0 else uri.substr(0, hash)
	var fragment: String = "" if hash < 0 else uri.substr(hash + 1).uri_decode()
	if not context.resources.has(document):
		# A registered schema: by its full URI, or by the name exactly as the $ref writes it ("common.schema.json").
		var written: String = _without_fragment(_resolve_uri(_ROOT_URI, ref))
		var registered: String = document if _registered_schemas.has(document) else (written if not ref.begins_with("#") and _registered_schemas.has(written) else "")
		if registered.is_empty():
			return []
		context.resources[registered] = [_registered_schemas[registered], registered]
		_index_schema(context, _registered_schemas[registered], registered)
		if document != registered:
			context.resources[document] = context.resources[registered]
	if not context.resources.has(document):
		return []
	var entry: Array = context.resources[document]
	if fragment.is_empty():
		return entry
	if not fragment.begins_with("/"):
		return context.anchors.get(document + "#" + fragment, [])
	# A JSON Pointer: "/$defs/item" walks into the schema. An $id passed on the way changes the base.
	var node: Variant = entry[0]
	var node_base: String = entry[1]
	for token: String in fragment.substr(1).split("/"):
		token = token.replace("~1", "/").replace("~0", "~")
		if node is Dictionary and node.get("$id") is String:
			node_base = _without_fragment(_resolve_uri(node_base, node["$id"]))
		if node is Dictionary and node.has(token):
			node = node[token]
		elif node is Array and token.is_valid_int() and int(token) >= 0 and int(token) < node.size():
			node = node[int(token)]
		else:
			return []
	return [node, node_base]


## Resolves a URI reference against a base URI (RFC 3986, enough for $id and $ref).
static func _resolve_uri(base: String, ref: String) -> String:
	if ref.begins_with("#"):
		return _without_fragment(base) + ref
	if _has_scheme(ref):
		return _remove_dot_segments(ref)
	var base_document: String = _without_fragment(base)
	var scheme_end: int = base_document.find(":")
	if ref.begins_with("//"):
		return base_document.substr(0, scheme_end + 1) + _remove_dot_segments(ref)
	var authority_end: int = base_document.length()
	if base_document.substr(scheme_end + 1).begins_with("//"):
		var slash: int = base_document.find("/", scheme_end + 3)
		authority_end = slash if slash >= 0 else base_document.length()
	if ref.begins_with("/"):
		return base_document.substr(0, authority_end) + _remove_dot_segments(ref)
	var directory_end: int = base_document.rfind("/")
	if directory_end < authority_end:
		# The base has no path: "http://host" gets "/" + the reference, "urn:..." keeps only its scheme.
		if base_document.substr(scheme_end + 1).begins_with("//"):
			return base_document.substr(0, authority_end) + _remove_dot_segments("/" + ref)
		return base_document.substr(0, scheme_end + 1) + ref
	return base_document.substr(0, authority_end) + _remove_dot_segments(base_document.substr(authority_end, directory_end - authority_end + 1) + ref)


## Removes "." and ".." segments from the path of a URI.
static func _remove_dot_segments(uri: String) -> String:
	if not (uri.contains("/./") or uri.contains("/../") or uri.ends_with("/.") or uri.ends_with("/..")):
		return uri
	var fragment_at: int = uri.find("#")
	var fragment: String = "" if fragment_at < 0 else uri.substr(fragment_at)
	var path: String = uri if fragment_at < 0 else uri.substr(0, fragment_at)
	var output: PackedStringArray = []
	var parts: PackedStringArray = path.split("/")
	for i: int in parts.size():
		var part: String = parts[i]
		if part == ".":
			if i == parts.size() - 1:
				output.append("")
		elif part == "..":
			if output.size() > 1:
				output.remove_at(output.size() - 1)
			if i == parts.size() - 1:
				output.append("")
		else:
			output.append(part)
	return "/".join(output) + fragment


static func _has_scheme(uri: String) -> bool:
	var colon: int = uri.find(":")
	if colon <= 0:
		return false
	for character: String in uri.substr(0, colon):
		if not (character.is_valid_identifier() or character in "0123456789+-."):
			return false
	return not uri.substr(0, 1).is_valid_int()


static func _without_fragment(uri: String) -> String:
	var hash: int = uri.find("#")
	return uri if hash < 0 else uri.substr(0, hash)

#endregion


#region Checking

## Checks one value against one schema and adds the problems found to the context.
static func _validate(context: _Context, data: Variant, schema: Variant, base: String, path: String, schema_path: String, depth: int) -> void:
	if depth > _MAX_DEPTH:
		_fail(context, path, schema_path, "depth", "the data or the schema is nested more than %d levels deep" % _MAX_DEPTH)
		return
	if schema is bool:
		if not schema:
			_fail(context, path, schema_path, "false", "no value is allowed here")
		return
	if not schema is Dictionary:
		_fail(context, path, schema_path, "schema", "a schema must be a JSON object or a boolean")
		return
	if schema.get("$id") is String:
		base = _without_fragment(_resolve_uri(base, schema["$id"]))
	for keyword: String in _UNSUPPORTED:
		if schema.has(keyword):
			_fail(context, path, schema_path + "/" + keyword, keyword, "the keyword %s is not supported, so this part was not checked" % keyword)

	if schema.has("$ref"):
		_check_ref(context, data, schema["$ref"], base, path, schema_path + "/$ref", depth)
	_check_value(context, data, schema, path, schema_path)
	if _is_number(data):
		_check_number(context, float(data), schema, path, schema_path)
	elif data is String:
		_check_string(context, data, schema, path, schema_path)
	elif data is Array:
		_check_array(context, data, schema, base, path, schema_path, depth)
	elif data is Dictionary:
		_check_object(context, data, schema, base, path, schema_path, depth)
	_check_combinations(context, data, schema, base, path, schema_path, depth)


static func _check_ref(context: _Context, data: Variant, ref: Variant, base: String, path: String, schema_path: String, depth: int) -> void:
	if not ref is String:
		_fail(context, path, schema_path, "$ref", "$ref must be text")
		return
	var target: Array = _resolve_ref(context, base, ref)
	if target.is_empty():
		_fail(context, path, schema_path, "$ref", "the $ref '%s' cannot be found: it is not in this schema or a registered one (files and URLs are never loaded, register them with register_schema)" % ref)
		return
	var loop_key: String = _resolve_uri(base, ref) + "|" + path
	if context.active_refs.has(loop_key):
		_fail(context, path, schema_path, "$ref", "the $ref '%s' loops back to itself without checking anything" % ref)
		return
	context.active_refs[loop_key] = true
	_validate(context, data, target[0], target[1], path, schema_path, depth + 1)
	context.active_refs.erase(loop_key)


## type, enum and const.
static func _check_value(context: _Context, data: Variant, schema: Dictionary, path: String, schema_path: String) -> void:
	if schema.has("type"):
		var types: Variant = schema["type"]
		if types is String:
			types = [types]
		if not types is Array:
			_fail(context, path, schema_path + "/type", "type", "type must be text or a list of text")
		else:
			var matches: bool = false
			for type_name: Variant in types:
				if _is_type(data, type_name):
					matches = true
					break
			if not matches:
				_fail(context, path, schema_path + "/type", "type", "expected %s, got %s" % [" or ".join(PackedStringArray(types.map(func(type_name: Variant) -> String: return str(type_name)))), _type_name(data)])
	if schema.has("enum"):
		if not schema["enum"] is Array:
			_fail(context, path, schema_path + "/enum", "enum", "enum must be a list")
		elif not schema["enum"].any(func(allowed: Variant) -> bool: return _json_equal(data, allowed)):
			_fail(context, path, schema_path + "/enum", "enum", "must be one of %s, got %s" % [_short(schema["enum"]), _short(data)])
	if schema.has("const") and not _json_equal(data, schema["const"]):
		_fail(context, path, schema_path + "/const", "const", "must be %s, got %s" % [_short(schema["const"]), _short(data)])


static func _check_number(context: _Context, number: float, schema: Dictionary, path: String, schema_path: String) -> void:
	if schema.has("multipleOf"):
		var divisor: Variant = schema["multipleOf"]
		if not _is_number(divisor) or divisor <= 0:
			_fail(context, path, schema_path + "/multipleOf", "multipleOf", "multipleOf must be a number above 0")
		elif not _is_multiple(number, float(divisor)):
			_fail(context, path, schema_path + "/multipleOf", "multipleOf", "must be a multiple of %s, got %s" % [_short(divisor), _short(number)])
	# exclusiveMinimum / exclusiveMaximum are numbers; true/false next to minimum / maximum is the older (draft 4) form.
	for limit: Array in [["minimum", "exclusiveMinimum", 1.0], ["maximum", "exclusiveMaximum", -1.0]]:
		var inclusive: Variant = schema.get(limit[0])
		var exclusive: Variant = schema.get(limit[1])
		var direction: float = limit[2]
		if exclusive is bool and _is_number(inclusive):
			if exclusive:
				exclusive = inclusive
				inclusive = null
			else:
				exclusive = null
		for keyword_and_value: Array in [[limit[0], inclusive, false], [limit[1], exclusive, true]]:
			var bound: Variant = keyword_and_value[1]
			if bound == null:
				continue
			if not _is_number(bound):
				_fail(context, path, schema_path + "/" + keyword_and_value[0], keyword_and_value[0], "%s must be a number" % keyword_and_value[0])
				continue
			var difference: float = (number - float(bound)) * direction # above 0 when the value is on the allowed side
			if difference < 0 or (keyword_and_value[2] and difference == 0):
				var words: String = ("at least %s" if not keyword_and_value[2] else "more than %s") if direction > 0 else ("at most %s" if not keyword_and_value[2] else "less than %s")
				_fail(context, path, schema_path + "/" + keyword_and_value[0], keyword_and_value[0], "must be %s, got %s" % [words % _short(bound), _short(number)])


static func _check_string(context: _Context, text: String, schema: Dictionary, path: String, schema_path: String) -> void:
	_count_ok(context, schema, "minLength", text.length(), path, schema_path, "must be at least %d characters long, got %d")
	_count_ok(context, schema, "maxLength", text.length(), path, schema_path, "must be at most %d characters long, got %d")
	if schema.has("pattern"):
		var regex: RegEx = _regex(schema["pattern"]) if schema["pattern"] is String else null
		if regex == null:
			_fail(context, path, schema_path + "/pattern", "pattern", "the pattern %s is not a valid regular expression" % _short(schema["pattern"]))
		elif regex.search(text) == null:
			_fail(context, path, schema_path + "/pattern", "pattern", "must match the pattern %s, got %s" % [_short(schema["pattern"]), _short(text)])


static func _check_array(context: _Context, array: Array, schema: Dictionary, base: String, path: String, schema_path: String, depth: int) -> void:
	_count_ok(context, schema, "minItems", array.size(), path, schema_path, "must have at least %d items, got %d")
	_count_ok(context, schema, "maxItems", array.size(), path, schema_path, "must have at most %d items, got %d")
	if schema.get("uniqueItems") == true:
		for i: int in array.size():
			for j: int in range(i + 1, array.size()):
				if _json_equal(array[i], array[j]):
					_fail(context, path, schema_path + "/uniqueItems", "uniqueItems", "items %d and %d are equal, but items must be unique" % [i, j])
					break

	# prefixItems check the first items one by one, items checks the rest. ("items" as a list is the older form of prefixItems.)
	var prefix: Variant = schema.get("prefixItems")
	var prefix_keyword: String = "prefixItems"
	var rest: Variant = schema.get("items")
	var rest_keyword: String = "items"
	if rest is Array:
		prefix = rest
		prefix_keyword = "items"
		rest = schema.get("additionalItems")
		rest_keyword = "additionalItems"
	var checked: int = 0
	if prefix is Array:
		checked = mini(prefix.size(), array.size())
		for i: int in checked:
			_validate(context, array[i], prefix[i], base, path + "/" + str(i), schema_path + "/%s/%d" % [prefix_keyword, i], depth + 1)
	elif prefix != null:
		_fail(context, path, schema_path + "/prefixItems", "prefixItems", "prefixItems must be a list of schemas")
	if rest != null:
		for i: int in range(checked, array.size()):
			_validate(context, array[i], rest, base, path + "/" + str(i), schema_path + "/" + rest_keyword, depth + 1)

	if schema.has("contains"):
		var found: int = 0
		for i: int in array.size():
			if _passes(context, array[i], schema["contains"], base, path + "/" + str(i), schema_path + "/contains", depth + 1):
				found += 1
		var minimum: Variant = schema.get("minContains", 1)
		var maximum: Variant = schema.get("maxContains")
		if _is_number(minimum) and found < minimum:
			_fail(context, path, schema_path + "/contains", "contains", "must contain at least %d matching items, found %d" % [int(minimum), found])
		if _is_number(maximum) and found > maximum:
			_fail(context, path, schema_path + "/maxContains", "maxContains", "must contain at most %d matching items, found %d" % [int(maximum), found])


static func _check_object(context: _Context, object: Dictionary, schema: Dictionary, base: String, path: String, schema_path: String, depth: int) -> void:
	_count_ok(context, schema, "minProperties", object.size(), path, schema_path, "must have at least %d properties, got %d")
	_count_ok(context, schema, "maxProperties", object.size(), path, schema_path, "must have at most %d properties, got %d")
	if schema.has("required"):
		if not schema["required"] is Array:
			_fail(context, path, schema_path + "/required", "required", "required must be a list of names")
		else:
			for name: Variant in schema["required"]:
				if not object.has(name):
					_fail(context, path, schema_path + "/required", "required", "the property '%s' is required" % str(name))
	if schema.get("dependentRequired") is Dictionary:
		for name: String in schema["dependentRequired"]:
			if object.has(name) and schema["dependentRequired"][name] is Array:
				for needed: Variant in schema["dependentRequired"][name]:
					if not object.has(needed):
						_fail(context, path, schema_path + "/dependentRequired", "dependentRequired", "the property '%s' is required when '%s' is present" % [str(needed), name])
	if schema.get("dependentSchemas") is Dictionary:
		for name: String in schema["dependentSchemas"]:
			if object.has(name):
				_validate(context, object, schema["dependentSchemas"][name], base, path, schema_path + "/dependentSchemas/" + _escape_pointer(name), depth + 1)
	if schema.get("dependencies") is Dictionary: # the older (draft 7) form of dependentRequired and dependentSchemas
		for name: String in schema["dependencies"]:
			var dependency: Variant = schema["dependencies"][name]
			if not object.has(name):
				continue
			if dependency is Array:
				for needed: Variant in dependency:
					if not object.has(needed):
						_fail(context, path, schema_path + "/dependencies", "dependencies", "the property '%s' is required when '%s' is present" % [str(needed), name])
			else:
				_validate(context, object, dependency, base, path, schema_path + "/dependencies/" + _escape_pointer(name), depth + 1)

	var properties: Variant = schema.get("properties", {})
	var patterns: Variant = schema.get("patternProperties", {})
	if not properties is Dictionary or not patterns is Dictionary:
		_fail(context, path, schema_path, "properties", "properties and patternProperties must be objects")
		return
	for key: Variant in object:
		var name: String = str(key)
		var key_path: String = path + "/" + _escape_pointer(name)
		var matched: bool = false
		if properties.has(name):
			matched = true
			_validate(context, object[key], properties[name], base, key_path, schema_path + "/properties/" + _escape_pointer(name), depth + 1)
		for pattern: String in patterns:
			var regex: RegEx = _regex(pattern)
			if regex == null:
				_fail(context, path, schema_path + "/patternProperties", "patternProperties", "the pattern %s is not a valid regular expression" % _short(pattern))
			elif regex.search(name) != null:
				matched = true
				_validate(context, object[key], patterns[pattern], base, key_path, schema_path + "/patternProperties/" + _escape_pointer(pattern), depth + 1)
		if not matched and schema.has("additionalProperties"):
			if schema["additionalProperties"] is bool and not schema["additionalProperties"]:
				_fail(context, key_path, schema_path + "/additionalProperties", "additionalProperties", "the property '%s' is not allowed" % name)
			else:
				_validate(context, object[key], schema["additionalProperties"], base, key_path, schema_path + "/additionalProperties", depth + 1)
		if schema.has("propertyNames") and not _passes(context, name, schema["propertyNames"], base, key_path, schema_path + "/propertyNames", depth + 1):
			_fail(context, key_path, schema_path + "/propertyNames", "propertyNames", "the property name '%s' is not allowed by propertyNames" % name)


## allOf, anyOf, oneOf, not and if / then / else.
static func _check_combinations(context: _Context, data: Variant, schema: Dictionary, base: String, path: String, schema_path: String, depth: int) -> void:
	for keyword: String in ["allOf", "anyOf", "oneOf"]:
		if not schema.has(keyword):
			continue
		var options: Variant = schema[keyword]
		if not options is Array or options.is_empty():
			_fail(context, path, schema_path + "/" + keyword, keyword, "%s must be a non-empty list of schemas" % keyword)
			continue
		if keyword == "allOf":
			for i: int in options.size():
				_validate(context, data, options[i], base, path, schema_path + "/allOf/%d" % i, depth + 1)
			continue
		var passing: Array[int] = []
		for i: int in options.size():
			if _passes(context, data, options[i], base, path, schema_path + "/%s/%d" % [keyword, i], depth + 1):
				passing.append(i)
		if passing.is_empty():
			_fail(context, path, schema_path + "/" + keyword, keyword, "does not match any of the %d schemas in %s" % [options.size(), keyword])
		elif keyword == "oneOf" and passing.size() > 1:
			_fail(context, path, schema_path + "/oneOf", "oneOf", "matches more than one schema in oneOf (schemas %s)" % ", ".join(PackedStringArray(passing.map(func(index: int) -> String: return str(index)))))
	if schema.has("not") and _passes(context, data, schema["not"], base, path, schema_path + "/not", depth + 1):
		_fail(context, path, schema_path + "/not", "not", "must not match the schema in not")
	if schema.has("if"):
		var branch: String = "then" if _passes(context, data, schema["if"], base, path, schema_path + "/if", depth + 1) else "else"
		if schema.has(branch):
			_validate(context, data, schema[branch], base, path, schema_path + "/" + branch, depth + 1)


## True if the data matches the schema. Its problems are not reported (anyOf, contains... report their own).
static func _passes(context: _Context, data: Variant, schema: Variant, base: String, path: String, schema_path: String, depth: int) -> bool:
	var before: int = context.errors.size()
	_validate(context, data, schema, base, path, schema_path, depth)
	var passed: bool = context.errors.size() == before
	context.errors.resize(before)
	return passed


## Checks a count against minLength, maxItems...: the keyword's name says whether it is a lower or an upper limit.
static func _count_ok(context: _Context, schema: Dictionary, keyword: String, count: int, path: String, schema_path: String, message: String) -> bool:
	if not schema.has(keyword):
		return true
	var limit: Variant = schema[keyword]
	if not _is_number(limit) or limit < 0 or limit != floor(limit):
		_fail(context, path, schema_path + "/" + keyword, keyword, "%s must be a whole number of 0 or more" % keyword)
		return false
	var ok: bool = count >= limit if keyword.begins_with("min") else count <= limit
	if not ok:
		_fail(context, path, schema_path + "/" + keyword, keyword, message % [int(limit), count])
	return ok

#endregion


#region Helpers

static func _fail(context: _Context, path: String, schema_path: String, keyword: String, message: String) -> void:
	context.errors.append({"path": path, "keyword": keyword, "message": message, "schema_path": schema_path})


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


static func _is_type(data: Variant, type_name: Variant) -> bool:
	match type_name:
		"null":
			return data == null
		"boolean":
			return data is bool
		"integer":
			return data is int or (data is float and is_finite(data) and data == floor(data))
		"number":
			return _is_number(data)
		"string":
			return data is String
		"array":
			return data is Array
		"object":
			return data is Dictionary
	return false


static func _type_name(data: Variant) -> String:
	for type_name: String in ["null", "boolean", "integer", "number", "string", "array", "object"]:
		if _is_type(data, type_name):
			return type_name
	return type_string(typeof(data))


## JSON equality: numbers by value (1 equals 1.0), objects ignoring key order, a bool is never a number.
static func _json_equal(first: Variant, second: Variant) -> bool:
	if _is_number(first) and _is_number(second):
		return float(first) == float(second)
	if (first is String or first is StringName) and (second is String or second is StringName):
		return String(first) == String(second)
	if first is Array and second is Array:
		if first.size() != second.size():
			return false
		for i: int in first.size():
			if not _json_equal(first[i], second[i]):
				return false
		return true
	if first is Dictionary and second is Dictionary:
		if first.size() != second.size():
			return false
		for key: Variant in first:
			if not second.has(key) or not _json_equal(first[key], second[key]):
				return false
		return true
	return typeof(first) == typeof(second) and first == second


static func _is_multiple(number: float, divisor: float) -> bool:
	var quotient: float = number / divisor
	if not is_finite(quotient) or absf(quotient) > _MAX_SAFE_INT:
		# The quotient is too large to show a fraction. A whole number is a multiple of 0.5, 1e-8... (1 / divisor is whole);
		# otherwise the remainder, which fmod computes exactly, decides (1e20 is not a multiple of 3).
		var reciprocal: float = 1.0 / divisor
		if number == floor(number) and divisor < 1.0 and absf(reciprocal - roundf(reciprocal)) <= 1e-9 * reciprocal:
			return true
		return fmod(number, divisor) == 0.0
	return absf(quotient - roundf(quotient)) <= 1e-9 * maxf(1.0, absf(quotient))


static func _regex(pattern: String) -> RegEx:
	if not _regex_cache.has(pattern):
		var regex := RegEx.new()
		_regex_cache[pattern] = regex if regex.compile(_to_godot_regex(pattern), false) == OK else null
	return _regex_cache[pattern]


## Rewrites the parts of an ECMA-262 pattern (the flavour JSON Schema uses) that Godot's regular expressions (PCRE2)
## read differently: \s and \S also cover Unicode spaces, \p{Letter} long names, and \uXXXX escapes.
static func _to_godot_regex(pattern: String) -> String:
	var result: String = ""
	var in_class: bool = false
	var i: int = 0
	while i < pattern.length():
		var character: String = pattern[i]
		if character == "\\" and i + 1 < pattern.length():
			var next: String = pattern[i + 1]
			if (next == "p" or next == "P") and pattern.substr(i + 2, 1) == "{" and pattern.find("}", i + 3) > 0:
				var close: int = pattern.find("}", i + 3)
				var name: String = pattern.substr(i + 3, close - i - 3).trim_prefix("General_Category=").trim_prefix("gc=")
				result += "\\%s{%s}" % [next, _UNICODE_CATEGORIES.get(name.to_lower(), name)]
				i = close + 1
				continue
			if next == "u" and pattern.substr(i + 2, 1) == "{" and pattern.find("}", i + 3) > 0:
				var end: int = pattern.find("}", i + 3)
				result += "\\x{%s}" % pattern.substr(i + 3, end - i - 3)
				i = end + 1
				continue
			if next == "u" and pattern.substr(i + 2, 4).is_valid_hex_number():
				result += "\\x{%s}" % pattern.substr(i + 2, 4)
				i += 6
				continue
			if next == "s":
				result += _ECMA_SPACE if in_class else "[" + _ECMA_SPACE + "]"
				i += 2
				continue
			if next == "S" and not in_class:
				result += "[^" + _ECMA_SPACE + "]"
				i += 2
				continue
			result += character + next
			i += 2
			continue
		if character == "[" and not in_class:
			in_class = true
		elif character == "]" and in_class:
			in_class = false
		result += character
		i += 1
	return result


## A key as a JSON Pointer segment: "~" and "/" are escaped.
static func _escape_pointer(key: String) -> String:
	return key.replace("~", "~0").replace("/", "~1")


## A value as short JSON text for a message.
static func _short(value: Variant) -> String:
	if value is float and is_finite(value) and value == floor(value) and absf(value) < _MAX_SAFE_INT:
		return str(int(value)) # JSON numbers arrive as floats: show 5, not 5.0
	var text: String = _stringify(value, "", false)
	return text if text.length() <= 80 else text.substr(0, 77) + "..."

#endregion
