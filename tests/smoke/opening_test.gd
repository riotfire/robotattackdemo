extends Node
## End-to-end test of the playtest-simulation package and the defense loop, on the real main scene, headless
## in fixed-step time: 90 s intermissions, the authored six-wave opening (the wave 2 Lobber before any gun and
## the pistol it unlocks, live caps, the teaching thief, the plated 350 HP Foreman whose defeat calls off its
## adds, the Rung Runner on the silo ladder while a raid hits the far side, the second Foreman's clods at range),
## no free items, 3-wave phases and the checkpoint, and construction (free placement with Tab, reserve,
## assemble, cancel, the siren cutoff) with a catwalk spring that throws a climber off.
## A scripted defender pops ground robots once they reach the silo, so waves clear on every seed; climbers
## are left to the spring. Uses its own fresh profile in the system temp directory, never the player's.
## Run from the project folder (add `-- --seed=1234` for a fixed run seed):
##   <godot> --headless --path . --fixed-fps 60 res://tests/smoke/opening_test.tscn
## Exits 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main/main.tscn"

var _profile: String = OS.get_temp_dir().path_join("opening_test_profile_%d.json" % OS.get_process_id())
var _main: Node
var _director: WaveDirector
var _construction: ConstructionManager
var _farmer: Farmer
var _hud: Hud
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _section_title: String = ""
var _finished: bool = false
var _game_over_expected: bool = false
## The scripted defender pops robots that reach the silo (never Foremen or climbers unless told).
var _defend: bool = false
var _defend_climbers: bool = false
var _silo_floor: float = 0.3
## Per wave: robots that entered, the most alive at once, and the spawned robots themselves.
var _spawned: Array[Robot] = []
## What each spawned robot was when it entered (robots are freed when they die): archetype id and thief.
var _entered: Array[Dictionary] = []
var _max_live: int = 0
var _kills_by_farmer: Dictionary[StringName, int] = {}
var _rewards: PackedStringArray = PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.use_profile(_profile, true)
	SaveManager.tutorial_completed = true
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	EventBus.robot_spawned.connect(_on_robot_spawned)
	EventBus.robot_destroyed.connect(_on_robot_destroyed)
	EventBus.reward_granted.connect(func(text: String) -> void: _rewards.append(text))
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	var silo := GameState.silo
	if silo != null and is_instance_valid(silo) and _silo_floor > 0.0:
		silo.structure = maxf(silo.structure, silo.max_structure * _silo_floor)
		silo.grain = maxf(silo.grain, silo.max_grain * _silo_floor)
	if _director != null and _director.phase in [WaveDirector.Phase.SPAWNING, WaveDirector.Phase.MOP_UP]:
		_max_live = maxi(_max_live, _director.live_robot_count())
	if _defend:
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			var robot := node as Robot
			if robot.is_foreman or (robot is LadderRobot and not _defend_climbers):
				continue
			var at_silo := silo != null and silo.distance_to_wall(robot.global_position) < 3.5
			if at_silo or robot.is_thief or (robot is VerticalRobot and (robot as VerticalRobot).travel == VerticalRobot.Travel.PERCHED):
				robot.take_damage(DamagePacket.create(99999.0, _farmer, robot.global_position))


func _on_robot_spawned(robot: Node3D) -> void:
	var foe := robot as Robot
	if foe == null:
		return
	_spawned.append(foe)
	_entered.append({"id": foe.archetype.id, "thief": foe.is_thief})


func _entered_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for entry in _entered:
		ids.append(entry["id"])
	return ids


func _thieves_entered() -> int:
	return _entered.filter(func(entry: Dictionary) -> bool: return entry["thief"]).size()


func _on_robot_destroyed(robot: Node3D, killer: Node) -> void:
	if killer == _farmer and robot is Robot:
		var id := (robot as Robot).archetype.id
		_kills_by_farmer[id] = _kills_by_farmer.get(id, 0) + 1


