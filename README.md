# ForgeJSONGD

Simplify your Godot save/load systems with this GDScript singleton. Effortlessly serialize any class to JSON and deserialize back, with automatic handling of Godot types. Go beyond basic conversion with advanced tools to compare, find differences, and apply patches to your game or app data.

## Features

  * **Serialization (Class Object to JSON):**
	  * Converts Godot class instances into JSON-compatible dictionaries.
	  * Handles nested objects and arrays recursively, preserving complex data structures.
	  * Supports saving JSON data to files with optional encryption for enhanced security.
  * **Deserialization (JSON to Class Object):**
	  * Loads JSON data from files with optional decryption for secure data retrieval.
	  * Converts JSON strings and dictionaries back into Godot class instances.
	  * Reconstructs nested object hierarchies, including custom classes and resource references.
  * **JSON Comparison & Diffing:**
	  * Quickly check if two JSON files, strings, or dictionaries are identical.
	  * Generate a detailed "diff" dictionary highlighting changes, additions, and deletions between two JSON objects.
  * **JSON Operations:**
	  * Perform powerful patch operations between two JSON objects, including `Add`, `AddDiffer`, `Replace`, `Remove`, and `RemoveValue`.
	  * Apply changes from one JSON object to another, useful for patching saved data or syncing states.
  * **Automatic Type Recognition:** Intelligently manages various data types, including:
	  * Vectors (`Vector2`, `Vector3`, etc.)
	  * Colors
	  * Enums
	  * Arrays (including typed arrays)
	  * Dictionaries (including typed dictionaries)
	  * Custom classes

## Installation

1.  **Download:** Download the project from this repository.
2.  **Add to Project:** Place the `addons` folder in your Godot project folder.

## Configuration

### Toggling Export-Only Mode

By default, **ForgeJSONGD** serializes all script variables. You can change this behavior to only serialize variables marked with `@export` by setting a static variable.

```gdscript
# Set this to true to only save/load properties marked with @export.
# This is false by default, meaning all script variables are saved.
ForgeJSONGD.only_exported_values = true
```

## Usage (GDScript)

### 1\. Class to JSON

**a) Convert a Class Instance to a JSON Dictionary:**

```gdscript
# Assuming you have a class named 'PlayerData' (see Example section):
var player_data = PlayerData.new()
# ... Set properties of player_data ...

# Convert to a JSON dictionary:
var json_data = ForgeJSONGD.class_to_json(player_data)

# json_data now holds a Dictionary representation of your class instance.

# Convert a Class Instance to a JSON String
var json_string: String = ForgeJSONGD.class_to_json_string(player_data)
```

**b) Save JSON Data to a File:**

```gdscript
var file_success: bool = ForgeJSONGD.store_json_file("user://saves/player_data.json", json_data, "my_secret_key") # Optional encryption key

# Check if saving was successful:
if file_success:
	print("Player data saved successfully!")
else:
	print("Error saving player data.")
```

### 2\. JSON to Class

**a) Load JSON Data from a File:**

```gdscript
var loaded_data: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://saves/player_data.json", "your_secret_key")

if loaded_data:
	# ... Access properties of loaded_data ...
else:
	print("Error loading player data.")
```

**b) Convert a JSON String to a Class Instance:**

```gdscript
var json_string = '{ "name": "Alice", "score": 1500 }'
var player_data: PlayerData = ForgeJSONGD.json_string_to_class(PlayerData, json_string)
```

**c) Convert a JSON Dictionary to a Class Instance:**

```gdscript
var json_dict = { "name": "Bob", "score": 2000 }
var player_data: PlayerData = ForgeJSONGD.json_to_class(PlayerData, json_dict)
```

**d) Convert a JSON File to a Dictionary:**

```gdscript
var loaded_data: Dictionary = ForgeJSONGD.json_file_to_dict("user://saves/player_data.json", "your_secret_key")

if loaded_data:
	# ... Access properties of loaded_data ...
else:
	print("Error loading data.")
```

## Example Class (PlayerData.gd)

```gdscript
class_name PlayerData

@export var name: String
@export var score: int
var internal_variable: String = "This is not exported" # Also saved by default
@export var inventory: Array = []
```

## Example Usage (GDScript)

```gdscript
# Create a PlayerData instance
var player = PlayerData.new()
player.name = "Bob"
player.score = 100
player.inventory = ["Sword", "Potion"]

# Save the player data to a JSON file
ForgeJSONGD.store_json_file("user://player.sav", ForgeJSONGD.class_to_json(player))

# Load the player data from the JSON file
var loaded_player: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://player.sav")

# Print the loaded player's name
print(loaded_player.name) # Output: Bob
```

## Usage with C\#

While **ForgeJSONGD** is written in GDScript, you can easily call its methods from C\# using Godot's interoperability features. This allows you to serialize and deserialize your C\# classes seamlessly.

### 1\. Define Your C\# Data Class

First, create the C\# class you want to serialize. For best results, have it inherit from `GodotObject`.

**Data.cs**

```csharp
using Godot;

public partial class Data : GodotObject
{
	[Export]
	public string Name { get; set; } = "Default Name";
	
	[Export]
	public int Age { get; set; } = 15;
}
```

### 2\. Call ForgeJSONGD from C\#

Next, in another C\# script, you can load the `ForgeJSONGD.gd` script and call its methods.

