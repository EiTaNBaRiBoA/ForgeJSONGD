using Godot;

[GlobalClass]
public partial class CustomData : GodotObject
{
	public string Code { get; set; } = "";

	// Replaces the automatic serialization.
	public Godot.Collections.Dictionary _forge_serialize() => new() { { "packed", "code:" + Code } };

	// C# classes use an instance method: it receives the JSON and returns the finished object.
	public GodotObject _forge_deserialize(Godot.Collections.Dictionary json)
	{
		Code = ((string)json["packed"]).Substring("code:".Length);
		return this;
	}
}
