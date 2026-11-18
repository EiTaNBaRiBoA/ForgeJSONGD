## Runs the official JSON Schema Test Suite (https://github.com/json-schema-org/JSON-Schema-Test-Suite) against
## ForgeJSONGD.validate_json, for draft 2020-12. The suite is not part of this project: pass the folder of its
## validation/tests with the FORGE_SCHEMA_SUITE environment variable (run_tests.ps1 -SchemaSuite <folder>).
## The other schemas a test case refers to ("externalSchemas") are given with ForgeJSONGD.register_schema.
## Test cases that need something the validator does not do on purpose are counted as skipped, with the reason:
## keywords it reports as unsupported, and $ref to the JSON Schema meta-schemas, which are not registered.
extends Node

const DIALECT = 2020
const SKIP_KEYWORDS = ["unevaluatedProperties", "unevaluatedItems", "$dynamicRef", "$dynamicAnchor", "$recursiveRef", "$recursiveAnchor"]

var skipped: Dictionary = {} # reason -> count


func _ready() -> void:
	var folder: String = OS.get_environment("FORGE_SCHEMA_SUITE")
	TestUtil.check(not folder.is_empty() and DirAccess.dir_exists_absolute(folder), "the suite folder is given (%s)" % folder)
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		TestUtil.finish("SchemaSuite", get_tree())
		return
	for sub_folder: String in ["", "optional"]:
		var totals: Array[int] = [0, 0]
		var path: String = folder.path_join(sub_folder)
		for file_name: String in DirAccess.get_files_at(path):
			if file_name.ends_with(".json"):
				var result: Array[int] = _run_file(path.path_join(file_name), sub_folder.path_join(file_name) if sub_folder else file_name, sub_folder == "")
				totals[0] += result[0]
				totals[1] += result[1]
		print("%s suite tests passed: %d of %d run" % ["Optional" if sub_folder else "Required", totals[0], totals[0] + totals[1]])
	for reason: String in skipped:
		print("Skipped (%s): %d" % [reason, skipped[reason]])
	TestUtil.finish("SchemaSuite", get_tree())


## Runs the test cases of one file. Required tests count as checks; optional ones (format, regex details...) are
## printed as known issues when they fail, because the standard does not require them.
func _run_file(path: String, label: String, required: bool) -> Array[int]:
	var cases: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if cases is Dictionary:
		cases = cases.get("tests", []) # {"description": ..., "tests": [test cases]}
	var passed: int = 0
	var failed: int = 0
	for test_case: Dictionary in cases:
		if not _applies(test_case.get("compatibility", "")):
			continue
		var reason: String = _skip_reason(test_case)
		if not reason.is_empty():
			skipped[reason] = skipped.get(reason, 0) + test_case.tests.size()
			continue
		for uri: String in test_case.get("externalSchemas", {}):
			TestUtil.check(ForgeJSONGD.register_schema(test_case.externalSchemas[uri], uri), "%s: %s / the other schema %s is registered" % [label, test_case.description, uri])
		for test: Dictionary in test_case.tests:
			var errors: Array[Dictionary] = ForgeJSONGD.validate_json(ForgeJSONGDBase._stringify(test.data, "", false), test_case.schema) # as JSON text: a lone string would be read as a file path
			var ok: bool = errors.is_empty() == test.valid
			var test_name: String = "%s: %s / %s" % [label, test_case.description, test.description]
			if ok:
				passed += 1
			else:
				failed += 1
			if required:
				TestUtil.check(ok, test_name + ("" if ok else " (errors: %s)" % str(errors.map(func(e: Dictionary) -> String: return e.message))))
			elif not ok:
				TestUtil.known_issue(false, "optional " + test_name)
		ForgeJSONGD.clear_registered_schemas() # each test case has its own other schemas
	return [passed, failed]


## True when a test case applies to draft 2020-12: the suite's own rule, where each part of "7", "<=2019", "=2020"...
## is a range of releases and the first range that reaches the release decides.
func _applies(compatibility: String) -> bool:
	var valid: bool = true
	for rule: String in compatibility.split(",", false):
		var version: int = int(rule.trim_prefix("<=").trim_prefix("="))
		if rule.begins_with("<="):
			valid = DIALECT <= version
		elif rule.begins_with("="):
			valid = DIALECT == version
		else:
			valid = DIALECT >= version
		if DIALECT <= version:
			break
	return valid


## Why a test case is skipped, or "" to run it.
func _skip_reason(test_case: Dictionary) -> String:
	if "format-assertion" in test_case.get("tags", []):
		return "checks format as an assertion; in 2020-12 format is an annotation by default"
	var text: String = JSON.stringify([test_case.schema, test_case.get("externalSchemas", {})])
	for keyword: String in SKIP_KEYWORDS:
		if text.contains('"%s"' % keyword):
			return "uses %s, which is reported as unsupported" % keyword
	if text.contains('"$ref":"https://json-schema.org/'):
		return "$ref to a JSON Schema meta-schema, which is not registered"
	return ""
