class_name InputRouter
extends Node
## Per-player input (GDD 18.4, 18.8). Gameplay code reads intents from here, never from Input directly,
## so a second local or network player only needs another router keyed by its device or peer id.
## M0: player 0 owns the keyboard, the mouse and every gamepad.

@export var player_index: int = 0
## Radians of look per pixel of mouse motion.
@export var mouse_sensitivity: float = 0.0022
## Radians per second at full right-stick deflection (x = yaw, y = pitch).
@export var stick_look_speed: Vector2 = Vector2(3.2, 2.2)
@export var invert_y: bool = false

## Off while a debug console or menu has focus.
var enabled: bool = true
var _mouse_look: Vector2 = Vector2.ZERO
## Swallows the click that captured the mouse so it doesn't also fire.
var _fire_blocked_until_ms: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		_mouse_look += (event as InputEventMouseMotion).screen_relative * mouse_sensitivity
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_fire_blocked_until_ms = Time.get_ticks_msec() + 200
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Look delta in radians since the last call (x = yaw right, y = pitch down).
func consume_look(delta: float) -> Vector2:
	var look := _mouse_look + Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down") * stick_look_speed * delta
	_mouse_look = Vector2.ZERO
	if not enabled:
		return Vector2.ZERO
	if invert_y:
		look.y = -look.y
	return look


func is_pressed(action: StringName) -> bool:
	return enabled and not _is_blocked(action) and Input.is_action_pressed(action)


func is_just_pressed(action: StringName) -> bool:
	return enabled and not _is_blocked(action) and Input.is_action_just_pressed(action)


func _is_blocked(action: StringName) -> bool:
	return action == &"fire" and Time.get_ticks_msec() < _fire_blocked_until_ms
