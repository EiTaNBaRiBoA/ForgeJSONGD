using Godot;

[GlobalClass]
public partial class SecretData : GodotObject
{
	[Export]
	public string UserName { get; set; } = "";

	[Export]
	public string Password { get; set; } = "";

	// Godot finds this by its exact name, so it is written in snake_case with the _forge_ prefix.
	public Godot.Collections.Array _forge_excluded_properties() => new() { "Password" };
}
