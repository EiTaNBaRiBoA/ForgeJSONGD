# ForgeJSONGD tests

The tests are a Godot .NET project of their own, in `tests/project` (scenes, test classes, the C#
tests). Its `.gdignore` keeps a Godot project that holds this whole repository from loading the
test classes.

## Running the tests

You need the .NET build of Godot (`Godot_v4.7.2-stable_mono`) and the .NET SDK. From the repository
root, one command makes a working copy of the test project in a temporary folder (with this
repository's addon at `addons/ForgeJSONGD`), builds the C# project, imports it and runs every scene:

```powershell
.\run_tests.ps1 -Godot "C:\path\to\Godot_v4.7.2-stable_mono_win64_console.exe"
```

`-WorkDir <folder>` chooses where the working copy goes. The script exits with code 1 if any scene
fails.

To also run the official [JSON Schema Test Suite](https://github.com/json-schema-org/JSON-Schema-Test-Suite) against `validate_json`, clone it anywhere and pass its `validation/tests` folder:

```powershell
git clone --depth 1 https://github.com/json-schema-org/JSON-Schema-Test-Suite.git C:\temp\JSON-Schema-Test-Suite
.\run_tests.ps1 -SchemaSuite C:\temp\JSON-Schema-Test-Suite\validation\tests
```

Each scene runs its assertions on `_ready` and prints `PASS` / `FAIL` lines plus a summary (helper:
`tests/project/Tests/TestUtil.gd`). To run one scene by hand, open the working copy the script made,
build and import it (see [Building and running](../docs/CSharp-Tutorial.md#building-and-running)), then:

```
godot_mono --headless --path <working copy> res://Scenes/main.tscn --quit-after 30
```

## What each scene covers

| Scene | Covers |
|---|---|
| `Scenes/main.tscn` | Full round trip, encryption, JSON strings, equality/diff and every `Operation` |
| `EnumAndDictionary/enum.tscn` | Enums with default and custom values |
| `Inheritence/test.tscn` | Inheritance and polymorphism: children in parent-typed properties, and parents and children mixed in typed/untyped arrays, typed/untyped dictionaries and nested objects |
| `Typed Dictionary/Typed.tscn` | Typed dictionaries, typed arrays, object keys |
| `Tests/features.tscn` | Built-in types in `Variant`/untyped containers and as typed variables, `_forge_` hooks (excluded properties, constructor arguments, custom serialization), the script registry |
| `Tests/regression.tscn` | Scenarios fixed in the addon's history: enum names, numeric-looking strings in typed containers, loading without a type hint, `only_exported_values`, `.tres` resources, unsafe `str_to_var` strings, files and encryption, compare/operation edge cases |
| `Tests/behaviors.tscn` | Behaviors and limits the guides describe: number precision, untyped containers, export modes, failure results, public helpers, the registry with resources, unknown scripts |
| `Tests/behaviors_more.tscn` | Resources in arrays and dictionaries, unsupported values (`Callable`, `RID`, objects without a script), empty and non-object files, enum details, equality details |
| `Tests/docs_examples.tscn` | Every code example of the GDScript guide, run for real (classes in `Tests/Docs/`) |
| `Tests/exactness.tscn` | Numbers, text, dictionary keys, moved scripts and inner classes come back exactly as saved |
| `Tests/dto.tscn` | JSON for HTTP APIs: a class that returns true from `_forge_plain_json` writes standard JSON, reads what a server sends (nulls, wrong shapes, hostile class names and paths), and classes that are not plain stay exact |
| `Tests/http.tscn` | A real HTTP round trip: an `HTTPRequest` posts a DTO to a small server running inside the scene, and the server records the exact bytes it received |
| `Tests/robustness.tscn` | Data of an unexpected shape (not an object, wrong types), members that already hold an object, empty objects, odd class names and keys, stored constructor arguments, speed with many objects, enums made with `@export_enum` (with and without values), and hooks that return the wrong type |
| `Tests/fidelity.tscn` | The whole chain on real files for 13 kinds of data (save-file format, plain API format, every built-in type, shared objects, resources): create the file, load it, compare it with the original and the loaded object, save again and get an identical file, and make sure a change is reported exactly |
| `Tests/validation.tscn` | `validate_json` and `class_to_json_schema`: every supported keyword, the ways to pass data and schemas, the problems reported (paths, messages, broken schemas, unsupported keywords, `$ref` that loops or points outside), class schemas (JSON keys, plain and save-file forms, enums, nested and recursive classes, child classes, `_forge_schema` rules), and that every data class of the project (GDScript and C#) accepts what `class_to_json` writes for it |
| `Tests/schema_suite.tscn` | Only with `-SchemaSuite`: the official JSON Schema Test Suite for draft 2020-12. The other schemas a test refers to are given with `register_schema`. Tests that use an unsupported keyword, a JSON Schema meta-schema, or `format` as an assertion are counted as skipped; failing optional tests print `KNOWN ISSUE` |
| `Tests/options.tscn` | Script aliases, resources saved by path, extra built-in properties, renamed variables, indent and key order settings |
| `CSharp/csharp_test.tscn` | C#: the `Forge.cs` wrapper and raw `Call` route, C# class shapes (arrays and dictionaries of custom classes, native C# arrays, enums, numbers, Godot structs, `Resource` classes, `Variant`), child classes, the `_forge_` hooks from C#, the registry, encryption, the one-class-per-file rule, validation with a C# class and its `_forge_schema` |

`Tests/behaviors_more.tscn` prints one `SCRIPT ERROR` on purpose: it loads a class whose `_init` needs arguments and has no `_forge_constructor_args`, which the guide documents as an error. `Tests/robustness.tscn` prints five: it saves and loads a class whose hooks return the wrong type, to make sure such a mistake cannot change how other classes are saved afterwards.

`TestUtil.known_issue()` records an addon bug that is not fixed yet: it prints `KNOWN ISSUE` and never fails the run, and prints `FIXED (promote to check)` once it passes. There are none at the moment. (`Tests/schema_suite.tscn` uses it for the optional tests of the official suite that it does not pass: numbers with more digits than a double holds, which Godot's JSON parser cannot keep, and schemas that ask to be read by the rules of an older draft.)
