class_name Hud
extends CanvasLayer
## Graybox HUD (GDD 17.2): silo Structure and Grain, farmer HP and armor, jetpack fuel arc, wave and
## phase, intermission countdown, weapon and ammo, parts, thieves, the family name card, prompts, toasts
## and the Harvest Report. Built in code because it is graybox UI; the cardboard-and-felt look comes later.
## Keeps processing while the tree is paused so it can show game over and handle Retry Phase / Start over.
## Also (the playtest simulation and defense plans): the authored wave's title and hint between waves, the
## worst leak with its time to seal, a low-health warning pointing at the nearest heal, a climbing warning
## while a Rung Runner is on the silo ladder or catwalk, the construction status, and reward banners.

## The intermission before the first split-pressure wave, where the HUD asks for a spring at the ladder top.
const SPRING_LESSON_WAVE: int = 5

@export var director: WaveDirector

var _player: Farmer = null

var _wave_label: Label
var _phase_number_label: Label
var _phase_label: Label
var _phase_pill: StyleBoxFlat
var _robots_label: Label
var _boss: Robot
var _last_player_hp: float = -1.0
var _hp_flash_left: float = 0.0
var _boss_root: Control
var _boss_card: Control  # the panel, so shaking moves the whole card
var _boss_bar: ProgressBar
var _boss_name: Label
var _boss_shown: float = 100.0
var _boss_shake_left: float = 0.0
var _boss_glow_left: float = 0.0
var _structure_bar: ProgressBar
var _grain_bar: ProgressBar
var _leak_label: Label
var _hp_bar: ProgressBar
var _armor_bar: ProgressBar
var _god_label: Label
var _family_label: Label
var _name_card: PanelContainer
var _name_card_title: Label
var _name_card_detail: Label
var _name_card_left: float = 0.0
var _hint_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _magazine_label: Label
var _slot_row: HBoxContainer
var _slot_chips: Dictionary[int, Label] = {}
var _part_labels: Dictionary[StringName, Label] = {}
var _chip_on: StyleBoxFlat
var _chip_off: StyleBoxFlat
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
var _climbers: Array[Node3D] = []
var _climber_alert: Label
var _low_hp_label: Label
var _vignette: TextureRect
var _build_label: Label
var _leak_hint: Label
var _banner_left: float = 0.0
var _worst_crack: SiloCrack = null
var _retry_button: Button
var _start_over_button: Button
var _pegboard_button: Button
var _report_ready_at: int = 0
const LOW_HP: float = 0.3
const SILO_HIT_HOLD: float = 5.0
const SILO_ALARM_COOLDOWN: float = 9.0
const SILO_REMOTE_DISTANCE: float = 15.0
## HUD palette: warm cream text on translucent dark-clay cards.
const INK := Color(1.0, 0.96, 0.86)
const INK_DIM := Color(0.93, 0.87, 0.74, 0.8)
const CARD := Color(0.13, 0.09, 0.06, 0.55)
const PART_COLORS: Dictionary[StringName, Color] = {
	&"al": Color(0.78, 0.82, 0.86), &"cu": Color(0.86, 0.5, 0.3), &"au": Color(1.0, 0.8, 0.28), &"pc": Color(0.45, 0.88, 1.0)}
const PART_SHORT: Dictionary[StringName, String] = {&"al": "Al", &"cu": "Cu", &"au": "Au", &"pc": "PC"}


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
	EventBus.reward_granted.connect(_on_reward_granted)
	EventBus.climber_alert.connect(_on_climber_alert)
	EventBus.crack_closed.connect(_on_crack_closed)
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
		set_tutorial_lesson("The shed sells tools and upgrades. The STABLES workshop builds defenses.\nSpend your parts, then ring the dinner bell when you're ready.")
		_banner_left = 0.0
	elif phase == WaveDirector.Phase.INTERMISSION and wave == SPRING_LESSON_WAVE and not StatService.has_flag(&"defense.spring_trap"):
		# Split pressure starts next wave: the first time defenses decide a wave (ROADMAP 4.13).
		_build_choice_prompted = true
		set_tutorial_lesson("Next wave splits up: a climber on the silo ladder AND a raid on the far side.\nBuild a Spring Trap at the STABLES, pick it up, then carry it to the ladder top.")
		_banner_left = 0.0
	elif wave >= 2 and phase != WaveDirector.Phase.INTERMISSION and _build_choice_prompted and _banner_left <= 0.0:
		set_tutorial_lesson("")


