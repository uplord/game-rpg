extends CanvasLayer

const MAX_LANDSCAPE_ASPECT := 16.0 / 9.0
const BASE_DESKTOP_UI_SIZE := Vector2(1920.0, 1080.0)
const BASE_DESKTOP_PORTRAIT_UI_SIZE := Vector2(1080.0, 1920.0)
const UI_MARGIN := 16

const INVENTORY_MODAL_CONTENT := preload("res://ui/modal_content/inventory_content.tscn")
const SKILLS_MODAL_CONTENT := preload("res://ui/modal_content/skills_content.tscn")
const QUESTS_MODAL_CONTENT := preload("res://ui/modal_content/quests_content.tscn")
const SHOP_MODAL_CONTENT := preload("res://ui/modal_content/shop_content.tscn")
const MORE_MODAL_CONTENT := preload("res://ui/modal_content/more_content.tscn")

@onready var ui_frame: Control = $UiFrame
@onready var top_margin: MarginContainer = $UiFrame/VBoxContainer/TopBar/MarginContainer
@onready var bottom_margin: MarginContainer = $UiFrame/VBoxContainer/BottomBar/MarginContainer
@onready var bottom_bar: Control = $UiFrame/VBoxContainer/BottomBar
@onready var bottom_background: ColorRect = $UiFrame/VBoxContainer/BottomBar/ColorRect
@onready var bar_left: ColorRect = $AspectBars/Left
@onready var bar_right: ColorRect = $AspectBars/Right
@onready var bar_top: ColorRect = $AspectBars/Top
@onready var bar_bottom: ColorRect = $AspectBars/Bottom
@onready var modal_layer: Control = $ModalLayer

@onready var inventory_button: Button = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/MenuButtons/InventoryButton
@onready var skills_button: Button = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/MenuButtons/SkillsButton
@onready var quests_button: Button = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/MenuButtons/QuestsButton
@onready var shop_button: Button = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/MenuButtons/ShopButton
@onready var more_button: Button = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/MenuButtons/MoreButton
@onready var chat_button: Button = $UiFrame/VBoxContainer/BottomBar/MarginContainer/BoxContainer/ChatSlot/ChatButton
@onready var interact_button: Button = $UiFrame/VBoxContainer/BottomBar/MarginContainer/BoxContainer/InteractButton
@onready var chat_panel: PanelContainer = $UiFrame/ChatPanel
@onready var chat_input: LineEdit = $UiFrame/ChatPanel/Margin/VBox/Input
@onready var chat_log: RichTextLabel = $UiFrame/ChatPanel/Margin/VBox/Log

@onready var player_name_label: Label = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/PlayerCard/Margin/Row/Info/NameRow/Name
@onready var player_level_label: Label = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/PlayerCard/Margin/Row/Info/NameRow/Level
@onready var hp_bar: ProgressBar = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/PlayerCard/Margin/Row/Info/HP
@onready var mp_bar: ProgressBar = $UiFrame/VBoxContainer/TopBar/MarginContainer/BoxContainer/PlayerCard/Margin/Row/Info/MP
@onready var quest_title_label: Label = $UiFrame/QuestTracker/Margin/VBox/Title
@onready var quest_objective_label: Label = $UiFrame/QuestTracker/Margin/VBox/Objective

var _layout_update_pending := false
var _display_scale := 1.0


func _ready() -> void:
    get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
    if not get_viewport().size_changed.is_connected(_queue_layout_update):
        get_viewport().size_changed.connect(_queue_layout_update)

    inventory_button.pressed.connect(func(): _open_scene_modal("Inventory", INVENTORY_MODAL_CONTENT))
    skills_button.pressed.connect(func(): _open_scene_modal("Skills", SKILLS_MODAL_CONTENT))
    quests_button.pressed.connect(func(): _open_scene_modal("Quests", QUESTS_MODAL_CONTENT))
    shop_button.pressed.connect(func(): _open_scene_modal("Shop", SHOP_MODAL_CONTENT))
    more_button.pressed.connect(func(): _open_scene_modal("More", MORE_MODAL_CONTENT))
    chat_button.pressed.connect(_toggle_chat)
    interact_button.pressed.connect(_request_interact)
    chat_input.text_submitted.connect(_submit_chat)

    if not GameState.state_changed.is_connected(_on_game_state_changed):
        GameState.state_changed.connect(_on_game_state_changed)
    if not GameState.state_loaded.is_connected(_refresh_hud):
        GameState.state_loaded.connect(_refresh_hud)

    _configure_world_click_passthrough(ui_frame)
    _refresh_hud()
    _queue_layout_update()


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_T:
            _toggle_chat()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ENTER and chat_panel.visible:
            chat_input.grab_focus()
            get_viewport().set_input_as_handled()
        elif event.keycode == KEY_ESCAPE and chat_input.has_focus():
            chat_input.release_focus()
            get_viewport().set_input_as_handled()


