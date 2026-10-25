class_name PauseMenu
extends CanvasLayer
## In-game pause screen and development controls. This layer keeps running while gameplay is paused.

@export var director: WaveDirector
@export var cheats: DebugCheats
@export var hud: Hud

var _root: Control
var _panel: PanelContainer
var _status: Label
var _wave_picker: SpinBox
var _god_button: Button
var _fps_button: Button
var _model_button: Button
var _time_row: HFlowContainer
var _weather_row: HFlowContainer
var _new_game: Button
var _new_game_armed: bool = false
var _resume: Button
var _previous_mouse_mode: int = Input.MOUSE_MODE_CAPTURED


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build()
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	_root.visible = false


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"pause"):
		return
	if GameState.is_game_over:
		return
	if _root.visible:
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _root.visible:
		return
	_refresh_status()
	_god_button.text = "God mode: %s" % ("ON" if GameState.god_mode else "OFF")


func open() -> void:
	if GameState.is_game_over:
		return
	_previous_mouse_mode = Input.mouse_mode
	_disarm_new_game()
	_root.visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wave_picker.value = maxi(1, director.wave + 1) if director != null else 1
	_refresh_status()
	_refresh_sky_buttons()
	_resume.grab_focus()


func close() -> void:
	_root.visible = false
	get_tree().paused = false
	if not GameState.is_game_over and DisplayServer.get_name() != "headless":
		Input.mouse_mode = _previous_mouse_mode


func _on_wave_phase_changed(phase: int, _wave: int) -> void:
	if _root.visible and phase == WaveDirector.Phase.GAME_OVER:
		_root.visible = false


func _refresh_status() -> void:
	if director == null:
		_status.text = "Wave director unavailable"
		return
	var live := director.live_robot_count()
	var queued := director.robots_to_come()
	_status.text = "SEED  %d     WAVE  %d     %s     ROBOTS  %d live / %d queued" % [
		GameState.run_seed, director.wave, WaveDirector.PHASE_NAMES[director.phase], live, queued]


