extends Node

signal state_loaded
signal state_changed(section: String)

const DEFAULT_AREA_ID := "area.starter_town"
const DEFAULT_SPAWN_ID := "default"

var character: Dictionary = {}
var progression: Dictionary = {}
var inventory: Array = []
var equipment: Dictionary = {}
var learned_skills: Array = []
var skill_loadouts: Dictionary = {}
var quests: Dictionary = {}
var gold: int = 0
var world: Dictionary = {}

func _ready() -> void:
    load_or_create()

func load_or_create() -> void:
    var saved: Dictionary = LocalSave.load_game()
    if saved.is_empty():
        _apply_new_game_defaults()
        save()
    else:
        _apply_save(saved)
    state_loaded.emit()

func save() -> bool:
    return LocalSave.save_game(to_save_data())

func reset_to_new_game() -> void:
    _apply_new_game_defaults()
    save()
    state_loaded.emit()

func to_save_data() -> Dictionary:
    return {
        "character": character.duplicate(true),
        "progression": progression.duplicate(true),
        "inventory": inventory.duplicate(true),
        "equipment": equipment.duplicate(true),
        "learned_skills": learned_skills.duplicate(true),
        "skill_loadouts": skill_loadouts.duplicate(true),
        "quests": quests.duplicate(true),
        "gold": gold,
        "world": world.duplicate(true),
    }

func set_world_location(area_id: String, spawn_id: String = DEFAULT_SPAWN_ID) -> void:
    world["area_id"] = area_id
    world["spawn_id"] = spawn_id
    state_changed.emit("world")

func _apply_new_game_defaults() -> void:
    character = {
        "id": "local_character",
        "name": "Adventurer",
        "level": 1,
        "xp": 0,
        "hp": 100,
        "mp": 100,
        "max_health": 100,
        "max_mana": 100,
    }
    progression = {
        "combat": {"level": 1, "xp": 0},
        "mining": {"level": 1, "xp": 0},
        "woodcutting": {"level": 1, "xp": 0},
        "fishing": {"level": 1, "xp": 0},
        "smithing": {"level": 1, "xp": 0},
        "cooking": {"level": 1, "xp": 0},
        "woodworking": {"level": 1, "xp": 0},
        "crafting": {"level": 1, "xp": 0},
    }
    inventory = []
    equipment = {}
    learned_skills = []
    skill_loadouts = {
        "combat": [],
        "mining": [],
        "woodcutting": [],
        "fishing": [],
    }
    quests = {}
    gold = 0
    world = {
        "area_id": DEFAULT_AREA_ID,
        "spawn_id": DEFAULT_SPAWN_ID,
    }

func _apply_save(saved: Dictionary) -> void:
    _apply_new_game_defaults()
    character.merge(saved.get("character", {}), true)
    progression.merge(saved.get("progression", {}), true)
    inventory = saved.get("inventory", []).duplicate(true)
    equipment.merge(saved.get("equipment", {}), true)
    learned_skills = saved.get("learned_skills", []).duplicate(true)
    skill_loadouts.merge(saved.get("skill_loadouts", {}), true)
    quests.merge(saved.get("quests", {}), true)
    gold = int(saved.get("gold", 0))
    world.merge(saved.get("world", {}), true)
