extends Area2D

signal area_transition_requested(area_id: String, spawn_id: String)

@export var destination_area_id := ""
@export var destination_spawn_id := "default"
@export var require_input := false

var _player_inside := false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _unhandled_input(event: InputEvent) -> void:
	if require_input and _player_inside and event.is_action_pressed("interact"):
		_request_transition()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		if not require_input:
			_request_transition()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false

func _request_transition() -> void:
	if destination_area_id.is_empty():
		return
	area_transition_requested.emit(destination_area_id, destination_spawn_id)
