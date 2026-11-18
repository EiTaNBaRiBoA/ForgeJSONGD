using Godot;
using Godot.Collections;

/// <summary>
/// Thin C# wrapper around the ForgeJSONGD GDScript addon. Copy this file into your project.
/// Every method just calls the GDScript method of the same name.
/// </summary>
public static class Forge
{
	/// <summary>Same order as ForgeJSONGD.Operation in GDScript.</summary>
	public enum Operation
	{
		Add,
		AddDiffer,
		Replace,
		Remove,
		RemoveValue,
	}

	private static string _scriptPath = "res://addons/ForgeJSONGD/ForgeJSONGD.gd";
	private static Script _script;

	/// <summary>Where ForgeJSONGD.gd is in your project. Change it if you installed the addon somewhere else.</summary>
	public static string ScriptPath
	{
		get => _scriptPath;
		set
		{
			_scriptPath = value;
			_script = null;
		}
	}

	private static Script Addon => _script ??= ResourceLoader.Load<Script>(_scriptPath);

	// --- Class to JSON ---

	public static Dictionary ClassToJson(GodotObject value, bool specifyClass = false) =>
		Addon.Call("class_to_json", value, specifyClass).As<Dictionary>();

	public static string ClassToJsonString(GodotObject value, bool specifyClass = false) =>
		Addon.Call("class_to_json_string", value, specifyClass).AsString();

	public static bool StoreJsonFile(string path, Dictionary data, string securityKey = "") =>
		Addon.Call("store_json_file", path, data, securityKey).AsBool();

	// --- JSON to class ---

	public static T JsonToClass<[MustBeVariant] T>(Dictionary json) where T : GodotObject, new() =>
		Addon.Call("json_to_class", ScriptOf<T>.Value, json).As<T>();

	public static T JsonStringToClass<[MustBeVariant] T>(string json) where T : GodotObject, new() =>
		Addon.Call("json_string_to_class", ScriptOf<T>.Value, json).As<T>();

	public static T JsonFileToClass<[MustBeVariant] T>(string path, string securityKey = "") where T : GodotObject, new() =>
		Addon.Call("json_file_to_class", ScriptOf<T>.Value, path, securityKey).As<T>();

	public static Dictionary JsonFileToDict(string path, string securityKey = "") =>
		Addon.Call("json_file_to_dict", path, securityKey).As<Dictionary>();

	/// <summary>Loads an object without knowing its class. The JSON must come from ClassToJson(value, true).</summary>
	public static GodotObject JsonToClass(Dictionary json) =>
		Addon.Call("json_to_class", default(Variant), json).As<GodotObject>();

	// --- JSON utilities ---

	/// <summary>Each argument can be a Dictionary, a JSON string, a file path or an object.</summary>
	public static bool CheckEqualJsons(Variant first, Variant second) =>
		Addon.Call("check_equal_jsons", first, second).AsBool();

	public static Dictionary CompareJsonsDiff(Variant first, Variant second) =>
		Addon.Call("compare_jsons_diff", first, second).As<Dictionary>();

	public static Dictionary JsonOperation(Variant baseJson, Variant referenceJson, Operation operation) =>
		Addon.Call("json_operation", baseJson, referenceJson, (int)operation).As<Dictionary>();

	// --- Validation ---

	/// <summary>
	/// Checks JSON data against a JSON Schema and returns the problems found (empty when the data is valid).
	/// The data can be a Dictionary, an Array, JSON text, a file path or an object; the schema a Dictionary, JSON text or a file path.
	/// </summary>
	public static Array<Dictionary> ValidateJson(Variant json, Variant schema) =>
		Addon.Call("validate_json", json, schema).AsGodotArray<Dictionary>();

	/// <summary>Checks JSON data against the schema of a C# class (see ClassToJsonSchema).</summary>
	public static Array<Dictionary> ValidateJson<[MustBeVariant] T>(Variant json) where T : GodotObject, new() =>
		Addon.Call("validate_json", json, ScriptOf<T>.Value).AsGodotArray<Dictionary>();

	/// <summary>The JSON Schema of the JSON that ClassToJson writes for a C# class, with the rules from its _forge_schema.</summary>
	public static Dictionary ClassToJsonSchema<[MustBeVariant] T>() where T : GodotObject, new() =>
		Addon.Call("class_to_json_schema", ScriptOf<T>.Value).As<Dictionary>();

	/// <summary>
	/// Makes a schema (a Dictionary, JSON text or a file path) available to "$ref" in other schemas, under uri,
	/// else its "$id", else (for a file) its file name. A $ref never loads files or URLs by itself.
	/// </summary>
	public static bool RegisterSchema(Variant schema, string uri = "") =>
		Addon.Call("register_schema", schema, uri).AsBool();

	public static void ClearRegisteredSchemas() => Addon.Call("clear_registered_schemas");

	// --- Script registry and aliases ---

	public static void RegisterScript(Script script) => Addon.Call("register_script", script);

	public static void ClearRegisteredScripts() => Addon.Call("clear_registered_scripts");

	public static void RegisterScriptAlias(Script script, string alias, bool saveAs = true) =>
		Addon.Call("register_script_alias", script, alias, saveAs);

	public static void ClearScriptAliases() => Addon.Call("clear_script_aliases");

	// Finds (once per type) the script a C# type is attached to.
	private static class ScriptOf<T> where T : GodotObject, new()
	{
		public static readonly Variant Value = Find();

		private static Variant Find()
		{
			var probe = new T();
			var script = probe.GetScript();
			if (probe is not RefCounted)
				probe.Free();
			return script;
		}
	}
}
