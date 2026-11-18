extends Node
class_name Model


@export var modelName : String
@export var modelID : int
@export var modelVector2 : Vector2
@export var modelVector3 : Vector3
@export var arrayOfVectors : Array
@export var arrayOfColors : Array[Color]
@export var arrayOfVectors2 : Array[Vector2]
# Basic Types
@export var bool_var: bool = false
@export var int_var: int = 42
@export var float_var: float = 3.14159
@export var string_var: String = "Hello, Godot!"

# Vector Types
@export var vector2_var: Vector2 = Vector2(1, 2)
@export var vector3_var: Vector3 = Vector3(1, 2, 3)
@export var vector4_var: Vector4 = Vector4(1, 2, 3, 4)

# Color
@export var color_var: Color = Color(1, 0, 0, 1) # Red

# NodePath
@export var nodepath_var: NodePath = NodePath("")

# Resources
@export var texture_var: Texture = null
@export var material_var: Material = null
@export var mesh_var: Mesh = null

# Enums
enum MyEnum {
	OPTION_A,
	OPTION_B,
	OPTION_C
}
@export var enum_var: MyEnum = MyEnum.OPTION_A

# Arrays
@export var int_array_var: Array[int]
@export var string_array_var: Array[String]

# Dictionaries
@export var dictionary_var: Dictionary 
@export var arrayOfInnerModels : Array
