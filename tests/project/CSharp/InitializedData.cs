using Godot;

[GlobalClass]
public partial class InitializedData : GodotObject
{
	// Initialized, like most C# members.
	[Export] public Data Friend { get; set; } = new Data();
}
