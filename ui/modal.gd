extends Control
class_name UplordModal

signal opened
signal closed
signal open_changed(is_open: bool)

enum ModalPosition { CENTER, LEFT, RIGHT, TOP, BOTTOM }

@export var title: String = "Inventory":
	set(value):
		title = value
		if is_node_ready():
			title_label.text = value
@export var close_on_backdrop: bool = true
@export var close_on_escape: bool = true
@export var show_close_button: bool = true
@export var animate: bool = true

# Responsive size/position settings live on each ModalContent scene.
# These defaults are only used when content does not inherit ModalContent.
const DEFAULT_DESKTOP_PORTRAIT_SIZE := Vector2(600.0, 760.0)
const DEFAULT_DESKTOP_LANDSCAPE_SIZE := Vector2(900.0, 600.0)
const DEFAULT_MOBILE_PORTRAIT_SIZE := Vector2(360.0, 600.0)
const DEFAULT_MOBILE_LANDSCAPE_SIZE := Vector2(700.0, 320.0)
const DEFAULT_MOBILE_OUTER_MARGIN := 16.0


@onready var scrim: ColorRect = $Scrim
@onready var center: Control = $Center
@onready var modal_panel: PanelContainer = $Center/Modal
@onready var title_label: Label = $Center/Modal/VBox/Header/HBoxContainer/Title
@onready var close_button: Button = $Center/Modal/VBox/Header/HBoxContainer/CloseButton
@onready var content_scroll: ScrollContainer = $Center/Modal/VBox/ContentScroll
@onready var content: VBoxContainer = $Center/Modal/VBox/ContentScroll/Content
@onready var footer_separator: HSeparator = $Center/Modal/VBox/FooterSeparator
@onready var footer: MarginContainer = $Center/Modal/VBox/Footer

var is_open: bool = false
var _available_size := Vector2.ZERO
var _layout_rect := Rect2()
var _has_layout_rect := false
var _tween: Tween
var _mobile_sheet := false
var _panel_rest_position := Vector2.ZERO
var _desktop_panel_style: StyleBoxFlat
var _resize_pending := false
var _backdrop_armed := false
var _active_touches: Dictionary = {}
var _content_desktop_portrait_size := DEFAULT_DESKTOP_PORTRAIT_SIZE
var _content_desktop_portrait_position: int = ModalPosition.CENTER
var _content_desktop_landscape_size := DEFAULT_DESKTOP_LANDSCAPE_SIZE
var _content_desktop_landscape_position: int = ModalPosition.CENTER
var _content_mobile_portrait_size := DEFAULT_MOBILE_PORTRAIT_SIZE
var _content_mobile_portrait_position: int = ModalPosition.CENTER
var _content_mobile_portrait_outer_margin := DEFAULT_MOBILE_OUTER_MARGIN
var _content_mobile_landscape_size := DEFAULT_MOBILE_LANDSCAPE_SIZE
var _content_mobile_landscape_position: int = ModalPosition.CENTER
var _content_mobile_landscape_outer_margin := DEFAULT_MOBILE_OUTER_MARGIN

func _ready() -> void:
	title_label.text = title
	close_button.visible = show_close_button
	close_button.pressed.connect(close)
	scrim.gui_input.connect(_on_backdrop_gui_input)
	visibility_changed.connect(_on_visibility_changed)
	if not get_viewport().size_changed.is_connected(_queue_viewport_resize):
		get_viewport().size_changed.connect(_queue_viewport_resize)
	var base_style := modal_panel.get_theme_stylebox("panel")
	if base_style is StyleBoxFlat:
		_desktop_panel_style = base_style.duplicate() as StyleBoxFlat
	visible = false


func _queue_viewport_resize() -> void:
	if _resize_pending:
		return
	_resize_pending = true
	call_deferred("_apply_viewport_resize")

func _apply_viewport_resize() -> void:
	# Rotation can update the viewport and the native iOS safe area on separate
	# frames. Wait twice so both values have settled before sizing the modal.
	await get_tree().process_frame
	await get_tree().process_frame
	_resize_pending = false
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	_available_size = viewport_size
	if is_open:
		if _has_layout_rect:
			resize_for_rect(_layout_rect)
		else:
			resize_for(viewport_size)
		# resize_for() updates the resting position used by the fade animation.
		modal_panel.position = _panel_rest_position

