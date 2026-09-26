extends Node

## Single-player character-facing API. Gameplay/UI should use this service instead
## of writing GameState dictionaries directly. A later online implementation can
## route the same requests to the authoritative game server.

func get_character() -> Dictionary:
	return GameState.character.duplicate(true)

func get_progression() -> Dictionary:
	return GameState.progression.duplicate(true)

func get_gold() -> int:
	return GameState.gold

func get_total_level() -> int:
	return SkillProgression.get_total_level()

func set_character_name(value: String) -> void:
	var cleaned := value.strip_edges()
	if cleaned.is_empty():
		return
	GameState.character["name"] = cleaned
	GameState.state_changed.emit("character")

func save() -> bool:
	return GameState.save()
