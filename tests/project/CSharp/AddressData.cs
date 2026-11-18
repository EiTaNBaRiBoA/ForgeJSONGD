using Godot;

[GlobalClass]
public partial class AddressData : GodotObject
{
	[Export] public string City { get; set; } = "";

	[Export] public string Zip { get; set; } = "";

	public Godot.Collections.Dictionary _forge_json_keys() => new() { { "City", "city" }, { "Zip", "zip" } };
}
