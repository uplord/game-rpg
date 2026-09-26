extends Node2D

signal area_loaded(area_id: String, spawn_id: String)

const PLAYER_SCENE := preload("res://content/player/player.tscn")
const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0
# Extra artwork outside the fixed gameplay bounds. Players and transitions stay
# inside the same authored play area on every device; safe areas only reveal bleed.
const MAP_BLEED := Vector2(180.0, 120.0)
# Portrait deliberately shows extra non-gameplay scenery above the authored map.
# This keeps the character closer to the landscape visual size without changing
# gameplay coordinates, collisions, movement speed, or landscape framing.
const PORTRAIT_EXTRA_SKY := 270.0

@onready var world_content: Node2D = $WorldContent
@onready var area_root: Node2D = $WorldContent/AreaRoot
@onready var player_root: Node2D = $WorldContent/PlayerRoot
@onready var camera: Camera2D = $Camera2D
@onready var phantom_camera: Node2D = $PhantomCamera2D
@onready var bar_left: ColorRect = $Cover/BarLeft
@onready var bar_right: ColorRect = $Cover/BarRight
@onready var bar_top: ColorRect = $Cover/BarTop
@onready var bar_bottom: ColorRect = $Cover/BarBottom

var current_area: Node2D
var player: CharacterBody2D
var _transition_locked := false
var _resize_pending := false
var _current_definition: Dictionary = {}
var map_scale := 1.0
var current_look_ahead := 0.0
var target_look_ahead := 0.0
var look_ahead_distance := 0.0
var portrait_hud_height := 0.0
@export var look_ahead_speed := 4.0

func _ready() -> void:
	if not get_window().size_changed.is_connected(_queue_resize_update):
		get_window().size_changed.connect(_queue_resize_update)
	if not get_viewport().size_changed.is_connected(_queue_resize_update):
		get_viewport().size_changed.connect(_queue_resize_update)
	await load_saved_area()

func _process(delta: float) -> void:
	# Directional look-ahead is a portrait-only camera behaviour. In landscape
	# the player stays centred until Phantom Camera reaches an authored map edge.
	var effective_look_ahead := target_look_ahead if _is_portrait() else 0.0
	current_look_ahead = lerpf(
		current_look_ahead,
		effective_look_ahead,
		1.0 - exp(-look_ahead_speed * delta)
	)
	if is_instance_valid(phantom_camera):
		# Phantom Camera offsets are authored-world units. Convert the desired
		# screen-space look-ahead through the camera zoom so portrait framing stays
		# visually consistent without scaling the gameplay scene.
		var zoom_scale := maxf(map_scale, 0.001)
		# In portrait the solid HUD occupies the bottom of the screen. Camera2D
		# still renders the full viewport, so move the camera centre DOWN by half
		# the HUD height. This makes the authored world's bottom edge line up with
		# the top of the HUD instead of being hidden underneath it.
		var portrait_y_offset := _get_camera_y_offset(zoom_scale)
		var wanted := Vector2(
			current_look_ahead * look_ahead_distance / zoom_scale,
			portrait_y_offset
		)
		if phantom_camera.follow_offset.distance_squared_to(wanted) > 0.01:
			phantom_camera.follow_offset = wanted

func set_look_ahead_direction(direction: float) -> void:
	target_look_ahead = clampf(direction, -1.0, 1.0)

func set_portrait_hud_height(height: float) -> void:
	var next_height := maxf(0.0, height)
	if is_equal_approx(portrait_hud_height, next_height):
		return
	portrait_hud_height = next_height
	_queue_resize_update()

func load_saved_area() -> void:
	var area_id := str(GameState.world.get("area_id", GameState.DEFAULT_AREA_ID))
	var spawn_id := str(GameState.world.get("spawn_id", GameState.DEFAULT_SPAWN_ID))
	var loaded := await load_area(area_id, spawn_id, false)
	if not loaded:
		await load_area(GameState.DEFAULT_AREA_ID, GameState.DEFAULT_SPAWN_ID, false)

