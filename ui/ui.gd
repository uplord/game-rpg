extends CanvasLayer

# Match the display behaviour used by the reference game:
# - no fixed Godot stretch viewport
# - one platform display scale for the whole canvas (1x/2x/3x)
# - landscape gameplay is centred inside a 16:9 frame
# - portrait uses the complete logical viewport
# - the safe area only insets the UI frame; child controls keep authored sizes
const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0
const UI_MARGIN := 16

const INVENTORY_MODAL_CONTENT := preload("res://ui/modal_content/inventory_content.tscn")
const SHOP_MODAL_CONTENT := preload("res://ui/modal_content/shop_content.tscn")
const QUESTS_MODAL_CONTENT := preload("res://ui/modal_content/quests_content.tscn")

@onready var ui_frame: Control = $UiFrame
@onready var top_margin: MarginContainer = $UiFrame/VBoxContainer/TopBar/MarginContainer
@onready var bottom_margin: MarginContainer = $UiFrame/VBoxContainer/BottomBar/MarginContainer
@onready var bar_left: ColorRect = $AspectBars/Left
@onready var bar_right: ColorRect = $AspectBars/Right
@onready var bar_top: ColorRect = $AspectBars/Top
@onready var bar_bottom: ColorRect = $AspectBars/Bottom
@onready var modal_layer: Control = $ModalLayer
@onready var modal_inventory_button: Control = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/HBoxContainer/SkillButton
@onready var modal_shop_button: Control = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/HBoxContainer/SkillButton2
@onready var modal_quest_button: Control = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/HBoxContainer/SkillButton3

var _layout_update_pending := false
var _display_scale := 1.0


func _ready() -> void:
    # Work in real logical window coordinates. The backing/display scale below
    # scales the entire game consistently instead of scaling individual controls.
    get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    if not get_viewport().size_changed.is_connected(_queue_layout_update):
        get_viewport().size_changed.connect(_queue_layout_update)
    modal_inventory_button.gui_input.connect(_on_inventory_gui_input)
    modal_shop_button.gui_input.connect(_on_shop_gui_input)
    modal_quest_button.gui_input.connect(_on_quest_gui_input)
    _queue_layout_update()


func _event_opens_modal(event: InputEvent) -> bool:
    if event is InputEventMouseButton:
        return event.button_index == MOUSE_BUTTON_LEFT and event.pressed
    if event is InputEventScreenTouch:
        return event.pressed
    return false


func _open_scene_modal(modal_title: String, content_scene: PackedScene) -> void:
    modal_layer.open_modal(modal_title, content_scene)


func _on_inventory_gui_input(event: InputEvent) -> void:
    if _event_opens_modal(event):
        _open_scene_modal("Inventory", INVENTORY_MODAL_CONTENT)


func _on_shop_gui_input(event: InputEvent) -> void:
    if _event_opens_modal(event):
        _open_scene_modal("Shop", SHOP_MODAL_CONTENT)


func _on_quest_gui_input(event: InputEvent) -> void:
    if _event_opens_modal(event):
        _open_scene_modal("Quests", QUESTS_MODAL_CONTENT)


func _queue_layout_update() -> void:
    if _layout_update_pending:
        return
    _layout_update_pending = true
    call_deferred("_apply_layout")


