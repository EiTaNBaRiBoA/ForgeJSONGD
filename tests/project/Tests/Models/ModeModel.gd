class_name ModeModel extends RefCounted

enum Mode { FAST_MODE, SLOW_MODE = 5, VERY_SLOW_MODE = 7 }

@export var mode: Mode = Mode.FAST_MODE
