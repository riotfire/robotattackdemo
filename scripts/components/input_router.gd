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
## Mouse travel, in pixels, that pushes the weapon wheel's pointer all the way out.
@export var wheel_mouse_radius: float = 120.0

## Off while a debug console or menu has focus.
var enabled: bool = true
## On while the weapon wheel is open: look input steers the wheel's pointer instead of the camera.
var look_locked: bool = false:
	set(value):
		look_locked = value
		_mouse_look = Vector2.ZERO
		_wheel_mouse = Vector2.ZERO
var _mouse_look: Vector2 = Vector2.ZERO
var _wheel_mouse: Vector2 = Vector2.ZERO
## Swallows the click that captured the mouse so it doesn't also fire.
var _fire_blocked_until_ms: int = 0


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and captured:
		var motion := (event as InputEventMouseMotion).screen_relative
		if look_locked:
			_wheel_mouse = (_wheel_mouse + motion / wheel_mouse_radius).limit_length(1.0)
		else:
			_mouse_look += motion * mouse_sensitivity
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed and not captured:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_fire_blocked_until_ms = Time.get_ticks_msec() + 200
	elif event.is_action_pressed(&"pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func move_vector() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	# The left stick steers the weapon wheel while it's open, so it must not also walk the farmer.
	if look_locked and _left_stick().length() >= WeaponHolder.WHEEL_DEADZONE:
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")


## Look delta in radians since the last call (x = yaw right, y = pitch down).
func consume_look(delta: float) -> Vector2:
	var look := _mouse_look + Input.get_vector(&"look_left", &"look_right", &"look_up", &"look_down") * stick_look_speed * delta
	_mouse_look = Vector2.ZERO
	if not enabled or look_locked:
		return Vector2.ZERO
	if invert_y:
		look.y = -look.y
	return look


## The raw left stick (x right, y down), ignoring the keyboard bindings that share the move actions.
func _left_stick() -> Vector2:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		pads = [0]
	var best := Vector2.ZERO
	for pad in pads:
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		if stick.length() > best.length():
			best = stick
	return best.limit_length(1.0)


## The weapon wheel's pointer (x right, y down, length 0-1): the left stick while it's pushed, otherwise
## how far the mouse has moved since the wheel opened.
func wheel_pointer() -> Vector2:
	if not enabled:
		return Vector2.ZERO
	var stick := _left_stick()
	return stick if stick.length() >= WeaponHolder.WHEEL_DEADZONE else _wheel_mouse


func is_pressed(action: StringName) -> bool:
	return enabled and not _is_blocked(action) and Input.is_action_pressed(action)


func is_just_pressed(action: StringName) -> bool:
	return enabled and not _is_blocked(action) and Input.is_action_just_pressed(action)


func _is_blocked(action: StringName) -> bool:
	return action == &"fire" and Time.get_ticks_msec() < _fire_blocked_until_ms