func load_area(area_id: String, spawn_id: String = "default", save_location: bool = true) -> bool:
	if _transition_locked:
		return false
	_transition_locked = true

	var definition := ContentRepository.get_definition(area_id)
	if definition.is_empty():
		push_error("[Uplord][World] Unknown area: %s" % area_id)
		_transition_locked = false
		return false
	var scene_path := str(definition.get("scene", ""))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("[Uplord][World] Could not load area scene: %s" % scene_path)
		_transition_locked = false
		return false

	if is_instance_valid(current_area):
		current_area.queue_free()
		current_area = null
	current_area = packed.instantiate() as Node2D
	area_root.add_child(current_area)
	_current_definition = definition

	if not is_instance_valid(player):
		player = PLAYER_SCENE.instantiate() as CharacterBody2D
		player_root.add_child(player)

	# Calculate the height-driven camera zoom before placing the player/camera.
	# The gameplay scene itself stays at authored 1:1 scale.
	_apply_orientation_scale()
	var spawn := _find_spawn(spawn_id)
	player.position = spawn.position if spawn != null else Vector2(960, 760)
	player.cancel_auto_move()
	_connect_transitions()
	_configure_camera()

	if save_location:
		GameState.set_world_location(area_id, spawn_id)
		GameState.save()

	area_loaded.emit(area_id, spawn_id)
	print("[Uplord][World] Loaded %s at spawn %s" % [area_id, spawn_id])
	await get_tree().physics_frame
	await get_tree().process_frame
	_snap_camera_to_player()
	_transition_locked = false
	return true

func _find_spawn(spawn_id: String) -> Marker2D:
	if current_area == null:
		return null
	var exact := current_area.get_node_or_null("Spawns/%s" % spawn_id) as Marker2D
	if exact != null:
		return exact
	return current_area.get_node_or_null("Spawns/default") as Marker2D

func _connect_transitions() -> void:
	var transitions := current_area.get_node_or_null("Transitions") if current_area != null else null
	if transitions == null:
		return
	for child in transitions.get_children():
		if child is Area2D and child.has_signal("area_transition_requested"):
			child.area_transition_requested.connect(_on_area_transition_requested)

func _on_area_transition_requested(area_id: String, spawn_id: String) -> void:
	# Area2D body_entered is emitted while PhysicsServer2D is flushing queries.
	# Defer the scene swap so collision shapes are never added/removed in that phase.
	call_deferred("_deferred_area_transition", area_id, spawn_id)

func _deferred_area_transition(area_id: String, spawn_id: String) -> void:
	if _transition_locked:
		return
	await get_tree().physics_frame
	await load_area(area_id, spawn_id)

func _configure_camera() -> void:
	if is_instance_valid(player) and is_instance_valid(phantom_camera):
		phantom_camera.follow_target = player
	_apply_camera_limits()
	_apply_black_bars()

func _queue_resize_update() -> void:
	if _resize_pending:
		return
	_resize_pending = true
	call_deferred("_apply_resize_update")

func _apply_resize_update() -> void:
	# Resizing changes only camera presentation. Map/player/NPC/enemy/transition
	# transforms remain at authored 1:1 world coordinates.
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_orientation_scale()
	_apply_black_bars()
	_apply_camera_limits()

	# Apply the new camera zoom and portrait look-ahead immediately. The authored
	# gameplay scene itself always remains at 1:1 scale.
	_apply_camera_zoom()
	if is_instance_valid(phantom_camera):
		var zoom_scale := maxf(map_scale, 0.001)
		if _is_portrait():
			current_look_ahead = target_look_ahead
		else:
			current_look_ahead = 0.0
		phantom_camera.follow_offset = Vector2(
			current_look_ahead * look_ahead_distance / zoom_scale,
			_get_camera_y_offset(zoom_scale)
		)

	world_content.reset_physics_interpolation()
	await get_tree().physics_frame
	_snap_camera_to_player()
	_resize_pending = false

func _get_camera_y_offset(zoom_scale: float) -> float:
	# Camera2D renders the complete physical viewport. Shift its centre so the
	# scaled world is framed inside the actual gameplay rectangle instead of being
	# centred across presentation-only safe-area/HUD pixels.
	var screen_size := get_viewport().get_visible_rect().size
	var safe := _get_safe_insets(screen_size)
	var reserved_top := safe.y if _is_mobile() else 0.0
	var reserved_bottom := 0.0
	if _is_portrait():
		# The portrait controls live inside the safe-area UiFrame, so the top of
		# the solid HUD is above BOTH the bottom safe inset and the HUD itself.
		# The white background may bleed through the safe area, but Camera2D must
		# frame the authored map against the actual top edge of that HUD.
		reserved_bottom = portrait_hud_height + (safe.w if _is_mobile() else 0.0)
	elif _is_mobile():
		# Landscape has no solid HUD, so both physical safe-area insets are outside
		# the gameplay rectangle. This keeps the authored map bottom above the home
		# indicator instead of letting the world fit underneath it.
		reserved_bottom = safe.w
	return (reserved_bottom - reserved_top) * 0.5 / maxf(zoom_scale, 0.001)

