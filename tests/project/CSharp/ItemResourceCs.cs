using Godot;

[GlobalClass]
public partial class ItemResourceCs : Resource
{
	[Export] public string ItemName { get; set; } = "";

	// A save should point at the item file, not hold a copy of it.
	public bool _forge_save_by_path() => true;
}
