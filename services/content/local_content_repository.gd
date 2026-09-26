extends Node

const DEFINITION_ROOT := "res://data/definitions"

var _definitions: Dictionary = {}

func _ready() -> void:
	reload()

func reload() -> void:
	_definitions.clear()
	_load_directory(DEFINITION_ROOT)
	print("[Uplord][Content] Loaded %d local definitions." % _definitions.size())

func get_definition(definition_id: String) -> Dictionary:
	return _definitions.get(definition_id, {}).duplicate(true)

func has_definition(definition_id: String) -> bool:
	return _definitions.has(definition_id)

func get_definitions_by_type(definition_type: String) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	for definition: Dictionary in _definitions.values():
		if str(definition.get("type", "")) == definition_type:
			matches.append(definition.duplicate(true))
	return matches

func _load_directory(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full_path := path.path_join(entry)
			if dir.current_is_dir():
				_load_directory(full_path)
			elif entry.get_extension().to_lower() == "json":
				_load_definition_file(full_path)
		entry = dir.get_next()
	dir.list_dir_end()

func _load_definition_file(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[Uplord][Content] Could not read %s" % path)
		return

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[Uplord][Content] Invalid definition JSON: %s" % path)
		return

	var definition: Dictionary = parsed
	var definition_id := str(definition.get("id", ""))
	if definition_id.is_empty():
		push_warning("[Uplord][Content] Definition has no id: %s" % path)
		return
	if _definitions.has(definition_id):
		push_warning("[Uplord][Content] Duplicate definition id: %s" % definition_id)
		return

	_definitions[definition_id] = definition