func open(available_size: Vector2 = Vector2.ZERO) -> void:
	if available_size != Vector2.ZERO:
		_available_size = available_size
	elif _available_size == Vector2.ZERO:
		_available_size = size

	if _has_layout_rect:
		resize_for_rect(_layout_rect)
	else:
		resize_for(_available_size)
	# Keep backdrop dismissal disabled until the pointer/touch that opened the modal
	# has fully ended. This prevents the opening mobile tap from immediately closing it.
	_backdrop_armed = false
	visible = true
	is_open = true
	call_deferred("_try_arm_backdrop")
	mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.visible = show_close_button

	if animate:
		_play_open_animation()
	else:
		scrim.modulate.a = 1.0
		modal_panel.modulate.a = 1.0
		modal_panel.scale = Vector2.ONE

	# Do not auto-focus the close button when the modal opens. This avoids the
	# focused/selected visual state appearing immediately on desktop and mobile.
	close_button.release_focus()
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()
	opened.emit()
	open_changed.emit(true)

	# A newly-instantiated content scene can update its minimum size on the next
	# layout pass. Re-apply the modal bounds after that pass so the very first
	# open uses the same settled geometry as subsequent opens.
	call_deferred("_stabilize_open_layout")

func _stabilize_open_layout() -> void:
	await get_tree().process_frame
	if not is_open or not visible:
		return
	if _has_layout_rect:
		resize_for_rect(_layout_rect)
	else:
		resize_for(_available_size)
	modal_panel.position = _panel_rest_position

func close() -> void:
	if not is_open:
		return
	is_open = false
	open_changed.emit(false)

	if animate and visible:
		_play_close_animation()
	else:
		_finish_close()

func toggle(available_size: Vector2 = Vector2.ZERO) -> void:
	if is_open:
		close()
	else:
		open(available_size)

func set_title(value: String) -> void:
	title = value

func open_modal(header_title: String, content_scene: PackedScene, available_size: Vector2 = Vector2.ZERO) -> Node:
	# Configure the reusable shell and its content in one call.
	set_title(header_title)
	var instance := set_content_scene(content_scene)
	_apply_content_layout(instance)
	scroll_to_top()
	open(available_size)
	return instance

func _apply_content_layout(instance: Node) -> void:
	# Each content scene owns its modal dimensions. This lets Inventory, Shop,
	# Quests, etc. all use different responsive sizes from the Inspector.
	# Avoid depending on the global class cache here. Godot can parse this script
	# before ModalContent has been registered, especially after importing a fresh ZIP.
	if instance != null and _has_modal_layout_properties(instance):
		_content_desktop_portrait_size = instance.desktop_portrait_size
		_content_desktop_portrait_position = instance.desktop_portrait_position
		_content_desktop_landscape_size = instance.desktop_landscape_size
		_content_desktop_landscape_position = instance.desktop_landscape_position
		_content_mobile_portrait_size = instance.mobile_portrait_size
		_content_mobile_portrait_position = instance.mobile_portrait_position
		_content_mobile_portrait_outer_margin = instance.mobile_portrait_outer_margin
		_content_mobile_landscape_size = instance.mobile_landscape_size
		_content_mobile_landscape_position = instance.mobile_landscape_position
		_content_mobile_landscape_outer_margin = instance.mobile_landscape_outer_margin
	else:
		_reset_content_layout()

func _has_modal_layout_properties(instance: Object) -> bool:
	var required := [
		"desktop_portrait_size",
		"desktop_portrait_position",
		"desktop_landscape_size",
		"desktop_landscape_position",
		"mobile_portrait_size",
		"mobile_portrait_position",
		"mobile_portrait_outer_margin",
		"mobile_landscape_size",
		"mobile_landscape_position",
		"mobile_landscape_outer_margin",
	]
	var available := {}
	for property in instance.get_property_list():
		available[property.name] = true
	for property_name in required:
		if not available.has(property_name):
			return false
	return true