func _on_upgrade_purchased(id: StringName, _level: int) -> void:
	if id == &"build.spring_trap" and director != null and director.phase == WaveDirector.Phase.INTERMISSION:
		set_tutorial_lesson("Spring Trap recipe! Visit the STABLES workshop to build a copy and pick it up.\nCarry it to the ladder top. A climber that steps on it gets thrown off.")
		_banner_left = 8.0
		return
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
	_update_banner(delta)
	_update_climbers()
	_update_low_hp()
	_update_build()
	_update_worst_leak()
	_update_boss(delta)
	_toast_left -= delta
	_toast_label.visible = _toast_left > 0.0
	_name_card_left -= delta
	_name_card.visible = _name_card_left > 0.0
	for key: StringName in _part_labels:
		_part_labels[key].text = str(GameState.parts[key])


## After a loss: Retry Phase (R, Enter, Jump, Interact), Start over at Phase 1 (Backspace, Y) or the pegboard
## with no clock running (P, Start). PHASE_CHECKPOINT_PROGRESSION_PLAN.md's retry flow.
func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_game_over or Time.get_ticks_msec() < _report_ready_at or _pegboard_open():
		return
	var key := event as InputEventKey
	var joy := event as InputEventJoypadButton
	var code := key.physical_keycode if key != null and key.pressed and not key.echo else KEY_NONE
	var button := joy.button_index if joy != null and joy.pressed else JOY_BUTTON_INVALID
	if code == KEY_BACKSPACE or button == JOY_BUTTON_Y:
		get_viewport().set_input_as_handled()
		_start_again(false)
	elif code == KEY_P or button == JOY_BUTTON_START:
		get_viewport().set_input_as_handled()
		_open_report_pegboard()
	elif event.is_action_pressed(&"jump") or event.is_action_pressed(&"interact") \
			or code in [KEY_R, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_start_again(true)


func _start_again(retry: bool) -> void:
	Main.restart(get_tree(), retry)


func _pegboard_open() -> bool:
	var pegboard := _pegboard()
	return pegboard != null and pegboard.is_open


func _pegboard() -> PegboardUI:
	return get_parent().get_node_or_null(^"Pegboard") as PegboardUI if get_parent() != null else null


func _open_report_pegboard() -> void:
	var pegboard := _pegboard()
	if pegboard != null and _player != null and is_instance_valid(_player):
		pegboard.open(_player)


func _update_wave() -> void:
	var wave := maxi(1, GameState.wave)
	_wave_label.text = "WAVE %d" % GameState.wave_in_phase(wave)
	_phase_number_label.text = "PHASE %d" % GameState.phase_of(wave)
	if director == null:
		return
	var pill := Color(0.35, 0.3, 0.22)
	match director.phase:
		WaveDirector.Phase.INTERMISSION:
			_phase_label.text = "INTERMISSION  %s" % _clock(director.time_left)
			pill = Color(0.3, 0.5, 0.25)
		WaveDirector.Phase.SIREN:
			_phase_label.text = "SIREN!  %s" % _clock(director.time_left)
			pill = Color(0.75, 0.45, 0.1) if int(Time.get_ticks_msec() / 400.0) % 2 == 0 else Color(0.6, 0.3, 0.08)
		WaveDirector.Phase.SPAWNING:
			_phase_label.text = "ATTACK  %s" % _clock(director.spawn_window - director.spawn_clock)
			pill = Color(0.7, 0.2, 0.15)
		WaveDirector.Phase.MOP_UP:
			_phase_label.text = "MOP-UP"
			pill = Color(0.6, 0.28, 0.15)
		WaveDirector.Phase.CLEARED:
			_phase_label.text = "CLEARED!"
			pill = Color(0.25, 0.55, 0.35)
		WaveDirector.Phase.GAME_OVER:
			_phase_label.text = "GAME OVER"
			pill = Color(0.3, 0.1, 0.1)
		WaveDirector.Phase.TUTORIAL:
			_phase_label.text = "MORNING CHORES"
			pill = Color(0.35, 0.45, 0.6)
	_phase_pill.bg_color = Color(pill, 0.85)
	var to_come := director.robots_to_come() if director.phase != WaveDirector.Phase.TUTORIAL else 0
	var live := director.live_robot_count() if director.phase != WaveDirector.Phase.TUTORIAL else 0
	var thieves := get_tree().get_nodes_in_group(Robot.THIEF_GROUP).size()
	var parts := PackedStringArray()
	if live > 0 or to_come > 0:
		parts.append("%d robot%s" % [live, "" if live == 1 else "s"] + ("  ·  %d coming" % to_come if to_come > 0 else ""))
	if thieves > 0:
		parts.append("%d THIE%s!" % [thieves, "F" if thieves == 1 else "VES"])
	_robots_label.text = "  ·  ".join(parts)
	_robots_label.visible = not parts.is_empty()
	_robots_label.add_theme_color_override(&"font_color", Color(1.0, 0.55, 0.45) if thieves > 0 else INK)
	var in_fight := director.phase in [WaveDirector.Phase.SIREN, WaveDirector.Phase.SPAWNING, WaveDirector.Phase.MOP_UP]
	_family_label.text = director.genome.family_name if director.genome != null and in_fight else ""
	if not _family_label.text.is_empty() and not director.plans.is_empty():
		_family_label.text += " - " + director.plan_title().trim_suffix("!") + "!"
	_family_label.visible = not _family_label.text.is_empty()
	var preparing := director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.SIREN]


