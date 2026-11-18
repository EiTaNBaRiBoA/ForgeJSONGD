using Godot;
using Godot.Collections;

// validate_json and class_to_json_schema from C#: the class is the schema, rules come from _forge_schema.
public partial class CSharpTests
{
	private void TestValidation()
	{
		var schema = Forge.ClassToJsonSchema<SignupData>();
		var definition = schema["$defs"].AsGodotDictionary()["SignupData"].AsGodotDictionary();
		var properties = definition["properties"].AsGodotDictionary();
		Check(properties.ContainsKey("userName") && properties.ContainsKey("age") && !properties.ContainsKey("UserName"), "a C# class schema uses the JSON keys");
		Check(properties["age"].AsGodotDictionary()["type"].AsString() == "integer" && properties["age"].AsGodotDictionary()["minimum"].AsInt32() == 13, "the C# member type and the _forge_schema rule are both there");
		Check(definition["required"].AsGodotArray()[0].AsString() == "userName", "required C# member names become JSON keys");

		var good = new SignupData { UserName = "ann", Age = 20, Address = new AddressData { City = "Rome" } };
		Check(Forge.ValidateJson<SignupData>(good).Count == 0, "a C# object passes its own class schema");
		Check(Forge.ValidateJson<SignupData>(Forge.ClassToJsonString(good)).Count == 0, "and so does its JSON text");

		var errors = Forge.ValidateJson<SignupData>("{\"userName\":\"an\",\"age\":5,\"tags\":[1],\"address\":{\"city\":2}}");
		var printed = new Array<string>();
		foreach (var error in errors)
			printed.Add(error["path"].AsString() + ": " + error["message"].AsString());
		var expected = new Array<string>
		{
			"/userName: must be at least 3 characters long, got 2",
			"/age: must be at least 13, got 5",
			"/tags/0: expected string, got integer",
			"/address/city: expected string, got integer",
		};
		Check(printed == expected || string.Join("|", printed) == string.Join("|", expected), "wrong data from a server is reported where it is, as the C# guide prints it (" + string.Join(" | ", printed) + ")");
		Check(Forge.ValidateJson<SignupData>("{\"age\":20}")[0]["keyword"].AsString() == "required", "a missing required field is reported");

		var plain = new Dictionary { { "type", "object" }, { "properties", new Dictionary { { "n", new Dictionary { { "type", "integer" } } } } } };
		Check(Forge.ValidateJson(new Dictionary { { "n", 1 } }, plain).Count == 0 && Forge.ValidateJson("{\"n\":\"x\"}", plain).Count == 1, "a JSON Schema dictionary from C#");

		// A schema that refers to another one: register the other one first.
		var userSchema = "{\"properties\":{\"id\":{\"$ref\":\"common.schema.json#/$defs/id\"}}}";
		Check(Forge.ValidateJson("{\"id\":0}", userSchema)[0]["keyword"].AsString() == "$ref", "from C#, an unregistered $ref is reported");
		Check(Forge.RegisterSchema("{\"$defs\":{\"id\":{\"type\":\"integer\",\"minimum\":1}}}", "common.schema.json"), "from C#, a schema is registered");
		Check(Forge.ValidateJson("{\"id\":0}", userSchema)[0]["path"].AsString() == "/id" && Forge.ValidateJson("{\"id\":3}", userSchema).Count == 0, "and the $ref finds it");
		Forge.ClearRegisteredSchemas();
		Check(Forge.ValidateJson("{\"id\":3}", userSchema).Count == 1, "ClearRegisteredSchemas forgets it");

		// A C# class that extends GodotObject and creates its member objects ("= new()"): loading fills those objects,
		// it does not replace them, so nothing is left unfreed.
		var objectsBefore = Performance.GetMonitor(Performance.Monitor.ObjectCount);
		var dto = Forge.JsonStringToClass<DtoData>("{\"id\":1,\"address\":{\"city\":\"Rome\"}}");
		Check(Performance.GetMonitor(Performance.Monitor.ObjectCount) - objectsBefore == 2, "loading a C# class with a member object creates the two objects, nothing more");
		Check(dto.Id == 1 && dto.Address.City == "Rome", "and the member object holds the data");
		var sameAddress = dto.Address;
		Addon_FillExisting(dto, "{\"address\":{\"zip\":\"00100\"}}");
		Check(ReferenceEquals(dto.Address, sameAddress) && dto.Address.City == "Rome" && dto.Address.Zip == "00100", "loading into an existing C# object fills its member where it is");
		dto.Address.Free();
		dto.Free();

		// Every C# data class accepts what ClassToJson writes for it.
		Check(Forge.ValidateJson<Shapes>(new Shapes()).Count == 0 && Forge.ValidateJson<Data>(new Data { Friend = new ChildData() }).Count == 0, "C# shapes and C# inheritance pass their schemas");
	}

	// Fills an existing object from JSON text (the wrapper's JsonStringToClass<T> always creates a new object).
	private void Addon_FillExisting(GodotObject target, string json) => _forge.Call("json_string_to_class", target, json);
}