func _reset_content_layout() -> void:
	_content_desktop_portrait_size = DEFAULT_DESKTOP_PORTRAIT_SIZE
	_content_desktop_portrait_position = ModalPosition.CENTER
	_content_desktop_landscape_size = DEFAULT_DESKTOP_LANDSCAPE_SIZE
	_content_desktop_landscape_position = ModalPosition.CENTER
	_content_mobile_portrait_size = DEFAULT_MOBILE_PORTRAIT_SIZE
	_content_mobile_portrait_position = ModalPosition.CENTER
	_content_mobile_portrait_outer_margin = DEFAULT_MOBILE_OUTER_MARGIN
	_content_mobile_landscape_size = DEFAULT_MOBILE_LANDSCAPE_SIZE
	_content_mobile_landscape_position = ModalPosition.CENTER
	_content_mobile_landscape_outer_margin = DEFAULT_MOBILE_OUTER_MARGIN

func set_text_content(body: String, hint: String = "") -> void:
	# Lightweight demo content. Feature scenes can replace this later with
	# set_content_scene() while keeping the same modal shell.
	clear_content()

	var body_label := Label.new()
	body_label.text = body
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.add_theme_font_size_override("font_size", 12)
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(body_label)

	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = hint
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.add_theme_font_size_override("font_size", 12)
		hint_label.add_theme_color_override("font_color", Color(0.62, 0.69, 0.76, 1.0))
		hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(hint_label)

	scroll_to_top()

func set_content_scene(scene: PackedScene, clear_existing: bool = true) -> Node:
	if clear_existing:
		clear_content()
	if scene == null:
		return null
	var instance := scene.instantiate()
	content.add_child(instance)
	return instance

func add_content(node: Control) -> void:
	if node.get_parent() != null:
		node.reparent(content)
	else:
		content.add_child(node)

func clear_content() -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()

func set_footer_visible(value: bool) -> void:
	footer.visible = value
	footer_separator.visible = value

func add_footer(node: Control) -> void:
	if node.get_parent() != null:
		node.reparent(footer)
	else:
		footer.add_child(node)
	set_footer_visible(true)

func clear_footer() -> void:
	for child in footer.get_children():
		child.queue_free()
	set_footer_visible(false)

func scroll_to_top() -> void:
	content_scroll.scroll_vertical = 0

func resize_for(available_size: Vector2) -> void:
	# Backwards-compatible full-viewport layout. The game UI normally calls
	# resize_for_rect() so desktop aspect bars are excluded from modal bounds.
	resize_for_rect(Rect2(Vector2.ZERO, available_size))

func resize_for_rect(layout_rect: Rect2) -> void:
	if layout_rect.size.x <= 0.0 or layout_rect.size.y <= 0.0:
		return
	_layout_rect = layout_rect
	_has_layout_rect = true
	_available_size = get_viewport().get_visible_rect().size
	_mobile_sheet = OS.get_name() == "iOS" or OS.get_name() == "Android"
	var is_landscape := layout_rect.size.x > layout_rect.size.y

	var target := _content_mobile_landscape_size if _mobile_sheet and is_landscape else _content_mobile_portrait_size if _mobile_sheet else _content_desktop_landscape_size if is_landscape else _content_desktop_portrait_size
	var requested_position := _content_mobile_landscape_position if _mobile_sheet and is_landscape else _content_mobile_portrait_position if _mobile_sheet else _content_desktop_landscape_position if is_landscape else _content_desktop_portrait_position
	target.x = maxf(1.0, target.x)
	target.y = maxf(1.0, target.y)

	if _mobile_sheet:
		_apply_mobile_panel_style()
		_apply_mobile_layout_rect(layout_rect, target, requested_position)
	else:
		_apply_desktop_panel_style()
		_apply_desktop_layout_rect(layout_rect, target, requested_position)

	_panel_rest_position = modal_panel.position

func _position_in_rect(rect: Rect2, panel_size: Vector2, placement: int, margin: float) -> Vector2:
	var inner := rect.grow(-margin)
	if inner.size.x < panel_size.x:
		inner.size.x = panel_size.x
	if inner.size.y < panel_size.y:
		inner.size.y = panel_size.y
	var result := inner.position + (inner.size - panel_size) * 0.5
	match placement:
		ModalPosition.LEFT:
			result.x = inner.position.x
		ModalPosition.RIGHT:
			result.x = inner.end.x - panel_size.x
		ModalPosition.TOP:
			result.y = inner.position.y
		ModalPosition.BOTTOM:
			result.y = inner.end.y - panel_size.y
		ModalPosition.CENTER:
			pass
	return result