**TestCSharp.cs**

```csharp
using Godot;

public partial class TestCSharp : Node
{
	private const string SavePath = "user://csharp.json";
	private const string ForgeJSONGDPath = "res://addons/ForgeJSONGD/ForgeJSONGD.gd";

	public override void _Ready()
	{
		// Load the ForgeJSONGD script
		var forgeJsonScript = ResourceLoader.Load<Script>(ForgeJSONGDPath);
		if (forgeJsonScript == null)
		{
			GD.PrintErr("Failed to load ForgeJSONGD script!");
			return;
		}

		// --- SAVING ---
		// 1. Create an instance of your C# data class
		var dataToSave = new Data
		{
			Name = "C-Sharp Player",
			Age = 25
		};

		// 2. Convert the C# object to a JSON dictionary
		var jsonDict = forgeJsonScript.Call("class_to_json", dataToSave).As<Godot.Collections.Dictionary>();

		// 3. Store the JSON dictionary in a file
		forgeJsonScript.Call("store_json_file", SavePath, jsonDict);
		GD.Print("C# data saved successfully.");


		// --- LOADING ---
		// 1. Call json_file_to_class to load and deserialize the data
		//    The first argument is a script or instance of the target class to provide type information.
		var loadedData = forgeJsonScript.Call("json_file_to_class", dataToSave.GetScript(), SavePath).As<Data>();

		if (loadedData != null)
		{
			GD.Print($"Loaded data successfully: Name = {loadedData.Name}, Age = {loadedData.Age}");
			// Output: Loaded data successfully: Name = C-Sharp Player, Age = 25
		}
		else
		{
			GD.PrintErr("Failed to load or deserialize C# data.");
		}
	}
}
```

## JSON Utilities and Operations

The class also provides powerful tools for comparing and manipulating JSON data directly.

**a) Check for Equality**

You can quickly check if two JSON sources (file paths, strings, or dictionaries) are identical.

```gdscript
var dict1 = {"name": "Alice", "score": 100}
var dict2 = {"name": "Alice", "score": 100}
var dict3 = {"name": "Bob", "score": 150}

var are_equal = ForgeJSONGD.check_equal_jsons(dict1, dict2)
print(are_equal) # Output: true

var are_different = ForgeJSONGD.check_equal_jsons(dict1, dict3)
print(are_different) # Output: false
```

**b) Compare and Find Differences (Diff)**

Generate a dictionary that highlights the differences between two JSON objects.

```gdscript
var old_data = {"name": "Player1", "level": 5, "items": ["sword"]}
var new_data = {"name": "Player1", "level": 6, "items": ["sword", "shield"], "new_key": "value"}

var diff = ForgeJSONGD.compare_jsons_diff(old_data, new_data)
# diff will contain a detailed report of the changes.
print(diff)
```

**c) Perform JSON Operations**

Apply changes from one JSON object to another using a specific operation. This is useful for patching, merging, removing, and syncing data.

The available operations are defined in the `ForgeJSONGD.Operation` enum:

  * `Add`: Adds keys from the reference JSON. If a key already exists, it combines the old and new values into an array.
  * `AddDiffer`: Adds keys from the reference JSON that do not exist, and merges values for keys that have different values.
  * `Replace`: Updates values in the source JSON with values from the reference JSON for all matching keys.
  * `Remove`: Removes keys from the source JSON that also exist in the reference JSON, regardless of their value.
  * `RemoveValue`: Removes a key-value pair from the source JSON only if both the key *and* its value match a pair in the reference JSON.

<!-- end list -->

```gdscript
# --- Example Data ---
var source_json = {"a": 1, "b": 2, "c": 3} # source_json can be a class object, file path or dictionary.
var reference_json = {"b": 20, "c": 3, "d": 4} # reference_json can be a class object, file path or dictionary.

# --- Operation: Add ---
# Merges values for "b" and adds "d".
var add_result = ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Add)
print(add_result) # Output: {"a": 1, "b": [2, 20], "c": 3, "d": 4}

# --- Operation: AddDiffer ---
# Merges "b" because values differ, keeps "c" as is, and adds "d".
var add_differ_result = ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.AddDiffer)
print(add_differ_result) # Output: {"a": 1, "b": [2, 20], "c": 3, "d": 4}

# --- Operation: Replace ---
# Replaces the value of "b" with 20.
var replace_result = ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Replace)
print(replace_result) # Output: {"a": 1, "b": 20, "c": 3}

# --- Operation: Remove ---
# Removes "b" and "c" because their keys exist in reference_json.
var remove_result = ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Remove)
print(remove_result) # Output: {"a": 1}

# --- Operation: RemoveValue ---
# Removes "c" because both key and value match. Does not remove "b" because values differ.
var remove_value_result = ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.RemoveValue)
print(remove_value_result) # Output: {"a": 1, "b": 2}
```

## Important Notes

  * **Supported Properties:**
	  * **GDScript:** By default, all script variables are serialized. To serialize **only** properties marked with `@export`, set `ForgeJSONGD.only_exported_values = true`.
	  * **C\#:** Only properties marked with the `[Export]` attribute will be serialized, regardless of the `only_exported_values` setting.
  * **Error Handling:** Implement robust error handling in your project to catch potential issues like file loading failures or JSON parsing errors.
