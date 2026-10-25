# ForgeJSONGD: C# Tutorial

ForgeJSONGD is written in GDScript, and works with your C# classes through Godot's cross-language calls. This guide covers setup, the rules your C# classes must follow, a ready-made C# wrapper, and every feature from C#.

The concepts (what is saved, inheritance, the JSON utilities, security, limits) are explained in detail in the [GDScript Tutorial](GDScript-Tutorial.md). This guide points there instead of repeating them, and covers what is different in C#.

Tested with the Godot 4.7.2 .NET build, targeting `net8.0`.

## Contents

1. [Setup](#setup)
2. [Your first save and load](#your-first-save-and-load)
3. [Writing classes ForgeJSONGD can save](#writing-classes-forgejsongd-can-save)
4. [The Forge.cs wrapper](#the-forgecs-wrapper)
5. [Supported types](#supported-types)
6. [Collections and inheritance](#collections-and-inheritance)
7. [Customizing a class from C#](#customizing-a-class-from-c)
8. [Security and the script registry](#security-and-the-script-registry)
9. [Comparing and patching JSON](#comparing-and-patching-json)
10. [Calling the addon without the wrapper](#calling-the-addon-without-the-wrapper)
11. [Building and running](#building-and-running)
12. [Limits and troubleshooting](#limits-and-troubleshooting)

---

## Setup

You need the **.NET build of Godot** and the **.NET SDK** (8 or newer; the SDK version only has to be at least the target version).

1. Copy the `addons/ForgeJSONGD` folder into your project's `addons` folder (see the [README](../README.md#installation)).
2. Your project needs a `.csproj` next to `project.godot`. A minimal one:

```xml
<Project Sdk="Godot.NET.Sdk/4.7.2">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <EnableDynamicLoading>true</EnableDynamicLoading>
  </PropertyGroup>
</Project>
```

   Use the SDK version that matches your Godot version.
3. Optionally, set the assembly name in `project.godot` (Godot works it out from the `.csproj` if you leave it out):

```ini
[dotnet]

project/assembly_name="MyGame"
```

4. Copy the [`Forge.cs`](#the-forgecs-wrapper) wrapper into your project. It is optional, but it removes all the string-based calls.

## Your first save and load

A class to save (see the [rules](#writing-classes-forgejsongd-can-save)):

```csharp
// Data.cs
using Godot;

[GlobalClass]
public partial class Data : GodotObject
{
	[Export] public string Name { get; set; } = "Default Name";
	[Export] public int Age { get; set; } = 15;
}
```

Saving and loading with the wrapper:

```csharp
var data = new Data { Name = "C-Sharp Player", Age = 25 };

Forge.StoreJsonFile("user://data.json", Forge.ClassToJson(data));

var loaded = Forge.JsonFileToClass<Data>("user://data.json");
GD.Print($"{loaded.Name}, {loaded.Age}"); // C-Sharp Player, 25
```

That is it: `Forge.ClassToJson` + `Forge.StoreJsonFile` to save, `Forge.JsonFileToClass<T>` to load. Encryption works the same as in GDScript: pass a key as the last argument (`Forge.StoreJsonFile(path, json, "my_key")` and `Forge.JsonFileToClass<Data>(path, "my_key")`).

Other ways in and out:

```csharp
Godot.Collections.Dictionary json = Forge.ClassToJson(data);        // object -> dictionary
string text = Forge.ClassToJsonString(data);                        // object -> JSON text
Data a = Forge.JsonToClass<Data>(json);                             // dictionary -> object
Data b = Forge.JsonStringToClass<Data>(text);                       // text -> object (null if invalid)
Godot.Collections.Dictionary d = Forge.JsonFileToDict("user://data.json"); // file -> dictionary
```

The behavior of each of these (missing files, invalid JSON, defaults for missing keys...) is the same as in GDScript: see the [method reference](GDScript-Tutorial.md#method-reference) and [error handling](GDScript-Tutorial.md#error-handling).

---

## Writing classes ForgeJSONGD can save

Godot has to know your class and its members, so:

| Rule | Why |
|---|---|
| Mark the class `partial` and `[GlobalClass]` | Godot registers global classes by name. ForgeJSONGD finds classes (children, nested objects) by that name. |
| Inherit from `GodotObject`, `RefCounted`, `Resource` or `Node` | Plain C# classes are not Godot objects. For data, `GodotObject` or `RefCounted` is enough. |
| **One class per file, and the file name is the class name** (`Data` in `Data.cs`) | Godot attaches one script per file. A second class in the same file cannot be loaded by name. |
| Mark every member you want saved with `[Export]` | Godot only knows exported members. |
| Give the class a parameterless constructor | `Forge.JsonToClass<T>` requires it (`new()`), and ForgeJSONGD uses it when there are no stored constructor arguments. Extra constructors are allowed, see [constructor arguments](#customizing-a-class-from-c). |

What is saved:

```csharp
[GlobalClass]
public partial class PartialData : GodotObject
{
	[Export] public string Saved { get; set; } = "";       // saved
	public string NotSaved { get; set; } = "";             // not saved: no [Export]
	[Export] public int SavedField = 0;                     // fields work too when exported
	public int NotSavedField = 0;                           // not saved
}
```

Only `[Export]` members are saved and loaded, whatever `only_exported_values` is set to. After loading, members that were not saved keep the value the constructor gave them.

---

## The Forge.cs wrapper

Copy this file into your project. Every method calls the GDScript method of the same name. Change `ScriptPath` if the addon is not at `res://addons/ForgeJSONGD/`.

```csharp
using Godot;
using Godot.Collections;

/// <summary>
/// Thin C# wrapper around the ForgeJSONGD GDScript addon. Copy this file into your project.
/// Every method just calls the GDScript method of the same name.
/// </summary>
public static class Forge
{
	/// <summary>Same order as ForgeJSONGD.Operation in GDScript.</summary>
	public enum Operation
	{
		Add,
		AddDiffer,
		Replace,
		Remove,
		RemoveValue,
	}

	private static string _scriptPath = "res://addons/ForgeJSONGD/ForgeJSONGD.gd";
	private static Script _script;

	/// <summary>Where ForgeJSONGD.gd is in your project. Change it if you installed the addon somewhere else.</summary>
	public static string ScriptPath
	{
		get => _scriptPath;
		set
		{
			_scriptPath = value;
			_script = null;
		}
	}

	private static Script Addon => _script ??= ResourceLoader.Load<Script>(_scriptPath);

	// --- Class to JSON ---

	public static Dictionary ClassToJson(GodotObject value, bool specifyClass = false) =>
		Addon.Call("class_to_json", value, specifyClass).As<Dictionary>();

	public static string ClassToJsonString(GodotObject value, bool specifyClass = false) =>
		Addon.Call("class_to_json_string", value, specifyClass).AsString();

	public static bool StoreJsonFile(string path, Dictionary data, string securityKey = "") =>
		Addon.Call("store_json_file", path, data, securityKey).AsBool();

	// --- JSON to class ---

	public static T JsonToClass<[MustBeVariant] T>(Dictionary json) where T : GodotObject, new() =>
		Addon.Call("json_to_class", ScriptOf<T>.Value, json).As<T>();

	public static T JsonStringToClass<[MustBeVariant] T>(string json) where T : GodotObject, new() =>
		Addon.Call("json_string_to_class", ScriptOf<T>.Value, json).As<T>();

	public static T JsonFileToClass<[MustBeVariant] T>(string path, string securityKey = "") where T : GodotObject, new() =>
		Addon.Call("json_file_to_class", ScriptOf<T>.Value, path, securityKey).As<T>();

	public static Dictionary JsonFileToDict(string path, string securityKey = "") =>
		Addon.Call("json_file_to_dict", path, securityKey).As<Dictionary>();

	/// <summary>Loads an object without knowing its class. The JSON must come from ClassToJson(value, true).</summary>
	public static GodotObject JsonToClass(Dictionary json) =>
		Addon.Call("json_to_class", default(Variant), json).As<GodotObject>();

	// --- JSON utilities ---

	/// <summary>Each argument can be a Dictionary, a JSON string, a file path or an object.</summary>
	public static bool CheckEqualJsons(Variant first, Variant second) =>
		Addon.Call("check_equal_jsons", first, second).AsBool();

	public static Dictionary CompareJsonsDiff(Variant first, Variant second) =>
		Addon.Call("compare_jsons_diff", first, second).As<Dictionary>();

	public static Dictionary JsonOperation(Variant baseJson, Variant referenceJson, Operation operation) =>
		Addon.Call("json_operation", baseJson, referenceJson, (int)operation).As<Dictionary>();

	// --- Script registry ---

	public static void RegisterScript(Script script) => Addon.Call("register_script", script);

	public static void ClearRegisteredScripts() => Addon.Call("clear_registered_scripts");

	// Finds (once per type) the script a C# type is attached to.
	private static class ScriptOf<T> where T : GodotObject, new()
	{
		public static readonly Variant Value = Find();

		private static Variant Find()
		{
			var probe = new T();
			var script = probe.GetScript();
			if (probe is not RefCounted)
				probe.Free();
			return script;
		}
	}
}
```

Notes on the wrapper:

* `JsonToClass<T>`, `JsonStringToClass<T>` and `JsonFileToClass<T>` need `T` to have a parameterless constructor (`new()`). It is used once per type to find the script.
* `JsonStringToClass<T>` returns `null` for invalid JSON. `JsonFileToClass<T>` returns a new `T` when the file is missing or empty.
* If `ScriptPath` is wrong, Godot cannot load the script and the wrapper throws (`Failed loading resource: ...ForgeJSONGD.gd`). Set `Forge.ScriptPath` before the first call if you installed the addon elsewhere.

---

## Supported types

All of these round-trip when exported with `[Export]` (every line below is covered by a test):

| C# type | Notes |
|---|---|
| `string`, `bool`, `int`, `long`, `byte`, `float`, `double` | exact, including `long` values above 2^53 and every digit of a `double` |
| C# `enum` | saved by name (`"Angry"`), also loads from the number |
| `Vector2`, `Vector3`, `Color` | |
| `Rect2`, `Aabb`, `Transform3D`, `Quaternion` | saved as text, restored with their type |
| `NodePath`, `StringName` | plain text |
| `int[]`, `string[]` | saved as JSON arrays |
| `Vector2[]`, `byte[]` | saved as text (`byte[]` as base64) |
| `Godot.Collections.Array<T>` for `int`, `string`, `Vector2`, `Color`, and your classes | |
| `Godot.Collections.Dictionary<string, int>`, `<string, YourClass>` | |
| `Godot.Collections.Array`, `Godot.Collections.Dictionary` (untyped) | |
| `YourClass[]` (array of your classes) | |
| Your own classes, including child classes | see [below](#collections-and-inheritance) |
| Classes that inherit `Resource` | saved inline |
| Resources from files (`Texture2D`, ...) | saved as the file path; also inside untyped `Godot.Collections.Array` / `Dictionary` and `Variant` members |
| `Variant` | keeps the type of the value it holds |

Numbers keep their type everywhere, also inside **untyped** `Godot.Collections.Array` / `Dictionary` and `Variant` members: an `int` stays an `int` and a `double` stays a `double` (see [Numbers, text and keys stay exact](GDScript-Tutorial.md#numbers-text-and-keys-stay-exact)).

---

## Collections and inheritance

Child classes are kept wherever a parent type is declared, in single members, arrays and dictionaries, typed or untyped:

```csharp
// ChildData.cs
using Godot;

[GlobalClass]
public partial class ChildData : Data
{
	[Export] public string Nickname { get; set; } = "";
}
```

```csharp
// Shapes.cs (members shown are part of a tested class)
[GlobalClass]
public partial class Shapes : GodotObject
{
	[Export] public Data Single { get; set; }
	[Export] public Godot.Collections.Array<Data> TypedItems { get; set; } = new();
	[Export] public Godot.Collections.Array UntypedItems { get; set; } = new();
	[Export] public Godot.Collections.Dictionary<string, Data> TypedDict { get; set; } = new();
	[Export] public Data[] NativeItems { get; set; } = System.Array.Empty<Data>();
}
```

```csharp
var shapes = new Shapes
{
	Single = new ChildData { Name = "Kid", Nickname = "K" },
	TypedItems = new Godot.Collections.Array<Data> { new Data { Name = "plain" }, new ChildData { Name = "kid", Nickname = "K" } },
	NativeItems = new Data[] { new Data(), new ChildData { Nickname = "N" } },
};

var loaded = Forge.JsonStringToClass<Shapes>(Forge.ClassToJsonString(shapes));

GD.Print(loaded.Single is ChildData);        // True
GD.Print(loaded.TypedItems[0] is ChildData); // False: a plain Data stays a Data
GD.Print(loaded.TypedItems[1] is ChildData); // True
GD.Print(loaded.NativeItems[1] is ChildData); // True
```

In an untyped `Godot.Collections.Array`, take the element out as a `GodotObject` and use pattern matching:

```csharp
if (loaded.UntypedItems[1].As<GodotObject>() is ChildData kid)
	GD.Print(kid.Nickname);
```

### Loading without knowing the class

Save with `specifyClass: true` and load with `Forge.JsonToClass(json)` (no type):

```csharp
var json = Forge.ClassToJson(new ChildData { Nickname = "N" }, specifyClass: true);
GodotObject anything = Forge.JsonToClass(json);
GD.Print(anything is ChildData); // True
```

Unlike GDScript, a single C# object member always stores its class name in the JSON (`"script_inheritance": "Data"`, even when it holds a plain `Data`), because Godot does not report the declared type of C# object members and the name is needed to load it. Typed collections only store it for child classes, like in GDScript.

The other rules from the GDScript guide apply: [classes need a name](GDScript-Tutorial.md#rules-to-keep-in-mind), a class that no longer exists loads as the declared parent type, and so on.

---

## Customizing a class from C#

The optional `_forge_` methods work from C#. Godot finds them by their **exact name**, so write them in snake_case, exactly as below (they are public methods; the names are not C# style on purpose):

| Method | What it does |
|---|---|
| `public Godot.Collections.Array _forge_excluded_properties()` | Names of members to skip when saving and loading. |
| `public Godot.Collections.Array _forge_constructor_args()` | Arguments passed to a constructor on load. |
| `public Godot.Collections.Dictionary _forge_serialize()` | Replaces the automatic saving. |
| `public GodotObject _forge_deserialize(Godot.Collections.Dictionary json)` | **Instance** method that receives the JSON and returns the finished object (C# cannot use the static form). |

Skipping members (use the **C# member names**):

```csharp
[GlobalClass]
public partial class SecretData : GodotObject
{
	[Export] public string UserName { get; set; } = "";
	[Export] public string Password { get; set; } = "";

	public Godot.Collections.Array _forge_excluded_properties() => new() { "Password" };
}
```

Constructor arguments (keep the parameterless constructor too):

```csharp
[GlobalClass]
public partial class ArgsData : GodotObject
{
	[Export] public int Count { get; set; }
	[Export] public string Label { get; set; } = "";

	public ArgsData() { }                       // used when there are no stored arguments
	public ArgsData(int count, string label) { Count = count; Label = label; }

	public Godot.Collections.Array _forge_constructor_args() => new() { Count, Label };
}
```

Taking over saving and loading:

```csharp
[GlobalClass]
public partial class CustomData : GodotObject
{
	public string Code { get; set; } = "";

	public Godot.Collections.Dictionary _forge_serialize() => new() { { "packed", "code:" + Code } };

	public GodotObject _forge_deserialize(Godot.Collections.Dictionary json)
	{
		Code = ((string)json["packed"]).Substring("code:".Length);
		return this;
	}
}
```

The full behavior of each hook is in [Customizing a class](GDScript-Tutorial.md#customizing-a-class).

---

## Security and the script registry

Encryption works with the key arguments shown above. To allow only certain classes to be created from a JSON file, register their scripts:

```csharp
Forge.RegisterScript(GD.Load<Script>("res://Data.cs"));
// Register every class that can appear, including child classes.

var data = Forge.JsonFileToClass<Data>("user://data.json"); // only registered scripts are created from names in the file

Forge.ClearRegisteredScripts(); // every script is allowed again
```

A class named in the JSON that is not registered is not created:

* in a **typed collection** (`Array<Data>`, `Dictionary<string, Data>`, `Data[]`) it loads as the declared element type (a `ChildData` becomes a `Data`);
* in a **single object member** (`public Data Friend`) the member stays `null`, because Godot does not tell ForgeJSONGD which type a C# object member is declared with.

The details are in [Security](GDScript-Tutorial.md#security).

---

## Comparing and patching JSON

Each argument can be a `Godot.Collections.Dictionary`, a JSON string, a file path or an object:

```csharp
Forge.CheckEqualJsons(first, second);   // bool: same data? (ignores key order and 1 vs 1.0)

var diff = Forge.CompareJsonsDiff(oldData, newData);  // {"Age": {"old": 25, "new": 99}}

var source = new Godot.Collections.Dictionary { { "a", 1 }, { "b", 2 } };
var reference = new Godot.Collections.Dictionary { { "b", 2 } };
var result = Forge.JsonOperation(source, reference, Forge.Operation.RemoveValue); // {"a": 1}
```

`Forge.Operation` has the same members, in the same order, as `ForgeJSONGD.Operation`: `Add`, `AddDiffer`, `Replace`, `Remove`, `RemoveValue`. What each does is in [Operations](GDScript-Tutorial.md#operations).

---

## Calling the addon without the wrapper

The wrapper is a convenience. Without it, load the GDScript and use `Call`:

```csharp
var forge = ResourceLoader.Load<Script>("res://addons/ForgeJSONGD/ForgeJSONGD.gd");

var json = forge.Call("class_to_json", data).As<Godot.Collections.Dictionary>();
forge.Call("store_json_file", "user://csharp.json", json);

// The first argument of the loading methods is the script of the class to build:
var loaded = forge.Call("json_file_to_class", data.GetScript(), "user://csharp.json").As<Data>();

// Without a type (the JSON must have been saved with specify_class = true):
var any = forge.Call("json_to_class", default(Variant), json).As<GodotObject>();

// Operations take the enum number: Add = 0, AddDiffer = 1, Replace = 2, Remove = 3, RemoveValue = 4.
var result = forge.Call("json_operation", first, second, 4).As<Godot.Collections.Dictionary>();
```

Every method in the [method reference](GDScript-Tutorial.md#method-reference) can be called this way by its GDScript name (`snake_case`). `only_exported_values` does not apply to C#: only `[Export]` members are ever saved.

---

## Building and running

The C# assembly must be built, and Godot must then scan the project so it knows your `[GlobalClass]` types. Both steps are what the editor does for you when you press *Build* and open the project.

From the command line (for example in CI), run the two steps **in this order**:

```
godot_mono --headless --editor --path . --build-solutions --quit
godot_mono --headless --path . --import --quit
godot_mono --headless --path . res://YourScene.tscn
```

You can also build with `dotnet build` (point NuGet at the packages shipped with Godot, in `GodotSharp/Tools/nupkgs`, with `-p:RestoreAdditionalProjectSources=<path>`), then run the `--import` step.

These steps work without a `.sln` file: only the `.csproj` is needed.

**If you skip the `--import` step** after a build, Godot does not know your classes yet, and ForgeJSONGD can no longer find them by name: child classes come back as the parent class, nested objects fail to load, and Godot prints errors such as *"Attempted to set a variable of type 'Dictionary' into a TypedDictionary.Value of type 'Object'"* or *"Unable to cast object of type 'Godot.GodotObject'..."*. Run the import step (or open the project in the editor once) and the problem disappears.

---

## Limits and troubleshooting

The [limits of the GDScript guide](GDScript-Tutorial.md#limits-and-things-to-know) apply. C#-specific points:

| Problem | Cause and fix |
|---|---|
| A member is not saved | It has no `[Export]`, or the class is not `partial` / not a Godot object, or it is excluded by `_forge_excluded_properties`. |
| A class is not found when loading (child comes back as parent) | The class has no `[GlobalClass]`, is not the class named like its file, or the project was built but not imported yet. See [Building and running](#building-and-running). |
| `Failed loading resource: res://addons/ForgeJSONGD/ForgeJSONGD.gd` | The addon is somewhere else. Set `Forge.ScriptPath`. |
| `Unable to cast object of type 'Godot.GodotObject' to type '...'` | Godot does not know your classes yet because the project was built but not imported. Run the import step, see [Building and running](#building-and-running). |
| `_forge_...` method is ignored | The method name must be written exactly in snake_case as in the table, and must be public. |
| `Forge.JsonToClass<T>` does not compile | `T` must derive from `GodotObject` and have a parameterless constructor. |