func _run() -> void:
	await _frames(10)
	_director = _main.get_node(^"WaveDirector") as WaveDirector
	_construction = _main.get_node(^"Construction") as ConstructionManager
	_hud = _main.get_node(^"HUD") as Hud
	_farmer = GameState.players[0] as Farmer
	GameState.god_mode = true
	EventBus.game_over.connect(_on_game_over)
	var region := _main.get_node(^"Farm/NavRegion") as NavigationRegion3D
	await _wait_until(func() -> bool: return not region.is_baking(), 10.0)
	await _frames(5)

	_section("Start")
	_check(_director.phase == WaveDirector.Phase.INTERMISSION and _director.wave == 1, "a fresh profile starts in wave 1's intermission")
	_check(_director.intermission_seconds() == 90.0 and _director.time_left <= 90.0 and _director.time_left > 88.0,
			"the intermission is 90 s, siren included (%.1f left)" % _director.time_left)
	_check(GameState.curve.waves_per_phase == 3 and GameState.phase_of(4) == 2 and GameState.wave_in_phase(6) == 3,
			"phases are 3 waves")
	_check(not StatService.has_flag(&"pistol.unlocked") and not StatService.jetpack_available(),
			"wrench only; the jetpack waits for wave 9")
	_check(_construction.sites.is_empty(), "no marked build spots on the farm")
	_check(_main.get_node_or_null(^"PrepPanel") == null, "no quick-buy panel: shopping is at the tool shed")
	await _press_action(&"build")
	_check(_construction._menu != null and _construction._menu.is_open() and not _farmer.input.enabled,
			"Tab opens the build menu")
	var before := _director.time_left
	await _frames(30)
	_check(_director.time_left < before, "building doesn't pause the intermission")
	_construction.close_menu()
	_check(_farmer.input.enabled, "closing it gives control back")

	_section("Wave 1: First Bonks")
	await _start_wave()
	_check(_director.opening != null and _director.opening.title == "First Bonks", "wave 1 is the authored opening")
	_check(_director.active_lanes.size() == 1 and _director.active_lanes[0] in [1, 2],
			"one lane, the one facing the farmer's start (%s)" % [_director.active_lanes])
	await _wait_until(func() -> bool: return not _spawned.is_empty(), 5.0)
	var first := _spawned[0] if not _spawned.is_empty() else null
	var out := first.global_position.distance_to(GameState.silo.global_position) if first != null else 0.0
	_check(first != null and out > 38.0 and out < 52.0, "the first Nibblers burst out of the crops ~45 m out (%.1f m)" % out)
	_defend = true
	await _clear_wave(120.0)
	var ids := _entered_ids()
	_check(ids.size() == 15 and ids.count(&"nibbler") == 15, "15 Nibblers (%s)" % [ids])
	_check(_max_live <= 4, "never more than 4 alive (%d)" % _max_live)
	_check(_thieves_entered() == 0, "no thieves in wave 1")
	GameState.add_parts({&"al": 50})
	_check(not StatService.has_flag(&"pistol.unlocked") and not StatService.can_purchase(StatService.PISTOL_ID) and _rewards.is_empty(),
			"clearing wave 1 hands over nothing, and the pistol can't be bought yet")

	_section("Wave 2: Take the High Ground")
	await _wait_for_intermission(2)
	_check(absf(_director.time_left - 90.0) < 0.6, "90 s again")
	await _start_wave()
	var t := await _wait_until(func() -> bool: return _first_of(&"roof_lobber") != null, 5.0)
	var lobber := _first_of(&"roof_lobber") as VerticalRobot
	_check(lobber != null and lobber.forced_roof == &"ToolShed", "the first Lobber, before any gun, sent to the tool shed")
	_check(not StatService.has_flag(&"pistol.unlocked"), "the farmer has only melee to reach it with")
	await _clear_wave(150.0)
	_check(_entered_ids().count(&"roof_lobber") == 2 and _entered_ids().count(&"nibbler") == 12, "two Lobbers and 12 Nibblers (%s)" % [_entered_ids()])
	_check(_rewards.size() == 1 and "Pistol" in _rewards[0], "beating it announces the pistol blueprint (%s)" % [_rewards])
	_check(not StatService.has_flag(&"pistol.unlocked") and StatService.can_purchase(StatService.PISTOL_ID),
			"which is bought at the shed, not handed over")

	_section("Wave 3: the first Foreman")
	await _wait_for_intermission(3)
	_check(StatService.purchase(StatService.PISTOL_ID), "the Rivet Pistol is bought for wave 3")
	_check(_director.curve.is_big_haul(3), "wave 3 is the Big Haul")
	await _start_wave()
	t = await _wait_until(func() -> bool: return _foreman() != null, 5.0)
	var foreman := _foreman() as HeavyRobot
	_check(foreman != null and is_equal_approx(foreman.health.max_health, 350.0), "the Foreman has the authored 350 HP (%.0f)"
			% (foreman.health.max_health if foreman else 0.0))
	_check(foreman != null and foreman.authored and foreman.extra_traits.is_empty() and foreman.windup_time() == 1.2
			and foreman.get_node_or_null(^"Model/VentGlow") != null, "fixed behavior: no random trait, a 1.2 s slam tell, a vent glow")
	_check(_entered.size() == 1, "it enters alone")
	var hp_before := foreman.health.current
	_farmer.teleport_to(foreman.global_position + Vector3(0.0, 0.5, 20.0))
	await _frames(2)
	foreman.take_damage(DamagePacket.create(12.0, _farmer, foreman.global_position + Vector3.UP))
	_check(absf(hp_before - foreman.health.current - 12.0 * HeavyRobot.PLATED_SHARE) < 0.01,
			"its plates blunt a rivet from 20 m (%.1f damage)" % (hp_before - foreman.health.current))
	var vent_seen := [false]
	var watch_vent := func() -> bool:
		vent_seen[0] = vent_seen[0] or (is_instance_valid(foreman) and foreman.vent_open())
		return vent_seen[0]
	await _wait_until(watch_vent, 60.0)
	_check(vent_seen[0], "after a slam its back vent glows: the x3 punish window")
	var pc_before := GameState.parts[&"pc"]
	foreman.take_damage(DamagePacket.create(99999.0, null, foreman.global_position))
	await _frames(3)
	_check(_director.robots_to_come() == 0, "its defeat calls off the adds still to come")
	_check(GameState.parts[&"pc"] >= pc_before + 2, "the first Foreman kill banks its bounty (+%d PC)" % (GameState.parts[&"pc"] - pc_before))
	_check(SaveManager.foreman_bounty_paid(3), "and records it, so a retry can't farm it")
	await _clear_wave(60.0)
	await _wait_for_intermission(4)
	_check(SaveManager.resume_wave == 4, "clearing the Big Haul moves the checkpoint to wave 4 (%d)" % SaveManager.resume_wave)
	_check(int(SaveManager.phase_attempts(1).get("best", 0)) == 1, "phase 1 cleared on the first attempt")

	_section("Wave 4: Stop That Sack")
	_defend = false
	await _start_wave()
	_check(_director.active_lanes.size() == 2, "two lanes")
	await _wait_until(func() -> bool: return _entered.size() >= 2, 5.0)
	_check(_entered_ids().slice(0, 2) == [&"nibbler", &"nibbler"], "a Nibbler pair warms the wave up")
	await _wait_until(func() -> bool: return _entered_ids().count(&"clanker") >= 2, 15.0)
	_check(_entered_ids().count(&"clanker") == 2, "then a Clanker pair, not a trio")
	var thief_spawned := func() -> bool: return _thieves_entered() > 0
	await _frames(240)
	_check(not thief_spawned.call(), "the teaching thief waits while the pair stands")
	for robot in _spawned:
		if is_instance_valid(robot) and robot.archetype.id == &"clanker":
			robot.take_damage(DamagePacket.create(99999.0, _farmer, robot.global_position))
	t = await _wait_until(thief_spawned, 20.0)
	_check(t >= 5.5, "exactly one thief, %.1f s after the pair is down (a short respite)" % t)
	_defend = true
	t = await _wait_until(func() -> bool: return _first_of(&"roof_lobber") != null, 30.0)
	var barn := _first_of(&"roof_lobber") as VerticalRobot
	_check(barn != null and barn.forced_roof == &"Barn", "a Lobber takes the barn roof")
	await _clear_wave(150.0)
	_check(_thieves_entered() == 1, "exactly one thief (%d)" % _thieves_entered())
	_check(not StatService.has_flag(&"defense.spring_trap") and _rewards.size() == 1, "clearing wave 4 hands over no recipe")

	_section("Construction")
	await _wait_for_intermission(5)
	_check(_hud._tutorial_lesson.text.contains("Spring Trap") and _hud._tutorial_lesson.text.contains("ladder"),
			"before the first split wave the HUD asks for a Spring Trap at the ladder top")
	GameState.add_parts({&"al": 100})
	_check(StatService.purchase(&"build.spring_trap") and StatService.has_flag(&"defense.spring_trap"),
			"the Spring Trap recipe is bought on the BUILD board")
	var spring_def := _construction.definition(&"spring_trap")
	# The spring goes where the ladder comes up, through the API: the camera can't be aimed headless.
	var top := _ladder_top()
	var top_spot := _construction.spot_at(top, Vector3.FORWARD, spring_def, top.y)
	_check(top_spot.problem.is_empty() and top_spot.kind == &"catwalk",
			"the catwalk at the ladder top is open floor (%s)" % top_spot.problem)
	var al_before := GameState.parts[&"al"]
	_check(_construction.place(spring_def, top_spot, _farmer).is_empty(), "a spring goes on the catwalk at the ladder top")
	var placed_frame := Engine.get_physics_frames()
	var ladder_top := _construction.jobs[0].site if not _construction.jobs.is_empty() else null
	_check(GameState.parts[&"al"] == al_before - spring_def.cost_al, "it costs its 12 Al like every copy")
	_check(ladder_top != null and not ladder_top.occupant.active and _construction.capacity_used() == 2,
			"it reserves capacity and stands as an inactive ghost")
	StatService.grant(&"build.barricade")
	StatService.grant(&"build.decoy")
	var wall_def := _construction.definition(&"scrap_barricade")
	# Free placement through the real controls: Tab, pick a recipe, then Interact where the ghost stands.
	_check(await _find_open_stand(wall_def), "the farmer finds open ground to build on")
	await _press_action(&"build")
	_check(_construction._menu.is_open(), "Tab opens the build menu")
	_construction._choose_recipe(_farmer, wall_def)
	await _frames(3)
	_check(_construction.is_placing() and _farmer.building and _construction.last_spot != null,
			"choosing a recipe shows its ghost in front of the farmer")
	_check(_construction.last_spot.problem.is_empty(), "green where it fits (%s)" % _construction.last_spot.problem)
	al_before = GameState.parts[&"al"]
	await _press_action(&"interact")
	var wall_site := _construction.jobs[-1].site if _construction.jobs.size() == 2 else null
	_check(wall_site != null and GameState.parts[&"al"] == al_before - wall_def.cost_al and not _construction.is_placing(),
			"Interact builds it there, reserving its 8 Al at once")
	var refund := _construction.cancel(wall_site) if wall_site != null else {}
	_check(GameState.parts[&"al"] == al_before and int(refund.get(&"al", 0)) == wall_def.cost_al, "cancelling unbuilt work refunds it all")
	await _frames(30)
	_check(not _farmer.building, "the farmer's hands are free again")
	_construction._choose_recipe(_farmer, _construction.definition(&"scarecrow_decoy"))
	await _frames(3)
	await _press_action(&"build")
	_check(not _construction.is_placing() and _construction.jobs.size() == 1, "Tab again puts the ghost away")
	await _wait_until(func() -> bool: return ladder_top.occupant != null and ladder_top.occupant.active, 15.0)
	var took := float(Engine.get_physics_frames() - placed_frame) / Engine.physics_ticks_per_second
	_check(ladder_top.occupant.active and took > 9.0 and took < 12.5, "the spring assembles in about 10 s of intermission (%.1f s)" % took)
	var decoy_def := _construction.definition(&"scarecrow_decoy")
	_check(await _find_open_stand(decoy_def), "open ground for a decoy")
	_check(_construction.place(decoy_def, _construction.spot_ahead(_farmer, decoy_def), _farmer).is_empty(), "a decoy queues")
	var gate := _construction.jobs[-1].site
	_director.ring_bell()
	await _frames(2)
	await _frames(int(Engine.physics_ticks_per_second * 4))
	_check(gate.occupant != null and not gate.occupant.active and _construction.jobs.size() == 1,
			"the siren freezes unfinished work: the decoy stays a ghost through the wave")

	_section("Wave 5: Up the Ladder")
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 6.0)
	var slots: PackedInt32Array = _director.get(&"_slot_lanes")
	var main_lane := slots[0] if not slots.is_empty() else 0
	_check(main_lane in [5, 6], "the main lane is on the ladder's side (%d)" % main_lane)
	var runner_found := await _wait_until(func() -> bool: return _first_of(&"rung_runner") != null, 5.0)
	var runner := _first_of(&"rung_runner") as LadderRobot
	_check(runner_found >= 0.0 and runner != null, "a Rung Runner opens the wave")
	t = await _wait_until(func() -> bool: return _entered_ids().count(&"clanker") >= 2, 10.0)
	t = _director.spawn_clock
	_check(t < 8.0 and slots.size() == 3 and WaveDirector._lane_gap(slots[2], main_lane) >= 3
			and slots[2] in _director.active_lanes,
			"%.1f s in, a raid comes from the far side while it climbs (lane %d vs %d)" % [t, slots[2] if slots.size() == 3 else 0, main_lane])
	t = await _wait_until(func() -> bool: return is_instance_valid(runner) and runner.travel == LadderRobot.Travel.CLIMB, 30.0)
	_check(t >= 0.0, "it walks to the silo ladder and climbs (%.1f s)" % t)
	await _frames(2)
	_check(_hud._climber_alert.visible and "LADDER" in _hud._climber_alert.text, "the HUD warns: climber on the silo ladder")
	var launched := [false]
	var watch_launch := func() -> bool:
		launched[0] = launched[0] or (is_instance_valid(runner) and runner.ai_state == Robot.AiState.LAUNCHED)
		return launched[0] or not is_instance_valid(runner) or runner.ai_state == Robot.AiState.DEAD
	t = await _wait_until(watch_launch, 20.0)
	_check(launched[0], "stepping onto the catwalk, the spring throws it off")
	await _wait_until(func() -> bool: return not is_instance_valid(runner) or runner.ai_state in [Robot.AiState.DEAD, Robot.AiState.STUNNED, Robot.AiState.SEEK], 6.0)
	_check(_kills_by_farmer.get(&"rung_runner", 0) >= 1, "the fall kills it, credited to the farmer who placed the trap")
	_defend_climbers = true
	await _clear_wave(180.0)

	_section("Wave 6: the second Foreman")
	await _wait_for_intermission(6)
	t = await _wait_until(func() -> bool: return gate.occupant != null and gate.occupant.active, 8.0)
	_check(t >= 0.0, "next intermission the frozen decoy resumes and finishes (%.1f s)" % t)
	await _start_wave()
	t = await _wait_until(func() -> bool: return _foreman() != null, 5.0)
	foreman = _foreman() as HeavyRobot
	_check(foreman != null and absf(foreman.health.max_health - 900.0) < 1.0 and foreman.throw_phase,
			"the authored 900 HP (%.0f) and the clod throw" % (foreman.health.max_health if foreman else 0.0))
	var foreman_lane := Array(_director.active_lanes).filter(func(lane: int) -> bool: return lane not in [5, 6])
	_check(not foreman_lane.is_empty(), "it comes from the far side, away from the ladder (%s)" % [_director.active_lanes])
	var clods := [0]
	(foreman.get_node(^"ClodThrow") as RangedAttack).fired.connect(func() -> void: clods[0] += 1)
	var away := foreman.global_position - GameState.silo.global_position
	away.y = 0.0
	_farmer.teleport_to(foreman.global_position - away.normalized() * 11.0 + Vector3.UP * 0.5)
	t = await _wait_until(func() -> bool: return clods[0] > 0 or not is_instance_valid(foreman), 12.0)
	_check(clods[0] > 0 and foreman.health.fraction() > 0.99,
			"at full health it already throws clods at a farmer who keeps away (%.1f s)" % t)
	foreman.take_damage(DamagePacket.create(foreman.health.max_health * 0.6, null, foreman.global_position))
	await _frames(3)
	_check(foreman.health.fraction() < 0.5 and foreman._clod_wait <= HeavyRobot.CLOD_PERIOD_HURT, "hurt, its clods come faster")
	foreman.take_damage(DamagePacket.create(99999.0, null, foreman.global_position))
	await _clear_wave(90.0)
	await _wait_for_intermission(7)
	_check(SaveManager.resume_wave == 7, "phase 2 cleared: the checkpoint is wave 7")

	_section("Wave 7: generated, with climbers")
	_check(_director.authored_wave(7) == null, "the curve takes over after the opening")
	var events: Array = _director.call(&"_build_spawn_events", 7)
	var ladders := events.filter(func(e: WaveDirector.SpawnEvent) -> bool: return e.archetype.id == &"rung_runner").size()
	var lobbers := events.filter(func(e: WaveDirector.SpawnEvent) -> bool: return e.archetype.id == &"roof_lobber").size()
	_check(ladders >= 1 and lobbers >= 1, "its climber share holds both Lobbers (%d) and Rung Runners (%d)" % [lobbers, ladders])
	_check(events.any(func(e: WaveDirector.SpawnEvent) -> bool: return e.archetype.id == &"drone"), "the Drone debuts on wave 7")

	_section("Loss and checkpoint")
	_game_over_expected = true
	_defend = false
	_silo_floor = 0.0
	await _start_wave()
	var al_left := GameState.parts[&"al"]
	GameState.silo.take_damage(DamagePacket.create(99999.0, null, GameState.silo.wall_point_toward(Vector3.BACK, 1.0)))
	await _frames(3)
	_check(GameState.is_game_over and SaveManager.resume_wave == 7, "losing wave 7 keeps the checkpoint at its phase start")
	_check(GameState.parts[&"al"] >= al_left, "parts are kept")
	_check(int(SaveManager.phase_attempts(3).get("latest", 0)) == 1, "the attempt is recorded")
	_check(_hud._game_over_panel.visible and "Retry Phase 3" in _hud._retry_button.text, "the Harvest Report offers Retry Phase 3")
	get_tree().paused = false
	_finish()


