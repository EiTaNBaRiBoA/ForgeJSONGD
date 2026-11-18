class_name ApiScoreboard
extends Scoreboard


# The same class as Scoreboard, but written and read as standard JSON.
func _forge_plain_json() -> bool:
	return true
