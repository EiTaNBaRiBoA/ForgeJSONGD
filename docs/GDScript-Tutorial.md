# ForgeJSONGD: GDScript Tutorial

This guide covers everything ForgeJSONGD can do from GDScript. Using C#? Read the [C# Tutorial](CSharp-Tutorial.md) for setup and C# rules; the concepts below apply to both languages.

## Contents

1. [Your first save and load](#your-first-save-and-load)
2. [What is saved, and how](#what-is-saved-and-how)
3. [Method reference](#method-reference)
4. [Settings](#settings)
5. [Inheritance and polymorphism](#inheritance-and-polymorphism)
6. [Customizing a class](#customizing-a-class)
7. [Built-in types in `Variant` and untyped containers](#built-in-types-in-variant-and-untyped-containers)
8. [Enums](#enums)
9. [Resources](#resources)
10. [Security](#security)
11. [Comparing and patching JSON](#comparing-and-patching-json)
12. [Error handling](#error-handling)
13. [Limits and things to know](#limits-and-things-to-know)
14. [Troubleshooting](#troubleshooting)

---

## Your first save and load

Any class works. Give it a `class_name` so it can be found when loading:

```gdscript
# player_data.gd
class_name PlayerData

@export var name: String
@export var score: int
var internal_variable: String = "This is not exported" # also saved by default
@export var inventory: Array = []
```

Save it:

```gdscript
var player := PlayerData.new()
player.name = "Bob"
player.score = 100
player.inventory = ["Sword", "Potion"]

ForgeJSONGD.store_json_file("user://player.sav", ForgeJSONGD.class_to_json(player))
```

Load it by telling ForgeJSONGD which class to build:

```gdscript
var loaded_player: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://player.sav")
print(loaded_player.name)  # Bob
print(loaded_player.score) # 100
```

That is the whole idea: `class_to_json` + `store_json_file` to save, `json_file_to_class` to load. The rest of this guide covers the other ways to get data in and out, and the less common cases.

If you only want the JSON as a dictionary or as text:

```gdscript
var json_data: Dictionary = ForgeJSONGD.class_to_json(player)
var json_string: String = ForgeJSONGD.class_to_json_string(player)
```

If your JSON comes from text or a dictionary instead of a file:

```gdscript
var from_string: PlayerData = ForgeJSONGD.json_string_to_class(PlayerData, '{ "name": "Alice", "score": 1500 }')
var from_dict: PlayerData = ForgeJSONGD.json_to_class(PlayerData, { "name": "Bob", "score": 2000 })
```

Variables that are missing from the JSON keep the default value of the class (`from_dict.inventory` is still `[]`), and keys that the class does not have are ignored.

To read a file as a plain dictionary, without building a class:

```gdscript
var loaded_data: Dictionary = ForgeJSONGD.json_file_to_dict("user://saves/player_data.json")
```

### Encrypting a file

Pass a key as the last argument when saving and loading:

```gdscript
ForgeJSONGD.store_json_file("user://saves/player_data.json", ForgeJSONGD.class_to_json(player), "my_secret_key")
var loaded: PlayerData = ForgeJSONGD.json_file_to_class(PlayerData, "user://saves/player_data.json", "my_secret_key")
```

Reading an encrypted file without the right key fails: `json_file_to_dict` returns `{}` and Godot logs an error. See [Security](#security).

Missing folders in the path are created for you (`user://saves/slot1/player.json` works even if neither folder exists yet).

---

## What is saved, and how

**Which variables:** by default every script variable of the class, exported or not. Set [`only_exported_values`](#settings) to save only `@export` and `@export_storage` variables. A class can also skip variables itself, see [Customizing a class](#customizing-a-class). Variables inherited from a parent *script* are included; built-in properties of Godot nodes (position, name...) are not, only script variables.

**How each type looks in the JSON:**

| Variable type | In the JSON | Example |
|---|---|---|
| `bool`, `int`, `float`, `String` | as is | `42`, `true`, `"text"` |
| Enum | the key name | `"Angry"` (see [Enums](#enums)) |
| `Vector2/3/4`, `Vector2i/3i/4i` | text | `"Vector2(1, 2)"` |
| `Color` | hex text `RRGGBBAA` | `"ff0000ff"` |
| `Rect2`, `Rect2i`, `AABB`, `Plane`, `Quaternion`, `Basis`, `Transform2D`, `Transform3D`, `Projection` | text | `"Rect2(1, 2, 3, 4)"` |
| `PackedVector2Array`, `PackedVector3Array`, `PackedVector4Array`, `PackedColorArray` | text | `"PackedVector2Array(1, 2, 3, 4)"` |
| `PackedByteArray` | base64 text | `"PackedByteArray(\"AQID\")"` |
| `PackedInt32Array`, `PackedInt64Array`, `PackedFloat32Array`, `PackedFloat64Array`, `PackedStringArray` | JSON array | `[1, 2, 3]` |
| `NodePath`, `StringName` | plain text | `"a/b"` |
| `Array`, `Array[T]` | JSON array, each element converted by these same rules | `[1, 2]` |
| `Dictionary`, `Dictionary[K, V]` | JSON object, keys written as text | `{"a": 1}` |
| Object with a script | JSON object of its variables | `{"name": "Rex"}` |
| `Resource` saved in a file other than `.tres` | its path (in untyped places: `{"forge_resource_path": "<path>"}`) | `"res://icon.svg"` |
| `Resource` saved in a `.tres` file, or not saved to disk | JSON object of its variables | `{"label": "x"}` |
| `null` | `null` | `null` |
| `Variant` | depends on the value, with the type kept | see [below](#built-in-types-in-variant-and-untyped-containers) |

Because JSON has only one number type, whole numbers in untyped places come back as floats. A typed `int` variable converts back to `int` when loading.

**What is not supported:** objects without a script (for example a plain `RefCounted.new()` stored in a variable of type `Object`) are saved as `null`, and `Callable` and `RID` values are not restored. Classes declared inside another script (`class Inner:`) cannot be found by name. See [Limits](#limits-and-things-to-know).

---

## Method reference

All methods are static. `ForgeJSONGD` is an abstract class: never create an instance of it.

### Saving

#### `class_to_json(object: Object, specify_class: bool = false) -> Dictionary`

Converts an object to a dictionary of JSON-compatible values.

* `specify_class`: when `true`, the dictionary also contains `"script_inheritance"` with the class name (or script path), so the object can be loaded later [without knowing its class](#loading-without-knowing-the-class). Nested objects add it by themselves whenever it is needed, you only set this for the top-level object.

#### `class_to_json_string(object: Object, specify_class: bool = false) -> String`

Same as above, but returns JSON text.

#### `store_json_file(file_path: String, data: Dictionary, security_key: String = "") -> bool`

Writes `data` to a file as JSON with tab indentation. Creates missing folders. If `security_key` is not empty the file is encrypted. Returns `true` on success and `false` (with an error printed) when the file cannot be written.

#### `convert_array_to_json(array: Array) -> Array` and `convert_dictionary_to_json(dictionary: Dictionary) -> Dictionary`

Convert a container of objects and values on its own, using the same rules as above. Useful when the thing you want to save is an array or dictionary instead of one object:

```gdscript
var json_array: Array = ForgeJSONGD.convert_array_to_json([dog, cat])
```

### Loading

The first argument of the loading methods is either a **script** (a new instance is created: `PlayerData`), an **existing instance** (it is filled with the data), or `null` (the class is read from the JSON, see [Loading without knowing the class](#loading-without-knowing-the-class)).

#### `json_to_class(script_or_instance: Variant, json: Dictionary) -> Object`

Dictionary to object.

```gdscript
var existing := PlayerData.new()
ForgeJSONGD.json_to_class(existing, {"score": 5}) # fills existing, other variables are left alone
```

#### `json_string_to_class(script_or_instance: Variant, json_string: String) -> Object`

JSON text to object. Returns `null` if the text is not valid JSON.

#### `json_file_to_class(script_or_instance: Variant, file_path: String, security_key: String = "") -> Object`

File to object. If the file does not exist, is empty or cannot be read, and you passed a script, you get a **new instance with default values** (handy for a first run with no save file). With an existing instance and no readable file, it is returned unchanged.

#### `json_file_to_dict(file_path: String, security_key: String = "") -> Dictionary`

File to dictionary. Returns `{}` when the file is missing, is not valid JSON, or cannot be decrypted. To tell a missing file from an empty one, check `FileAccess.file_exists(path)` first.

### Comparing and patching

`check_equal_jsons`, `compare_jsons_diff` and `json_operation` are covered in [Comparing and patching JSON](#comparing-and-patching-json).

### Script registry

`register_script(script)`, `register_scripts(scripts)` and `clear_registered_scripts()` are covered in [Security](#security).

### Constants

* `ForgeJSONGD.SCRIPT_INHERITANCE` is `"script_inheritance"`, the key that holds a class name or script path.
* `ForgeJSONGD.CONSTRUCTOR_ARGS` is `"script_constructor_args"`, the key that holds constructor arguments (see [Customizing a class](#customizing-a-class)).

---

## Settings

`ForgeJSONGD.only_exported_values: bool` (default `false`) is a global switch:

```gdscript
ForgeJSONGD.only_exported_values = true # only @export and @export_storage variables are saved and loaded
```

* `false`: every script variable is saved and loaded, including ones without `@export`.
* `true`: only variables with `@export` or `@export_storage` are saved and loaded. Plain `var` variables are skipped in both directions.

The setting is global and stays set until you change it back. In C#, only `[Export]` members are ever saved, regardless of this setting.

---

## Inheritance and polymorphism

You do not need any extra setup for inheritance. When a variable is declared with a **parent** type but holds a **child** instance, ForgeJSONGD stores the child's script name next to its data, and loads the child back with all of its properties.

```gdscript
# animal.gd
class_name Animal
extends Resource

@export var name: String
```

```gdscript
# dog.gd
class_name Dog
extends Animal

@export var tricks: Array[String]
```

```gdscript
# cat.gd
class_name Cat
extends Animal

@export var lives: int = 9
```

```gdscript
# zoo.gd - every variable is typed with the PARENT class Animal
class_name Zoo
extends Resource

@export var star: Animal
@export var animals: Array[Animal]
@export var by_name: Dictionary[String, Animal]
```

```gdscript
var rex := Dog.new()
rex.name = "Rex"
rex.tricks = ["sit", "roll"]
var tom := Cat.new()
tom.name = "Tom"
var generic := Animal.new()
generic.name = "Generic"

var zoo := Zoo.new()
zoo.star = rex
zoo.animals = [rex, tom, generic] # a Dog, a Cat and a plain Animal
zoo.by_name = {"tom": tom}

ForgeJSONGD.store_json_file("user://zoo.json", ForgeJSONGD.class_to_json(zoo))

var loaded: Zoo = ForgeJSONGD.json_file_to_class(Zoo, "user://zoo.json")
print(loaded.star is Dog)                # true
print(loaded.animals[1] is Cat)          # true
print(loaded.animals[2] is Cat)          # false, a plain Animal stays an Animal
print((loaded.animals[0] as Dog).tricks) # ["sit", "roll"]
```

The saved JSON only adds `script_inheritance` where the declared type is not enough to tell the class. The plain `Animal` has none:

```json
{
  "animals": [
    { "name": "Rex", "script_inheritance": "Dog", "tricks": ["sit", "roll"] },
    { "lives": 9, "name": "Tom", "script_inheritance": "Cat" },
    { "name": "Generic" }
  ],
  "by_name": { "tom": { "lives": 9, "name": "Tom", "script_inheritance": "Cat" } },
  "star": { "name": "Rex", "script_inheritance": "Dog", "tricks": ["sit", "roll"] }
}
```

This works for single variables, `Array[Animal]`, `Dictionary[String, Animal]`, untyped arrays and dictionaries, `Variant` variables, and objects nested inside other objects.

### Loading without knowing the class

If you do not know the class when loading (for example a save slot that can hold a `Dog` or a `Cat`), save with `specify_class = true` and load by passing `null` instead of a class:

```gdscript
var json := ForgeJSONGD.class_to_json(rex, true) # also stores "script_inheritance": "Dog"
var animal: Object = ForgeJSONGD.json_to_class(null, json)
print(animal is Dog) # true
```

This also works with `json_string_to_class(null, text)`. If the JSON names no script, or a script that does not exist, you get a plain `Object`.

### Rules to keep in mind

* **Give child classes a `class_name`.** The name is how the class is found when loading. A script without `class_name` is found by its path (`res://...`), so do not move or rename that file after saving.
* **Classes declared inside another script** (an inner `class`) have no name or path, so they cannot be found. Put them in their own file.
* **A class that no longer exists** (you deleted or renamed it after saving) loads as the declared type of the variable, keeping the data that fits. In an untyped container or `Variant`, which has no declared type, the data stays a plain dictionary.
* **Variables of the child** are only saved and loaded if they are script variables (`@export` only, if `only_exported_values` is on).

---

## Customizing a class

A class can define any of these optional methods. They all start with `_forge_`, so they will not clash with your own methods. Classes that do not define them behave as usual.

| Method | What it does |
|---|---|
| `func _forge_excluded_properties() -> Array` | Names of variables to skip when saving **and** loading. |
| `func _forge_constructor_args() -> Array` | Arguments for `_init`. They are saved, and passed to `_init` again on load. Needed when `_init` has required parameters. |
| `func _forge_serialize() -> Dictionary` | Replaces the automatic saving of the class with your own dictionary. |
| `static func _forge_deserialize(json: Dictionary) -> Object` | Builds the object from that dictionary. Use together with `_forge_serialize`. |

### Skipping variables

```gdscript
class_name Account

var user_name: String
var password: String # never written to the save file
var level: int


func _forge_excluded_properties() -> Array:
	return ["password"]
```

The excluded variables are skipped when saving, and ignored when loading even if the JSON contains them.

### Classes whose `_init` needs arguments

```gdscript
class_name Weapon

var damage: int
var title: String


func _init(new_damage: int, new_title: String) -> void: # no default values
	damage = new_damage
	title = new_title


func _forge_constructor_args() -> Array:
	return [damage, title]
```

The arguments are saved under `"script_constructor_args"`. On load, ForgeJSONGD creates the object with those arguments, then loads the variables. Without this method, a class with required `_init` parameters cannot be created: Godot prints an error and you get a plain `Object` back.

### Taking over saving and loading

```gdscript
class_name Scoreboard

var scores: Array[int] = []


# Stores the scores as one comma separated text.
func _forge_serialize() -> Dictionary:
	return {"scores": ",".join(PackedStringArray(scores.map(str)))}


# Static: receives the dictionary and returns the finished object.
static func _forge_deserialize(json: Dictionary) -> Object:
	var board := Scoreboard.new()
	for part: String in String(json.get("scores", "")).split(",", false):
		board.scores.append(part.to_int())
	return board
```

* `_forge_serialize` returns the dictionary that is saved for the class. The values in it are converted by the normal rules. If the class is saved with `specify_class` (or in an untyped place), `"script_inheritance"` is added to it for you.
* `_forge_deserialize` receives the dictionary exactly as it was loaded from JSON, and returns the object. The automatic loading of variables is skipped.
* `_forge_deserialize` can also be a normal (non-static) method. A new instance is created first, then the method is called on it and its return value is used. C# classes must use this form, see the [C# Tutorial](CSharp-Tutorial.md#customizing-a-class-from-c).

---

## Built-in types in `Variant` and untyped containers

A variable with a declared type (`Rect2`, `PackedByteArray`...) always loads back as that type. But a `Variant` variable, or an untyped `Array` or `Dictionary`, gives no hint about the type when loading. So in those places ForgeJSONGD writes the types JSON cannot represent as text that remembers the type, and turns them back on load:

```gdscript
var model := MyModel.new()
model.any = Rect2(1, 2, 3, 4)                                  # a Variant variable
model.list = [Rect2(1, 2, 3, 4), PackedByteArray([1, 2, 3]), Color.RED, Vector2i(1, 2)] # an untyped Array
model.data = {"box": AABB(), "nested": {"matrix": Basis.IDENTITY}} # an untyped Dictionary
# After saving and loading, every value above is the same type again.
```

This covers vectors, `Color`, `Rect2/Rect2i`, `AABB`, `Plane`, `Quaternion`, `Basis`, `Transform2D/3D`, `Projection` and all packed arrays, including inside nested arrays and dictionaries. Objects stored in a `Variant` variable keep their class too.

Things that stay plain text: dictionary **keys**, `StringName` and `NodePath` values (so files stay readable).

Typed containers (`Array[Rect2]`, `Dictionary[String, Transform3D]`) use the same text form. Typed `Color` containers keep the hex form.

---

## Enums

Enum variables are saved by **name**, so the file stays readable and survives reordering the enum:

```gdscript
enum Mood { CALM, HAPPY = 5, ANGRY = 9 }
@export var mood: Mood = Mood.ANGRY   # saved as "Angry"
```

* The enum must be on a variable with a declared enum type.
* Names are written like Godot shows them in the inspector (`VERY_SLOW_MODE` becomes `"Very_Slow_Mode"`).
* When loading, matching ignores upper/lower case and treats `_` and spaces the same, so `"very_slow_mode"` and `"VERY SLOW MODE"` also work. A plain number is accepted too (the integer value of the enum). An unknown name loads as `0`.
* Custom values (`HAPPY = 5`) are respected.

---

## Resources

* A resource that is stored in a file other than `.tres` (a texture, for example) is saved as its **path**, and loaded again with `ResourceLoader`. This also works inside typed containers: `Array[Texture2D]` and `Dictionary[String, Texture2D]` are saved as paths and load the resources again.
* A resource stored in a `.tres` file, or one that was never saved to disk, is saved **inline** as a JSON object of its variables, and rebuilt on load.
* A `null` resource stays `null`.
* In an **untyped** place (a `Variant` variable, an untyped `Array` or `Dictionary`, nested containers), nothing tells the type when loading, so a resource from a file is saved as a small marker object holding the path, `{"forge_resource_path": "res://icon.svg"}`, and loaded again from it.

You can also write a resource path in the JSON by hand: `{"texture": "res://icon.svg"}` loads the texture.

---

## Security

A save file is data from outside your game. Treat it that way if players can edit it or share it.

**Encryption** (`security_key`) stops players from reading or editing a file easily. It does not authenticate who made the file. A wrong or missing key makes the read fail and return `{}`.

**Script allow-list.** By default, a JSON file can name any script of your project (`"script_inheritance": "res://..."`) and ForgeJSONGD will create an instance of it. If files can come from other people (shared saves, downloaded levels), register the scripts that may appear. Once at least one script is registered, **only** registered scripts are created from names found in JSON:

```gdscript
ForgeJSONGD.register_script(Dog)
ForgeJSONGD.register_scripts([Cat, Animal])

var zoo: Zoo = ForgeJSONGD.json_file_to_class(Zoo, "user://zoo.json")

ForgeJSONGD.clear_registered_scripts() # every script is allowed again
```

* Register every class that can appear, **including child classes**.
* Scripts you pass yourself, like `Zoo` above, are always allowed.
* A script in the JSON that is not registered is not created. It loads as the declared type of the variable instead (a `Cat` in an `Array[Animal]` becomes an `Animal` with the data that fits), and a warning is printed. In an untyped place it stays plain data.
* A resource path in the JSON whose resource uses an unregistered script is not loaded. Resources without a script (textures, for example) still load.
* The registry is global.

**Text values.** When loading, text that looks like a Godot value (for example `"Vector2(1, 2)"`) is converted with `str_to_var`, but only for a safe list of types, and never if the text contains `Object(`, `Callable(` or `Signal(`.

---

## Comparing and patching JSON

These three methods accept any of: a **Dictionary**, a **JSON string**, a **file path** to a JSON file, or an **object** (converted with `class_to_json`). The inputs are never modified.

Two JSON sources count as the same data when they have the same content, ignoring the **order of keys**, the difference between **`1` and `1.0`**, and **`NodePath` vs text**. The order of items in an **array** matters.

### Equality

```gdscript
var dict1 := {"name": "Alice", "score": 100}
var dict2 := {"name": "Alice", "score": 100}
var dict3 := {"name": "Bob", "score": 150}

print(ForgeJSONGD.check_equal_jsons(dict1, dict2)) # true
print(ForgeJSONGD.check_equal_jsons(dict1, dict3)) # false
```

`check_equal_jsons(first, second) -> bool` also works for a saved file against the object it came from: `check_equal_jsons("user://player.sav", player)`.

### Differences

`compare_jsons_diff(first, second) -> Dictionary` returns `{}` when the data is equal. Otherwise each changed key maps to `{"old": ..., "new": ...}`. Nested dictionaries are compared key by key, arrays are reported as a whole, and a key that exists only on one side shows `null` for the other:

```gdscript
var old_data := {"name": "Player1", "level": 5, "items": ["sword"]}
var new_data := {"name": "Player1", "level": 6, "items": ["sword", "shield"], "new_key": "value"}

print(ForgeJSONGD.compare_jsons_diff(old_data, new_data))
# {
#   "level":   {"old": 5, "new": 6},
#   "items":   {"old": ["sword"], "new": ["sword", "shield"]},
#   "new_key": {"old": null, "new": "value"}
# }
```

### Operations

`json_operation(base_json, reference_json, operation) -> Dictionary` combines two JSON sources and returns the result. The operation is one of `ForgeJSONGD.Operation`:

| Operation | What it does |
|---|---|
| `Add` | Adds keys that only exist in the reference. For a key in both: numbers and text are combined into an array `[base, reference]`, arrays get **all** reference items appended, dictionaries are merged recursively. |
| `AddDiffer` | Like `Add`, but equal values stay as they are, and arrays only get reference items they do not have yet. |
| `Replace` | Takes the reference value for every key in both (arrays are replaced as a whole), and adds keys that only exist in the reference. |
| `Remove` | Removes every key that exists in the reference, whatever its value. In arrays, removes the items that appear in the reference. Dictionaries are handled recursively. |
| `RemoveValue` | Like `Remove`, but only when the value is equal too. |

```gdscript
var source_json := {"a": 1, "b": 2, "c": 3}
var reference_json := {"b": 20, "c": 3, "d": 4}

ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Add)
# {"a": 1, "b": [2, 20], "c": [3, 3], "d": 4}

ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.AddDiffer)
# {"a": 1, "b": [2, 20], "c": 3, "d": 4}

ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Replace)
# {"a": 1, "b": 20, "c": 3, "d": 4}

ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.Remove)
# {"a": 1}

ForgeJSONGD.json_operation(source_json, reference_json, ForgeJSONGD.Operation.RemoveValue)
# {"a": 1, "b": 2}
```

With nested data and arrays:

```gdscript
var base := {"player": {"hp": 10, "items": ["sword", "shield"]}}
var ref := {"player": {"hp": 10, "items": ["shield"]}}

ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Remove)    # {"player": {"items": ["sword"]}}
ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Replace)   # {"player": {"hp": 10, "items": ["shield"]}}
ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.AddDiffer) # {"player": {"hp": 10, "items": ["sword", "shield"]}}
ForgeJSONGD.json_operation(base, ref, ForgeJSONGD.Operation.Add)       # items becomes ["sword", "shield", "shield"]
```

If both inputs hold equal data, `Replace` returns the data unchanged, and `Remove` and `RemoveValue` return `{}`. The `"script_inheritance"` key is never changed by an operation.

Typical uses: apply a patch to saved data (`Replace` or `AddDiffer`), merge settings (`Add`), strip debug keys from a save (`Remove`), and detect whether a save changed (`compare_jsons_diff`).

---

## Error handling

| Situation | Result |
|---|---|
| `store_json_file` cannot write the file | returns `false`, Godot prints an error |
| `json_file_to_class` with a script, file missing or unreadable | a new instance with default values |
| `json_file_to_dict`, file missing, invalid JSON, or wrong key | `{}` (the last two also print an error) |
| `json_string_to_class` with invalid JSON | `null` |
| `json_to_class(null, json)` with no usable `script_inheritance` | a plain `Object` |
| The JSON names an unknown or unregistered script | the declared type of the variable is used, or plain data in untyped places |
| A key in the JSON that the class does not have | ignored |
| A variable missing from the JSON | keeps its default |

A robust load looks like this:

```gdscript
var path := "user://player.sav"
var player: PlayerData
if FileAccess.file_exists(path):
	player = ForgeJSONGD.json_file_to_class(PlayerData, path)
else:
	player = PlayerData.new() # first run
```

---

## Limits and things to know

* **Floats keep every digit.** They are written with the shortest text that reads back as the exact same number (`0.1` stays `0.1`, `3.141592653589793` is kept whole). Very large and very small numbers use exponent notation (`1e+20`), which is valid JSON.
* **Numbers are doubles.** Whole numbers above 2^53 (9,007,199,254,740,992) lose precision, because JSON has no integer type. Use text for such values (for example IDs).
* **Whole numbers come back as floats in untyped places.** In an untyped `Array`, `Dictionary` or `Variant`, `5` comes back as `5.0`. Typed variables (`int`, `Array[int]`, `Dictionary[String, int]`) convert back to `int`.
* **Untyped containers read number-like and bool-like text as values.** The text `"123"` in an untyped array comes back as the number `123.0`, and `"true"` as `true`. Use a typed container (`Array[String]`) to keep such text exactly.
* **Integer keys of untyped dictionaries become float keys.** `{1: "a"}` comes back as `{1.0: "a"}`, so `has(1)` is `false` and `has(1.0)` is `true`. `Dictionary[int, String]` keeps `int` keys.
* **Objects as dictionary keys** (`Dictionary[ClassA, ClassB]`) work, but JSON keys must be text, so the key is saved as the JSON text of the object (`"{ \"classAProperty\": \"ClassAText\" }"`). It loads back as an object.
* **One class per script, with a `class_name`.** Inner classes cannot be loaded by name. Renaming or moving a script file breaks files saved with its old name or path (it then loads as the declared type).
* **Equal data, different formats.** Files written by this version store `Rect2`, `PackedByteArray` and similar types as text (`"Rect2(1, 2, 3, 4)"`). Files written by older versions still load, but a `Rect2` or packed array stored as display text by an older version (for example `"[P: (1.0, 2.0), S: (3.0, 4.0)]"`) was never readable and is not converted.
* **Newer files in older addons.** Older versions of ForgeJSONGD read files from this version, and restore vectors, `Color`, `Rect2` and the other types they already knew. Packed arrays in untyped places stay as text there.
* **Nodes.** A class that extends `Node` works like any other class (only its script variables are saved). Children and built-in properties (position, name, ...) are not saved: save the data you need in script variables.
* **Global settings.** `only_exported_values` and the script registry are global: they apply to every call until you change them.

---

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| A child class loads as its parent | The child has no `class_name` and was moved, or the script is not registered ([registry](#security)), or in C# the class cache is stale ([C# builds](CSharp-Tutorial.md#building-and-running)). |
| A variable is not saved | It is a Godot property instead of a script variable, `only_exported_values` is `true` and it has no `@export`, the class excludes it with `_forge_excluded_properties`, or (C#) it has no `[Export]`. |
| Text like `"123"` turned into a number | It was in an untyped container. Use `Array[String]` / `Dictionary[String, String]`. |
| `has(1)` is `false` after loading a dictionary | Int keys of an untyped dictionary become floats. Use a typed `Dictionary[int, ...]`. |
| A `Rect2`/`Transform3D` is back to its default | The file was written as display text by an older version, or the variable was declared with a different type than the file. |
| `json_file_to_dict` returns `{}` | The file is missing, not valid JSON, or the key is wrong or missing for an encrypted file. |
| Loading an object whose `_init` needs arguments gives a plain `Object` and an error | Add `_forge_constructor_args`, or give the parameters default values. |
| `check_equal_jsons` says different for data that looks the same | Array order differs, or a value differs in type (`"1"` text vs `1` number). Key order and `1` vs `1.0` never matter. |
