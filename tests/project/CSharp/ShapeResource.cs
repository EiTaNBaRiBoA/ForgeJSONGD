using Godot;

[GlobalClass]
public partial class ShapeResource : Resource
{
	[Export]
	public string Label { get; set; } = "";
}
