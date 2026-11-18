using Godot;

// JSON for HTTP APIs from C#: standard JSON out, whatever the server sends in.
public partial class CSharpTests
{
	private void TestDto()
	{
		var request = new DtoData
		{
			Id = 7, UserName = "ann", IsAdmin = true, Score = 2.0, Position = new Vector2(1, 2), Secret = "never sent",
			Tags = new Godot.Collections.Array<string> { "a", "b" },
			Address = new AddressData { City = "Tokyo", Zip = "100" },
		};
		request.Meta["count"] = 5;
		request.Meta["ratio"] = 2.0;
		request.Meta["1"] = "one";
		request.Meta["text"] = "Vector2(1, 2)";

		var text = Forge.ClassToJsonString(request);
		const string expected = "{\"address\":{\"city\":\"Tokyo\",\"zip\":\"100\"},\"id\":7,\"isAdmin\":true,\"meta\":{\"1\":\"one\",\"count\":5,\"ratio\":2.0,\"text\":\"Vector2(1, 2)\"},\"position\":{\"x\":1.0,\"y\":2.0},\"score\":2.0,\"tags\":[\"a\",\"b\"],\"userName\":\"ann\"}";
		Check(text == expected, "a C# request body is exactly the expected JSON text");
		Check(!text.Contains("script_") && !text.Contains("forge_") && !text.Contains("Secret"), "no class name, marker or excluded member is written");

		var response = "{\"id\":9,\"userName\":\"bob\",\"isAdmin\":null,\"score\":3,\"tags\":[\"x\"],\"unknown\":1,"
			+ "\"address\":{\"city\":\"Osaka\",\"zip\":54321,\"script_inheritance\":\"AddressData\"},"
			+ "\"script_inheritance\":\"res://CSharp/Data.cs\",\"position\":{\"x\":3,\"y\":4},"
			+ "\"meta\":{\"forge_float\":3,\"n\":null,\"k\":[1,2.5]}}";
		var loaded = Forge.JsonStringToClass<DtoData>(response);
		Check(loaded != null && loaded.Id == 9 && loaded.UserName == "bob", "a C# response is read, also under the API key names");
		Check(!loaded.IsAdmin && loaded.Score == 3.0, "a null keeps the default and an int fills a double");
		Check(loaded.Tags.Count == 1 && loaded.Tags[0] == "x" && loaded.Position == new Vector2(3, 4), "arrays and vectors are read");
		Check(loaded.Address.City == "Osaka" && loaded.Address.Zip == "54321", "a nested C# object that was initialized is filled, and a number fills a string");
		Check(loaded.Meta["forge_float"].VariantType == Variant.Type.Int && (int)loaded.Meta["forge_float"] == 3, "a free-form dictionary is read exactly as sent");
		Check(Forge.JsonStringToClass<DtoData>("{ broken") == null, "invalid text gives null");

		var again = Forge.JsonStringToClass<DtoData>(Forge.ClassToJsonString(request));
		Check(again.UserName == "ann" && again.IsAdmin && again.Address.City == "Tokyo" && again.Position == new Vector2(1, 2), "a C# DTO round-trips");

		// Members without an entry in _forge_json_keys keep their C# name; a null member stays null; the dictionary overloads work.
		var keys = Forge.ClassToJson(new PartialKeysData { Mapped = "m", Unmapped = "u" });
		Check(keys.ContainsKey("mapped") && keys.ContainsKey("Unmapped") && !keys.ContainsKey("Mapped"), "members without a key mapping keep their C# name");
		var nullable = Forge.JsonToClass<NullableDto>(new Godot.Collections.Dictionary
		{
			{ "Name", "x" },
			{ "Address", new Godot.Collections.Dictionary { { "City", "Z" } } },
		});
		Check(nullable.Name == "x" && nullable.Address == null, "a C# member that is null stays null (it cannot be created from data)");

		Run(TestOptionsFromCSharp);

		// Aliases from C#: a stable name for a class, the old name still loads.
		Forge.RegisterScriptAlias(GD.Load<Script>("res://CSharp/ChildData.cs"), "child_v1");
		var holder = new Data { Friend = new ChildData { Name = "Kid", Nickname = "K" } };
		var holderText = Forge.ClassToJsonString(holder);
		Check(holderText.Contains("\"script_inheritance\":\"child_v1\""), "a C# class is saved under its alias");
		Check(Forge.JsonStringToClass<Data>(holderText).Friend is ChildData, "and loaded through it");
		Forge.ClearScriptAliases();
	}
}
