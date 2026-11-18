using Godot;

[GlobalClass]
public partial class Shapes : GodotObject
{
	// Collections of custom classes
	[Export] public Godot.Collections.Array<Data> TypedItems { get; set; } = new();
	[Export] public Godot.Collections.Array UntypedItems { get; set; } = new();
	[Export] public Godot.Collections.Dictionary<string, Data> TypedDict { get; set; } = new();
	[Export] public Godot.Collections.Dictionary UntypedDict { get; set; } = new();
	[Export] public Data[] NativeItems { get; set; } = System.Array.Empty<Data>();

	// Native C# arrays and typed Godot arrays of simple values
	[Export] public int[] Ints { get; set; } = System.Array.Empty<int>();
	[Export] public string[] Strings { get; set; } = System.Array.Empty<string>();
	[Export] public Vector2[] Points { get; set; } = System.Array.Empty<Vector2>();
	[Export] public byte[] Bytes { get; set; } = System.Array.Empty<byte>();
	[Export] public Godot.Collections.Array<int> IntArray { get; set; } = new();
	[Export] public Godot.Collections.Array<Vector2> VectorArray { get; set; } = new();
	[Export] public Godot.Collections.Array<Color> ColorArray { get; set; } = new();
	[Export] public Godot.Collections.Array<string> NestedNames { get; set; } = new();
	[Export] public Godot.Collections.Dictionary<string, int> Scores { get; set; } = new();

	// Numbers and enums
	[Export] public Mood Mood { get; set; } = Mood.Calm;
	[Export] public long Big { get; set; }
	[Export] public double Precise { get; set; }
	[Export] public byte Small { get; set; }

	// Godot structs
	[Export] public Vector3 Position3 { get; set; }
	[Export] public Rect2 Rect { get; set; }
	[Export] public Aabb Box { get; set; }
	[Export] public Transform3D Transform { get; set; } = Transform3D.Identity;
	[Export] public Quaternion Rotation { get; set; } = Quaternion.Identity;
	[Export] public NodePath Path { get; set; } = new NodePath("");
	[Export] public StringName Tag { get; set; } = new StringName("");

	// Objects
	[Export] public ShapeResource Resource { get; set; }
	[Export] public Data Single { get; set; }
	[Export] public Variant Anything { get; set; }
}