const HP_FLASH_TIME := 0.35
const BOSS_SHAKE_TIME := 0.3
const BOSS_GLOW_TIME := 0.45
const BOSS_BAR_COLOR := Color(0.9, 0.6, 0.2)


func _on_boss_hit(robot: Node3D, harmed: bool) -> void:
	if robot != _boss:
		_boss = robot as Robot
		_boss_shown = _boss.health.fraction() * 100.0 if _boss != null else 0.0
		_boss_name.text = (_boss.foreman_title if not _boss.foreman_title.is_empty() else "THE FOREMAN").to_upper()
	if harmed:
		_boss_glow_left = BOSS_GLOW_TIME
	else:
		_boss_shake_left = BOSS_SHAKE_TIME


func _update_boss(delta: float) -> void:
	if _boss != null and (not is_instance_valid(_boss) or _boss.ai_state == Robot.AiState.DEAD):
		_boss = null
	if _boss == null:
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			var robot := node as Robot
			if robot != null and robot.is_foreman and robot.ai_state != Robot.AiState.DEAD:
				_boss = robot
				_boss_shown = 100.0
				_boss_name.text = (robot.foreman_title if not robot.foreman_title.is_empty() else "THE FOREMAN").to_upper()
				break
	_boss_root.visible = _boss != null
	if _boss == null:
		return
	var target := _boss.health.fraction() * 100.0
	_boss_shown = move_toward(_boss_shown, target, delta * 90.0)
	_boss_bar.value = _boss_shown
	_boss_shake_left = maxf(0.0, _boss_shake_left - delta)
	_boss_glow_left = maxf(0.0, _boss_glow_left - delta)
	var shake := sin(_boss_shake_left * 90.0) * 12.0 * (_boss_shake_left / BOSS_SHAKE_TIME)
	_boss_card.position = Vector2(shake, 0.0)
	var glow := _boss_glow_left / BOSS_GLOW_TIME
	_set_bar_color(_boss_bar, BOSS_BAR_COLOR.lerp(Color(1.0, 0.15, 0.1), glow))
	_boss_card.modulate = Color.WHITE.lerp(Color(1.4, 0.7, 0.7), glow)


func _update_silo() -> void:
	var silo := GameState.silo
	if silo == null:
		return
	var structure := silo.structure_fraction()
	_structure_bar.value = structure * 100.0
	_set_bar_color(_structure_bar, Color(0.95, 0.35, 0.25).lerp(Color(0.55, 0.78, 0.9), clampf((structure - 0.2) / 0.6, 0.0, 1.0)))
	_grain_bar.value = silo.grain_fraction() * 100.0
	var leak := silo.total_leak_rate()
	_leak_label.visible = silo.get_cracks().size() > 0
	_leak_label.text = "Leaking grain  %.1f/s" % leak
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


# --- Banners, climbers, low health, construction, the worst leak -------------------------------------

func _on_reward_granted(text: String) -> void:
	set_tutorial_lesson(text)
	_banner_left = 7.0


func _update_banner(delta: float) -> void:
	if _banner_left <= 0.0:
		return
	_banner_left -= delta
	if _banner_left <= 0.0:
		set_tutorial_lesson("")


func _on_climber_alert(robot: Node3D, climbing: bool) -> void:
	_climbers.erase(robot)
	if climbing:
		_climbers.append(robot)


