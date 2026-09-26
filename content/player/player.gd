extends CharacterBody2D

@export var move_speed := 400.0

const HOLD_THRESHOLD := 0.2
const FOLLOW_START_DISTANCE := 64.0
const FOLLOW_STOP_DISTANCE := 16.0
const CLICK_STOP_DISTANCE := 8.0
const MIN_CLICK_DISTANCE := 10.0

enum MouseMode { NONE, CLICK_MOVE, HOLD_FOLLOW }

var mouse_mode := MouseMode.NONE
var click_target := Vector2.ZERO
var mouse_down_time := 0.0
var mouse_press_active := false
var hold_started := false
var follow_moving := false
var _touch_screen_position := Vector2.ZERO
var _using_touch := false
var last_facing := 1
var pointer_started_on_player := false

@onready var sprite: Sprite2D = $Body/Sprite

func _ready() -> void:
	add_to_group("player")
	_apply_facing()
	_update_camera_look_ahead()

func _process(_delta: float) -> void:
	if not mouse_press_active:
		return
	if _now() - mouse_down_time > HOLD_THRESHOLD and not hold_started:
		hold_started = true
		_start_hold_follow()

func _physics_process(_delta: float) -> void:
	# Build the axes explicitly. This avoids horizontal input being lost when
	# multiple keyboard events are active and mirrors the reference movement
	# controller's independent left/right/up/down actions.
	var input_vector := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if input_vector != Vector2.ZERO:
		cancel_auto_move()
		velocity = input_vector.normalized() * move_speed
	else:
		velocity = _get_pointer_velocity()

	move_and_slide()
	_update_facing_from_velocity()
	_update_camera_look_ahead()

	if get_slide_collision_count() > 0 and mouse_mode == MouseMode.CLICK_MOVE:
		mouse_mode = MouseMode.NONE
		click_target = Vector2.ZERO
		velocity = Vector2.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _is_pointer_over_ui():
			return
		_using_touch = false
		_handle_pointer_button(event.pressed, event.position)
	elif event is InputEventMouseMotion and mouse_press_active:
		_touch_screen_position = event.position
	elif event is InputEventScreenTouch:
		if event.pressed and _is_pointer_over_ui():
			return
		_using_touch = true
		_handle_pointer_button(event.pressed, event.position)
	elif event is InputEventScreenDrag and mouse_press_active:
		_using_touch = true
		_touch_screen_position = event.position

func _handle_pointer_button(pressed: bool, screen_position: Vector2) -> void:
	_touch_screen_position = screen_position
	if pressed:
		mouse_down_time = _now()
		pointer_started_on_player = _screen_point_hits_player(screen_position)
		# Clicking the character is a facing control, not a movement command.
		# Do not allow the hold-follow timer to start from a press on the player.
		if pointer_started_on_player:
			mouse_press_active = false
			hold_started = false
			return
		mouse_press_active = true
		hold_started = false
		return

	if pointer_started_on_player:
		pointer_started_on_player = false
		_toggle_facing()
		return

	if not mouse_press_active:
		return
	mouse_press_active = false
	var held_time := _now() - mouse_down_time
	if held_time < HOLD_THRESHOLD:
		_start_click_move(_screen_to_local_world(screen_position))
	else:
		mouse_mode = MouseMode.NONE
		follow_moving = false

func _toggle_facing() -> void:
	last_facing *= -1
	_apply_facing()
	_update_camera_look_ahead()

func _screen_point_hits_player(screen_position: Vector2) -> bool:
	if not is_instance_valid(sprite) or sprite.texture == null:
		return false
	var canvas_transform := get_viewport().get_canvas_transform()
	var world_position := canvas_transform.affine_inverse() * screen_position
	var sprite_local := sprite.to_local(world_position)
	return sprite.get_rect().has_point(sprite_local)

func _start_click_move(target: Vector2) -> void:
	if position.distance_squared_to(target) < MIN_CLICK_DISTANCE * MIN_CLICK_DISTANCE:
		return
	click_target = target
	mouse_mode = MouseMode.CLICK_MOVE
	follow_moving = false

func _start_hold_follow() -> void:
	click_target = Vector2.ZERO
	mouse_mode = MouseMode.HOLD_FOLLOW
	follow_moving = false

func _get_pointer_velocity() -> Vector2:
	match mouse_mode:
		MouseMode.CLICK_MOVE:
			var to_target := click_target - position
			if to_target.length_squared() <= CLICK_STOP_DISTANCE * CLICK_STOP_DISTANCE:
				mouse_mode = MouseMode.NONE
				click_target = Vector2.ZERO
				return Vector2.ZERO
			return to_target.normalized() * move_speed
		MouseMode.HOLD_FOLLOW:
			var screen_dir := _get_screen_pointer_position() - get_global_transform_with_canvas().origin
			var distance_sq := screen_dir.length_squared()
			if not follow_moving and distance_sq > FOLLOW_START_DISTANCE * FOLLOW_START_DISTANCE:
				follow_moving = true
			elif follow_moving and distance_sq < FOLLOW_STOP_DISTANCE * FOLLOW_STOP_DISTANCE:
				follow_moving = false
			if follow_moving:
				return screen_dir.normalized() * move_speed
	return Vector2.ZERO

func _update_facing_from_velocity() -> void:
	if absf(velocity.x) <= 0.01:
		return
	var new_facing := -1 if velocity.x < 0.0 else 1
	if new_facing == last_facing:
		return
	last_facing = new_facing
	_apply_facing()

func _apply_facing() -> void:
	if is_instance_valid(sprite):
		sprite.flip_h = last_facing < 0

func _update_camera_look_ahead() -> void:
	var controller := get_parent().get_parent().get_parent() if get_parent() != null and get_parent().get_parent() != null else null
	if controller != null and controller.has_method("set_look_ahead_direction"):
		var direction := float(last_facing)
		if mouse_mode == MouseMode.HOLD_FOLLOW and mouse_press_active:
			var screen_dir := _get_screen_pointer_position() - get_global_transform_with_canvas().origin
			if screen_dir.length_squared() > FOLLOW_STOP_DISTANCE * FOLLOW_STOP_DISTANCE:
				direction = clampf(screen_dir.normalized().x, -1.0, 1.0)
		controller.set_look_ahead_direction(direction)

func cancel_auto_move() -> void:
	mouse_press_active = false
	hold_started = false
	follow_moving = false
	mouse_mode = MouseMode.NONE
	click_target = Vector2.ZERO
	velocity = Vector2.ZERO

func _screen_to_local_world(screen_position: Vector2) -> Vector2:
	# Convert the click/touch through Camera2D into PlayerRoot's authored-world
	# coordinates. WorldContent stays at 1:1; camera zoom handles presentation.
	var canvas_transform := get_viewport().get_canvas_transform()
	var world_position := canvas_transform.affine_inverse() * screen_position
	var parent_2d := get_parent() as Node2D
	return parent_2d.to_local(world_position) if parent_2d != null else world_position

func _get_screen_pointer_position() -> Vector2:
	return _touch_screen_position if _using_touch else get_viewport().get_mouse_position()

func _is_pointer_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