func _apply_orientation_scale() -> void:
	if _current_definition.is_empty():
		return
	var screen_size := get_viewport().get_visible_rect().size
	var bounds := _get_bounds()
	var safe := _get_safe_insets(screen_size)
	var game_rect := _get_gameplay_rect(screen_size)

	# Scale the world against the actual visible gameplay frame, not the full
	# desktop window. On desktop the black bars live outside game_rect. On
	# mobile the gameplay frame is the safe vertical region and the map artwork
	# is still allowed to bleed beneath the device safe areas.
	var usable_height := game_rect.size.y
	var portrait := screen_size.y > screen_size.x
	if _is_mobile():
		if portrait:
			# The portrait HUD is laid out inside the mobile safe-area UiFrame. Its
			# top edge is therefore above the bottom safe inset. Fit the map to the
			# exact safe gameplay height first; the trimmed HUD is removed below.
			usable_height = maxf(1.0, screen_size.y - safe.y - safe.w)
		else:
			# Landscape has no solid bottom HUD. Fit the world to the safe gameplay
			# height so the authored map bottom stops above the home indicator.
			usable_height = maxf(1.0, screen_size.y - safe.y - safe.w)
	if portrait:
		# The portrait bottom HUD is screen-space UI, not gameplay space. Exclude
		# its rendered height when deriving camera zoom so the world is fitted to
		# the shorter visible map area above the solid bar. Landscape is unchanged.
		usable_height = maxf(1.0, usable_height - portrait_hud_height)
	var visible_world_height := bounds.size.y
	if portrait:
		visible_world_height += PORTRAIT_EXTRA_SKY
	map_scale = usable_height / maxf(visible_world_height, 1.0)

	var playable_width := game_rect.size.x
	if _is_mobile():
		playable_width = maxf(1.0, screen_size.x - safe.x - safe.z)
	look_ahead_distance = clampf((playable_width * 0.5) - 96.0, 80.0, 280.0)

	# Keep every gameplay node in authored coordinates. Resizing changes only the
	# camera zoom, so CharacterBody2D velocity/collisions remain identical at every
	# window size and orientation.
	world_content.scale = Vector2.ONE
	_apply_camera_zoom()
	world_content.reset_physics_interpolation()

func _apply_camera_zoom() -> void:
	var zoom_value := maxf(map_scale, 0.001)
	var world_zoom := Vector2.ONE * zoom_value
	if is_instance_valid(phantom_camera):
		phantom_camera.zoom = world_zoom
	if is_instance_valid(camera):
		camera.zoom = world_zoom

func _apply_camera_limits() -> void:
	if _current_definition.is_empty() or phantom_camera == null:
		return
	var gameplay_bounds := _get_bounds()
	var screen_size := get_viewport().get_visible_rect().size
	var safe := _get_safe_insets(screen_size)
	var game_rect := _get_gameplay_rect(screen_size)

	# Camera2D still renders the full viewport. Expand Phantom Camera's limits by
	# the black-bar thickness so the *visible 16:9 frame* stops exactly on the
	# authored gameplay bounds. The bars are presentation only and never become
	# player movement space. Mobile uses the same idea for safe-area bleed.
	var left_visual := safe.x
	var top_visual := safe.y
	var right_visual := safe.z
	# On mobile portrait the controls are inset above the bottom safe area, so
	# the camera reservation includes that inset even though the HUD background
	# itself visually bleeds through it.
	var bottom_visual := safe.w if _is_mobile() else 0.0
	if not _is_mobile():
		left_visual = game_rect.position.x
		top_visual = game_rect.position.y
		right_visual = maxf(0.0, screen_size.x - game_rect.end.x)
		bottom_visual = maxf(0.0, screen_size.y - game_rect.end.y)

	# Limits are also authored-world coordinates now. Convert presentation-only
	# bars/safe-area bleed from screen pixels back through the camera zoom.
	var zoom_scale := maxf(map_scale, 0.001)
	phantom_camera.limit_left = int(floor(gameplay_bounds.position.x - left_visual / zoom_scale))
	var portrait_sky := PORTRAIT_EXTRA_SKY if screen_size.y > screen_size.x else 0.0
	phantom_camera.limit_top = int(floor(gameplay_bounds.position.y - portrait_sky - top_visual / zoom_scale))
	phantom_camera.limit_right = int(ceil(gameplay_bounds.end.x + right_visual / zoom_scale))
	# Portrait reserves the bottom HUD from the playable camera region. Allow the
	# full Camera2D viewport to extend behind that HUD so the actual authored
	# bottom edge remains visible immediately above the HUD.
	phantom_camera.limit_bottom = int(ceil(
		gameplay_bounds.end.y + (bottom_visual + portrait_hud_height) / zoom_scale
	))

