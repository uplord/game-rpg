extends ModalContent

@onready var total_level_label: Label = $Content/Summary/TotalLevel
@onready var skill_list: VBoxContainer = $Content/Scroll/SkillList

func _ready() -> void:
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	_refresh()

func _exit_tree() -> void:
	if GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.disconnect(_on_state_changed)

func _on_state_changed(section: String) -> void:
	if section == "progression" or section == "character":
		_refresh()

func _refresh() -> void:
	total_level_label.text = "Total level  %d" % SkillProgression.get_total_level()
	for child in skill_list.get_children():
		child.queue_free()
	for definition in SkillProgression.get_skill_definitions():
		if bool(definition.get("enabled", true)):
			skill_list.add_child(_make_skill_row(definition))

func _make_skill_row(definition: Dictionary) -> Control:
	var skill_id := str(definition.get("skill_id", ""))
	var level := SkillProgression.get_level(skill_id)
	var xp := SkillProgression.get_xp(skill_id)
	var needed := SkillProgression.xp_needed_for_next_level(skill_id)
	var into_level := SkillProgression.xp_into_level(skill_id)
	var next_unlock := SkillProgression.get_next_unlock(skill_id)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, 92.0)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var name_label := Label.new()
	name_label.text = str(definition.get("name", skill_id.capitalize()))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	header.add_child(name_label)
	var level_label := Label.new()
	level_label.text = "Level %d" % level
	header.add_child(level_label)

	var progress := ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12.0
	progress.max_value = 1.0
	progress.value = SkillProgression.progress_to_next_level(skill_id)
	box.add_child(progress)

	var detail := Label.new()
	if level >= SkillProgression.MAX_LEVEL:
		detail.text = "%s XP  •  MAX LEVEL" % _format_number(xp)
	else:
		detail.text = "%s / %s XP to Level %d" % [_format_number(into_level), _format_number(needed), level + 1]
	box.add_child(detail)

	var unlock_label := Label.new()
	if next_unlock.is_empty():
		unlock_label.text = "All current unlocks reached"
	else:
		unlock_label.text = "Next unlock: Lv %d  %s" % [int(next_unlock.get("level", 1)), str(next_unlock.get("name", "Unlock"))]
	unlock_label.modulate.a = 0.72
	box.add_child(unlock_label)
	return panel

func _format_number(value: int) -> String:
	var raw := str(value)
	var output := ""
	var count := 0
	for i in range(raw.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			output = "," + output
		output = raw[i] + output
		count += 1
	return output
