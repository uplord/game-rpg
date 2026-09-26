extends Node

signal inventory_changed
signal equipment_changed
signal bank_changed

const EQUIPMENT_SLOTS := ["helm", "armour", "cape", "main_hand", "off_hand"]

func get_item_definition(item_id: String) -> Dictionary:
	return ContentRepository.get_definition("item.%s" % item_id)

func get_item_definitions() -> Array[Dictionary]:
	var definitions := ContentRepository.get_definitions_by_type("item")
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("order", 9999)) < int(b.get("order", 9999))
	)
	return definitions

func get_inventory() -> Array:
	return GameState.inventory.duplicate(true)

func get_bank() -> Array:
	return GameState.bank.duplicate(true)

func get_equipment() -> Dictionary:
	return GameState.equipment.duplicate(true)

func get_quantity(item_id: String) -> int:
	for entry_value in GameState.inventory:
		if entry_value is Dictionary:
			var entry := entry_value as Dictionary
			if str(entry.get("item_id", "")) == item_id:
				return int(entry.get("quantity", 0))
	return 0

func can_use_item(item_id: String) -> bool:
	var definition := get_item_definition(item_id)
	if definition.is_empty():
		return false
	for requirement_value in definition.get("requirements", []):
		if requirement_value is Dictionary:
			var requirement := requirement_value as Dictionary
			if not SkillProgression.can_use(str(requirement.get("skill", "")), int(requirement.get("level", 1))):
				return false
	return true

func requirement_text(item_id: String) -> String:
	var definition := get_item_definition(item_id)
	var parts: Array[String] = []
	for requirement_value in definition.get("requirements", []):
		if requirement_value is Dictionary:
			var requirement := requirement_value as Dictionary
			parts.append("%s %d" % [str(requirement.get("skill", "")).capitalize(), int(requirement.get("level", 1))])
	return ", ".join(parts)

func add_item(item_id: String, quantity: int = 1, autosave: bool = true) -> bool:
	if quantity <= 0 or get_item_definition(item_id).is_empty():
		return false
	var definition := get_item_definition(item_id)
	var stackable := bool(definition.get("stackable", false))
	if stackable:
		for entry_value in GameState.inventory:
			if entry_value is Dictionary:
				var entry := entry_value as Dictionary
				if str(entry.get("item_id", "")) == item_id:
					entry["quantity"] = int(entry.get("quantity", 0)) + quantity
					_changed("inventory", autosave)
					return true
	GameState.inventory.append({"item_id": item_id, "quantity": quantity})
	_changed("inventory", autosave)
	return true

func remove_item(item_id: String, quantity: int = 1, autosave: bool = true) -> bool:
	if quantity <= 0:
		return false
	for index in range(GameState.inventory.size()):
		var entry_value: Variant = GameState.inventory[index]
		if entry_value is Dictionary:
			var entry := entry_value as Dictionary
			if str(entry.get("item_id", "")) == item_id:
				var current := int(entry.get("quantity", 0))
				if current < quantity:
					return false
				if current == quantity:
					GameState.inventory.remove_at(index)
				else:
					entry["quantity"] = current - quantity
				_changed("inventory", autosave)
				return true
	return false

func equip(item_id: String, autosave: bool = true) -> bool:
	var definition := get_item_definition(item_id)
	if definition.is_empty() or not can_use_item(item_id) or get_quantity(item_id) <= 0:
		return false
	var slot := str(definition.get("equipment_slot", ""))
	if slot.is_empty() or not slot in EQUIPMENT_SLOTS:
		return false
	var previous := str(GameState.equipment.get(slot, ""))
	if not remove_item(item_id, 1, false):
		return false
	if not previous.is_empty():
		add_item(previous, 1, false)
	GameState.equipment[slot] = item_id
	GameState.state_changed.emit("equipment")
	inventory_changed.emit()
	equipment_changed.emit()
	if autosave:
		GameState.save()
	return true

func unequip(slot: String, autosave: bool = true) -> bool:
	if not slot in EQUIPMENT_SLOTS:
		return false
	var item_id := str(GameState.equipment.get(slot, ""))
	if item_id.is_empty():
		return false
	GameState.equipment.erase(slot)
	add_item(item_id, 1, false)
	GameState.state_changed.emit("equipment")
	inventory_changed.emit()
	equipment_changed.emit()
	if autosave:
		GameState.save()
	return true

func get_equipped_tool(tool_type: String) -> Dictionary:
	for slot in ["main_hand", "off_hand"]:
		var item_id := str(GameState.equipment.get(slot, ""))
		if item_id.is_empty():
			continue
		var definition := get_item_definition(item_id)
		if str(definition.get("tool_type", "")) == tool_type:
			return definition
	return {}

func has_tool(tool_type: String, minimum_tier: int = 1) -> bool:
	var tool := get_equipped_tool(tool_type)
	return not tool.is_empty() and int(tool.get("tool_tier", 0)) >= minimum_tier

func _changed(section: String, autosave: bool) -> void:
	GameState.state_changed.emit(section)
	if section == "inventory":
		inventory_changed.emit()
	elif section == "bank":
		bank_changed.emit()
	if autosave:
		GameState.save()
