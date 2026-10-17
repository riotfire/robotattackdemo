class_name DebugCheats
extends Node
## Debug keys and a tiny console (GDD 18.9). Only active in debug builds.

const HELP_TEXT := """DEBUG KEYS
F1  this help
F2  ring the bell (skip intermission / siren)
F3  give parts (+100 Al +20 Cu +5 Au +2 PC)
F4  clear all robots
F5  skip to the next wave
F6  god mode
F7  unlock the jetpack
F8  damage the silo (100)
`   console:  wave <n>   give <al|cu|au|pc|all> <n>
              godmode   jetpack   silo <dmg>   grain <n>
              kill   bell   buy <upgrade id>   intermission <s>
              reset (wipe profile)"""

@export var director: WaveDirector
@export var hud: Hud

var _console: LineEdit


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)
		set_process_unhandled_key_input(false)
		return
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	_console = LineEdit.new()
	_console.placeholder_text = "wave 5 | give al 100 | godmode | jetpack | silo 200 | grain 500 | kill | bell | buy attack.pistol | reset"
	_console.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_console.offset_top = 300.0
	_console.offset_left = 400.0
	_console.offset_right = -400.0
	_console.visible = false
	_console.text_submitted.connect(_on_console_submitted)
	layer.add_child(_console)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_QUOTELEFT:
		_toggle_console(not _console.visible)
		get_viewport().set_input_as_handled()
	elif _console.visible and key.physical_keycode == KEY_ESCAPE:
		_toggle_console(false)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F1:
			if hud != null:
				hud.toggle_help()
		KEY_F2:
			ring_bell()
		KEY_F3:
			give(&"all", 0)
		KEY_F4:
			if director != null:
				director.clear_robots(false)
			_say("Robots cleared")
		KEY_F5:
			if director != null:
				skip_to_wave(director.wave + 1)
		KEY_F6:
			toggle_god_mode()
		KEY_F7:
			GameState.unlock_jetpack()
			_say("Jetpack unlocked")
		KEY_F8:
			damage_silo(100.0)
		_:
			return
	get_viewport().set_input_as_handled()


func ring_bell() -> void:
	if director != null:
		director.ring_bell()


func skip_to_wave(n: int) -> void:
	if director != null:
		director.skip_to_wave(n)
		_say("Skipping to wave %d" % n)


func give(part: StringName, amount: int) -> void:
	if part == &"all":
		GameState.add_parts({&"al": 100, &"cu": 20, &"au": 5, &"pc": 2})
		_say("+100 Al  +20 Cu  +5 Au  +2 PC")
	elif part in GameState.PART_KEYS:
		GameState.add_parts({part: amount})
		_say("+%d %s" % [amount, GameState.PART_NAMES[part]])


func toggle_god_mode() -> void:
	GameState.god_mode = not GameState.god_mode
	_say("God mode %s" % ("ON" if GameState.god_mode else "OFF"))


## Hits the silo wall facing the first player, so cracks open where you can see them.
func damage_silo(amount: float) -> void:
	var silo := GameState.silo
	if silo == null:
		return
	var from := GameState.players[0].global_position if not GameState.players.is_empty() else Vector3.FORWARD * 10.0
	silo.take_damage(DamagePacket.create(amount, self, silo.wall_point_toward(from, 1.0)))
	_say("Silo -%d" % roundi(amount))


## Sets the intermission length for this session (ROADMAP D1); trims the current countdown if longer.
func set_intermission(seconds: float) -> void:
	if director == null or seconds <= director.siren_lead_time:
		_say("Intermission must be longer than the %d s siren" % roundi(director.siren_lead_time if director else 10.0))
		return
	director.intermission_time = seconds
	if director.phase == WaveDirector.Phase.INTERMISSION:
		director.time_left = minf(director.time_left, seconds)
	_say("Intermission: %d s" % roundi(seconds))


func _on_console_submitted(text: String) -> void:
	_console.clear()
	var words := text.strip_edges().to_lower().split(" ", false)
	if words.is_empty():
		_toggle_console(false)
		return
	var arg := words[1] if words.size() > 1 else ""
	match words[0]:
		"wave":
			skip_to_wave(maxi(1, arg.to_int()))
		"give":
			give(StringName(arg), words[2].to_int() if words.size() > 2 else 100)
		"godmode", "god":
			toggle_god_mode()
		"jetpack":
			GameState.unlock_jetpack()
			_say("Jetpack unlocked")
		"silo":
			damage_silo(arg.to_float() if arg != "" else 100.0)
		"grain":
			if GameState.silo != null:
				GameState.silo.grain = clampf(arg.to_float(), 0.0, GameState.silo.max_grain)
		"kill":
			if director != null:
				director.clear_robots(false)
		"bell":
			ring_bell()
		"buy":
			var id := StringName(text.strip_edges().split(" ", false)[1]) if words.size() > 1 else &""
			_say("Bought %s" % id if StatService.purchase(id) else "Can't buy %s" % id)
		"intermission":
			set_intermission(arg.to_float())
		"reset":
			SaveManager.reset_profile()
			_say("Profile wiped: parts, upgrades, jetpack and records")
		_:
			_say("Unknown command: %s" % words[0])
	_toggle_console(false)


func _toggle_console(open: bool) -> void:
	_console.visible = open
	for player in GameState.players:
		var router := player.get_node_or_null(^"InputRouter") as InputRouter
		if router != null:
			router.enabled = not open
	if open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_console.grab_focus()
	else:
		_console.release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _say(text: String) -> void:
	EventBus.hud_message.emit(text, 2.0)
