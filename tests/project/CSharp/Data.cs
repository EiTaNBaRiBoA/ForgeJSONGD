using Godot;

[GlobalClass]
public partial class Data : GodotObject
{
	[Export]
	public string Name { get; set; } = "Default Name";

	[Export]
	public int Age { get; set; } = 15;

	[Export]
	public float Score { get; set; } = 1.5f;

	[Export]
	public bool Active { get; set; } = true;

	[Export]
	public Vector2 Position { get; set; } = Vector2.Zero;

	[Export]
	public Color Tint { get; set; } = Colors.White;

	[Export]
	public Godot.Collections.Array<string> Tags { get; set; } = new();

	[Export]
	public Data Friend { get; set; }
}
