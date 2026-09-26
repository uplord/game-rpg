extends ModalContent

@onready var capacity_label: Label = $Content/Header/Capacity
@onready var equipment_list: VBoxContainer = $Content/Equipment/EquipmentList
@onready var inventory_list: VBoxContainer = $Content/InventoryScroll/InventoryList
@onready var empty_label: Label = $Content/InventoryScroll/InventoryList/Empty

func _ready() -> void:
	if not GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.connect(_on_state_changed)
	_refresh()

func _exit_tree() -> void:
	if GameState.state_changed.is_connected(_on_state_changed):
		GameState.state_changed.disconnect(_on_state_changed)

func _on_state_changed(section: String) -> void:
	if section == "inventory" or section == "equipment" or section == "progression":
		_refresh()

func _refresh() -> void:
	for child in equipment_list.get_children():
		child.queue_free()
	for child in inventory_list.get_children():
		if child != empty_label:
			child.queue_free()

	var inventory := ItemService.get_inventory()
	capacity_label.text = "%d items" % _occupied_slots(inventory)
	empty_label.visible = inventory.is_empty()

	var equipment := ItemService.get_equipment()
	for slot in ItemService.EQUIPMENT_SLOTS:
		equipment_list.add_child(_make_equipment_row(slot, str(equipment.get(slot, ""))))

	for entry_value in inventory:
		if entry_value is Dictionary:
			inventory_list.add_child(_make_item_row(entry_value as Dictionary))

func _occupied_slots(inventory: Array) -> int:
	return inventory.size()

func _make_equipment_row(slot: String, item_id: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 34.0
	var slot_label := Label.new()
	slot_label.text = slot.replace("_", " ").capitalize()
	slot_label.custom_minimum_size.x = 110.0
	row.add_child(slot_label)
	var item_label := Label.new()
	item_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if item_id.is_empty():
		item_label.text = "Empty"
		item_label.modulate.a = 0.55
	else:
		var definition := ItemService.get_item_definition(item_id)
		item_label.text = str(definition.get("name", item_id))
	row.add_child(item_label)
	if not item_id.is_empty():
		var button := Button.new()
		button.text = "Unequip"
		button.pressed.connect(func(): ItemService.unequip(slot))
		row.add_child(button)
	return row

func _make_item_row(entry: Dictionary) -> Control:
	var item_id := str(entry.get("item_id", ""))
	var quantity := int(entry.get("quantity", 1))
	var definition := ItemService.get_item_definition(item_id)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 58.0
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var name_label := Label.new()
	name_label.text = str(definition.get("name", item_id)) + ("  ×%d" % quantity if quantity > 1 else "")
	name_label.add_theme_font_size_override("font_size", 14)
	info.add_child(name_label)
	var detail := Label.new()
	var requirement := ItemService.requirement_text(item_id)
	var category := str(definition.get("category", "item")).capitalize()
	detail.text = category if requirement.is_empty() else "%s  •  Requires %s" % [category, requirement]
	detail.modulate.a = 0.68
	info.add_child(detail)
	var slot := str(definition.get("equipment_slot", ""))
	if not slot.is_empty():
		var button := Button.new()
		button.text = "Equip"
		button.disabled = not ItemService.can_use_item(item_id)
		if button.disabled:
			button.tooltip_text = "Requires %s" % ItemService.requirement_text(item_id)
		button.pressed.connect(func(): ItemService.equip(item_id))
		row.add_child(button)
	return panel
