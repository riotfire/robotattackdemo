extends SceneTree
## Writes the default input map (GDD 5.2: keyboard + mouse and gamepad / Steam Deck) into project.godot.
## Run from the project folder:
##   <godot> --headless --path . --script res://tools/setup_input_map.gd
## Actions stay remappable in Project Settings > Input Map. Debug cheats (F1-F8, `) are read directly
## by scripts/systems/debug_cheats.gd and are not listed here.


func _initialize() -> void:
	_action(&"move_forward", [KEY_W], [], [], [Vector2(JOY_AXIS_LEFT_Y, -1.0)])
	_action(&"move_back", [KEY_S], [], [], [Vector2(JOY_AXIS_LEFT_Y, 1.0)])
	_action(&"move_left", [KEY_A], [], [], [Vector2(JOY_AXIS_LEFT_X, -1.0)])
	_action(&"move_right", [KEY_D], [], [], [Vector2(JOY_AXIS_LEFT_X, 1.0)])
	_action(&"look_left", [], [], [], [Vector2(JOY_AXIS_RIGHT_X, -1.0)])
	_action(&"look_right", [], [], [], [Vector2(JOY_AXIS_RIGHT_X, 1.0)])
	_action(&"look_up", [], [], [], [Vector2(JOY_AXIS_RIGHT_Y, -1.0)])
	_action(&"look_down", [], [], [], [Vector2(JOY_AXIS_RIGHT_Y, 1.0)])
	_action(&"jump", [KEY_SPACE], [], [JOY_BUTTON_A], [])
	_action(&"aim", [], [MOUSE_BUTTON_RIGHT], [], [Vector2(JOY_AXIS_TRIGGER_LEFT, 1.0)], 0.3)
	_action(&"fire", [], [MOUSE_BUTTON_LEFT], [], [Vector2(JOY_AXIS_TRIGGER_RIGHT, 1.0)], 0.3)
	_action(&"melee", [KEY_V], [], [JOY_BUTTON_RIGHT_STICK], [])
	_action(&"interact", [KEY_E], [], [JOY_BUTTON_X], [])
	_action(&"reload", [KEY_R], [], [JOY_BUTTON_X], [])
	# Weapon wheel (GDD 5.2): hold to open, tap for the last weapon.
	_action(&"weapon_wheel", [KEY_Q], [], [JOY_BUTTON_Y], [])
	_action(&"weapon_next", [], [MOUSE_BUTTON_WHEEL_DOWN], [], [])
	_action(&"weapon_prev", [], [MOUSE_BUTTON_WHEEL_UP], [], [])
	_action(&"weapon_1", [KEY_1], [], [], [])
	_action(&"weapon_2", [KEY_2], [], [], [])
	_action(&"weapon_3", [KEY_3], [], [], [])
	_action(&"weapon_4", [KEY_4], [], [], [])
	_action(&"weapon_5", [KEY_5], [], [], [])
	_action(&"weapon_6", [KEY_6], [], [], [])
	_action(&"shoulder_swap", [], [MOUSE_BUTTON_MIDDLE], [], [])
	# Godot's default ui_accept and ui_cancel have no gamepad buttons, so the pegboard and menus
	# ignored A and B. These keep the keyboard defaults and add the pad.
	_action(&"ui_accept", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [], [JOY_BUTTON_A], [])
	_action(&"ui_cancel", [KEY_ESCAPE], [], [JOY_BUTTON_B], [])
	_action(&"pause", [KEY_ESCAPE], [], [JOY_BUTTON_START], [])
	# Build a defense where you stand (intermission only): pick a recipe, then place it (ConstructionManager).
	_action(&"build", [KEY_TAB], [], [JOY_BUTTON_BACK], [])
	var err := ProjectSettings.save()
	print("Input map saved: %s" % error_string(err))
	quit(0 if err == OK else 1)


func _action(action: StringName, keys: Array[Key], mouse_buttons: Array[MouseButton], joy_buttons: Array[JoyButton],
		joy_axes: Array[Vector2], deadzone: float = 0.2) -> void:
	var events: Array[InputEvent] = []
	for key in keys:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.device = -1
		events.append(e)
	for button in mouse_buttons:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.device = -1
		events.append(e)
	for button in joy_buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = button
		e.device = -1
		events.append(e)
	for axis in joy_axes:
		var e := InputEventJoypadMotion.new()
		e.axis = int(axis.x) as JoyAxis
		e.axis_value = axis.y
		e.device = -1
		events.append(e)
	ProjectSettings.set_setting("input/" + action, {"deadzone": deadzone, "events": events})
