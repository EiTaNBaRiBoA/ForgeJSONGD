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
