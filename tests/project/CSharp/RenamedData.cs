using Godot;

[GlobalClass]
public partial class RenamedData : GodotObject
{
	// Was called "Name" in older versions.
	[Export] public string DisplayName { get; set; } = "default";

	public Godot.Collections.Dictionary _forge_renamed_properties() => new() { { "Name", "DisplayName" } };
}