func _configure_world_click_passthrough(node: Node) -> void:
    if node is Control:
        var control := node as Control
        if control is BaseButton or control is LineEdit or control is PanelContainer:
            control.mouse_filter = Control.MOUSE_FILTER_STOP
        else:
            control.mouse_filter = Control.MOUSE_FILTER_IGNORE
    for child in node.get_children():
        _configure_world_click_passthrough(child)


func _open_scene_modal(modal_title: String, content_scene: PackedScene) -> void:
    modal_layer.open_modal(modal_title, content_scene)


func _toggle_chat() -> void:
    chat_panel.visible = not chat_panel.visible
    if chat_panel.visible:
        chat_input.grab_focus()
    else:
        chat_input.release_focus()


func _submit_chat(message: String) -> void:
    var cleaned := message.strip_edges()
    if cleaned.is_empty():
        return
    chat_log.append_text("[color=#dce7f2]You:[/color] %s\n" % cleaned)
    chat_input.clear()


func _request_interact() -> void:
    # Phase 3 owns the HUD interaction surface. Phase 8 will route this through
    # the NPC/resource interaction system; the E action remains the shared hook.
    Input.action_press("interact")
    await get_tree().process_frame
    Input.action_release("interact")


func _on_game_state_changed(_section: String) -> void:
    _refresh_hud()


func _refresh_hud() -> void:
    var character := CharacterService.get_character()
    player_name_label.text = str(character.get("name", "Adventurer"))
    player_level_label.text = "Total %d" % CharacterService.get_total_level()

    var max_hp := maxf(float(character.get("max_health", 100)), 1.0)
    var max_mp := maxf(float(character.get("max_mana", 100)), 1.0)
    hp_bar.max_value = max_hp
    hp_bar.value = clampf(float(character.get("hp", max_hp)), 0.0, max_hp)
    hp_bar.tooltip_text = "HP %d / %d" % [int(hp_bar.value), int(max_hp)]
    mp_bar.max_value = max_mp
    mp_bar.value = clampf(float(character.get("mp", max_mp)), 0.0, max_mp)
    mp_bar.tooltip_text = "MP %d / %d" % [int(mp_bar.value), int(max_mp)]

    quest_title_label.text = "No tracked quest"
    quest_objective_label.text = "Open Quests to choose an objective."
    for quest_id in GameState.quests:
        var quest_value: Variant = GameState.quests[quest_id]
        if quest_value is Dictionary:
            var quest := quest_value as Dictionary
            var status := str(quest.get("status", ""))
            if status == "active" or bool(quest.get("tracked", false)):
                quest_title_label.text = str(quest.get("name", quest_id))
                quest_objective_label.text = str(quest.get("objective", "Quest in progress"))
                break


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

    var ui_scale := 1.0
    if not mobile:
        var physical_game_size := game_rect.size * _display_scale
        var desktop_base_size := BASE_DESKTOP_UI_SIZE if landscape else BASE_DESKTOP_PORTRAIT_UI_SIZE
        ui_scale = minf(
            physical_game_size.x / desktop_base_size.x,
            physical_game_size.y / desktop_base_size.y
        )
        ui_scale = maxf(ui_scale, 0.01)

    ui_frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
    ui_frame.scale = Vector2.ONE * ui_scale
    ui_frame.position = usable_rect.position
    ui_frame.size = usable_rect.size / ui_scale

    bottom_background.visible = not landscape
    var safe_bottom_for_hud := maxf(0.0, game_rect.end.y - usable_rect.end.y)
    var mobile_portrait_top_trim := 16.0 if mobile and not landscape else 0.0
    bottom_background.offset_top = mobile_portrait_top_trim
    bottom_background.offset_bottom = safe_bottom_for_hud / ui_scale if not landscape else 0.0
    var portrait_hud_height := (bottom_bar.size.y - mobile_portrait_top_trim) * ui_scale if not landscape else 0.0
    var world := get_node_or_null("../World")
    if world != null and world.has_method("set_portrait_hud_height"):
        world.set_portrait_hud_height(portrait_hud_height)

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

    modal_layer.set_anchors_preset(Control.PRESET_TOP_LEFT)
    modal_layer.scale = Vector2.ONE * ui_scale
    modal_layer.position = game_rect.position
    modal_layer.size = game_rect.size / ui_scale
    # Modal geometry is expressed in ModalLayer-local coordinates. Keeping the
    # modal layout rect local prevents desktop UI scaling / aspect-bar offsets
    # from being applied twice when positioning the panel.
    if modal_layer.has_method("resize_for_rect"):
        modal_layer.resize_for_rect(Rect2(Vector2.ZERO, modal_layer.size))


func _apply_aspect_bars(viewport_size: Vector2, frame_position: Vector2, frame_size: Vector2, show_bars: bool) -> void:
    for bar in [bar_left, bar_right, bar_top, bar_bottom]:
        bar.visible = show_bars
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
