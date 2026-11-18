using Godot;

[GlobalClass]
public partial class NullableDto : GodotObject
{
	[Export] public string Name { get; set; } = "";

	// Not initialized: a server cannot say which class to create, so this stays null.
	[Export] public AddressData Address { get; set; }

	// This class talks to a web API: it is written and read as standard JSON.
	public bool _forge_plain_json() => true;
}
