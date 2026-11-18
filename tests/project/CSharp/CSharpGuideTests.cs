using Godot;

// Statements of the C# guide that need their own check.
public partial class CSharpTests
{
	private void TestGuideStatements()
	{
		// Wrapper results for missing or invalid input.
		Check(Forge.JsonStringToClass<Data>("{ broken") == null, "Forge.JsonStringToClass returns null for invalid JSON");
		var fresh = Forge.JsonFileToClass<Data>("user://does_not_exist.json");
		Check(fresh != null && fresh.Name == "Default Name", "Forge.JsonFileToClass returns a new object when the file is missing");
		Check(Forge.JsonFileToDict("user://does_not_exist.json").Count == 0, "Forge.JsonFileToDict returns an empty dictionary when the file is missing");

		// Encryption from C#.
		var secret = new Data { Name = "Secret", Age = 42 };
		Check(Forge.StoreJsonFile("user://encrypted_csharp.json", Forge.ClassToJson(secret), "my_key"), "Forge.StoreJsonFile with a key");
		var decrypted = Forge.JsonFileToClass<Data>("user://encrypted_csharp.json", "my_key");
		Check(decrypted.Name == "Secret" && decrypted.Age == 42, "Forge.JsonFileToClass with the same key");
		Check(Forge.JsonFileToDict("user://encrypted_csharp.json").Count == 0, "an encrypted file cannot be read without the key");

		// float and double keep every digit.
		var floats = new Data { Score = 0.1f };
		var floatsLoaded = Forge.JsonStringToClass<Data>(Forge.ClassToJsonString(floats));
		Check(floatsLoaded.Score == 0.1f, "a C# float round-trips exactly");

		// Large numbers and text that looks like a Godot value stay exact.
		var exact = new Shapes { Big = 9007199254740993, Anything = 9007199254740993 };
		exact.UntypedItems.Add("Vector2(1, 2)");
		exact.UntypedItems.Add(9007199254740993);
		exact.UntypedItems.Add(5.0);
		var exactLoaded = Forge.JsonStringToClass<Shapes>(Forge.ClassToJsonString(exact));
		Check(exactLoaded.Big == 9007199254740993, "a C# long above 2^53 is exact");
		Check(exactLoaded.UntypedItems[0].VariantType == Variant.Type.String && (string)exactLoaded.UntypedItems[0] == "Vector2(1, 2)", "text that looks like a Godot value stays text in an untyped Array");
		Check(exactLoaded.UntypedItems[1].VariantType == Variant.Type.Int && (long)exactLoaded.UntypedItems[1] == 9007199254740993, "a large int in an untyped Array is exact");
		Check(exactLoaded.UntypedItems[2].VariantType == Variant.Type.Float, "a whole-number double in an untyped Array stays a double");
		Check(exactLoaded.Anything.VariantType == Variant.Type.Int && (long)exactLoaded.Anything == 9007199254740993, "a large int in a Variant member is exact");

		// Untyped collections give numbers back as doubles, typed ones keep int.
		var shapes = new Shapes();
		shapes.UntypedItems.Add(5);
		shapes.IntArray.Add(5);
		var loaded = Forge.JsonStringToClass<Shapes>(Forge.ClassToJsonString(shapes));
		Check(loaded.UntypedItems[0].VariantType == Variant.Type.Int, "a number in an untyped Array stays an int");
		Check(loaded.IntArray[0] == 5, "a number in an Array<int> is an int");

		// A resource from a file inside an untyped collection comes back as the resource.
		var texture = GD.Load<Texture2D>("res://icon.svg");
		var withTexture = new Shapes();
		withTexture.UntypedItems.Add(texture);
		withTexture.Anything = texture;
		var textureLoaded = Forge.JsonStringToClass<Shapes>(Forge.ClassToJsonString(withTexture));
		Check(textureLoaded.UntypedItems[0].As<GodotObject>() == texture, "a Texture2D in an untyped Godot Array loads as the texture");
		Check(textureLoaded.Anything.As<GodotObject>() == texture, "a Texture2D in a Variant member loads as the texture");

		// Declared types: C# reports none for a single object member, but typed collections have one.
		var json2 = Forge.ClassToJson(new Data { Friend = new Data { Name = "plain friend" } });
		Check(((Godot.Collections.Dictionary)json2["Friend"]).ContainsKey("script_inheritance"), "a single C# object member always stores its script name (Godot reports no declared type)");
		var mixed = new Shapes { TypedItems = new Godot.Collections.Array<Data> { new ChildData { Name = "kid", Nickname = "K" } }, Single = new ChildData { Name = "single", Nickname = "S" } };
		var mixedText = Forge.ClassToJsonString(mixed);
		Forge.RegisterScript(GD.Load<Script>("res://CSharp/Shapes.cs"));
		var restricted = Forge.JsonStringToClass<Shapes>(mixedText);
		Forge.ClearRegisteredScripts();
		Check(restricted.Single == null, "with a registry, an unregistered class in a single C# member leaves it null");
		Check(restricted.TypedItems.Count == 1 && restricted.TypedItems[0] is not ChildData && restricted.TypedItems[0].Name == "kid", "with a registry, an unregistered class in a typed C# collection loads as the declared type");

		// Two classes in one file: the one named like the file works, the second is not found by name.
		var second = new SecondInFile { Second = "changed" };
		var json = Forge.ClassToJson(second, true);
		Check(!(Forge.JsonToClass(json) is SecondInFile), "a second class in a file is not found by name");
		var first = Forge.JsonToClass(Forge.ClassToJson(new MultiClassFile { First = "changed" }, true));
		Check(first is MultiClassFile { First: "changed" }, "the class named like its file is found by name");
	}
}