## A Rung Runner on the silo ladder or catwalk: which way the ladder is, and how many are up there.
func _update_climbers() -> void:
	_climbers = _climbers.filter(_still_climbing)
	var warn := not _climbers.is_empty() and _player != null and is_instance_valid(_player) and not GameState.is_game_over
	_climber_alert.visible = warn
	if not warn:
		return
	var climbing := 0
	for robot in _climbers:
		if (robot as LadderRobot).travel == LadderRobot.Travel.CLIMB:
			climbing += 1
	var up_top := _climbers.size() - climbing
	var where := _silo_direction(_climbers[0].global_position - _player.global_position)
	var what := "ON THE SILO LADDER" if climbing > 0 else "ON THE CATWALK"
	var count := " x%d" % _climbers.size() if _climbers.size() > 1 else ""
	_climber_alert.text = "CLIMBER %s%s  ·  %s%s" % [what, count, where,
			"  ·  %d up top" % up_top if climbing > 0 and up_top > 0 else ""]


static func _still_climbing(robot: Node3D) -> bool:
	return is_instance_valid(robot) and robot is LadderRobot and (robot as LadderRobot).is_elevated() \
			and (robot as Robot).ai_state != Robot.AiState.DEAD


## Below LOW_HP: a red edge and the way to the nearest heal (the well or the porch).
func _update_low_hp() -> void:
	var low := _player != null and is_instance_valid(_player) and _player.is_alive() and not GameState.is_game_over \
			and _player.health.fraction() < LOW_HP and director != null and director.phase != WaveDirector.Phase.TUTORIAL
	_vignette.visible = low
	_low_hp_label.visible = low
	if not low:
		return
	var pulse := 0.55 + 0.35 * sin(Time.get_ticks_msec() * 0.008)
	_vignette.modulate.a = pulse
	var best: HealZone = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(HealZone.GROUP):
		var zone := node as HealZone
		if zone.contains(_player):
			_low_hp_label.text = "HEALING... stay put"
			return
		var distance := zone.global_position.distance_to(_player.global_position)
		if distance < best_distance:
			best_distance = distance
			best = zone
	if best == null:
		_low_hp_label.text = "LOW HEALTH"
		return
	var place := "the well" if best.name.contains("Well") else "the porch"
	_low_hp_label.text = "LOW HEALTH  ·  heal at %s, %d m %s" % [place, roundi(best_distance),
			_silo_direction(best.global_position - _player.global_position)]


## The construction line under the wave card: the job being built, what waits, and the capacity.
func _update_build() -> void:
	var manager := get_tree().get_first_node_in_group(ConstructionManager.GROUP) as ConstructionManager
	if manager == null or director == null or GameState.is_game_over:
		_build_label.visible = false
		return
	var text := ""
	if manager.is_open():
		var job := manager.active_job()
		var placing := manager.placing_definition() if manager.is_placing() else null
		if placing != null:
			var spot := manager.last_spot
			var verb := "CARRYING"
			text = "%s %s: E / click to place  ·  Tab to return" % [verb, placing.display_name]
			if spot != null and not spot.problem.is_empty():
				text += "\n" + spot.problem
		elif not manager.ready_stock().is_empty():
			text = "%d defense(s) READY: pick up at the STABLES" % manager.ready_stock().size()
		elif job != null:
			text = "STABLES: BUILDING %s %d%%%s" % [job.definition.display_name, roundi(job.fraction() * 100.0),
					"  (lending a hand x2)" if manager.assisted(job) else ""]
			if manager.jobs.size() > 1:
				text += "  ·  %d waiting" % (manager.jobs.size() - 1)
		if not text.is_empty() or not manager.deployed().is_empty():
			text += ("  ·  " if not text.is_empty() else "") + "capacity %d/%d" % [manager.capacity_used(), manager.capacity_total()]
	elif not manager.jobs.is_empty():
		text = "%d unfinished: frozen until the intermission" % manager.jobs.size()
	if manager.workshop != null and manager.workshop.lesson_active():
		text += ("\n" if not text.is_empty() else "") + manager.workshop.lesson_text()
	_build_label.text = text
	_build_label.visible = not text.is_empty()


