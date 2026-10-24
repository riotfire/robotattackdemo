class_name Hud
extends CanvasLayer
## Graybox HUD (GDD 17.2): silo Structure and Grain, farmer HP and armor, jetpack fuel arc, wave and
## phase, intermission countdown, weapon and ammo, parts, thieves, the family name card, prompts, toasts
## and the Harvest Report. Built in code because it is graybox UI; the cardboard-and-felt look comes later.
## Keeps processing while the tree is paused so it can show game over and handle restart.

@export var director: WaveDirector

var _player: Farmer = null

var _wave_label: Label
var _phase_label: Label
var _robots_label: Label
var _structure_bar: ProgressBar
var _structure_label: Label
var _grain_bar: ProgressBar
var _grain_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _armor_bar: ProgressBar
var _family_label: Label
var _name_card: PanelContainer
var _name_card_title: Label
var _name_card_detail: Label
var _name_card_left: float = 0.0
var _hint_label: Label
var _weapon_label: Label
var _parts_label: Label
var _prompt_label: Label
var _toast_label: Label
var _toast_left: float = 0.0
var _repair_bar: ProgressBar
var _crosshair: Crosshair
var _weapon_wheel: WeaponWheel
var _game_over_panel: PanelContainer
var _game_over_label: Label
var _help_label: Label
var _tutorial_lesson: Label
var _tutorial_action: String = ""
var _silo_alert: PanelContainer
var _fps_label: Label
var _fps_refresh_left: float = 0.0
var _silo_alert_title: Label
var _silo_alert_detail: Label
var _silo_alert_style: StyleBoxFlat
var _silo_hit_left: float = 0.0
var _silo_alarm_cooldown: float = 0.0
var _theft_explained: bool = false
var _sack_explained: bool = false
var _grain_return_explained: bool = false
var _build_choice_prompted: bool = false
const SILO_HIT_HOLD: float = 5.0
const SILO_ALARM_COOLDOWN: float = 9.0
const SILO_REMOTE_DISTANCE: float = 15.0
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	EventBus.hud_message.connect(show_message)
	EventBus.game_over.connect(_on_game_over)
	EventBus.player_registered.connect(_on_player_registered)
	EventBus.family_revealed.connect(_on_family_revealed)
	EventBus.grain_stolen.connect(_on_grain_stolen)
	EventBus.robot_destroyed.connect(_on_robot_destroyed)
	EventBus.grain_returned.connect(_on_grain_returned)
	EventBus.silo_damaged.connect(_on_silo_damaged)
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	EventBus.upgrade_purchased.connect(_on_upgrade_purchased)
	for player in GameState.players:
		_on_player_registered(player)


func _on_player_registered(player: Node3D) -> void:
	if _player == null and player is Farmer:
		_player = player
		_weapon_wheel.holder = _player.weapons


func show_message(text: String, duration: float = 2.5) -> void:
	_toast_label.text = text
	_toast_left = duration


## A short explanation above the normal HUD. Actions and hold progress stay in their usual HUD positions.
func set_tutorial_lesson(text: String) -> void:
	_tutorial_lesson.text = text
	_tutorial_lesson.visible = not text.is_empty()


func set_tutorial_action(text: String) -> void:
	_tutorial_action = text


func _on_grain_stolen(_amount: float, _thief: Node3D) -> void:
	if not _theft_explained:
		_theft_explained = true
		show_message("That robot stole grain! Pop it to drop the sack.", 4.0)


func _on_robot_destroyed(robot: Node3D, _killer: Node) -> void:
	if not _sack_explained and robot is Robot and (robot as Robot).sack_amount > 0.0:
		_sack_explained = true
		show_message("It dropped the sack. Walk over it to return grain.", 4.0)


func _on_grain_returned(_amount: float) -> void:
	if _sack_explained and not _grain_return_explained:
		_grain_return_explained = true
		show_message("Grain returned to the silo.", 2.5)


func _on_silo_damaged(_amount: float, _at_position: Vector3) -> void:
	if (director != null and director.phase == WaveDirector.Phase.TUTORIAL) or GameState.is_game_over:
		return
	_silo_hit_left = SILO_HIT_HOLD
	if _silo_alarm_cooldown > 0.0 or _player == null or not is_instance_valid(_player):
		return
	var silo := GameState.silo
	if silo != null and silo.distance_to_wall(_player.global_position) >= SILO_REMOTE_DISTANCE:
		AudioDirector.play_cue(&"silo_alarm")
		_silo_alarm_cooldown = SILO_ALARM_COOLDOWN