# --- Helpers --------------------------------------------------------------------------------------

func _start_wave() -> void:
	_spawned.clear()
	_entered.clear()
	_max_live = 0
	if _director.phase == WaveDirector.Phase.INTERMISSION:
		_director.ring_bell()
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 6.0)


func _clear_wave(timeout: float) -> void:
	var t := await _wait_until(func() -> bool: return _director.phase in [WaveDirector.Phase.CLEARED, WaveDirector.Phase.INTERMISSION], timeout)
	_check(t >= 0.0, "wave %d clears (%.0f s)" % [_director.wave, _director.spawn_clock])


func _wait_for_intermission(wave: int) -> void:
	var t := await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.INTERMISSION and _director.wave == wave, 10.0)
	_check(t >= 0.0, "wave %d's intermission" % wave)
	_patch_up_silo()


## Where the silo ladder comes up onto the first catwalk.
func _ladder_top() -> Vector3:
	var silo := GameState.silo
	var ladder := silo.get_node(^"Ladder") as Climbable
	var toward := ladder.global_position - silo.global_position
	toward.y = 0.0
	return silo.global_position + toward.normalized() * LadderRobot.CATWALK_RADIUS \
			+ Vector3.UP * (ladder.global_position.y - silo.global_position.y + ladder.landings[0])