func _apply_desktop_layout_rect(layout_rect: Rect2, requested_size: Vector2, placement: int) -> void:
	const OUTER_MARGIN := 16.0
	var usable := Vector2(maxf(1.0, layout_rect.size.x - OUTER_MARGIN * 2.0), maxf(1.0, layout_rect.size.y - OUTER_MARGIN * 2.0))
	var target := Vector2(minf(requested_size.x, usable.x), minf(requested_size.y, usable.y))
	modal_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	modal_panel.custom_minimum_size = target
	modal_panel.size = target

	# Clamp the final position explicitly. This is especially important on the
	# first open, when a freshly-instantiated content scene may have just changed
	# the PanelContainer minimum size.
	var panel_position := _position_in_rect(layout_rect, target, placement, OUTER_MARGIN)
	var min_pos := layout_rect.position + Vector2(OUTER_MARGIN, OUTER_MARGIN)
	var max_pos := layout_rect.end - Vector2(OUTER_MARGIN, OUTER_MARGIN) - target
	panel_position.x = clampf(panel_position.x, min_pos.x, maxf(min_pos.x, max_pos.x))
	panel_position.y = clampf(panel_position.y, min_pos.y, maxf(min_pos.y, max_pos.y))
	modal_panel.position = panel_position

func _apply_mobile_panel_style() -> void:
	# Keep the rounded modal treatment on mobile. The margin is outside the modal,
	# so the rounded corners remain visible against the backdrop.
	if _desktop_panel_style != null:
		var style := _desktop_panel_style.duplicate() as StyleBoxFlat
		style.bg_color = Color(0.055, 0.075, 0.095, 1.0)
		modal_panel.add_theme_stylebox_override("panel", style)

func _apply_mobile_layout_rect(layout_rect: Rect2, requested_size: Vector2, placement: int) -> void:
	var available_size := get_viewport().get_visible_rect().size
	# DisplayServer returns the safe area in native window pixels, while this modal
	# is laid out in viewport coordinates. Convert using the actual window-to-
	# viewport ratio instead of screen_get_scale().
	var native_safe := DisplayServer.get_display_safe_area()
	var safe_rect := layout_rect
	var native_window := Vector2(DisplayServer.window_get_size())
	var has_left_safe_inset := false
	var has_right_safe_inset := false
	var has_top_safe_inset := false
	var has_bottom_safe_inset := false
	if native_safe.size.x > 0 and native_safe.size.y > 0 and native_window.x > 0.0 and native_window.y > 0.0:
		var to_viewport := Vector2(available_size.x / native_window.x, available_size.y / native_window.y)
		var native_safe_rect := Rect2(Vector2(native_safe.position) * to_viewport, Vector2(native_safe.size) * to_viewport)
		safe_rect = layout_rect.intersection(native_safe_rect)
		# If iOS already reserves space on a horizontal edge, do not add the
		# modal's outer margin on that same edge. This avoids a double inset in
		# landscape around the notch / Dynamic Island side.
		has_left_safe_inset = native_safe.position.x > 0
		has_right_safe_inset = native_safe.end.x < int(native_window.x)
		has_top_safe_inset = native_safe.position.y > 0
		has_bottom_safe_inset = native_safe.end.y < int(native_window.y)

	var is_landscape := available_size.x > available_size.y
	var outer_margin := _content_mobile_landscape_outer_margin if is_landscape else _content_mobile_portrait_outer_margin
	outer_margin = maxf(0.0, outer_margin)

	# Margins are per-edge. A native safe-area inset already provides spacing on
	# that edge, so never stack the configured outer margin on top of it. This
	# applies independently to all four edges (important in both portrait and
	# landscape on iPhone/iPad).
	var margin_left := 0.0 if has_left_safe_inset else outer_margin
	var margin_right := 0.0 if has_right_safe_inset else outer_margin
	var margin_top := 0.0 if has_top_safe_inset else outer_margin
	var margin_bottom := 0.0 if has_bottom_safe_inset else outer_margin
	var modal_bounds := Rect2(
		safe_rect.position + Vector2(margin_left, margin_top),
		Vector2(
			maxf(1.0, safe_rect.size.x - margin_left - margin_right),
			maxf(1.0, safe_rect.size.y - margin_top - margin_bottom)
		)
	)

	# Use the explicit orientation size. The only adjustment is a hard safety
	# clamp so a configured modal can never extend beyond the allowed bounds.
	var target := Vector2(
		minf(requested_size.x, modal_bounds.size.x),
		minf(requested_size.y, modal_bounds.size.y)
	)

	modal_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var panel_position := _position_in_rect(modal_bounds, target, placement, 0.0)
	var min_pos := modal_bounds.position
	var max_pos := modal_bounds.end - target
	panel_position.x = clampf(panel_position.x, min_pos.x, maxf(min_pos.x, max_pos.x))
	panel_position.y = clampf(panel_position.y, min_pos.y, maxf(min_pos.y, max_pos.y))
	modal_panel.position = panel_position
	modal_panel.size = target
	modal_panel.custom_minimum_size = target