func _on_wave_phase_changed(phase: int, wave: int) -> void:
	if phase == WaveDirector.Phase.INTERMISSION and wave == 2 and not _build_choice_prompted:
		_build_choice_prompted = true
		set_tutorial_lesson("The shed is open. Spend robot parts on what you need:\nwrench power, a pistol for range, repairs/defense, or speed.")
	elif wave >= 2 and phase != WaveDirector.Phase.INTERMISSION and _build_choice_prompted:
		set_tutorial_lesson("")


func _on_upgrade_purchased(_id: StringName, _level: int) -> void:
	if _build_choice_prompted and director != null and director.phase == WaveDirector.Phase.INTERMISSION:
		set_tutorial_lesson("")


func toggle_help() -> void:
	_help_label.visible = not _help_label.visible


## Shows or hides the FPS counter in the top-right corner (the pause menu owns the setting).
func set_fps_visible(on: bool) -> void:
	_fps_label.visible = on
	_fps_refresh_left = 0.0


func _update_fps(delta: float) -> void:
	_fps_refresh_left -= delta
	if _fps_label.visible and _fps_refresh_left <= 0.0:
		_fps_refresh_left = 0.25
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _process(delta: float) -> void:
	_update_fps(delta)
	_update_wave()
	_update_silo()
	_update_player()
	_update_silo_alert(delta)
	_toast_left -= delta
	_toast_label.visible = _toast_left > 0.0
	_name_card_left -= delta
	_name_card.visible = _name_card_left > 0.0
	_parts_label.text = "Al %d\nCu %d\nAu %d\nPC %d" % [
		GameState.parts[&"al"], GameState.parts[&"cu"], GameState.parts[&"au"], GameState.parts[&"pc"]]


func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_game_over:
		return
	var restart := event.is_action_pressed(&"jump") or event.is_action_pressed(&"interact")
	if event is InputEventKey and (event as InputEventKey).pressed:
		restart = restart or (event as InputEventKey).physical_keycode in [KEY_R, KEY_ENTER, KEY_KP_ENTER]
	if restart:
		get_viewport().set_input_as_handled()
		get_tree().paused = false
		get_tree().reload_current_scene()


func _update_wave() -> void:
	var wave := maxi(1, GameState.wave)
	_wave_label.text = "PHASE %d  ·  WAVE %d" % [GameState.phase_of(wave), GameState.wave_in_phase(wave)]
	if director == null:
		return
	match director.phase:
		WaveDirector.Phase.INTERMISSION:
			_phase_label.text = "INTERMISSION  %s" % _clock(director.time_left)
		WaveDirector.Phase.SIREN:
			_phase_label.text = "SIREN!  Robots in %s" % _clock(director.time_left)
		WaveDirector.Phase.SPAWNING:
			_phase_label.text = "ATTACK  %s" % _clock(director.spawn_window - director.spawn_clock)
		WaveDirector.Phase.MOP_UP:
			_phase_label.text = "MOP-UP"
		WaveDirector.Phase.CLEARED:
			_phase_label.text = "CLEARED!"
		WaveDirector.Phase.GAME_OVER:
			_phase_label.text = "GAME OVER"
		WaveDirector.Phase.TUTORIAL:
			_phase_label.text = "MORNING CHORES"
	if director.phase == WaveDirector.Phase.TUTORIAL:
		_wave_label.text = "PREPARE FOR WAVE 1"
		_robots_label.text = "Defend the silo"
		_family_label.text = ""
		return
	var to_come := director.robots_to_come()
	var thieves := get_tree().get_nodes_in_group(Robot.THIEF_GROUP).size()
	_robots_label.text = "Robots %d%s%s" % [director.live_robot_count(), "  +%d coming" % to_come if to_come > 0 else "",
			"   THIEVES %d!" % thieves if thieves > 0 else ""]
	_family_label.text = director.genome.family_name if director.genome != null else ""


func _update_silo() -> void:
	var silo := GameState.silo
	if silo == null:
		return
	_structure_bar.value = silo.structure_fraction() * 100.0
	_structure_label.text = "STRUCTURE  %d / %d   %s" % [ceili(silo.structure), roundi(silo.max_structure),
			Silo.DAMAGE_STATES[silo.damage_state()]]
	_grain_bar.value = silo.grain_fraction() * 100.0
	var cracks := silo.get_cracks().size()
	var leak := silo.total_leak_rate()
	_grain_label.text = "GRAIN  %d bu" % ceili(silo.grain) + ("   leaking %.1f/s  (%d crack%s)" % [leak, cracks, "" if cracks == 1 else "s"] if cracks > 0 else "")
	var warning := silo.damage_state() == 4 or _silo_hit_left > 0.0
	_structure_bar.modulate = Color(1.0, 0.6, 0.6) if warning and int(Time.get_ticks_msec() / 250.0) % 2 == 0 else Color.WHITE