## Walks the farmer round the silo until the spot in front of them takes `definition`.
func _find_open_stand(definition: DefenseDefinition) -> bool:
	var center := GameState.silo.global_position
	for ring in [12.0, 16.0, 20.0, 9.0]:
		for step in 12:
			var angle := step * TAU / 12.0
			_farmer.teleport_to(center + Vector3(sin(angle), 0.0, cos(angle)) * ring + Vector3.UP * 0.5)
			await _frames(4)
			if _farmer.state == Farmer.State.GROUNDED and _construction.spot_ahead(_farmer, definition).problem.is_empty():
				return true
	return false


func _foreman() -> Robot:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		if (node as Robot).is_foreman:
			return node as Robot
	return null


func _first_of(id: StringName) -> Robot:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		if (node as Robot).archetype.id == id:
			return node as Robot
	return null


func _patch_up_silo() -> void:
	var silo := GameState.silo
	for crack: SiloCrack in silo.get_cracks().duplicate():
		silo.repair_crack(crack, INF)
	silo.add_grain(silo.max_grain)


func _on_game_over(reason: StringName) -> void:
	if _game_over_expected or _finished:
		return
	_check(false, "the run lasts until the loss check (it ended in '%s': %s)" % [_section_title, reason])
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	print("")
	if _failures.is_empty():
		print("OPENING TEST PASSED (%d checks)" % _checks)
	else:
		print("OPENING TEST FAILED: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			print("  - " + failure)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_profile))
	get_tree().quit(0 if _failures.is_empty() else 1)


func _wait_until(condition: Callable, timeout: float) -> float:
	var waited := 0.0
	while not condition.call():
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if waited > timeout:
			return -1.0
	return waited


func _press_action(action: StringName) -> void:
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _section(title: String) -> void:
	_section_title = title
	print("\n== %s ==" % title)


func _check(ok: bool, what: String) -> void:
	if _finished or what.is_empty():
		return
	_checks += 1
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
