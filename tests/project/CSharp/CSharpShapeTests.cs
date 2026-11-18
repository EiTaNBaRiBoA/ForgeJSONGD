using Godot;

// Other C# class shapes: collections of custom classes, native C# arrays, enums, numbers, Godot structs.
public partial class CSharpTests
{
	private void TestShapes()
	{
		var kid = new ChildData { Name = "Kid", Nickname = "K" };
		var shapes = new Shapes
		{
			TypedItems = new Godot.Collections.Array<Data> { new Data { Name = "plain" }, kid },
			UntypedItems = new Godot.Collections.Array { new Data { Name = "u-plain" }, new ChildData { Name = "u-kid", Nickname = "UK" } },
			TypedDict = new Godot.Collections.Dictionary<string, Data> { { "plain", new Data { Name = "d-plain" } }, { "kid", new ChildData { Name = "d-kid", Nickname = "DK" } } },
			UntypedDict = new Godot.Collections.Dictionary { { "kid", new ChildData { Name = "ud-kid", Nickname = "UDK" } } },
			NativeItems = new Data[] { new Data { Name = "n-plain" }, new ChildData { Name = "n-kid", Nickname = "NK" } },
			Ints = new[] { 1, 2, 3 },
			Strings = new[] { "a", "b" },
			Points = new[] { new Vector2(1, 2), new Vector2(3, 4) },
			Bytes = new byte[] { 1, 2, 250 },
			IntArray = new Godot.Collections.Array<int> { 4, 5 },
			VectorArray = new Godot.Collections.Array<Vector2> { new Vector2(5, 6) },
			ColorArray = new Godot.Collections.Array<Color> { Colors.Red, Colors.Blue },
			NestedNames = new Godot.Collections.Array<string> { "x", "y" },
			Scores = new Godot.Collections.Dictionary<string, int> { { "a", 5 }, { "b", 7 } },
			Mood = Mood.Angry,
			Big = 123456789012,
			Precise = 3.141592653589793,
			Small = 200,
			Position3 = new Vector3(1, 2, 3),
			Rect = new Rect2(1, 2, 3, 4),
			Box = new Aabb(new Vector3(1, 2, 3), new Vector3(4, 5, 6)),
			Transform = new Transform3D(Basis.Identity, new Vector3(7, 8, 9)),
			Rotation = new Quaternion(Vector3.Up, 0.5f),
			Path = new NodePath("a/b"),
			Tag = new StringName("tag"),
			Resource = new ShapeResource { Label = "res" },
			Single = kid,
			Anything = new Rect2(1, 2, 3, 4),
		};

		var text = Forge.ClassToJsonString(shapes);
		Forge.StoreJsonFile("user://shapes.json", Forge.ClassToJson(shapes));
		var loaded = Forge.JsonStringToClass<Shapes>(text);
		Check(loaded != null, "Shapes: loads from a JSON string");
		if (loaded == null)
			return;

		Check(loaded.TypedItems.Count == 2 && loaded.TypedItems[0].Name == "plain", "Array<Data>: elements round-trip");
		Check(loaded.TypedItems[0] is not ChildData && loaded.TypedItems[1] is ChildData { Nickname: "K" }, "Array<Data>: a child instance keeps its class");
		Check(loaded.UntypedItems.Count == 2 && loaded.UntypedItems[1].As<GodotObject>() is ChildData { Nickname: "UK" }, "untyped Array: a child instance keeps its class");
		Check(loaded.UntypedItems[0].As<GodotObject>() is Data { Name: "u-plain" } and not ChildData, "untyped Array: a parent instance stays a parent");
		Check(loaded.TypedDict["kid"] is ChildData { Nickname: "DK" } && loaded.TypedDict["plain"] is not ChildData, "Dictionary<string, Data>: child classes are kept");
		Check(loaded.UntypedDict["kid"].As<GodotObject>() is ChildData { Nickname: "UDK" }, "untyped Dictionary: a child instance keeps its class");
		Check(loaded.NativeItems.Length == 2 && loaded.NativeItems[1] is ChildData { Nickname: "NK" }, "Data[]: elements and child classes are kept");

		Check(loaded.Ints.Length == 3 && loaded.Ints[2] == 3, "int[] round-trips");
		Check(loaded.Strings.Length == 2 && loaded.Strings[1] == "b", "string[] round-trips");
		Check(loaded.Points.Length == 2 && loaded.Points[1] == new Vector2(3, 4), "Vector2[] round-trips");
		Check(loaded.Bytes.Length == 3 && loaded.Bytes[2] == 250, "byte[] round-trips");
		Check(loaded.IntArray.Count == 2 && loaded.IntArray[1] == 5, "Array<int> round-trips");
		Check(loaded.VectorArray.Count == 1 && loaded.VectorArray[0] == new Vector2(5, 6), "Array<Vector2> round-trips");
		Check(loaded.ColorArray.Count == 2 && loaded.ColorArray[1] == Colors.Blue, "Array<Color> round-trips");
		Check(loaded.NestedNames.Count == 2 && loaded.NestedNames[0] == "x", "Array<string> round-trips");
		Check(loaded.Scores.Count == 2 && loaded.Scores["b"] == 7, "Dictionary<string, int> round-trips");

		Check(loaded.Mood == Mood.Angry, "C# enum round-trips");
		Check(loaded.Big == 123456789012, "long round-trips");
		Check(loaded.Precise == 3.141592653589793, "double round-trips exactly");
		Check(loaded.Small == 200, "byte round-trips");

		Check(loaded.Position3 == new Vector3(1, 2, 3), "Vector3 round-trips");
		Check(loaded.Rect == new Rect2(1, 2, 3, 4), "Rect2 round-trips");
		Check(loaded.Box == shapes.Box, "Aabb round-trips");
		Check(loaded.Transform == shapes.Transform, "Transform3D round-trips");
		Check(loaded.Rotation.IsEqualApprox(shapes.Rotation), "Quaternion round-trips");
		Check(loaded.Path == shapes.Path, "NodePath round-trips");
		Check(loaded.Tag == shapes.Tag, "StringName round-trips");

		Check(loaded.Resource != null && loaded.Resource.Label == "res", "a Resource-derived C# class round-trips");
		Check(loaded.Single is ChildData { Nickname: "K" }, "a child instance in a parent-typed property keeps its class");
		Check(loaded.Anything.VariantType == Variant.Type.Rect2 && loaded.Anything.AsRect2() == new Rect2(1, 2, 3, 4), "a Variant property keeps a Rect2");
		Check(Forge.CheckEqualJsons(shapes, loaded), "the loaded Shapes object equals the original");

		var empty = Forge.JsonStringToClass<Shapes>(Forge.ClassToJsonString(new Shapes()));
		Check(empty != null && empty.TypedItems.Count == 0 && empty.Ints.Length == 0 && empty.Single == null, "an empty Shapes object round-trips");
	}
}
