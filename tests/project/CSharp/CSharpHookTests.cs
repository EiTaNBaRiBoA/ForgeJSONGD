using Godot;

// Which C# members are saved, and which _forge_ hooks work from C#.
public partial class CSharpTests
{
	private void TestMembersAndHooks()
	{
		var partial = new PartialData { Saved = "yes", NotSaved = "no", SavedField = 3, NotSavedField = 4 };
		var json = Forge.ClassToJson(partial);
		Check(json.ContainsKey("Saved") && json.ContainsKey("SavedField"), "exported C# properties and fields are saved");
		Check(!json.ContainsKey("NotSaved") && !json.ContainsKey("NotSavedField"), "C# members without [Export] are not saved");
		var loaded = Forge.JsonStringToClass<PartialData>(Forge.ClassToJsonString(partial));
		Check(loaded.Saved == "yes" && loaded.SavedField == 3 && loaded.NotSaved == "" && loaded.NotSavedField == 0, "only the exported C# members are loaded");

		var custom = new CustomData { Code = "abc" };
		var customJson = Forge.ClassToJson(custom);
		Check(customJson.ContainsKey("packed") && (string)customJson["packed"] == "code:abc", "a C# _forge_serialize method is used");
		var customLoaded = Forge.JsonToClass<CustomData>(customJson);
		Check(customLoaded != null && customLoaded.Code == "abc", "a C# _forge_deserialize method is used");

		var args = new ArgsData(7, "seven");
		var argsJson = Forge.ClassToJson(args);
		Check(argsJson.ContainsKey("script_constructor_args"), "a C# _forge_constructor_args method is stored");
		var argsLoaded = Forge.JsonStringToClass<ArgsData>(Forge.ClassToJsonString(args));
		Check(argsLoaded != null && argsLoaded.Count == 7 && argsLoaded.Label == "seven", "the C# object loads after _forge_constructor_args");
	}
}
