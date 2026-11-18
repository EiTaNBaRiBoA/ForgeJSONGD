using Godot;

[GlobalClass]
public partial class ItemHolderCs : GodotObject
{
	[Export] public ItemResourceCs Item { get; set; }

	[Export] public Godot.Collections.Array<ItemResourceCs> Items { get; set; } = new();
}
