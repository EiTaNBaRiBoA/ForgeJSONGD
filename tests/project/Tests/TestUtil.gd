## Minimal assertion helper shared by the test scenes. Failures are counted and printed to stderr.
class_name TestUtil

static var failures: int = 0


static func check(condition: bool, test_name: String) -> void:
	if condition:
		print("PASS: ", test_name)
	else:
		failures += 1
		printerr("FAIL: ", test_name)


## Documents a behavior that is known to be broken in the addon. It never counts as a failure,
## and prints a notice once it starts passing so it can be promoted to a normal check().
static func known_issue(condition: bool, test_name: String) -> void:
	if condition:
		print("FIXED (promote to check): ", test_name)
	else:
		print("KNOWN ISSUE: ", test_name)


## Prints a summary. Pass the scene tree to quit with a non-zero exit code on failure (useful for --headless runs).
static func finish(suite: String, tree: SceneTree = null) -> void:
	print("== %s: %s ==" % [suite, "OK" if failures == 0 else "%d FAILED" % failures])
	free_orphan_nodes()
	if tree:
		tree.quit(1 if failures > 0 else 0)


## Several test models extend Node, and a Node is not freed by itself. Frees the ones the tests created and left
## outside the scene tree, so Godot does not report them as leaked when the scene quits.
static func free_orphan_nodes() -> void:
	for id: int in Node.get_orphan_node_ids():
		var node: Object = instance_from_id(id)
		if is_instance_valid(node):
			node.free()


## True for a plain Object: what loading returns when the JSON names no usable class. A plain Object is not freed
## by itself, so it is freed here.
static func is_plain_object(object: Object) -> bool:
	var plain: bool = object != null and object.get_class() == "Object" and object.get_script() == null
	if plain:
		object.free()
	return plain


## Frees an object that is not reference counted (a class that extends Object, or GodotObject in C#), with the
## objects of that kind its variables hold.
static func free_object(object: Object) -> void:
	if object == null or object is RefCounted or not is_instance_valid(object):
		return
	for property: Dictionary in object.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.type == TYPE_OBJECT:
			var member: Variant = object.get(property.name)
			if member is Object and is_instance_valid(member):
				free_object(member)
	object.free()
