using Godot;

[GlobalClass]
public partial class ArgsData : GodotObject
{
	[Export]
	public int Count { get; set; }

	[Export]
	public string Label { get; set; } = "";

	// Godot creates C# scripts with the parameterless constructor.
	public ArgsData()
	{
	}

	public ArgsData(int count, string label)
	{
		Count = count;
		Label = label;
	}

	public Godot.Collections.Array _forge_constructor_args() => new() { Count, Label };
}
