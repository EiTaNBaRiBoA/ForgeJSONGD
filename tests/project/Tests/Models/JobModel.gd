## Enums made with @export_enum: without values, with values, mixed, and on a String.
class_name JobModel extends RefCounted

@export_enum("Warrior", "Mage", "Thief") var job: int = 0
@export_enum("Slow:30", "Average:60", "Very Fast:200") var speed: int = 30
@export_enum("Low:5", "Next", "After") var mixed: int = 5
@export_enum("Rebecca", "Mary", "Leah") var hero: String = "Rebecca"
