extends Node

const SAVE_VERSION := 1
const SAVE_PATH := "user://savegame.json"

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func load_game() -> Dictionary:
	if not has_save():
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("[Uplord][Persistence] Could not open local save file.")
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[Uplord][Persistence] Local save is invalid; using a new character state.")
		return {}

	var data: Dictionary = parsed
	if int(data.get("save_version", 0)) != SAVE_VERSION:
		push_warning("[Uplord][Persistence] Save version does not match the current local schema.")
	return data

func save_game(state: Dictionary) -> bool:
	var payload := state.duplicate(true)
	payload["save_version"] = SAVE_VERSION

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("[Uplord][Persistence] Could not write local save file.")
		return false

	file.store_string(JSON.stringify(payload, "  "))
	return true

func delete_save() -> bool:
	if not has_save():
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH)) == OK
