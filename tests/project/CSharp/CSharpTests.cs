using Godot;

// Calls ForgeJSONGD from C# the way the addon README describes (Script.Call), and checks the results.
public partial class CSharpTests : Node
{
	private const string SavePath = "user://csharp.json";
	private const string ForgeJSONGDPath = "res://addons/ForgeJSONGD/addons/ForgeJSONGD/ForgeJSONGD.gd";

	private int _failures;
	private Script _forge;

	public override void _Ready()
	{
		_forge = ResourceLoader.Load<Script>(ForgeJSONGDPath);
		Check(_forge != null, "ForgeJSONGD script loads from C#");
		if (_forge == null)
		{
			Finish();
			return;
		}

		Forge.ScriptPath = ForgeJSONGDPath;
		Run(TestRoundTrip);
		Run(TestInheritance);
		Run(TestJsonUtilities);
		Run(TestRegistry);
		Run(TestHooks);
		Run(TestWrapper);
		Run(TestShapes);
		Run(TestMembersAndHooks);
		Run(TestGuideStatements);
		Run(TestDto);
		Run(TestValidation);
		Finish();
	}

	private void TestRoundTrip()
	{
		var original = new Data
		{
			Name = "C-Sharp Player",
			Age = 25,
			Score = 2.5f,
			Active = false,
			Position = new Vector2(3, 4),
			Tint = Colors.Red,
			Tags = new Godot.Collections.Array<string> { "a", "b" },
			Friend = new Data { Name = "Friend", Age = 30 },
		};

		var json = _forge.Call("class_to_json", original).As<Godot.Collections.Dictionary>();
		Check(json.ContainsKey("Name") && (string)json["Name"] == "C-Sharp Player", "class_to_json stores a C# string property");
		Check(json.ContainsKey("Friend"), "class_to_json stores a nested C# object");

		var stored = _forge.Call("store_json_file", SavePath, json).AsBool();
		Check(stored, "store_json_file stores the C# data");

		var loaded = _forge.Call("json_file_to_class", original.GetScript(), SavePath).As<Data>();
		Check(loaded != null, "json_file_to_class returns a Data object");
		if (loaded == null)
			return;
		Check(loaded.Name == original.Name && loaded.Age == original.Age, "string and int properties round-trip");
		Check(Mathf.IsEqualApprox(loaded.Score, original.Score) && loaded.Active == original.Active, "float and bool properties round-trip");
		Check(loaded.Position == original.Position, "Vector2 property round-trips");
		Check(loaded.Tint == original.Tint, "Color property round-trips");
		Check(loaded.Tags.Count == 2 && loaded.Tags[0] == "a" && loaded.Tags[1] == "b", "typed string array round-trips");
		Check(loaded.Friend != null && loaded.Friend.Name == "Friend" && loaded.Friend.Age == 30, "nested C# object round-trips");

		var text = _forge.Call("class_to_json_string", original).AsString();
		var fromString = _forge.Call("json_string_to_class", original.GetScript(), text).As<Data>();
		Check(fromString != null && fromString.Name == original.Name, "JSON string round-trips");

		Check(_forge.Call("check_equal_jsons", original, loaded).AsBool(), "the loaded C# object equals the original");
		loaded.Age = 99;
		var diff = _forge.Call("compare_jsons_diff", original, loaded).As<Godot.Collections.Dictionary>();
		Check(diff.ContainsKey("Age") && !diff.ContainsKey("Name"), "compare_jsons_diff reports only the changed property");
	}

	private void TestInheritance()
	{
		var holder = new Data { Name = "Holder", Friend = new ChildData { Name = "Kid", Nickname = "K" } };
		var text = _forge.Call("class_to_json_string", holder).AsString();
		var loaded = _forge.Call("json_string_to_class", holder.GetScript(), text).As<Data>();
		Check(loaded?.Friend is ChildData, "a C# child stored in a parent-typed property comes back as the child");
		Check(loaded?.Friend is ChildData kid && kid.Nickname == "K", "the C# child keeps its own property");

		var child = new ChildData { Name = "Direct", Nickname = "D" };
		var json = _forge.Call("class_to_json", child, true).As<Godot.Collections.Dictionary>();
		var viaHint = _forge.Call("json_to_class", Variant.From<GodotObject>(null), json).As<GodotObject>();
		Check(viaHint is ChildData direct && direct.Nickname == "D", "loading with a null script restores the C# class from JSON");
	}

	private void TestJsonUtilities()
	{
		var first = new Godot.Collections.Dictionary { { "a", 1 }, { "b", 2 } };
		var second = new Godot.Collections.Dictionary { { "b", 2 }, { "a", 1 } };
		Check(_forge.Call("check_equal_jsons", first, second).AsBool(), "check_equal_jsons ignores key order");

		var reference = new Godot.Collections.Dictionary { { "a", 1 } };
		// Enum value 4 is Operation.RemoveValue.
		var result = _forge.Call("json_operation", first, reference, 4).As<Godot.Collections.Dictionary>();
		Check(!result.ContainsKey("a") && result.ContainsKey("b"), "json_operation works from C#");
	}