func _jump_to_selected_wave() -> void:
	if cheats != null:
		cheats.skip_to_wave(roundi(_wave_picker.value))
	close()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.035, 0.045, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_panel = PanelContainer.new()
	# 680 wide, centered, and as tall as the window allows; the contents scroll when they don't fit.
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -340.0
	_panel.offset_right = 340.0
	_panel.offset_top = 24.0
	_panel.offset_bottom = -24.0
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.16, 0.12, 0.09, 0.98)
	panel_style.border_color = Color(0.78, 0.57, 0.28)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(24)
	_panel.add_theme_stylebox_override(&"panel", panel_style)
	_root.add_child(_panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.name = "VBox"
	box.add_theme_constant_override(&"separation", 10)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	var title := _label("PAUSED", 34, Color(1.0, 0.86, 0.52))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := _label("DEVELOPMENT TOOLKIT", 15, Color(0.78, 0.84, 0.88))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	_status = _label("", 15, Color(0.88, 0.92, 0.84))
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)

	_resume = _button("Resume  ·  Esc", "Resume")
	_resume.pressed.connect(close)
	box.add_child(_resume)

	box.add_child(_section("PROGRESSION"))
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override(&"separation", 8)
	box.add_child(wave_row)
	var wave_label := _label("Jump to wave", 17)
	wave_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wave_row.add_child(wave_label)
	_wave_picker = SpinBox.new()
	_wave_picker.min_value = 1
	_wave_picker.max_value = 999
	_wave_picker.step = 1
	_wave_picker.custom_minimum_size = Vector2(110, 38)
	wave_row.add_child(_wave_picker)
	var jump := _button("Jump", "Jump to selected wave")
	jump.pressed.connect(_jump_to_selected_wave)
	wave_row.add_child(jump)
	var wave_buttons := HBoxContainer.new()
	wave_buttons.add_theme_constant_override(&"separation", 8)
	box.add_child(wave_buttons)
	var next := _button("Next wave now", "Skip directly to the next wave")
	next.pressed.connect(_skip_next_wave)
	wave_buttons.add_child(next)
	var bell := _button("Ring bell", "End intermission or siren early")
	bell.pressed.connect(_ring_bell)
	wave_buttons.add_child(bell)

	box.add_child(_section("DISPLAY"))
	_fps_button = _button("", "Show or hide the frame rate in the top-right corner")
	_fps_button.pressed.connect(_toggle_fps)
	box.add_child(_fps_button)
	_refresh_fps_button()

	box.add_child(_section("PLAYER MODEL"))
	_model_button = _button("", "Swap the clay farmer for the rigged Blender farmer (test)")
	_model_button.pressed.connect(_toggle_rigged_model)
	box.add_child(_model_button)
	_refresh_model_button()

	box.add_child(_section("TIME OF DAY"))
	_time_row = _flow_row(box)
	box.add_child(_section("WEATHER"))
	_weather_row = _flow_row(box)
	_refresh_sky_buttons()

	box.add_child(_section("DEBUG TOOLS"))
	var tools_grid := GridContainer.new()
	tools_grid.columns = 2
	tools_grid.add_theme_constant_override(&"h_separation", 8)
	tools_grid.add_theme_constant_override(&"v_separation", 8)
	box.add_child(tools_grid)
	var parts := _button("Give parts", "+100 Al, +20 Cu, +5 Au, +2 PC")
	parts.pressed.connect(_give_parts)
	tools_grid.add_child(parts)
	_god_button = _button("God mode: OFF", "Toggle invulnerability")
	_god_button.pressed.connect(_toggle_god_mode)
	tools_grid.add_child(_god_button)
	var jetpack := _button("Unlock jetpack", "Unlock the jetpack")
	jetpack.pressed.connect(_unlock_jetpack)
	tools_grid.add_child(jetpack)
	var clear := _button("Clear robots", "Remove all active robots")
	clear.pressed.connect(_clear_robots)
	tools_grid.add_child(clear)
	var damage := _button("Damage silo", "Deal 100 damage to the silo")
	damage.pressed.connect(_damage_silo)
	tools_grid.add_child(damage)
	var help := _button("Toggle debug help", "Show or hide the debug key reference")
	help.pressed.connect(_toggle_help)
	tools_grid.add_child(help)
	var restart := _button("Restart run", "Restart this scene with a fresh run")
	restart.pressed.connect(_restart_run)
	tools_grid.add_child(restart)
	var restart_empty := _button("Restart, no parts", "Restart from wave 1 with zero parts and save that")
	restart_empty.pressed.connect(_restart_with_no_parts)
	tools_grid.add_child(restart_empty)
	_new_game = _button("New game: wipe profile", "Erase the whole profile (parts, upgrades, jetpack, records, Almanac, Level 0) and start over. Click twice.")
	_new_game.pressed.connect(_new_game_pressed)
	tools_grid.add_child(_new_game)

	var footer := _label("Gameplay is frozen while this menu is open. Esc resumes.", 13,
			Color(0.72, 0.72, 0.68))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(footer)
	_wave_picker.value = maxi(1, director.wave + 1) if director != null else 1


func _skip_next_wave() -> void:
	if cheats != null and director != null:
		cheats.skip_to_wave(director.wave + 1)
	close()


func _ring_bell() -> void:
	if cheats != null:
		cheats.ring_bell()
	close()


func _give_parts() -> void:
	if cheats != null:
		cheats.give(&"all", 0)


func _toggle_god_mode() -> void:
	if cheats != null:
		cheats.toggle_god_mode()


func _unlock_jetpack() -> void:
	GameState.unlock_jetpack()


func _clear_robots() -> void:
	if director != null:
		director.clear_robots(false)


func _damage_silo() -> void:
	if cheats != null:
		cheats.damage_silo(100.0)