## Between attacks, point at the worst leak with how long it takes to seal (FIRST_FIVE_WAVES_FUN_PLAN.md:
## "rather than making every crack compete for attention").
func _update_worst_leak() -> void:
	var silo := GameState.silo
	var calm := director != null and director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.CLEARED,
			WaveDirector.Phase.SIREN]
	var worst: SiloCrack = null
	if silo != null and calm and not GameState.is_game_over:
		for crack in silo.get_cracks():
			if worst == null or crack.size > worst.size or (crack.size == worst.size and _player != null
					and crack.global_position.distance_to(_player.global_position) < worst.global_position.distance_to(_player.global_position)):
				worst = crack
	if worst != _worst_crack:
		if _worst_crack != null and is_instance_valid(_worst_crack):
			_worst_crack.set_pointed(false)
		_worst_crack = worst
		if worst != null:
			worst.set_pointed(true)
	_leak_hint.visible = worst != null
	if worst == null:
		return
	var rate := StatService.get_stat(&"repair.speed", 1.0) * StatService.get_stat(&"repair.amount", 1.0)
	var where := ""
	if _player != null and is_instance_valid(_player):
		var distance := worst.global_position.distance_to(_player.global_position)
		where = "  ·  here" if distance < 3.0 else "  ·  %d m %s" % [roundi(distance), _silo_direction(worst.global_position - _player.global_position)]
	_leak_hint.text = "Worst leak: %s%s  ·  %.1f s to seal" % [worst.describe(), where, worst.repair_seconds_left() / maxf(0.1, rate)]


func _on_crack_closed(_crack: Node3D) -> void:
	if GameState.is_game_over or (director != null and director.phase == WaveDirector.Phase.TUTORIAL):
		return
	AudioDirector.play_cue(&"leak_sealed")
	var silo := GameState.silo
	if silo != null and silo.get_cracks().size() <= 1:
		show_message("Leak sealed! The silo is tight again.", 2.0)


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
		_last_player_hp = -1.0
		return
	var hp := _player.health.fraction()
	if _last_player_hp >= 0.0 and hp < _last_player_hp - 0.0001:
		_hp_flash_left = HP_FLASH_TIME
	_last_player_hp = hp
	_hp_flash_left = maxf(0.0, _hp_flash_left - get_process_delta_time())
	_hp_bar.value = hp * 100.0
	_set_bar_color(_hp_bar, Color(0.95, 0.3, 0.25).lerp(Color(0.45, 0.85, 0.4), clampf((hp - 0.2) / 0.4, 0.0, 1.0)))
	_hp_bar.modulate = Color(1.0, 0.7, 0.7) if hp < 0.3 and int(Time.get_ticks_msec() / 300.0) % 2 == 0 else Color.WHITE
	if _hp_flash_left > 0.0:
		var flash := _hp_flash_left / HP_FLASH_TIME
		_hp_bar.modulate = _hp_bar.modulate.lerp(Color(2.2, 0.5, 0.5), flash)
		_hp_bar.pivot_offset = _hp_bar.size * 0.5
		_hp_bar.scale = Vector2.ONE * (1.0 + 0.08 * flash)
	else:
		_hp_bar.scale = Vector2.ONE
	_armor_bar.visible = _player.max_armor > 0.0
	_armor_bar.value = _player.armor / _player.max_armor * 100.0 if _player.max_armor > 0.0 else 0.0
	_god_label.visible = GameState.god_mode
	var weapon := _player.weapons.current
	for carried in _player.weapons.weapons:
		var chip: Label = _slot_chips.get(carried.data.slot)
		if chip == null:
			chip = _label(_slot_row, 15)
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.custom_minimum_size = Vector2(28, 0)
			chip.add_theme_constant_override(&"outline_size", 0)
			chip.text = str(carried.data.slot)
			_slot_chips[carried.data.slot] = chip
		chip.visible = carried.is_available()
		var current := carried == weapon
		chip.add_theme_stylebox_override(&"normal", _chip_on if current else _chip_off)
		chip.add_theme_color_override(&"font_color", Color(0.2, 0.12, 0.05) if current else INK_DIM)
	_hint_label.visible = GameState.wave <= 1
	_hint_label.text = "E use" if weapon == null else "Q wheel   V melee   R reload   E use" + ("   Shift dash   Ctrl pound" if GameState.jetpack_unlocked else "")
	if weapon != null:
		_weapon_label.text = weapon.display_name.to_upper()
		var ammo := weapon.ammo_text()
		var split := ammo.split(" / ")
		_ammo_label.text = split[0]
		_ammo_label.add_theme_font_size_override(&"font_size", 40 if split.size() == 2 else 20)
		_magazine_label.text = "/ " + split[1] if split.size() == 2 else ""
		_ammo_label.visible = not ammo.is_empty()
		_magazine_label.visible = split.size() == 2
	else:
		_weapon_label.text = "NO TOOL"
		_ammo_label.visible = false
		_magazine_label.visible = false
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
	_prompt_label.visible = not prompt.is_empty()


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
	var lost := maxi(1, GameState.wave)
	var phase := GameState.phase_of(lost)
	_game_over_label.text = "HARVEST REPORT\n\n%s\n\nLost at Phase %d · Wave %d   (attempt %d)\nWaves survived: %d%s\nFamilies met: %d\nParts banked: Al %d  Cu %d  Au %d  PC %d\n\nYour parts and upgrades are kept. A retry starts Phase %d again with a full silo." % [
		cause, phase, GameState.wave_in_phase(lost), GameState.attempt, survived,
		"   NEW RECORD!" if survived >= best and survived > 0 else "   (best %d)" % best, families,
		GameState.parts[&"al"], GameState.parts[&"cu"], GameState.parts[&"au"], GameState.parts[&"pc"], phase]
	_retry_button.text = "Retry Phase %d   (R / Enter / A)" % phase
	_game_over_panel.visible = true
	_report_ready_at = Time.get_ticks_msec() + 600


