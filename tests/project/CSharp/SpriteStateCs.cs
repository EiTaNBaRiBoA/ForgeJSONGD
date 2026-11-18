using Godot;

[GlobalClass]
public partial class SpriteStateCs : Node2D
{
	[Export] public int Health { get; set; } = 10;

	// Besides the exported members, save where the node is (Godot property names).
	public Godot.Collections.Array _forge_extra_properties() => new() { "position", "rotation" };
}
