using Godot;

// A data class for an HTTP API whose fields are written in camelCase.
[GlobalClass]
public partial class DtoData : GodotObject
{
	[Export] public int Id { get; set; }

	[Export] public string UserName { get; set; } = "";

	[Export] public bool IsAdmin { get; set; }

	[Export] public double Score { get; set; } = 1.5;

	[Export] public Vector2 Position { get; set; } = Vector2.Zero;

	[Export] public Godot.Collections.Array<string> Tags { get; set; } = new();

	// Members that hold a class are initialized, so loading has an object to fill.
	[Export] public AddressData Address { get; set; } = new();

	[Export] public Godot.Collections.Dictionary Meta { get; set; } = new();

	[Export] public string Secret { get; set; } = "";

	// C# member name -> the key the API uses.
	public Godot.Collections.Dictionary _forge_json_keys() => new()
	{
		{ "Id", "id" }, { "UserName", "userName" }, { "IsAdmin", "isAdmin" }, { "Score", "score" },
		{ "Position", "position" }, { "Tags", "tags" }, { "Address", "address" }, { "Meta", "meta" },
	};

	public Godot.Collections.Array _forge_excluded_properties() => new() { "Secret" };

	// This class talks to a web API: it is written and read as standard JSON.
	public bool _forge_plain_json() => true;
}
