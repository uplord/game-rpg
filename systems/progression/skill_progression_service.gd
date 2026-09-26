extends Node

signal skill_xp_gained(skill_id: String, amount: int, new_xp: int)
signal skill_level_changed(skill_id: String, old_level: int, new_level: int)
signal skill_unlocked(skill_id: String, unlock: Dictionary)

const MAX_LEVEL := 99
const START_LEVEL := 1

func get_skill_definitions() -> Array[Dictionary]:
	var definitions := ContentRepository.get_definitions_by_type("skill")
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 999)) < int(b.get("order", 999))
	)
	return definitions

func get_skill_definition(skill_id: String) -> Dictionary:
	return ContentRepository.get_definition("skill.%s" % skill_id)

func get_skill(skill_id: String) -> Dictionary:
	var state: Dictionary = GameState.progression.get(skill_id, {})
	return {
		"level": int(state.get("level", START_LEVEL)),
		"xp": int(state.get("xp", 0)),
	}

func get_level(skill_id: String) -> int:
	return int(get_skill(skill_id).get("level", START_LEVEL))

func get_xp(skill_id: String) -> int:
	return int(get_skill(skill_id).get("xp", 0))

func get_total_level() -> int:
	var total := 0
	for definition in get_skill_definitions():
		if bool(definition.get("enabled", true)):
			total += get_level(str(definition.get("skill_id", "")))
	return total

func xp_for_level(level: int) -> int:
	# Cumulative XP curve. Level 1 starts at 0 XP and level 99 is the cap.
	var clamped_level := clampi(level, START_LEVEL, MAX_LEVEL)
	if clamped_level <= START_LEVEL:
		return 0
	return int(round(100.0 * pow(float(clamped_level - 1), 1.65)))

func level_for_xp(xp: int) -> int:
	var safe_xp := maxi(xp, 0)
	for level in range(START_LEVEL + 1, MAX_LEVEL + 1):
		if safe_xp < xp_for_level(level):
			return level - 1
	return MAX_LEVEL

func xp_into_level(skill_id: String) -> int:
	var level := get_level(skill_id)
	return get_xp(skill_id) - xp_for_level(level)

func xp_needed_for_next_level(skill_id: String) -> int:
	var level := get_level(skill_id)
	if level >= MAX_LEVEL:
		return 0
	return xp_for_level(level + 1) - xp_for_level(level)

func progress_to_next_level(skill_id: String) -> float:
	var needed := xp_needed_for_next_level(skill_id)
	if needed <= 0:
		return 1.0
	return clampf(float(xp_into_level(skill_id)) / float(needed), 0.0, 1.0)

func can_use(skill_id: String, required_level: int) -> bool:
	return get_level(skill_id) >= required_level

func add_xp(skill_id: String, amount: int, autosave: bool = true) -> Dictionary:
	if amount <= 0 or get_skill_definition(skill_id).is_empty():
		return get_skill(skill_id)

	var old_level := get_level(skill_id)
	var old_xp := get_xp(skill_id)
	var max_xp := xp_for_level(MAX_LEVEL)
	var new_xp := mini(old_xp + amount, max_xp)
	var new_level := level_for_xp(new_xp)
	GameState.progression[skill_id] = {"level": new_level, "xp": new_xp}
	GameState.state_changed.emit("progression")
	skill_xp_gained.emit(skill_id, new_xp - old_xp, new_xp)

	if new_level > old_level:
		skill_level_changed.emit(skill_id, old_level, new_level)
		_emit_new_unlocks(skill_id, old_level, new_level)

	if autosave:
		GameState.save()
	return get_skill(skill_id)

func get_unlocks(skill_id: String) -> Array[Dictionary]:
	var definition := get_skill_definition(skill_id)
	var result: Array[Dictionary] = []
	for value in definition.get("unlocks", []):
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("level", 1)) < int(b.get("level", 1))
	)
	return result

func get_next_unlock(skill_id: String) -> Dictionary:
	var current_level := get_level(skill_id)
	for unlock in get_unlocks(skill_id):
		if int(unlock.get("level", 1)) > current_level:
			return unlock
	return {}

func _emit_new_unlocks(skill_id: String, old_level: int, new_level: int) -> void:
	for unlock in get_unlocks(skill_id):
		var required := int(unlock.get("level", 1))
		if required > old_level and required <= new_level:
			skill_unlocked.emit(skill_id, unlock.duplicate(true))