func _update_silo_alert(delta: float) -> void:
	_silo_hit_left = maxf(0.0, _silo_hit_left - delta)
	_silo_alarm_cooldown = maxf(0.0, _silo_alarm_cooldown - delta)
	var silo := GameState.silo
	if (director != null and director.phase == WaveDirector.Phase.TUTORIAL) or GameState.is_game_over \
			or silo == null or _player == null or not is_instance_valid(_player):
		_silo_alert.visible = false
		_tutorial_lesson.visible = not _tutorial_lesson.text.is_empty()
		return
	var distance := maxf(0.0, silo.distance_to_wall(_player.global_position))
	var under_attack := _silo_hit_left > 0.0
	var leaking_away := silo.total_leak_rate() > 0.0 and distance >= SILO_REMOTE_DISTANCE
	_silo_alert.visible = under_attack or leaking_away
	_tutorial_lesson.visible = not _tutorial_lesson.text.is_empty() and not _silo_alert.visible
	if not _silo_alert.visible:
		return
	_silo_alert_title.text = "SILO UNDER ATTACK!" if under_attack else "SILO LEAKING GRAIN"
	_silo_alert_style.bg_color = Color(0.48, 0.08, 0.07, 0.94) if under_attack else Color(0.36, 0.24, 0.06, 0.92)
	_silo_alert_style.border_color = Color(1.0, 0.42, 0.24) if under_attack else Color(1.0, 0.79, 0.33)
	var direction := _silo_direction(silo.global_position - _player.global_position)
	var location := "Defend the silo" if distance < SILO_REMOTE_DISTANCE else "Silo %s · %d m away" % [direction, roundi(distance)]
	_silo_alert_detail.text = "%s · %d%% Structure%s" % [location, roundi(silo.structure_fraction() * 100.0),
		" · seal the leak" if not under_attack else ""]
	_silo_alert.modulate.a = 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.014) if under_attack else 1.0


func _silo_direction(offset: Vector3) -> String:
	offset.y = 0.0
	if offset.length_squared() < 0.001:
		return "ahead"
	var toward := offset.normalized()
	var forward := _player.camera_rig.flat_forward()
	var right := _player.camera_rig.flat_basis().x
	var ahead := toward.dot(forward)
	var sideways := toward.dot(right)
	if absf(ahead) >= absf(sideways):
		return "ahead" if ahead >= 0.0 else "behind you"
	return "to your right" if sideways >= 0.0 else "to your left"


func _update_player() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = null
		return
	_hp_bar.value = _player.health.fraction() * 100.0
	_hp_label.text = "HP  %d / %d%s%s" % [ceili(_player.health.current), roundi(_player.health.max_health),
			"   ARMOR %d" % ceili(_player.armor) if _player.max_armor > 0.0 else "", "   (GOD MODE)" if GameState.god_mode else ""]
	_armor_bar.visible = _player.max_armor > 0.0
	_armor_bar.value = _player.armor / _player.max_armor * 100.0 if _player.max_armor > 0.0 else 0.0
	var slots := PackedStringArray()
	for carried in _player.weapons.weapons:
		slots.append("%d %s%s" % [carried.data.slot, carried.display_name, "" if carried.is_available() else " (buy at the shed)"])
	_hint_label.text = "%s   hold Q wheel   V bonk   R reload   E use   F1 debug" % "  ".join(slots)
	var weapon := _player.weapons.current
	if weapon != null:
		var ammo := weapon.ammo_text()
		_weapon_label.text = weapon.display_name + ("   " + ammo if ammo != "" else "")
	_crosshair.fuel = _player.jetpack.fuel_fraction() if GameState.jetpack_unlocked else -1.0
	_crosshair.queue_redraw()

	var prompt := ""
	_repair_bar.visible = false
	if _player.repair.target != null and is_instance_valid(_player.repair.target):
		var crack := _player.repair.target
		_repair_bar.value = crack.repair_fraction() * 100.0
		_repair_bar.visible = true
		prompt = ("Repairing " if _player.repair.is_repairing else "Hold E / (X) to repair: ") + crack.describe()
	elif _player.interaction.focus != null:
		var target := _player.interaction.focus
		var usable := target.can_interact(_player)
		prompt = ("E / (X): " if usable else "") + target.prompt_text(_player)
		if usable and target.hold_time > 0.0:
			_repair_bar.value = _player.interaction.progress * 100.0
			_repair_bar.visible = true
	elif _player.movement.can_step_off_ladder():
		prompt = "SPACE / (A): step onto the catwalk"
	elif _player.state == Farmer.State.CLIMBING:
		prompt = "W/S climb   SPACE let go"
	elif _player.state == Farmer.State.ZIPLINING:
		prompt = "SPACE: let go of the zipline"
	if prompt.is_empty():
		prompt = _tutorial_action
	_prompt_label.text = prompt