func _apply_desktop_panel_style() -> void:
	if _desktop_panel_style != null:
		modal_panel.add_theme_stylebox_override("panel", _desktop_panel_style)

func _apply_mobile_safe_area(available_size: Vector2) -> void:
	var display_scale := maxf(DisplayServer.screen_get_scale(DisplayServer.window_get_current_screen()), 0.01)
	var native_safe := DisplayServer.get_display_safe_area()
	var safe_rect := Rect2(Vector2.ZERO, available_size)
	if native_safe.size.x > 0 and native_safe.size.y > 0:
		safe_rect = Rect2(Vector2(native_safe.position) / display_scale, Vector2(native_safe.size) / display_scale)

	var left := maxf(0.0, safe_rect.position.x)
	var top := maxf(0.0, safe_rect.position.y)
	var right := maxf(0.0, available_size.x - safe_rect.end.x)
	var bottom := maxf(0.0, available_size.y - safe_rect.end.y)

	# The black scrim continues behind the physical safe-area regions. The blue
	# modal begins at the safe-area edge and fills all usable screen space.
	modal_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_panel.offset_left = left
	modal_panel.offset_top = top
	modal_panel.offset_right = -right
	modal_panel.offset_bottom = -bottom
	modal_panel.custom_minimum_size = Vector2.ZERO

func _play_open_animation() -> void:
	_kill_tween()
	scrim.modulate.a = 0.0
	modal_panel.scale = Vector2.ONE
	modal_panel.modulate.a = 1.0

	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	_tween.tween_property(scrim, "modulate:a", 1.0, 0.20)

	# Both desktop and mobile fade in. Mobile is full-screen; desktop stays centred.
	modal_panel.position = _panel_rest_position
	modal_panel.modulate.a = 0.0
	_tween.tween_property(modal_panel, "modulate:a", 1.0, 0.18)

func _play_close_animation() -> void:
	_kill_tween()
	_tween = create_tween().set_parallel(true)
	_tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	_tween.tween_property(scrim, "modulate:a", 0.0, 0.18)

	# Both variants fade out without positional movement.
	_tween.tween_property(modal_panel, "modulate:a", 0.0, 0.16)

	_tween.chain().tween_callback(_finish_close)

func _finish_close() -> void:
	_backdrop_armed = false
	visible = false
	modal_panel.position = _panel_rest_position
	modal_panel.modulate.a = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

func _try_arm_backdrop() -> void:
	if not is_open:
		return
	# Mouse openings can be armed as soon as the opening button is released.
	# Touch openings are tracked in _input() and arm on their release.
	if _active_touches.is_empty() and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_backdrop_armed = true

func _input(event: InputEvent) -> void:
	# Track touches even before the modal opens, so open() knows whether it was
	# triggered by an in-progress mobile tap.
	if event is InputEventScreenTouch:
		if event.pressed:
			_active_touches[event.index] = true
		else:
			_active_touches.erase(event.index)
			if is_open and not _backdrop_armed and _active_touches.is_empty():
				call_deferred("_try_arm_backdrop")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and is_open and not _backdrop_armed:
			call_deferred("_try_arm_backdrop")

func _on_backdrop_gui_input(event: InputEvent) -> void:
	if not is_open or not close_on_backdrop:
		return

	# Do not let the same pointer/touch that opened the modal dismiss it.
	if not _backdrop_armed:
		scrim.accept_event()
		return

	# Scrim is a full-screen sibling behind the modal panel. The panel uses
	# MOUSE_FILTER_STOP, so any primary press received here is backdrop input.
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()
			scrim.accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			close()
			scrim.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if is_open and close_on_escape and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _on_visibility_changed() -> void:
	if not visible and is_open:
		is_open = false
