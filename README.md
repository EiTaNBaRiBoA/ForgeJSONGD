# ForgeJSONGD

Save and load your Godot classes as JSON, in one line each. ForgeJSONGD turns any GDScript or C# class into a JSON dictionary (or file, optionally encrypted) and builds it back, including nested objects, arrays, dictionaries, enums, inheritance, and Godot types like `Vector2`, `Color` and `Transform3D`. It can also compare two JSON data sets, list their differences, and patch one with the other.

## Guides

| Guide | For |
|---|---|
| [GDScript Tutorial](docs/GDScript-Tutorial.md) | Everything: every method, every supported type, inheritance, customization, security, comparing and patching, limits |
| [C# Tutorial](docs/CSharp-Tutorial.md) | Using ForgeJSONGD from C#: setup, a ready-made wrapper, C# class rules, builds |

## Features

  * **Class to JSON and back:** `class_to_json`, `json_to_class`, plus string and file variants. Variables you did not set keep their defaults, unknown keys are ignored.
  * **Files with optional encryption:** pass a key to `store_json_file` / `json_file_to_class`.
  * **Inheritance and polymorphism:** a child class stored in a parent-typed variable, array or dictionary comes back as the child. [Details](docs/GDScript-Tutorial.md#inheritance-and-polymorphism)
  * **JSON for web APIs:** add `func _forge_plain_json() -> bool: return true` to a data class and the normal functions write and read standard JSON for it, with the field names your API uses (`_forge_json_keys`). A server can never make a game create classes or load files. [Details](docs/GDScript-Tutorial.md#json-for-http-apis)
  * **Many types, automatically:** numbers, text, enums (saved by name), vectors, `Color`, `Rect2`, `AABB`, `Basis`, `Quaternion`, `Transform2D/3D`, `Plane`, `Projection`, packed arrays, `NodePath`, typed and untyped arrays and dictionaries, resources, `Variant`. [Type table](docs/GDScript-Tutorial.md#what-is-saved-and-how)
  * **Customizable classes:** skip variables, pass constructor arguments, or take over saving and loading with optional `_forge_` methods. [Details](docs/GDScript-Tutorial.md#customizing-a-class)
  * **Safe loading of untrusted files:** optionally allow only registered scripts. [Details](docs/GDScript-Tutorial.md#security)
  * **Compare, diff and patch:** `check_equal_jsons`, `compare_jsons_diff` and `json_operation` (`Add`, `AddDiffer`, `Replace`, `Remove`, `RemoveValue`). [Details](docs/GDScript-Tutorial.md#comparing-and-patching-json)
  * **GDScript and C#:** the same addon serves both languages. [C# guide](docs/CSharp-Tutorial.md)

## Installation

1. Download this repository.
2. Copy the `addons/ForgeJSONGD` folder into the `addons` folder of your Godot project.

No plugin needs to be enabled: `ForgeJSONGD` is a global class.

## Quick start (GDScript)

```gdscript
# player_data.gd
class_name PlayerData

@export var name: String
@export var score: int
@export var inventory: Array = []
```

```gdscript
var player := PlayerData.new()
player.name = "Bob"
player.score = 100
player.inventory = ["Sword", "Potion"]

# Save
ForgeJSONGD.store_json_file("user://player.sav", ForgeJSONGD.class_to_json(player))

# Load
var loaded: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://player.sav")
print(loaded.name) # Bob
```

## Quick start (C#)

```csharp
[GlobalClass]
public partial class Data : GodotObject
{
	[Export] public string Name { get; set; } = "";
	[Export] public int Age { get; set; }
}
```

```csharp
// Forge.cs is a small wrapper, see the C# tutorial.
Forge.StoreJsonFile("user://data.json", Forge.ClassToJson(new Data { Name = "Ann", Age = 30 }));
var loaded = Forge.JsonFileToClass<Data>("user://data.json");
GD.Print(loaded.Name); // Ann
```

## Methods at a glance

All methods are static: call them as `ForgeJSONGD.method(...)`.

| Method | Purpose |
|---|---|
| `class_to_json(object, specify_class = false) -> Dictionary` | Object to a JSON dictionary |
| `class_to_json_string(object, specify_class = false) -> String` | Object to JSON text |
| `store_json_file(path, data, security_key = "") -> bool` | Write a dictionary to a file (encrypted if a key is given) |
| `json_to_class(script_or_instance, json) -> Object` | Dictionary to an object |
| `json_string_to_class(script_or_instance, json_string) -> Object` | JSON text to an object (`null` if invalid) |
| `json_file_to_class(script_or_instance, path, security_key = "") -> Object` | File to an object |
| `json_file_to_dict(path, security_key = "") -> Dictionary` | File to a dictionary (`{}` on failure) |
| `check_equal_jsons(first, second) -> bool` | Are two JSON sources the same data |
| `compare_jsons_diff(first, second) -> Dictionary` | What changed between two JSON sources |
| `json_operation(base, reference, operation) -> Dictionary` | Patch one JSON source with another |
| `register_script_alias(script, alias, save_as = true)`, `clear_script_aliases()` | Stable names for classes, so renames do not break saves |
| `register_script(script)`, `register_scripts(scripts)`, `clear_registered_scripts()` | Optional allow-list of scripts |
| `convert_array_to_json(array)`, `convert_dictionary_to_json(dictionary)` | Convert containers on their own |

Settings: `ForgeJSONGD.only_exported_values` (default `false`), `ForgeJSONGD.json_indent` (default tab), `ForgeJSONGD.sort_keys` (default `true`). Enum: `ForgeJSONGD.Operation`.

Optional methods a class can define (all start with `_forge_`): `_forge_excluded_properties`, `_forge_extra_properties`, `_forge_json_keys`, `_forge_renamed_properties`, `_forge_plain_json`, `_forge_save_by_path`, `_forge_constructor_args`, `_forge_serialize`, `_forge_deserialize`. See [Customizing a class](docs/GDScript-Tutorial.md#customizing-a-class).

## Important notes

  * **What is saved:** GDScript saves every script variable by default; set `ForgeJSONGD.only_exported_values = true` to save only `@export` / `@export_storage` variables. C# saves only `[Export]` members.
  * **Errors:** saving returns `false` on failure; loading a missing file returns a new instance (or `{}` for a dictionary); invalid JSON text returns `null`. See [error handling](docs/GDScript-Tutorial.md#error-handling).
  * **Web APIs:** mark the data classes you send to or receive from an API with `_forge_plain_json`. Without it the format is the exact one made for save files, with class names and markers that an API does not expect.
  * **Security:** encrypt files with a key to protect them from editing, and register the allowed scripts if files can come from other people. See [security](docs/GDScript-Tutorial.md#security).
  * **Exact data:** ints stay ints (also above 2^53), floats keep every digit, text stays text, and dictionary keys keep their type. See [how](docs/GDScript-Tutorial.md#numbers-text-and-keys-stay-exact).
