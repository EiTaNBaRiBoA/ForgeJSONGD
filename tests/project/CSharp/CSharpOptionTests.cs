using Godot;

// The _forge_ options from C#: extra built-in properties, renamed members, resources saved by path.
public partial class CSharpTests
{
	private void TestOptionsFromCSharp()
	{
		var sprite = new SpriteStateCs { Health = 3, Position = new Vector2(10, 20), Rotation = 1.5f };
		var json = Forge.ClassToJson(sprite);
		Check(json.ContainsKey("Health") && json.ContainsKey("position") && json.ContainsKey("rotation") && !json.ContainsKey("scale"), "a C# Node2D saves the listed built-in properties");
		var restored = Forge.JsonStringToClass<SpriteStateCs>(Forge.ClassToJsonString(sprite));
		Check(restored.Health == 3 && restored.Position == new Vector2(10, 20) && Mathf.IsEqualApprox(restored.Rotation, 1.5f), "and loads them");
		sprite.Free();
		restored.Free();

		var old = Forge.JsonToClass<RenamedData>(new Godot.Collections.Dictionary { { "Name", "from an old file" } });
		Check(old.DisplayName == "from an old file", "an old member name loads into the renamed C# member");
		var both = Forge.JsonToClass<RenamedData>(new Godot.Collections.Dictionary { { "Name", "old" }, { "DisplayName", "new" } });
		Check(both.DisplayName == "new", "the current name wins when both are present");

		// A member that is already initialized still loads as the child class named in the file.
		var initialized = new InitializedData { Friend = new ChildData { Name = "Kid", Nickname = "K" } };
		var initializedLoaded = Forge.JsonStringToClass<InitializedData>(Forge.ClassToJsonString(initialized));
		Check(initializedLoaded.Friend is ChildData { Nickname: "K" }, "an initialized C# member loads as the child class named in the JSON");
		var hostile = Forge.JsonToClass<ApiInitializedData>(new Godot.Collections.Dictionary { { "Friend", new Godot.Collections.Dictionary { { "Name", "x" }, { "script_inheritance", "ChildData" } } } });
		Check(hostile.Friend is not ChildData && hostile.Friend.Name == "x", "plain JSON keeps the class of an initialized member and ignores the class name");

		var item = new ItemResourceCs { ItemName = "Sword" };
		const string path = "user://csharp_item.tres";
		ResourceSaver.Save(item, path);
		var fromFile = ResourceLoader.Load<ItemResourceCs>(path);
		var holder = new ItemHolderCs { Item = fromFile, Items = new Godot.Collections.Array<ItemResourceCs> { fromFile, fromFile } };
		var holderJson = Forge.ClassToJson(holder);
		Check((string)holderJson["Item"] == path, "a C# resource that asks for it is saved as its path");
		var loaded = Forge.JsonStringToClass<ItemHolderCs>(Forge.ClassToJsonString(holder));
		Check(ReferenceEquals(loaded.Item, fromFile) || loaded.Item == fromFile, "the same resource instance is loaded back");
		Check(loaded.Items.Count == 2 && loaded.Items[1] == fromFile, "also inside a typed collection");
	}
}