## The wave's family name card (GDD 10.2, 17.2), shown through the siren.
func _on_family_revealed(genome: Resource) -> void:
	var family := genome as RobotGenome
	if family == null:
		return
	_name_card_title.text = family.family_name.to_upper()
	if director != null and not director.plans.is_empty():
		_name_card_title.text += " - " + director.plan_title().trim_suffix("!").to_upper() + "!"
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

	# Top center: the boss health bar, shown while a Foreman is alive.
	_boss_root = Control.new()
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.offset_left = -280.0
	_boss_root.offset_right = 280.0
	_boss_root.offset_top = 18.0
	_boss_root.offset_bottom = 78.0
	_boss_root.visible = false
	root.add_child(_boss_root)
	var boss_box := _card(_boss_root)
	_boss_card = boss_box.get_parent()
	_boss_name = _label(boss_box, 16)
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar = _bar(boss_box, BOSS_BAR_COLOR, 520.0, 18.0)
	EventBus.boss_hit.connect(_on_boss_hit)

	# Top left: the wave card, then the silo card.
	var top_left := _vbox(root, Control.PRESET_TOP_LEFT, Vector2(24, 20))
	top_left.add_theme_constant_override(&"separation", 10)
	var wave_card := _card(top_left)
	var wave_row := HBoxContainer.new()
	wave_row.add_theme_constant_override(&"separation", 10)
	wave_card.add_child(wave_row)
	_wave_label = _label(wave_row, 30)
	_phase_number_label = _label(wave_row, 16, INK_DIM)
	_phase_number_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_phase_label = _label(wave_card, 17)
	_phase_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_phase_label.add_theme_constant_override(&"outline_size", 0)
	_phase_pill = _pill(Color(0.3, 0.5, 0.25), 8, Vector2(10, 3))
	_phase_label.add_theme_stylebox_override(&"normal", _phase_pill)
	_robots_label = _label(wave_card, 16)
	_family_label = _label(wave_card, 14, Color(0.8, 0.88, 1.0))
	_build_label = _label(wave_card, 14, Color(1.0, 0.78, 0.4))
	_build_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_build_label.custom_minimum_size.x = 300.0
	_build_label.visible = false

	var silo_card := _card(top_left)
	_structure_bar = _labeled_bar(silo_card, "SILO", Color(0.55, 0.78, 0.9))
	_grain_bar = _labeled_bar(silo_card, "GRAIN", Color(0.98, 0.8, 0.32))
	_leak_label = _label(silo_card, 14, Color(1.0, 0.7, 0.35))
	_leak_label.visible = false
	_leak_hint = _label(silo_card, 14, Color(1.0, 0.86, 0.5))
	_leak_hint.visible = false

	# Bottom left: health, with armor as a slim bar above it.
	var bottom_left := _vbox(root, Control.PRESET_BOTTOM_LEFT, Vector2(24, -24))
	bottom_left.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var health_card := _card(bottom_left)
	_god_label = _label(health_card, 13, Color(1.0, 0.85, 0.4))
	_god_label.text = "GOD MODE"
	_god_label.visible = false
	_armor_bar = _bar(health_card, Color(0.55, 0.75, 1.0), 260, 8)
	_armor_bar.visible = false
	_hp_bar = _labeled_bar(health_card, "HP", Color(0.45, 0.85, 0.4), 260, 18)

	# Bottom right: weapon name, big ammo count, owned weapon slots.
	var bottom_right := _vbox(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-24, -24))
	bottom_right.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var weapon_card := _card(bottom_right)
	(weapon_card.get_parent() as Control).size_flags_horizontal = Control.SIZE_SHRINK_END
	weapon_card.alignment = BoxContainer.ALIGNMENT_END
	_weapon_label = _label(weapon_card, 16, INK_DIM)
	_weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override(&"separation", 6)
	weapon_card.add_child(ammo_row)
	_ammo_label = _label(ammo_row, 40)
	_magazine_label = _label(ammo_row, 20, INK_DIM)
	_magazine_label.size_flags_vertical = Control.SIZE_SHRINK_END
	_chip_on = _pill(Color(1.0, 0.8, 0.35, 0.95), 6, Vector2(6, 2))
	_chip_off = _pill(Color(0.0, 0.0, 0.0, 0.3), 6, Vector2(6, 2))
	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_END
	_slot_row.add_theme_constant_override(&"separation", 4)
	weapon_card.add_child(_slot_row)
	_hint_label = _label(bottom_right, 13, INK_DIM)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	# Top right: banked parts as coins.
	var top_right := _vbox(root, Control.PRESET_TOP_RIGHT, Vector2(-24, 20))
	top_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_fps_label = _label(top_right, 14, Color(0.7, 0.95, 0.7))
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.visible = bool(SaveManager.settings.get("show_fps", false))
	var parts_card := _card(top_right)
	var parts_row := HBoxContainer.new()
	parts_row.add_theme_constant_override(&"separation", 14)
	parts_card.add_child(parts_row)
	for key in GameState.PART_KEYS:
		var part := HBoxContainer.new()
		part.add_theme_constant_override(&"separation", 5)
		part.tooltip_text = GameState.PART_NAMES[key]
		parts_row.add_child(part)
		var coin := PartCoin.new()
		coin.color = PART_COLORS[key]
		coin.short = PART_SHORT[key]
		coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		part.add_child(coin)
		_part_labels[key] = _label(part, 18)

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

	_prompt_label = _label(root, 19, INK)
	_prompt_label.add_theme_stylebox_override(&"normal", _pill(CARD, 10, Vector2(14, 6)))
	_hug(_prompt_label, Control.PRESET_CENTER_BOTTOM, -150)
	_prompt_label.visible = false

	_toast_label = _label(root, 26, Color(1.0, 0.9, 0.45))
	_toast_label.add_theme_stylebox_override(&"normal", _pill(CARD, 12, Vector2(18, 6)))
	_hug(_toast_label, Control.PRESET_CENTER_TOP, 130)
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

	_vignette = TextureRect.new()
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette := GradientTexture2D.new()
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.05, 1.05)
	var fade := Gradient.new()
	fade.set_color(0, Color(0.8, 0.0, 0.0, 0.0))
	fade.set_color(1, Color(0.85, 0.05, 0.02, 0.75))
	fade.add_point(0.55, Color(0.8, 0.0, 0.0, 0.0))
	vignette.gradient = fade
	_vignette.texture = vignette
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(_vignette)
	root.move_child(_vignette, 0)
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.visible = false

	_climber_alert = _label(root, 20, Color(1.0, 0.92, 0.55))
	_climber_alert.add_theme_stylebox_override(&"normal", _pill(Color(0.35, 0.22, 0.02, 0.9), 10, Vector2(14, 5)))
	_hug(_climber_alert, Control.PRESET_CENTER_TOP, 116)
	_climber_alert.visible = false

	_low_hp_label = _label(root, 20, Color(1.0, 0.85, 0.82))
	_low_hp_label.add_theme_stylebox_override(&"normal", _pill(Color(0.45, 0.06, 0.05, 0.88), 10, Vector2(14, 5)))
	_hug(_low_hp_label, Control.PRESET_CENTER_BOTTOM, -205)
	_low_hp_label.visible = false

	_game_over_panel = PanelContainer.new()
	_game_over_panel.custom_minimum_size = Vector2(760, 400)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.18, 0.12, 0.08, 0.94)
	panel_style.set_corner_radius_all(16)
	panel_style.set_content_margin_all(24)
	_game_over_panel.add_theme_stylebox_override(&"panel", panel_style)
	var report := VBoxContainer.new()
	report.add_theme_constant_override(&"separation", 16)
	_game_over_panel.add_child(report)
	_game_over_label = _label(report, 21)
	_game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_game_over_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var report_buttons := HBoxContainer.new()
	report_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	report_buttons.add_theme_constant_override(&"separation", 12)
	report.add_child(report_buttons)
	_retry_button = _report_button(report_buttons, "Retry Phase", func() -> void: _start_again(true))
	_start_over_button = _report_button(report_buttons, "Start over at Phase 1   (Backspace / Y)", func() -> void: _start_again(false))
	_pegboard_button = _report_button(report_buttons, "Pegboard   (P / Start)", _open_report_pegboard)
	_game_over_panel.visible = false
	root.add_child(_game_over_panel)
	_place(_game_over_panel, Control.PRESET_CENTER, Rect2(-380, -200, 760, 400))


