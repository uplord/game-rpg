extends Node2D

## Stage 1 single-player bootstrap.
## Networking/Firebase are intentionally absent. The client talks to local
## services through stable boundaries that can later be backed by a server.

func _ready() -> void:
	print("[Uplord][Main] Single-player foundation ready.")
	print("[Uplord][Main] Character: %s" % GameState.character.get("name", "Adventurer"))
	print("[Uplord][Main] Area: %s" % GameState.world.get("area_id", GameState.DEFAULT_AREA_ID))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		GameState.save()
		get_tree().quit()
