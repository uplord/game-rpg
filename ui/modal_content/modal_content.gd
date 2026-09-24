extends Control
class_name ModalContent

## Responsive layout settings owned by each modal content scene.
## These values are read automatically by UplordModal when the scene is opened.
enum ModalPosition { CENTER, LEFT, RIGHT, TOP, BOTTOM }

@export_group("Modal Layout")

@export_subgroup("Desktop Portrait")
@export var desktop_portrait_size: Vector2 = Vector2(600.0, 760.0)
@export var desktop_portrait_position: ModalPosition = ModalPosition.CENTER

@export_subgroup("Desktop Landscape")
@export var desktop_landscape_size: Vector2 = Vector2(900.0, 600.0)
@export var desktop_landscape_position: ModalPosition = ModalPosition.CENTER

@export_subgroup("Mobile Portrait")
@export var mobile_portrait_size: Vector2 = Vector2(360.0, 600.0)
@export var mobile_portrait_position: ModalPosition = ModalPosition.CENTER
@export var mobile_portrait_outer_margin: float = 16.0

@export_subgroup("Mobile Landscape")
@export var mobile_landscape_size: Vector2 = Vector2(700.0, 320.0)
@export var mobile_landscape_position: ModalPosition = ModalPosition.CENTER
@export var mobile_landscape_outer_margin: float = 16.0