	private void TestRegistry()
	{
		var holder = new Data { Name = "Holder", Friend = new ChildData { Name = "Kid", Nickname = "K" } };
		var text = _forge.Call("class_to_json_string", holder).AsString();
		var dataScript = GD.Load<Script>("res://CSharp/Data.cs");

		_forge.Call("register_script", dataScript);
		var blocked = _forge.Call("json_string_to_class", dataScript, text).As<Data>();
		Check(blocked != null && blocked.Friend is not ChildData, "an unregistered C# child script is not created");
		_forge.Call("clear_registered_scripts");
		var allowed = _forge.Call("json_string_to_class", dataScript, text).As<Data>();
		Check(allowed?.Friend is ChildData, "after clearing the registry the C# child loads again");
	}

	private void TestHooks()
	{
		var secret = new SecretData { UserName = "player", Password = "hunter2" };
		var json = _forge.Call("class_to_json", secret).As<Godot.Collections.Dictionary>();
		Check(json.ContainsKey("UserName") && !json.ContainsKey("Password"), "a C# _forge_excluded_properties method is used when saving");

		var fromFile = new Godot.Collections.Dictionary { { "UserName", "a" }, { "Password", "from_file" } };
		var loaded = _forge.Call("json_to_class", secret.GetScript(), fromFile).As<SecretData>();
		Check(loaded != null && loaded.UserName == "a" && loaded.Password == "", "a C# _forge_excluded_properties method is used when loading");
	}

	// The Forge.cs wrapper from the C# tutorial.
	private void TestWrapper()
	{
		var player = new Data { Name = "Wrapped", Age = 7, Friend = new ChildData { Name = "Kid", Nickname = "K" } };

		var json = Forge.ClassToJson(player);
		Check((string)json["Name"] == "Wrapped", "Forge.ClassToJson");
		Check(Forge.StoreJsonFile("user://forge_wrapper.json", json), "Forge.StoreJsonFile");
		var loaded = Forge.JsonFileToClass<Data>("user://forge_wrapper.json");
		Check(loaded != null && loaded.Name == "Wrapped" && loaded.Age == 7, "Forge.JsonFileToClass<T>");
		Check(loaded?.Friend is ChildData kid && kid.Nickname == "K", "Forge keeps the child class");
		Check(Forge.JsonFileToDict("user://forge_wrapper.json").ContainsKey("Name"), "Forge.JsonFileToDict");
		Check(Forge.JsonStringToClass<Data>(Forge.ClassToJsonString(player))?.Age == 7, "Forge.JsonStringToClass<T>");
		Check(Forge.JsonToClass<Data>(json)?.Name == "Wrapped", "Forge.JsonToClass<T>");
		Check(Forge.JsonToClass(Forge.ClassToJson(new ChildData { Nickname = "N" }, true)) is ChildData { Nickname: "N" }, "Forge.JsonToClass without a type");
		Check(Forge.CheckEqualJsons(player, loaded), "Forge.CheckEqualJsons");
		loaded.Age = 8;
		Check(Forge.CompareJsonsDiff(player, loaded).ContainsKey("Age"), "Forge.CompareJsonsDiff");

		var source = new Godot.Collections.Dictionary { { "a", 1 }, { "b", 2 } };
		var reference = new Godot.Collections.Dictionary { { "b", 2 } };
		Check(Forge.JsonOperation(source, reference, Forge.Operation.RemoveValue).ContainsKey("a"), "Forge.JsonOperation");

		Forge.RegisterScript(GD.Load<Script>("res://CSharp/Data.cs"));
		var blocked = Forge.JsonStringToClass<Data>(Forge.ClassToJsonString(player));
		Check(blocked != null && blocked.Friend is not ChildData, "Forge.RegisterScript blocks unregistered scripts");
		Forge.ClearRegisteredScripts();
		Check(Forge.JsonStringToClass<Data>(Forge.ClassToJsonString(player))?.Friend is ChildData, "Forge.ClearRegisteredScripts");
	}

	// An exception in one group is reported as a failure, and the other groups still run.
	private void Run(System.Action test)
	{
		try
		{
			test();
		}
		catch (System.Exception exception)
		{
			_failures++;
			GD.PrintErr($"FAIL: {test.Method.Name} threw {exception.GetType().Name}: {exception.Message}");
		}
	}

	private void Check(bool condition, string name)
	{
		if (condition)
		{
			GD.Print("PASS: ", name);
			return;
		}
		_failures++;
		GD.PrintErr("FAIL: ", name);
	}

	private void Finish()
	{
		GD.Print($"== CSharp: {(_failures == 0 ? "OK" : _failures + " FAILED")} ==");
		GetTree().Quit(_failures > 0 ? 1 : 0);
	}
}
