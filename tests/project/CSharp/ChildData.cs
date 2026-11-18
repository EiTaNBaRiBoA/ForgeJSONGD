using Godot;

[GlobalClass]
public partial class ChildData : Data
{
	[Export]
	public string Nickname { get; set; } = "";
}
