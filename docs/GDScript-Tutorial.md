# ForgeJSONGD: GDScript Tutorial

This guide covers everything ForgeJSONGD can do from GDScript. Using C#? Read the [C# Tutorial](CSharp-Tutorial.md) for setup and C# rules; the concepts below apply to both languages.

## Contents

1. [Your first save and load](#your-first-save-and-load)
2. [JSON for HTTP APIs](#json-for-http-apis)
3. [What is saved, and how](#what-is-saved-and-how)
4. [Method reference](#method-reference)
5. [Settings](#settings)
6. [Inheritance and polymorphism](#inheritance-and-polymorphism)
7. [Customizing a class](#customizing-a-class)
8. [Keeping saves working over time](#keeping-saves-working-over-time)
9. [Built-in types in `Variant` and untyped containers](#built-in-types-in-variant-and-untyped-containers)
   * [Numbers, text and keys stay exact](#numbers-text-and-keys-stay-exact)
10. [Enums](#enums)
11. [Resources](#resources)
12. [Security](#security)
13. [Comparing and patching JSON](#comparing-and-patching-json)
14. [Error handling](#error-handling)
15. [Limits and things to know](#limits-and-things-to-know)
16. [Troubleshooting](#troubleshooting)

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

## JSON for HTTP APIs

A class that you send to a web API, or receive from one (a DTO, a data transfer object), needs **standard JSON**: the API knows nothing about Godot. By default ForgeJSONGD writes a format made for game saves (a class name for child classes, markers that keep `5.0` apart from `5`, a prefix on text that looks like a Godot value...). To switch a class to standard JSON, add one method to it. Everything else is the same functions you already use:

```gdscript
# login_dto.gd
class_name LoginDto

var user_name: String = ""
var password: String = ""
var remember: bool = false
var attempts: int = 0


# This class talks to a web API: write and read it as standard JSON.
func _forge_plain_json() -> bool:
	return true


# The API calls the field "userName".
func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName"}
```

```gdscript
var login := LoginDto.new()
login.user_name = "ann"
login.password = "pw"
login.remember = true
login.attempts = 2

var body: String = ForgeJSONGD.class_to_json_string(login)
print(body) # {"attempts":2,"password":"pw","remember":true,"userName":"ann"}
```

Sending it, and reading the answer into another class, with an `HTTPRequest` node (a real round trip like this is run by `Tests/http.tscn`):

```gdscript
$HTTPRequest.request("https://example.com/login", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)

func _on_http_request_request_completed(result: int, code: int, headers: PackedStringArray, response: PackedByteArray) -> void:
	var user: UserDto = ForgeJSONGD.json_string_to_class(UserDto, response.get_string_from_utf8())
```

The class decides, so there is nothing to remember at each call, and the same functions serve both uses: a class that returns `true` from `_forge_plain_json` is plain, anything else is the exact format used for save files.

* **Everything inside a plain class is plain**: nested objects, arrays and dictionaries of objects, child classes, free-form `Dictionary` / `Variant` data.
* **A plain class is plain wherever it appears**, also inside a class that is not plain (a save file that holds the last server answer, for example). The class that is not plain stays exact.
* **The same data both ways:** make a small subclass that returns `false`: `class_name SavedUser` / `extends UserDto` / `func _forge_plain_json() -> bool: return false`.

### What a plain class writes

* **Only standard JSON.** No `script_inheritance`, `script_uid`, `script_constructor_args`, `forge_float`, `forge_int`, `forge_text:`, `forge_int:` or `forge_resource_path` is ever written (not even with `specify_class = true`), so a child class is written as plain data and the API gets exactly the fields you declared.
* **Numbers are plain numbers**: `5` stays `5` and `2.0` stays `2.0`, also in free-form `Dictionary` / `Array` / `Variant` data. A large int is a plain JSON number with every digit.
* **Text and dictionary keys are written as they are**, whatever they look like (`"123"`, `"true"`, `"Vector2(1, 2)"`). Number keys of a free-form dictionary are written as their text (`1` becomes `"1"`).
* **Vectors are `{"x": 1.0, "y": 2.0}`** (`{"x", "y", "z"}`, `{"x", "y", "z", "w"}` for the larger ones), **`Color` is its hex text** (`"ff0000ff"`), **enums are their name** (`"Admin"`), `null` is `null`.
* Types that have no standard JSON form (`Rect2`, `Transform3D`, packed arrays...) keep their [text form](#what-is-saved-and-how).
* `_forge_excluded_properties`, `_forge_json_keys`, `_forge_extra_properties` and `_forge_serialize` apply. Keys are sorted, or in the order of the variables if `ForgeJSONGD.sort_keys` is `false`.

### What a plain class accepts

Everything a server may send is data, never instructions:

* **A class name in the data is ignored.** `"script_inheritance"`, `"script_uid"` and `"script_constructor_args"` do nothing: the class is the one you declared (a variable declared `Address` is always an `Address`, a variable that already holds an object keeps that object's class). No script is created because a server asked for it.
* **No file is loaded.** A path like `"res://icon.svg"` sent for a `Texture2D` variable is not loaded.
* **Text is text.** `"Vector2(1, 2)"`, `"forge_text:abc"`, `"123"` or `"{\"a\": 1}"` arrive as that exact text, in String variables, `Array[String]` and in free-form data. Dictionary keys of free-form data stay text, as in JSON.
* **Free-form data is kept as sent**, including keys that look like markers (`{"forge_float": 3}` is just a dictionary). A whole number (`5` or `5.0`) is read as an `int`, others as `float`: JSON parsed by Godot cannot tell `5` from `5.0`.
* **Typed fields get their own type.** `{"id": 5.0}` fills an `int`, `{"score": 3}` fills a `float`, `{"zip": 54321}` fills a `String` (as `"54321"`), `{"position": {"x": 3, "y": 4}}` fills a `Vector2`, `"Admin"` or `5` fills an enum, and a large id sent as text (`"9007199254740993"`) fills an `int` exactly.
* **Missing, null and unknown.** A field the server leaves out, or sends as `null`, keeps its default. A field your class does not have is ignored. Data of the wrong shape (text for an array, a number for an object) is skipped and the field keeps its default. An empty object (`{}`) creates the declared object with its defaults. A `null` or wrong element inside an `Array[Dto]` becomes `null`.
* **Older names.** `_forge_renamed_properties` and a variable's own name are accepted besides its `_forge_json_keys` key (the key wins when both are present).

One limit comes from Godot, not from ForgeJSONGD: **Godot's JSON parser reads a JSON number above 2^53 as a double**, so `{"id": 9007199254740993}` arrives as `9007199254740992`. When a server sends 64-bit ids, ask for them as text (`"id": "9007199254740993"`), which is exact. Sending is not affected: an `int` is always written with every digit.

### Child classes

A plain class written with a child class holds no class name, so the receiving side loads it as the class it declares:

```gdscript
# ApiZoo is a Zoo that returns true from _forge_plain_json
var text := ForgeJSONGD.class_to_json_string(zoo)               # a Dog is written with its own variables, no "script_inheritance"
var loaded: ApiZoo = ForgeJSONGD.json_string_to_class(ApiZoo, text) # loads as the declared Animal
```

If the receiver needs the real class, use a class that is not plain (it keeps the class name) or add a field of your own that says the kind.

### Reading data you do not trust

Always pass the class you expect: `json_to_class(UserDto, data)`. With `null` as the class (`json_to_class(null, data)`) the class is taken from the data itself, which is what you want for your own save files and never for data from outside. Even then, the [allow-list](#security) limits what can be created. Constructor arguments stored in the data are only used by a class that defines `_forge_constructor_args`.

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

Numbers keep their type: an `int` comes back as an `int` and a `float` as a `float`, in typed and untyped places alike. See [Numbers, text and keys stay exact](#numbers-text-and-keys-stay-exact).

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
var json_dictionary: Dictionary = ForgeJSONGD.convert_dictionary_to_json({"main": dog, "pet": cat})
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

### Plain JSON for web APIs

There are no separate functions: a class that returns `true` from `_forge_plain_json` is written and read as standard JSON by the functions above. See [JSON for HTTP APIs](#json-for-http-apis).

### Script registry

`register_script(script)`, `register_scripts(scripts)` and `clear_registered_scripts()` are covered in [Security](#security). `register_script_alias(script, alias, save_as = true)` and `clear_script_aliases()` are covered in [Keeping saves working over time](#keeping-saves-working-over-time).

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

Two more settings control the text that is written (they apply to files and to JSON text):

```gdscript
ForgeJSONGD.json_indent = ""   # indentation of files written by store_json_file: "\t" (default), "  " for spaces, "" for compact files
ForgeJSONGD.sort_keys = false  # true (default): keys in alphabetical order. false: keys in the order of the variables in the class
```

`json_indent` only applies to `store_json_file` (JSON text from `class_to_json_string` is always compact). Both are global settings and reading is not affected: any indentation and key order loads.

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

* **Give child classes a `class_name`.** The name is how the class is found when loading. A script without `class_name` is found by its path (`res://...`), and ForgeJSONGD also stores its uid (`"script_uid"`), so it is still found if you move the file.
* **Classes declared inside another script** (an inner `class`) have no name or path of their own, so they are found through the script that uses them: a variable, `Array[Inner]` or `Dictionary[String, Inner]` declared with an inner class loads, and a variable of the owner that holds a child inner class is saved as `"::Inner"` and loads too. An inner class cannot be found by name anywhere else (for example by `json_to_class(null, json)` or in an untyped container). Put classes you need there in their own file.
* **A class that no longer exists** (you deleted or renamed it after saving) loads as the declared type of the variable, keeping the data that fits. In an untyped container or `Variant`, which has no declared type, the data stays a plain dictionary.
* **Variables of the child** are only saved and loaded if they are script variables (`@export` only, if `only_exported_values` is on).

---

## Customizing a class

A class can define any of these optional methods. They all start with `_forge_`, so they will not clash with your own methods. Classes that do not define them behave as usual.

| Method | What it does |
|---|---|
| `func _forge_excluded_properties() -> Array` | Names of variables to skip when saving **and** loading. |
| `func _forge_extra_properties() -> Array` | Names of built-in properties (`position`, `rotation`...) to save and load too, besides the script variables. |
| `func _forge_json_keys() -> Dictionary` | `{"variable_name": "jsonKey"}`: the key a variable uses in the JSON. For API field names. |
| `func _forge_renamed_properties() -> Dictionary` | `{"old_name": "new_name"}`: old saves still load into a renamed variable. |
| `func _forge_plain_json() -> bool` | Return `true` for a class that talks to a web API: it is written and read as [standard JSON](#json-for-http-apis). |
| `func _forge_save_by_path() -> bool` | For `Resource` classes: a resource that comes from a file is saved as its path. |
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

The arguments are saved under `"script_constructor_args"`. On load, ForgeJSONGD creates the object with those arguments, then loads the variables. Stored arguments are only passed to a class that defines `_forge_constructor_args` itself, so a file cannot choose the arguments of any other class. Without this method, a class with required `_init` parameters cannot be created: Godot prints an error and you get a plain `Object` back.

### Saving built-in properties such as `position`

By default only script variables are saved, so a `Node2D` loses its `position`. List the built-in properties to save too:

```gdscript
class_name SpriteState
extends Node2D

var health: int = 10


# Besides the script variables, save where the node is.
func _forge_extra_properties() -> Array:
	return ["position", "rotation", "scale", "modulate"]
```

They are saved and loaded like script variables (vectors as text, `Color` as hex...). Properties that are not in the list stay untouched.

### Other names in the JSON

`_forge_json_keys` gives a variable another key in the JSON. Typically the field names of an API:

```gdscript
func _forge_json_keys() -> Dictionary:
	return {"user_name": "userName", "big_id": "bigId"}
```

The key is written, and read back. The variable's own name is also accepted when loading (the key wins if both are in the JSON). It works in plain classes too. In C# use the member names: `{ "UserName", "userName" }`.

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

## Keeping saves working over time

Files outlive the code that wrote them. Three tools keep old saves loading after you rename or move things.

### Renamed variables

```gdscript
class_name RenamedModel

# Was called "name" and then "title" in older versions.
var display_name: String = "default"
var level: int = 1


func _forge_renamed_properties() -> Dictionary:
	return {"name": "display_name", "title": "display_name"}
```

Old files that hold `"name"` or `"title"` load into `display_name`. Saving always writes the current name, and when a file holds both an old and the current name, the current one wins.

### Renamed or moved classes: script aliases

A class is saved under its `class_name`, so renaming the class breaks files that name the old one. An alias is a stable name you choose and keep:

```gdscript
# Once, at startup:
ForgeJSONGD.register_script_alias(Dog, "dog_v1")
ForgeJSONGD.register_script_alias(Cat, "cat_v1")
```

From then on `Dog` is saved as `"script_inheritance": "dog_v1"` and loaded from it, whatever the class is called in the code. For a class you already renamed, add the **old name** as a load-only alias:

```gdscript
ForgeJSONGD.register_script_alias(Dog, "Hound", false) # old files that say "Hound" load as Dog, but "Hound" is never written

ForgeJSONGD.clear_script_aliases() # removes all aliases again
```

Aliases are separate from the [allow-list](#security): registering an alias does not restrict anything, but with an allow-list active the script must still be registered.

### Scripts without a class_name

A script without `class_name` is saved by its path. ForgeJSONGD also stores its uid (`"script_uid"`), so the script is found again if you move the file in the editor. With an alias, only the alias is stored.

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

## Numbers, text and keys stay exact

JSON itself has a single number type and only text keys, and Godot's parser returns every number as a float. ForgeJSONGD works around this so that what you load is what you saved. The file stays readable: only the rare cases below get a marker.

**Numbers.**

* An `int` is written as a plain number and loaded as an `int`, a fractional `float` (`2.5`) as a `float`, in typed and untyped places.
* In an untyped place (`Variant`, untyped `Array` / `Dictionary`) a **whole-number float** (`5.0`) would be indistinguishable from an `int`, so it is written as `{"forge_float": 5.0}`. In typed places (`float`, `Array[float]`) it is a plain number.
* An `int` of 2^53 (9,007,199,254,740,992) or more cannot be a JSON number without losing digits. It is written as text: `"9007199254740993"` in a typed place and `{"forge_int": "9007199254740993"}` in an untyped place, and loads back exactly (also in `Array[int]`, `Dictionary[String, int]` and `PackedInt64Array`).
* Floats are written with the shortest text that reads back as the exact same number (`0.1` stays `0.1`, `3.141592653589793` is kept whole). Very large and very small numbers use exponent notation (`1e+20`), which is valid JSON.

**Text.** Text is never turned into something else. Text that would be mistaken for another value is written with the prefix `forge_text:` and loses it again on load: Godot values (`"Vector2(1, 2)"`, `"Rect2(1, 2, 3, 4)"`, `"PackedByteArray(1, 2)"`...) and text that already starts with the prefix. Number-like, bool-like and JSON-like text (`"123"`, `"true"`, `"[1, 2]"`) stays plain text, in String variables, `Array[String]`, untyped containers and `Variant`. Ordinary text is written as is.

**Dictionary keys.** JSON keys are always text. Text keys are written as they are, so an ordinary dictionary (including `{"123": ...}` or `{"true": ...}`) is never changed. In an **untyped** dictionary a key that is not text gets a tag that says its type, and text that could be mistaken for a tag or a Godot value is escaped:

| Key | Written as | Loads as |
|---|---|---|
| `"plain"`, `"123"`, `"true"`, `"1.5"` (text) | the same text | text |
| `1`, `-7`, `9007199254740993` | `"forge_int:1"`, `"forge_int:-7"`, `"forge_int:9007199254740993"` | `int` |
| `1.5` | `"forge_float:1.5"` | `float` |
| `true` | `"forge_bool:true"` | `bool` |
| `Vector2(3, 4)` | `"Vector2(3, 4)"` | `Vector2` |
| `"Vector2(1, 2)"`, `"forge_int:5"` (text that looks like a Godot value or a tag) | `"forge_text:Vector2(1, 2)"`, `"forge_text:forge_int:5"` | text |

In a typed dictionary the key type is known (`Dictionary[int, String]`, `Dictionary[String, int]`), so its keys are plain text and load by that type.

**Files written by older versions** still load. Whole numbers that older versions wrote as `5.0` in untyped places load as `int` now (they could not be told apart), and `Rect2`, `AABB`, `Plane`, `Quaternion`, `Basis`, `Transform2D/3D`, `Projection` and packed arrays that older versions wrote as display text (for example `"[P: (1.0, 2.0), S: (3.0, 4.0)]"`) are read back too, with the precision of that text (about 6 digits).

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
* A resource class can ask to be saved **as its path even from a `.tres` file**, so a save points at the item file instead of holding a copy, and every reference loads the same shared instance:

```gdscript
class_name ItemResource
extends Resource

@export var item_name: String = ""


# A save should point at the item file, not hold a copy of it.
func _forge_save_by_path() -> bool:
	return true
```

A resource of such a class that comes from a file is saved as its path in variables and typed containers (`{"forge_resource_path": "<path>"}` in untyped places), and loaded again with `ResourceLoader`, so changes to the item file show in old saves. A resource that was never saved to a file is still saved inline. The [allow-list](#security) applies, and a plain class never loads files.
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

**Data from outside.** Always pass the class you expect (`json_to_class(UserDto, data)`). With `null` as the class the data chooses the class. A class that returns `true` from [`_forge_plain_json`](#json-for-http-apis) never takes a class name, a file path or any other instruction from its data.

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

* **Inner classes are found through their owner.** See the [inheritance rules](#rules-to-keep-in-mind). They cannot be found by name outside the script that declares them.
* **Objects as dictionary keys** (`Dictionary[ClassA, ClassB]`) work, but JSON keys must be text, so the key is saved as the JSON text of the object (`"{ \"classAProperty\": \"ClassAText\" }"`). It loads back as an object.
* **Files from this version in older addons.** Older versions of ForgeJSONGD read files from this version, and restore vectors, `Color`, `Rect2` and the other types they already knew. Packed arrays in untyped places stay as text there, and the number markers (`forge_float`, `forge_int`) show up as small dictionaries.
* **Objects without a script, `Callable` and `RID`** cannot be rebuilt (see [What is saved, and how](#what-is-saved-and-how)).
* **Nodes.** A class that extends `Node` works like any other class (only its script variables are saved). Children and built-in properties (position, name, ...) are not saved: save the data you need in script variables.
* **Global settings.** `only_exported_values` and the script registry are global: they apply to every call until you change them.
* **A class whose `_init` needs arguments** needs `_forge_constructor_args` (see [Customizing a class](#customizing-a-class)).

---

## Troubleshooting

| Problem | Likely cause and fix |
|---|---|
| A child class loads as its parent | The child has no `class_name` and was moved, or the script is not registered ([registry](#security)), or in C# the class cache is stale ([C# builds](CSharp-Tutorial.md#building-and-running)). |
| A variable is not saved | It is a Godot property instead of a script variable, `only_exported_values` is `true` and it has no `@export`, the class excludes it with `_forge_excluded_properties`, or (C#) it has no `[Export]`. |
| A `Rect2`/`Transform3D` is back to its default | The variable was declared with a different type than the file holds, or the text in the file is not a form ForgeJSONGD knows. |
| An API receives `forge_float`, `script_inheritance`... in the JSON | Add `func _forge_plain_json() -> bool: return true` to the class. See [JSON for HTTP APIs](#json-for-http-apis). |
| A field of the API is missing or has another name in my class | Give the variable the API's key with `_forge_json_keys`. |
| Saves stopped loading after I renamed a class or a variable | Register an alias for the class, or `_forge_renamed_properties` for the variable. See [Keeping saves working over time](#keeping-saves-working-over-time). |
| `position` / `rotation` of a node are not saved | They are built-in properties: list them in `_forge_extra_properties`. |
| `json_file_to_dict` returns `{}` | The file is missing, not valid JSON, or the key is wrong or missing for an encrypted file. |
| Loading an object whose `_init` needs arguments gives a plain `Object` and an error | Add `_forge_constructor_args`, or give the parameters default values. |
| `check_equal_jsons` says different for data that looks the same | Array order differs, or a value differs in type (`"1"` text vs `1` number). Key order and `1` vs `1.0` never matter. |