func _apply_layout() -> void:
    _layout_update_pending = false
    await get_tree().process_frame

    var window := get_window()
    var screen_index := DisplayServer.window_get_current_screen()
    _display_scale = maxf(DisplayServer.screen_get_scale(screen_index), 0.01)
    window.content_scale_factor = snapped(_display_scale, 0.01)

    var viewport_size := get_viewport().get_visible_rect().size
    if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
        return

    var landscape := viewport_size.x > viewport_size.y
    var frame_position := Vector2.ZERO
    var frame_size := viewport_size

    # Mobile landscape uses the complete display: no 16:9 black bars. Desktop
    # can still use the centred 16:9 presentation used by the reference game.
    var mobile := OS.get_name() == "iOS" or OS.get_name() == "Android"
    if landscape and not mobile:
        var aspect := viewport_size.x / viewport_size.y
        if aspect > MAX_LANDSCAPE_ASPECT:
            frame_size.x = viewport_size.y * MAX_LANDSCAPE_ASPECT
            frame_position.x = (viewport_size.x - frame_size.x) * 0.5
        elif aspect < MAX_LANDSCAPE_ASPECT:
            frame_size.y = viewport_size.x / MAX_LANDSCAPE_ASPECT
            frame_position.y = (viewport_size.y - frame_size.y) * 0.5

    _apply_aspect_bars(viewport_size, frame_position, frame_size, landscape and not mobile)

    # Convert the native safe-area rectangle to the same logical coordinates as
    # the viewport, then intersect it with the gameplay frame. The resulting
    # UiFrame is the only thing inset; all children retain their authored sizes.
    var safe_rect_native := DisplayServer.get_display_safe_area()
    var safe_rect := Rect2(Vector2.ZERO, viewport_size)
    if safe_rect_native.size.x > 0 and safe_rect_native.size.y > 0:
        safe_rect = Rect2(
            Vector2(safe_rect_native.position) / _display_scale,
            Vector2(safe_rect_native.size) / _display_scale
        )

    var game_rect := Rect2(frame_position, frame_size)
    var usable_rect := game_rect.intersection(safe_rect)
    if usable_rect.size.x <= 0.0 or usable_rect.size.y <= 0.0:
        usable_rect = game_rect

    ui_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
    ui_frame.position = usable_rect.position
    ui_frame.size = usable_rect.size

    # UiFrame is already inset to the device safe area. Do not add the normal
    # UI margin again on an edge that already has a non-zero safe-area inset.
    var safe_left := maxf(0.0, usable_rect.position.x - game_rect.position.x)
    var safe_top := maxf(0.0, usable_rect.position.y - game_rect.position.y)
    var safe_right := maxf(0.0, game_rect.end.x - usable_rect.end.x)
    var safe_bottom := maxf(0.0, game_rect.end.y - usable_rect.end.y)

    var margin_left := 0 if safe_left > 0.5 else UI_MARGIN
    var margin_top := 0 if safe_top > 0.5 else UI_MARGIN
    var margin_right := 0 if safe_right > 0.5 else UI_MARGIN
    var margin_bottom := 0 if safe_bottom > 0.5 else UI_MARGIN

    _set_edge_margins(top_margin, margin_left, margin_top, margin_right, UI_MARGIN)
    _set_edge_margins(bottom_margin, margin_left, UI_MARGIN, margin_right, margin_bottom)
    # Keep the modal inside the actual gameplay frame. On desktop this excludes
    # the 16:9 black bars; on mobile game_rect is the full viewport.
    modal_layer.resize_for_rect(game_rect)


func _apply_aspect_bars(viewport_size: Vector2, frame_position: Vector2, frame_size: Vector2, landscape: bool) -> void:
    var show_bars := landscape and (frame_position.x > 0.5 or frame_position.y > 0.5)
    $AspectBars.visible = show_bars
    if not show_bars:
        return

    _set_rect(bar_left, 0.0, 0.0, frame_position.x, viewport_size.y)
    _set_rect(bar_right, frame_position.x + frame_size.x, 0.0, maxf(0.0, viewport_size.x - frame_position.x - frame_size.x), viewport_size.y)
    _set_rect(bar_top, frame_position.x, 0.0, frame_size.x, frame_position.y)
    _set_rect(bar_bottom, frame_position.x, frame_position.y + frame_size.y, frame_size.x, maxf(0.0, viewport_size.y - frame_position.y - frame_size.y))


func _set_rect(control: Control, x: float, y: float, width: float, height: float) -> void:
    control.position = Vector2(x, y)
    control.size = Vector2(maxf(0.0, width), maxf(0.0, height))


func _set_edge_margins(container: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
    container.add_theme_constant_override("margin_left", left)
    container.add_theme_constant_override("margin_top", top)
    container.add_theme_constant_override("margin_right", right)
    container.add_theme_constant_override("margin_bottom", bottom)


func get_display_scale() -> float:
    return _display_scale


func native_pixels_to_viewport(value: Vector2) -> Vector2:
    return value / maxf(_display_scale, 0.01)


func viewport_to_native_pixels(value: Vector2) -> Vector2:
    return value * _display_scale