func _report_button(parent: Control, text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override(&"font_size", 15)
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(pressed)
	parent.add_child(button)
	return button


## Anchors `control` to a preset point and offsets it by `rect` from that anchor.
func _place(control: Control, preset: Control.LayoutPreset, rect: Rect2) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


## Centers `control` horizontally on the preset's anchor so it grows around its own text.
func _hug(control: Control, preset: Control.LayoutPreset, y: float) -> void:
	control.set_anchors_preset(preset)
	control.offset_left = 0.0
	control.offset_right = 0.0
	control.offset_top = y
	control.offset_bottom = y
	control.grow_horizontal = Control.GROW_DIRECTION_BOTH
	control.grow_vertical = Control.GROW_DIRECTION_BOTH


## A translucent rounded card holding a vertical stack.
func _card(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override(&"panel", _pill(CARD, 12, Vector2(14, 10)))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", 6)
	panel.add_child(box)
	return box


static func _pill(color: Color, radius: int, margin: Vector2) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin.x
	style.content_margin_right = margin.x
	style.content_margin_top = margin.y
	style.content_margin_bottom = margin.y
	return style


## A short caption in a fixed column, then the bar.
func _labeled_bar(parent: Control, caption: String, color: Color, width: float = 240, height: float = 14) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 10)
	parent.add_child(row)
	var label := _label(row, 13, INK_DIM)
	label.text = caption
	label.custom_minimum_size = Vector2(44, 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bar := _bar(row, color, width, height)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


func _set_bar_color(bar: ProgressBar, color: Color) -> void:
	(bar.get_theme_stylebox(&"fill") as StyleBoxFlat).bg_color = color


func _vbox(parent: Control, preset: Control.LayoutPreset, nudge: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	box.set_anchors_and_offsets_preset(preset)
	box.position += nudge
	box.add_theme_constant_override(&"separation", 4)
	return box


func _label(parent: Control, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override(&"font_size", font_size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.1, 0.07, 0.05))
	label.add_theme_constant_override(&"outline_size", 5 if font_size >= 18 else 3)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _bar(parent: Control, color: Color, width: float, height: float = 16) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, height)
	bar.size = bar.custom_minimum_size
	bar.show_percentage = false
	bar.max_value = 100.0
	bar.value = 100.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var radius := int(height * 0.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(radius)
	fill.border_color = Color(1.0, 1.0, 1.0, 0.25)
	fill.border_width_top = 2 if height >= 12 else 0
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	background.set_corner_radius_all(radius)
	background.border_color = Color(0.0, 0.0, 0.0, 0.35)
	background.set_border_width_all(1)
	bar.add_theme_stylebox_override(&"fill", fill)
	bar.add_theme_stylebox_override(&"background", background)
	parent.add_child(bar)
	return bar


## A small colored coin with the part's symbol, beside its count.
class PartCoin:
	extends Control

	var color: Color = Color.WHITE
	var short: String = ""

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		draw_circle(center, 13.0, color.darkened(0.45))
		draw_circle(center + Vector2(0, -1), 11.0, color)
		draw_arc(center + Vector2(0, -1), 8.5, PI * 1.1, PI * 1.6, 8, Color(1, 1, 1, 0.5), 1.5, true)
		var font := get_theme_default_font()
		var text_size := font.get_string_size(short, HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(font, center + Vector2(-text_size.x * 0.5, font.get_ascent(10) * 0.5 - 2), short,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.15, 0.1, 0.05, 0.9))


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
