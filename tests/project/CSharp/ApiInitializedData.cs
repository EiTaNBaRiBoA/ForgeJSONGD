using Godot;

// The same class as InitializedData, but read and written as standard JSON.
[GlobalClass]
public partial class ApiInitializedData : InitializedData
{
	public bool _forge_plain_json() => true;
}
