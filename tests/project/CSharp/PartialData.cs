using Godot;

[GlobalClass]
public partial class PartialData : GodotObject
{
	[Export]
	public string Saved { get; set; } = "";

	// Not exported, so Godot does not know about it and it is never saved.
	public string NotSaved { get; set; } = "";

	// Fields are saved only when exported.
	[Export]
	public int SavedField = 0;

	public int NotSavedField = 0;
}