func _on_game_over(reason: StringName) -> void:
	var cause := "The robots"
	match reason:
		&"silo":
			cause = "The silo was destroyed!"
		&"grain":
			cause = "The robots got the last of the grain!"
		&"farmer":
			cause = "The farmer is down!"
	var survived := GameState.waves_survived
	var best := int(SaveManager.records.get("best_wave", 0))
	var families := 0
	if director != null:
		families = director.genome_history.size()
	_game_over_label.text = "HARVEST REPORT\n\n%s\n\nWaves survived: %d  (Phase %d · Wave %d)%s\nFamilies met: %d\nParts banked: Al %d  Cu %d  Au %d  PC %d\n\nPress R, Enter or Jump to farm again" % [
		cause, survived, GameState.phase_of(maxi(1, survived)), GameState.wave_in_phase(maxi(1, survived)),
		"   NEW RECORD!" if survived >= best and survived > 0 else "   (best %d)" % best, families,
		GameState.parts[&"al"], GameState.parts[&"cu"], GameState.parts[&"au"], GameState.parts[&"pc"]]
	_game_over_panel.visible = true


## The wave's family name card (GDD 10.2, 17.2), shown through the siren.
func _on_family_revealed(genome: Resource) -> void:
	var family := genome as RobotGenome
	if family == null:
		return
	_name_card_title.text = family.family_name.to_upper()
	var traits := family.trait_names()
	_name_card_detail.text = "Family code %s   ·   %s   ·   %s" % [family.family_code,
			"Traits: " + ", ".join(traits) if not traits.is_empty() else "No traits",
			family.personality.capitalize()]
	_name_card.add_theme_stylebox_override(&"panel", _card_style(family.palette.primary, family.palette.secondary))
	_name_card_left = 9.0


static func _card_style(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill.darkened(0.55), 0.92)
	style.border_color = border.lightened(0.2)
	style.set_border_width_all(4)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(14)
	return style


static func _clock(seconds: float) -> String:
	var s := maxi(0, ceili(seconds))
	return "%d:%02d" % [floori(s / 60.0), s % 60]


