using Godot;

// A request body for an HTTP API, with validation rules (by C# member name).
[GlobalClass]
public partial class SignupData : GodotObject
{
	[Export] public string UserName { get; set; } = "";

	[Export] public int Age { get; set; }

	[Export] public Godot.Collections.Array<string> Tags { get; set; } = new();

	[Export] public AddressData Address { get; set; } = new();

	public bool _forge_plain_json() => true;

	public Godot.Collections.Dictionary _forge_json_keys() => new() { { "UserName", "userName" }, { "Age", "age" }, { "Tags", "tags" }, { "Address", "address" } };

	// JSON Schema rules, added to what the member types already say.
	public Godot.Collections.Dictionary _forge_schema() => new()
	{
		{ "required", new Godot.Collections.Array { "UserName" } },
		{ "properties", new Godot.Collections.Dictionary
			{
				{ "UserName", new Godot.Collections.Dictionary { { "minLength", 3 } } },
				{ "Age", new Godot.Collections.Dictionary { { "minimum", 13 } } },
			}
		},
	};
}