func _get_safe_insets(viewport_size: Vector2) -> Vector4:
	if not _is_mobile():
		return Vector4.ZERO
	var native_safe := DisplayServer.get_display_safe_area()
	var native_window := Vector2(DisplayServer.window_get_size())
	if native_safe.size.x <= 0 or native_safe.size.y <= 0 or native_window.x <= 0.0 or native_window.y <= 0.0:
		return Vector4.ZERO
	var to_viewport := Vector2(viewport_size.x / native_window.x, viewport_size.y / native_window.y)
	var left := maxf(0.0, float(native_safe.position.x) * to_viewport.x)
	var top := maxf(0.0, float(native_safe.position.y) * to_viewport.y)
	var right_native := maxf(0.0, native_window.x - float(native_safe.end.x))
	var bottom_native := maxf(0.0, native_window.y - float(native_safe.end.y))
	return Vector4(left, top, right_native * to_viewport.x, bottom_native * to_viewport.y)

func _get_bounds() -> Rect2:
	var data: Variant = _current_definition.get("bounds", [0, 0, 1920, 1080])
	if data is Array and data.size() >= 4:
		return Rect2(float(data[0]), float(data[1]), float(data[2]) - float(data[0]), float(data[3]) - float(data[1]))
	return Rect2(0, 0, 1920, 1080)

func _get_gameplay_rect(screen_size: Vector2) -> Rect2:
	# Portrait always uses the complete viewport. The centred 16:9 frame is a
	# desktop-landscape presentation only; applying it to portrait makes the
	# world scale/camera behave as if the portrait window were letterboxed.
	if _is_mobile() or screen_size.y > screen_size.x:
		return Rect2(Vector2.ZERO, screen_size)
	var frame_size := screen_size
	var frame_position := Vector2.ZERO
	var aspect := screen_size.x / maxf(screen_size.y, 1.0)
	if aspect > MAX_LANDSCAPE_ASPECT:
		frame_size.x = screen_size.y * MAX_LANDSCAPE_ASPECT
		frame_position.x = (screen_size.x - frame_size.x) * 0.5
	elif aspect < MAX_LANDSCAPE_ASPECT:
		frame_size.y = screen_size.x / MAX_LANDSCAPE_ASPECT
		frame_position.y = (screen_size.y - frame_size.y) * 0.5
	return Rect2(frame_position, frame_size)

func _apply_black_bars() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	if _is_mobile() or screen_size.y > screen_size.x:
		bar_left.visible = false
		bar_right.visible = false
		bar_top.visible = false
		bar_bottom.visible = false
		return
	var game_rect := _get_gameplay_rect(screen_size)
	var left_width := game_rect.position.x
	var right_width := maxf(0.0, screen_size.x - game_rect.end.x)
	var top_height := game_rect.position.y
	var bottom_height := maxf(0.0, screen_size.y - game_rect.end.y)

	bar_left.position = Vector2.ZERO
	bar_left.size = Vector2(left_width, screen_size.y)
	bar_left.visible = left_width > 0.5
	bar_right.position = Vector2(screen_size.x - right_width, 0.0)
	bar_right.size = Vector2(right_width, screen_size.y)
	bar_right.visible = right_width > 0.5
	bar_top.position = Vector2(game_rect.position.x, 0.0)
	bar_top.size = Vector2(game_rect.size.x, top_height)
	bar_top.visible = top_height > 0.5
	bar_bottom.position = Vector2(game_rect.position.x, screen_size.y - bottom_height)
	bar_bottom.size = Vector2(game_rect.size.x, bottom_height)
	bar_bottom.visible = bottom_height > 0.5

func _snap_camera_to_player() -> void:
	if phantom_camera == null:
		return
	if phantom_camera.has_method("process_logic"):
		phantom_camera.process_logic(0.0)
	if phantom_camera.has_method("teleport_position"):
		phantom_camera.teleport_position()
	if phantom_camera.has_method("reset_physics_interpolation"):
		phantom_camera.reset_physics_interpolation()
	if camera != null and phantom_camera.has_method("get_transform_output"):
		camera.global_transform = phantom_camera.get_transform_output()
		camera.zoom = phantom_camera.zoom
		camera.reset_smoothing()
		camera.reset_physics_interpolation()

func get_map_scale() -> float:
	return map_scale

func _is_portrait() -> bool:
	var screen_size := get_viewport().get_visible_rect().size
	return screen_size.y > screen_size.x

func _is_mobile() -> bool:
	# iPad follows the same no-black-bars / safe-area world behaviour as iPhone.
	return OS.has_feature("android") or OS.has_feature("ios")