func _time_of_day() -> TimeOfDay:
	return get_tree().get_first_node_in_group(&"time_of_day") as TimeOfDay


func _flow_row(box: VBoxContainer) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override(&"h_separation", 6)
	row.add_theme_constant_override(&"v_separation", 6)
	box.add_child(row)
	return row


## Fills a row with one toggle button per name (once; the farm may load after this menu is built).
func _fill_row(row: HFlowContainer, names: PackedStringArray, tooltip: String, picked: Callable) -> void:
	if row.get_child_count() == names.size():
		return
	for child in row.get_children():
		child.queue_free()
	for i in names.size():
		var button := _button(names[i], tooltip)
		button.toggle_mode = true
		button.pressed.connect(picked.bind(i))
		row.add_child(button)


func _refresh_sky_buttons() -> void:
	var sky := _time_of_day()
	if sky == null or sky.table == null:
		return
	var times := PackedStringArray()
	for preset in sky.table.presets:
		times.append(preset.display_name)
	var weathers := PackedStringArray()
	for weather in sky.table.weathers:
		weathers.append(weather.display_name)
	_fill_row(_time_row, times, "Switch to this time of day", _set_time)
	_fill_row(_weather_row, weathers, "Switch to this weather", _set_weather)
	for i in _time_row.get_child_count():
		(_time_row.get_child(i) as Button).set_pressed_no_signal(i == sky.preset_index)
	for i in _weather_row.get_child_count():
		(_weather_row.get_child(i) as Button).set_pressed_no_signal(i == sky.weather_index)


func _set_time(index: int) -> void:
	var sky := _time_of_day()
	if sky != null and sky.run_roll != null:
		sky.show_preset(index, false)
	_refresh_sky_buttons()


func _set_weather(index: int) -> void:
	var sky := _time_of_day()
	if sky != null and sky.run_roll != null:
		sky.set_weather_index(index)
	_refresh_sky_buttons()


func _toggle_fps() -> void:
	SaveManager.settings["show_fps"] = not bool(SaveManager.settings.get("show_fps", false))
	SaveManager.save_settings()
	if hud != null:
		hud.set_fps_visible(SaveManager.settings["show_fps"])
	_refresh_fps_button()


func _refresh_fps_button() -> void:
	_fps_button.text = "Show FPS: %s" % ("ON" if SaveManager.settings.get("show_fps", false) else "OFF")


func _toggle_rigged_model() -> void:
	SaveManager.settings["rigged_farmer"] = not bool(SaveManager.settings.get("rigged_farmer", false))
	SaveManager.save_settings()
	for farmer in get_tree().get_nodes_in_group(&"players"):
		(farmer as Farmer).set_rigged_model(bool(SaveManager.settings["rigged_farmer"]))
	_refresh_model_button()


func _refresh_model_button() -> void:
	_model_button.text = "Player model: %s" % ("Rigged farmer (test)" if SaveManager.settings.get("rigged_farmer", false) else "Clay farmer")


func _toggle_help() -> void:
	if hud != null:
		hud.toggle_help()


func _restart_run() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _restart_with_no_parts() -> void:
	GameState.clear_parts()
	SaveManager.save_profile()
	_restart_run()


## Two clicks, because this erases saved progress. The first click arms the button.
func _new_game_pressed() -> void:
	if not _new_game_armed:
		_new_game_armed = true
		_new_game.text = "Click again to wipe"
		return
	_disarm_new_game()
	SaveManager.reset_profile()
	_restart_run()


func _disarm_new_game() -> void:
	_new_game_armed = false
	if _new_game != null:
		_new_game.text = "New game: wipe profile"


func _section(text: String) -> Label:
	var label := _label(text, 15, Color(0.95, 0.68, 0.34))
	label.add_theme_constant_override(&"outline_size", 0)
	return label


func _label(text: String, font_size: int, color: Color = Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	return label


func _button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.custom_minimum_size = Vector2(0, 38)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button
