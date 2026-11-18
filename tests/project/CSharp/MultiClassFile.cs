using Godot;

// Two classes in one file: only the one named like the file can be found by name (a Godot rule).
[GlobalClass]
public partial class MultiClassFile : GodotObject
{
	[Export] public string First { get; set; } = "first";
}

[GlobalClass]
public partial class SecondInFile : GodotObject
{
	[Export] public string Second { get; set; } = "second";
}