# --- Construction ---------------------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top_left := _vbox(root, Control.PRESET_TOP_LEFT, Vector2(24, 20))
	_wave_label = _label(top_left, 30)
	_phase_label = _label(top_left, 24, Color(1.0, 0.85, 0.4))
	_robots_label = _label(top_left, 18)
	_family_label = _label(top_left, 15, Color(0.85, 0.9, 1.0))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	top_left.add_child(spacer)
	_label(top_left, 18, Color(0.9, 0.9, 0.9)).text = "SILO"
	_structure_bar = _bar(top_left, Color(0.85, 0.3, 0.25), 340)
	_structure_label = _label(top_left, 15)
	_grain_bar = _bar(top_left, Color(0.95, 0.78, 0.3), 340)
	_grain_label = _label(top_left, 15)

	var bottom_left := _vbox(root, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24))
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hp_label = _label(bottom_left, 16)
	_hp_bar = _bar(bottom_left, Color(0.4, 0.85, 0.4), 300)
	_armor_bar = _bar(bottom_left, Color(0.55, 0.75, 1.0), 300)
	_armor_bar.visible = false

	var bottom_right := _vbox(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -24))
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_weapon_label = _label(bottom_right, 24)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label = _label(bottom_right, 13, Color(0.85, 0.85, 0.85))
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var top_right := _vbox(root, Control.PRESET_TOP_RIGHT, Vector2(-24, 20))
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label = _label(top_right, 16, Color(0.7, 0.95, 0.7))
	_fps_label.visible = bool(SaveManager.settings.get("show_fps", false))
	_parts_label = _label(top_right, 18)
	_parts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_crosshair = Crosshair.new()
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_crosshair)
	_place(_crosshair, Control.PRESET_CENTER, Rect2(0, 0, 0, 0))

	_weapon_wheel = WeaponWheel.new()
	root.add_child(_weapon_wheel)
	_place(_weapon_wheel, Control.PRESET_CENTER, Rect2(0, 0, 0, 0))

	_repair_bar = _bar(root, Color(1.0, 0.75, 0.25), 160)
	_place(_repair_bar, Control.PRESET_CENTER, Rect2(-80, 44, 160, 16))
	_repair_bar.visible = false

	_prompt_label = _label(root, 20, Color(1.0, 0.95, 0.75))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_prompt_label, Control.PRESET_CENTER_BOTTOM, Rect2(-400, -160, 800, 30))

	_toast_label = _label(root, 30, Color(1.0, 0.9, 0.45))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_toast_label, Control.PRESET_CENTER_TOP, Rect2(-600, 130, 1200, 40))
	_toast_label.visible = false

	_tutorial_lesson = _label(root, 22, Color(1.0, 0.96, 0.82))
	_tutorial_lesson.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tutorial_lesson.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tutorial_lesson.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_lesson.add_theme_color_override(&"font_shadow_color", Color(0.08, 0.05, 0.03, 0.95))
	_tutorial_lesson.add_theme_constant_override(&"shadow_offset_x", 2)
	_tutorial_lesson.add_theme_constant_override(&"shadow_offset_y", 2)
	_place(_tutorial_lesson, Control.PRESET_CENTER_TOP, Rect2(-440, 24, 880, 76))
	_tutorial_lesson.visible = false

	_silo_alert = PanelContainer.new()
	_silo_alert.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_silo_alert_style = StyleBoxFlat.new()
	_silo_alert_style.set_corner_radius_all(12)
	_silo_alert_style.set_border_width_all(3)
	_silo_alert_style.set_content_margin_all(12)
	_silo_alert.add_theme_stylebox_override(&"panel", _silo_alert_style)
	var silo_alert_text := VBoxContainer.new()
	_silo_alert.add_child(silo_alert_text)
	_silo_alert_title = _label(silo_alert_text, 26, Color(1.0, 0.96, 0.84))
	_silo_alert_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_silo_alert_detail = _label(silo_alert_text, 17, Color(1.0, 0.94, 0.82))
	_silo_alert_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_silo_alert)
	_place(_silo_alert, Control.PRESET_CENTER_TOP, Rect2(-275, 24, 550, 82))
	_silo_alert.visible = false

	_name_card = PanelContainer.new()
	_name_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_box := VBoxContainer.new()
	_name_card.add_child(card_box)
	_name_card_title = _label(card_box, 30, Color(1.0, 0.95, 0.85))
	_name_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_card_detail = _label(card_box, 16, Color(0.9, 0.9, 0.95))
	_name_card_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_card.visible = false
	root.add_child(_name_card)
	_place(_name_card, Control.PRESET_CENTER_TOP, Rect2(-380, 185, 760, 90))

	_help_label = _label(root, 16)
	_help_label.text = DebugCheats.HELP_TEXT
	_place(_help_label, Control.PRESET_CENTER_RIGHT, Rect2(-460, -150, 440, 300))
	_help_label.visible = false

	_game_over_panel = PanelContainer.new()
	_game_over_panel.custom_minimum_size = Vector2(640, 340)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.12, 0.08, 0.92)
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(24)
	_game_over_panel.add_theme_stylebox_override(&"panel", panel_style)
	_game_over_label = _label(_game_over_panel, 22)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over_panel.visible = false
	root.add_child(_game_over_panel)
	_place(_game_over_panel, Control.PRESET_CENTER, Rect2(-320, -170, 640, 340))


## Anchors `control` to a preset point and offsets it by `rect` from that anchor.
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _vbox(parent: Control, preset: Control.LayoutPreset, nudge: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	box.set_anchors_and_offsets_preset(preset)
	box.position += nudge
	box.add_theme_constant_override(&"separation", 4)
	return box


func _label(parent: Control, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override(&"outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control, color: Color, width: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 16)
	bar.size = bar.custom_minimum_size
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(5)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	background.set_corner_radius_all(5)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.add_theme_stylebox_override(&"background", background)
	parent.add_child(bar)
	return bar


## Crosshair plus the jetpack fuel arc beside it (GDD 17.2). fuel < 0 hides the arc.
class Crosshair:
	extends Control

	var fuel: float = -1.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, 2.5, Color(1, 1, 1, 0.95))
		draw_arc(Vector2.ZERO, 11.0, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 1.5, true)
		if fuel >= 0.0:
			var start := PI * 0.75
			draw_arc(Vector2.ZERO, 26.0, start, start + PI * 0.5, 24, Color(0, 0, 0, 0.35), 5.0, true)
			if fuel > 0.0:
				var color := Color(0.4, 0.85, 1.0) if fuel > 0.25 else Color(1.0, 0.45, 0.3)
				draw_arc(Vector2.ZERO, 26.0, start + PI * 0.5 * (1.0 - fuel), start + PI * 0.5, 24, color, 5.0, true)
