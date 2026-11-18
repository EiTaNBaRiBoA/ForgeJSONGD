using Godot;

[GlobalClass]
public partial class PartialKeysData : GodotObject
{
	[Export] public string Mapped { get; set; } = "";

	[Export] public string Unmapped { get; set; } = "";

	public Godot.Collections.Dictionary _forge_json_keys() => new() { { "Mapped", "mapped" } };
}
