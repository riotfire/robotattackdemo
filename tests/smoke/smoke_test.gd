extends Node
## End-to-end smoke test: plays the real main scene headless in fixed-step time and checks M0 and M1:
## wave 1 -> intermission -> wave 2, navmesh paths after the prop rebake, families and name cards,
## spawning mixes and Clanker squads, cracks and repair, theft and grain sacks, weapons, pickups and the
## Scrap Vac, the pegboard and save round-trip, the dinner bell, jetpack, ladder, zipline, the Foreman's
## slam and shockwave, debug keys and all three game-over conditions.
## Uses its own fresh profile (user://smoke_test_profile.json), never the player's.
## Run from the project folder:
##   <godot> --headless --path . --fixed-fps 60 res://tests/smoke/smoke_test.tscn
## Exits 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main/main.tscn"
const PROFILE := "user://smoke_test_profile.json"

var _main: Node
var _director: WaveDirector
var _farmer: Farmer
var _pegboard: PegboardUI
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _al_from_wave_1: int = 0
## While > 0, the silo's Structure and grain can't drop below this fraction of their max. On some seeds the Nibblers
## finish off the unrepaired silo before the waits for spawns and cracks are over, which ends the run and fails every
## later check; the floor keeps the run alive without touching balance. Turned off where the test damages the silo itself.
var _silo_floor: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SaveManager.use_profile(PROFILE, true)
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_main)
	_run.call_deferred()


func _physics_process(_delta: float) -> void:
	var silo := GameState.silo
	if _silo_floor <= 0.0 or silo == null or not is_instance_valid(silo):
		return
	silo.structure = maxf(silo.structure, silo.max_structure * _silo_floor)
	silo.grain = maxf(silo.grain, silo.max_grain * _silo_floor)


func _run() -> void:
	await _frames(10)
	_director = _main.get_node(^"WaveDirector") as WaveDirector
	_pegboard = _main.get_node(^"Pegboard") as PegboardUI
	_farmer = GameState.players[0] as Farmer
	GameState.god_mode = true
	_silo_floor = 0.25
	var silo := GameState.silo

	_section("Start")
	_check(silo != null, "silo registered")
	_check(_director.phase == WaveDirector.Phase.INTERMISSION and _director.wave == 1, "starts in the wave 1 intermission")
	_check(absf(_director.time_left - 120.0) < 0.5, "intermission is 120 s (%.2f left)" % _director.time_left)
	# The rest of this test was written around a 30 s intermission, so run it at 30 s; the default is checked above.
	_director.intermission_time = 30.0
	_director.time_left = 30.0
	_check(not GameState.jetpack_unlocked, "fresh profile: jetpack locked")
	_check(_farmer.current_weapon == _farmer.wrench and not _farmer.is_weapon_available(_farmer.pistol),
			"fresh profile: wrench only, the pistol must be bought")
	var props := (_main.get_node(^"Farm/NavRegion/Props") as PropScatter).placed
	_check(props.size() >= 8, "seeded prop scatter placed %d props" % props.size())
	var region := _main.get_node(^"Farm/NavRegion") as NavigationRegion3D
	await _wait_until(func() -> bool: return not region.is_baking(), 10.0)
	await _frames(5)
	_check(region.navigation_mesh.resource_path == "", "navmesh rebaked at run start around the props")
	_check_lane_paths()

	_section("Wave 1")
	var siren_due := _director.time_left - _director.siren_lead_time
	var t := await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SIREN, 40.0)
	_check(absf(t - siren_due) < 0.5, "siren starts at T-10 (%.2f s left of the 30 s intermission)" % (_director.time_left))
	_check(_director.active_lanes.size() == 2, "wave 1 uses 2 lanes %s" % [_director.active_lanes])
	var family := _director.genome
	_check(family != null and family.family_name.begins_with("The ") and family.family_code.length() == 6,
			"wave family rolled: %s (%s)" % [family.family_name if family else "-", family.family_code if family else "-"])
	_check(SaveManager.almanac.any(func(e: Dictionary) -> bool: return e.get("code") == family.family_code),
			"family logged in the Almanac")
	t = await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 15.0)
	_check(absf(t - 10.0) < 0.5, "spawning starts 10 s after the siren (%.2f s)" % t)
	_check(_director.spawns_total == 9, "wave 1 buys 9 Nibblers with budget 18 (got %d)" % _director.spawns_total)
	var first := await _first_robot(20.0)
	if first != null:
		var kit := first.get_node(^"Model/Pose/Kit")
		_check(first.family_code == family.family_code and kit != null and kit.get_child_count() >= 10,
				"robots are kit-bashed from the family genome (%d parts)" % (kit.get_child_count() if kit else 0))

	t = await _wait_until(func() -> bool: return silo.structure < silo.max_structure, 60.0)
	_check(t >= 0.0, "Nibblers reach and damage the silo (first hit after %.1f s)" % t)
	t = await _wait_until(func() -> bool: return silo.get_cracks().size() >= 1, 60.0)
	_check(t >= 0.0, "a crack opens after 10%% Structure lost (structure %.0f)" % silo.structure)
	await _test_theft()
	await _test_wrench_and_pickups()
	await _wait_until(func() -> bool: return _director.spawns_done >= _director.spawns_total, 60.0)
	await _wait_until(func() -> bool: return silo.get_cracks().size() >= 3, 25.0)
	var grain_before := silo.grain
	var parts_before := GameState.parts[&"al"]
	_kill_all_robots()
	await _frames(30)
	t = await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.CLEARED, 60.0)
	_check(t >= 0.0, "wave 1 cleared after the last robot")
	_check(silo.grain > grain_before or is_equal_approx(silo.grain, silo.max_grain), "harvest bonus adds grain (%.1f -> %.1f)" % [grain_before, silo.grain])
	_check(GameState.parts[&"al"] > parts_before, "Scrap Vac banks leftover parts (%d -> %d Al)" % [parts_before, GameState.parts[&"al"]])
	_check(get_tree().get_nodes_in_group(Pickup.GROUP).all(func(p: Node) -> bool: return (p as Pickup).kind == Pickup.GRAIN or p.is_queued_for_deletion()),
			"Scrap Vac clears the parts off the field")
	_al_from_wave_1 = GameState.parts[&"al"]
	t = await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.INTERMISSION, 5.0)
	_check(t >= 0.0 and _director.wave == 2, "back to intermission, now for wave 2")
	_check(FileAccess.file_exists(PROFILE), "autosaved at the intermission start")

	_section("Repair")
	await _test_repair()

	_section("Pegboard and save")
	await _test_pegboard_and_save()

	_section("Wave 2")
	await _test_dinner_bell()
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 15.0)
	_check_spawn_mix(2)
	_check(_director.genome != family, "wave 2 rolls a new family: %s" % _director.genome.family_name)
	_check(_director.genome.theme != family.theme, "no theme repeats back to back (%s -> %s)" % [family.theme.theme_word, _director.genome.theme.theme_word])
	await _test_squads()
	await _test_pistol()
	await _wait_until(func() -> bool: return _director.spawns_done >= _director.spawns_total, 70.0)
	_kill_all_robots()
	t = await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.CLEARED, 40.0)
	_check(t >= 0.0, "wave 2 cleared")
	_check(GameState.jetpack_unlocked, "jetpack unlocks after wave 2")
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.INTERMISSION, 5.0)
	_check(_director.wave == 3, "intermission for wave 3")

	_section("Traversal")
	await _test_jetpack()
	await _test_ladder()
	await _test_zipline()

	_section("Big Haul")
	await _test_foreman()

	_section("Debug keys")
	var al := GameState.parts[&"al"]
	await _press_key(KEY_F3)
	_check(GameState.parts[&"al"] == al + 100, "F3 gives parts (%d -> %d Al)" % [al, GameState.parts[&"al"]])
	var next_wave := _director.wave + 1
	await _press_key(KEY_F5)
	_check(_director.wave == next_wave and _director.phase == WaveDirector.Phase.SIREN, "F5 skips to wave %d's siren" % next_wave)
	(_main.get_node(^"DebugCheats") as DebugCheats).call(&"_on_console_submitted", "wave 9")
	_check(_director.wave == 9 and GameState.waves_survived == 8, "console 'wave 9' jumps to wave 9")

	_section("Game over")
	_silo_floor = 0.0
	_kill_all_robots()
	# Full Structure first, so this 150 damage can't end the run on its own before the grain check.
	silo.structure = silo.max_structure
	(_main.get_node(^"DebugCheats") as DebugCheats).damage_silo(150.0)
	silo.grain = 0.5
	t = await _wait_until(func() -> bool: return GameState.is_game_over, 5.0)
	_check(GameState.is_game_over and GameState.game_over_reason == &"grain", "grain at 0 ends the run (reason %s)" % GameState.game_over_reason)
	_check(get_tree().paused, "game pauses on game over")
	_check(_director.phase == WaveDirector.Phase.GAME_OVER, "director stops")
	_check(int(SaveManager.records.get("best_wave", 0)) >= 8, "best wave recorded (%d)" % int(SaveManager.records.get("best_wave", 0)))
	get_tree().paused = false
	GameState.is_game_over = false
	GameState.god_mode = false
	_farmer.armor = 0.0
	_farmer.take_damage(DamagePacket.create(9999.0, null, _farmer.global_position))
	_check(GameState.is_game_over and GameState.game_over_reason == &"farmer", "farmer at 0 HP ends the run (reason %s)" % GameState.game_over_reason)
	get_tree().paused = false
	GameState.is_game_over = false
	silo.take_damage(DamagePacket.create(99999.0, null, silo.wall_point_toward(Vector3.BACK, 1.0)))
	_check(GameState.is_game_over and GameState.game_over_reason == &"silo", "silo at 0 Structure ends the run (reason %s)" % GameState.game_over_reason)
	get_tree().paused = false

	print("")
	print("Economy note: %d Al banked by the end of wave 1 (pistol costs 20)." % _al_from_wave_1)
	if _failures.is_empty():
		print("SMOKE TEST PASSED (%d checks)" % _checks)
	else:
		print("SMOKE TEST FAILED: %d of %d checks" % [_failures.size(), _checks])
		for failure in _failures:
			print("  - " + failure)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	get_tree().quit(0 if _failures.is_empty() else 1)


# --- Scenarios ------------------------------------------------------------------------------------

func _check_lane_paths() -> void:
	var map := (_main as Node3D).get_world_3d().navigation_map
	var silo := GameState.silo
	for node in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		var lane := node as LaneMarker
		var start := NavigationServer3D.map_get_closest_point(map, lane.global_position)
		var goal_wall := silo.wall_point_toward(lane.global_position, 0.0)
		var goal := goal_wall + (goal_wall - silo.global_position).normalized() * 0.9
		var path := NavigationServer3D.map_get_path(map, start, goal, true)
		var reached := not path.is_empty() and path[path.size() - 1].distance_to(goal) < 1.5
		_check(reached, "navmesh path from lane %d to the silo (%d points)" % [lane.lane_index, path.size()])


func _check_spawn_mix(wave: int) -> void:
	var budget := _director.curve.threat_budget(wave)
	var spent := 0.0
	var robots := 0
	var kinds := PackedStringArray()
	for event: WaveDirector.SpawnEvent in _director.get("_events"):
		spent += event.archetype.threat_cost()
		robots += event.robot_count()
		kinds.append(String(event.archetype.id))
	_check(spent <= budget + 0.01 and budget - spent < 2.0,
			"wave %d spends %.0f of its %.1f threat budget on %d robots (%s)" % [wave, spent, budget, robots, ", ".join(kinds)])


func _test_theft() -> void:
	var silo := GameState.silo
	var thieves := get_tree().get_nodes_in_group(Robot.THIEF_GROUP)
	var thief: Robot = null
	var has_sack := func() -> bool:
		for node in get_tree().get_nodes_in_group(Robot.THIEF_GROUP):
			if (node as Robot).sack_amount > 0.0:
				return true
		return false
	var t := await _wait_until(has_sack, 40.0)
	if t < 0.0:
		print("  NOTE  no thief reached the chute this run (%d thieves rolled); theft checks skipped" % thieves.size())
		return
	for node in get_tree().get_nodes_in_group(Robot.THIEF_GROUP):
		if (node as Robot).sack_amount > 0.0:
			thief = node as Robot
			break
	_check(thief.ai_state == Robot.AiState.FLEEING, "a Nibbler thief grabs a %d-bushel sack and runs for the corn" % roundi(thief.sack_amount))
	var at := thief.global_position
	var grain_before := silo.grain
	thief.take_damage(DamagePacket.create(9999.0, _farmer, at))
	await _frames(40)
	var sack: Pickup = null
	for node in get_tree().get_nodes_in_group(Pickup.GROUP):
		if (node as Pickup).kind == Pickup.GRAIN:
			sack = node as Pickup
	_check(sack != null, "destroying the thief drops the grain sack")
	if sack != null:
		_farmer.teleport_to(sack.global_position + Vector3.UP * 0.2)
		await _frames(10)
		_check(silo.grain > grain_before, "walking over the sack returns the grain (%.0f -> %.0f)" % [grain_before, silo.grain])


func _test_wrench_and_pickups() -> void:
	# A robot bashing the silo stands still, which keeps this check deterministic.
	var robot := await _first_robot(40.0, null, true)
	if robot == null:
		_check(false, "a robot is attacking the silo to test the wrench on")
		return
	var away := robot.global_position - GameState.silo.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.1 else Vector3.BACK
	_farmer.teleport_to(robot.global_position + away * 1.2 + Vector3.UP * 0.1)
	await _aim_camera_at(robot.global_position + Vector3.UP * 0.4)
	var hp_before := robot.health.current
	_farmer.wrench.swing()
	_check(is_equal_approx(hp_before - robot.health.current, 25.0), "wrench bonk does 25 to a Nibbler (%.0f -> %.0f HP)" % [hp_before, robot.health.current])
	_check(robot.target_kind == Robot.TargetKind.PLAYER, "a Nibbler hit from up close switches to the farmer")
	var parts_before := GameState.parts.values().reduce(func(a: int, b: int) -> int: return a + b, 0) as int
	robot.take_damage(DamagePacket.create(999.0, _farmer, robot.global_position))
	await _frames(150)
	var parts_after := GameState.parts.values().reduce(func(a: int, b: int) -> int: return a + b, 0) as int
	_check(parts_after > parts_before, "its parts burst out, magnetize and bank (%d -> %d)" % [parts_before, parts_after])
	_farmer.teleport_to(Vector3(0.0, 0.2, 14.0))


func _test_pistol() -> void:
	var target := await _first_robot(30.0, null, true)
	if target == null:
		_check(false, "a robot is attacking the silo to test the pistol on")
		return
	# Clear the line of fire: on some seeds a Clanker from the squad is standing right where the farmer lands.
	_kill_all_robots(target)
	_farmer.equip(1)
	var aim_at := target.global_position + Vector3.UP * 0.45 * target.type_scale()
	var out := aim_at - GameState.silo.global_position
	out.y = 0.0
	_farmer.teleport_to(aim_at + out.normalized() * 7.0 - Vector3.UP * 0.35 * target.type_scale())
	await _aim_camera_at(aim_at)
	var hp := target.health.current
	var ammo := _farmer.pistol.ammo
	_farmer.pistol.fire()
	_check(_farmer.pistol.ammo == ammo - 1, "pistol uses a round (%d -> %d)" % [ammo, _farmer.pistol.ammo])
	_check(target.health.current < hp or target.ai_state == Robot.AiState.DEAD,
			"pistol hitscan from the camera-center ray hits a %s (%.0f -> %.0f HP)" % [target.archetype.display_name, hp, target.health.current])
	_farmer.teleport_to(Vector3(0.0, 0.2, 14.0))


func _test_squads() -> void:
	var clanker: Robot = null
	var has_squad := func() -> bool:
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			if (node as Robot).squad != null:
				return true
		return false
	var t := await _wait_until(has_squad, 45.0)
	if t < 0.0:
		print("  NOTE  wave 2 rolled no Clanker squad this run; squad checks skipped")
		return
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		if (node as Robot).squad != null:
			clanker = node as Robot
			break
	var squad := clanker.squad
	_check(squad.members.size() == 3, "Clankers arrive as a squad of 3")
	_check(is_equal_approx(clanker.health.max_health, 60.0 * 1.072 * _trait_hp(clanker)),
			"Clanker HP 60 x wave 2 scaling (%.1f)" % clanker.health.max_health)
	var targets := squad.members.map(func(r: Robot) -> int: return r.target_kind)
	_check(targets.count(targets[0]) == 3, "the squad shares one target")


func _test_repair() -> void:
	var silo := GameState.silo
	if silo.get_cracks().is_empty():
		(_main.get_node(^"DebugCheats") as DebugCheats).damage_silo(120.0)
	# The smallest ground-level crack: overflow damage piles into existing cracks once they're all open.
	var crack: SiloCrack = null
	for c in silo.get_cracks():
		if crack == null or (c.band == 0 and crack.band != 0) or (c.band == crack.band and c.pool < crack.pool):
			crack = c
	_farmer.teleport_to(_stand_point_for(crack))
	await _frames(20)
	_check(_farmer.repair_target == crack, "standing next to a %s puts it in reach" % crack.describe())
	var leak_before := silo.total_leak_rate()
	var crack_leak := crack.leak_rate(silo.leak_rates)
	var structure_before := silo.structure
	var pool := crack.pool
	var crack_id := crack.get_instance_id()
	Input.action_press(&"interact")
	var t := await _wait_until(func() -> bool: return not silo.get_cracks().any(func(c: SiloCrack) -> bool: return c.get_instance_id() == crack_id),
			maxf(15.0, 1.5 * pool / _farmer.repair_rate_now()))
	Input.action_release(&"interact")
	_check(t >= 0.0, "holding repair closes the crack (%.1f s for %.0f Structure)" % [t, pool])
	_check(absf((leak_before - silo.total_leak_rate()) - crack_leak) < 0.01,
			"its leak stops (%.1f -> %.1f bu/s)" % [leak_before, silo.total_leak_rate()])
	_check(silo.structure > structure_before, "repair restores Structure (%.0f -> %.0f)" % [structure_before, silo.structure])


func _test_pegboard_and_save() -> void:
	var shed := get_tree().get_first_node_in_group(ToolShed.GROUP_SHED) as ToolShed
	_farmer.teleport_to(shed.interaction_point() + Vector3.UP * 0.2)
	await _frames(15)
	_check(_farmer.focus_interactable == shed, "the shed door is in reach")
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	await _frames(2)
	_check(_pegboard.is_open, "Interact at the shed opens the pegboard during the intermission")
	_check(not _farmer.input.enabled, "the farmer stops taking input while the pegboard is open")
	var short := 20 + 12 - GameState.parts[&"al"]
	if short > 0:
		GameState.add_parts({&"al": short})
	_check(_pegboard.buy(&"attack.pistol"), "buy the Rivet Pistol for 20 Al")
	_check(_farmer.is_weapon_available(_farmer.pistol) and _farmer.current_weapon == _farmer.pistol, "the pistol is now equipped")
	_check(not _pegboard.buy(&"attack.pistol"), "an unlock can't be bought twice")
	_check(not _pegboard.buy(&"travel.fuel_tank"), "Fuel Tank stays locked until the jetpack is unlocked")
	_check(_pegboard.buy(&"travel.comfy_boots"), "buy Comfy Boots level 1")
	_check(is_equal_approx(StatService.get_stat(&"player.run_speed", 7.0), 7.21), "run speed 7.0 -> %.2f m/s" % StatService.get_stat(&"player.run_speed", 7.0))
	_pegboard.close()
	_check(not _pegboard.is_open and _farmer.input.enabled, "closing the pegboard gives control back")

	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(PROFILE))
	var upgrades: Dictionary = (saved as Dictionary).get("upgrades", {}) if saved is Dictionary else {}
	_check(int(upgrades.get("attack.pistol", 0)) == 1 and int(upgrades.get("travel.comfy_boots", 0)) == 1,
			"purchases autosave to the profile")
	StatService.set_levels({})
	SaveManager.load_profile()
	_check(StatService.level_of(&"attack.pistol") == 1 and StatService.level_of(&"travel.comfy_boots") == 1, "loading the profile restores the pegboard")


func _test_dinner_bell() -> void:
	var bell := _main.get_node(^"Farm/DinnerBell") as DinnerBell
	_farmer.teleport_to(bell.interaction_point() + Vector3(0.8, 0.2, 0.0))
	await _frames(10)
	_check(_farmer.focus_interactable == bell, "the dinner bell is in reach")
	var al_before := GameState.parts[&"al"]
	Input.action_press(&"interact")
	var t := await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SIREN, 3.0)
	Input.action_release(&"interact")
	_check(t > 0.9 and t < 1.3, "holding Interact for 1 s rings the bell and starts the siren (%.2f s)" % t)
	_check(GameState.parts[&"al"] > al_before, "Early Bird bonus paid (%d -> %d Al)" % [al_before, GameState.parts[&"al"]])
	_farmer.teleport_to(Vector3(0.0, 0.2, 14.0))


func _test_jetpack() -> void:
	_farmer.teleport_to(Vector3(20.0, 0.3, 15.0))
	await _frames(40)
	_farmer.jetpack.refill()
	var ground_y := _farmer.global_position.y
	Input.action_press(&"jump")
	var peak := ground_y
	for i in 120:
		await get_tree().physics_frame
		peak = maxf(peak, _farmer.global_position.y)
	Input.action_release(&"jump")
	var reach := peak - ground_y
	_check(reach > 7.6 and reach < 9.6, "standing jump + full thrust reaches ~8.5 m (%.2f m)" % reach)
	_check(_farmer.jetpack.fuel <= 0.01, "1.2 s of fuel is used up")
	await _wait_until(func() -> bool: return _farmer.is_on_floor(), 5.0)
	var landed_fuel := _farmer.jetpack.fuel
	await _frames(20)
	_check(is_equal_approx(_farmer.jetpack.fuel, landed_fuel), "no recharge during the 0.5 s delay")
	var t := await _wait_until(func() -> bool: return _farmer.jetpack.fuel >= _farmer.jetpack.flight_time(), 4.0)
	_check(t > 1.5 and t < 2.6, "fuel refills on the ground in ~2 s after the delay (%.2f s)" % t)


func _test_ladder() -> void:
	var ladder := GameState.silo.get_node(^"Ladder") as Climbable
	_farmer.teleport_to(ladder.global_position + ladder.outward() * 0.9 + Vector3.UP * 0.2)
	_farmer.camera_rig.yaw = atan2(ladder.outward().x, ladder.outward().z)
	await _frames(20)
	Input.action_press(&"move_forward")
	var t := await _wait_until(func() -> bool: return _farmer.state == Farmer.State.CLIMBING, 3.0)
	_check(t >= 0.0, "walking into the silo ladder starts a climb")
	t = await _wait_until(func() -> bool: return _farmer.global_position.y >= 8.1, 5.0)
	Input.action_release(&"move_forward")
	_check(t > 1.5 and t < 2.6, "climbs at 4 m/s (8 m in %.2f s)" % t)
	await _frames(2)
	_check(_farmer.can_step_off_ladder(), "the HUD can offer stepping onto catwalk 1")
	Input.action_press(&"jump")
	await _frames(2)
	Input.action_release(&"jump")
	await _wait_until(func() -> bool: return _farmer.state == Farmer.State.GROUNDED and _farmer.is_on_floor(), 3.0)
	var y := _farmer.global_position.y
	_check(_farmer.is_on_floor() and y > 7.8 and y < 8.5, "stepped off onto the 8 m catwalk (y = %.2f)" % y)


func _test_zipline() -> void:
	var line := _main.get_node(^"Farm/Ziplines/Z1_SiloToBarn") as Zipline
	_farmer.teleport_to(line.interaction_point() + Vector3.UP * 0.1)
	await _frames(20)
	_check(_farmer.is_on_floor() and _farmer.focus_interactable == line, "Z1 start is reachable on the silo dome (y = %.2f)" % _farmer.global_position.y)
	Input.action_press(&"interact")
	await _frames(2)
	Input.action_release(&"interact")
	_check(_farmer.state == Farmer.State.ZIPLINING, "Interact grabs the zipline")
	var t := await _wait_until(func() -> bool: return _farmer.state == Farmer.State.GROUNDED and _farmer.is_on_floor(), 8.0)
	var expected := line.length() / line.speed
	_check(t > expected * 0.9 and t < expected + 1.5, "rides %.0f m at 12 m/s (%.2f s, expected ~%.2f)" % [line.length(), t, expected])
	var at := _farmer.global_position
	_check(at.y > 12.0 and at.x < -25.0, "lands on the barn roof (%.1f, %.1f, %.1f)" % [at.x, at.y, at.z])


func _test_foreman() -> void:
	(_main.get_node(^"DebugCheats") as DebugCheats).call(&"_on_console_submitted", "wave 5")
	await _wait_until(func() -> bool: return _director.phase == WaveDirector.Phase.SPAWNING, 15.0)
	_check(_director.curve.is_big_haul(5), "wave 5 is a Big Haul")
	var foreman: Robot = null
	var has_foreman := func() -> bool:
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			if (node as Robot).is_foreman:
				return true
		return false
	var t := await _wait_until(has_foreman, 60.0)
	_check(t >= 0.0, "a Foreman spawns during the Big Haul (after %.1f s)" % t)
	if t < 0.0:
		return
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		if (node as Robot).is_foreman:
			foreman = node as Robot
	var expected_hp := 400.0 * _director.curve.hp_multiplier(5) * 3.0 * _trait_hp(foreman)
	_check(foreman is HeavyRobot and is_equal_approx(foreman.health.max_health, expected_hp),
			"the Foreman is a Thumper with 3x HP (%.0f) and a bonus trait (%s)" % [foreman.health.max_health,
			", ".join(PackedStringArray(foreman.extra_traits.map(func(r: RobotTrait) -> String: return r.display_name)))])
	_check(foreman.roll_drops() == Robot.FOREMAN_DROPS, "Foreman drops are guaranteed: 10 Al, 6 Cu, 2 Au, 3 PC")
	# Put it next to the silo with the farmer nearby on the ground, and let it slam.
	_kill_all_robots(foreman)
	var silo := GameState.silo
	foreman.target_kind = Robot.TargetKind.SILO
	foreman.global_position = silo.global_position + Vector3.LEFT * (silo.radius + 1.6)
	foreman.reset_physics_interpolation()
	# Full Structure and no floor, so the slam shows up as a drop and can't end the run.
	_silo_floor = 0.0
	silo.structure = silo.max_structure
	GameState.god_mode = false
	_farmer.armor = 0.0
	_farmer.health.reset(_farmer.health.max_health)
	_farmer.teleport_to(silo.global_position + Vector3.LEFT * (silo.radius + 1.6) + Vector3.BACK * 4.0 + Vector3.UP * 0.2)
	await _frames(10)
	var structure := silo.structure
	var hp := _farmer.health.current
	t = await _wait_until(func() -> bool: return silo.structure < structure, 8.0)
	_check(t >= 0.0, "the Foreman slams the silo for %.0f" % (structure - silo.structure))
	await _frames(60)
	_check(_farmer.health.current < hp, "its shockwave ring hits a farmer standing on the ground (%.0f -> %.0f HP)" % [hp, _farmer.health.current])
	GameState.god_mode = true
	_silo_floor = 0.25


# --- Helpers --------------------------------------------------------------------------------------

func _trait_hp(robot: Robot) -> float:
	var multiplier := 1.0
	for robot_trait in robot.all_traits():
		multiplier *= robot_trait.hp_multiplier
	return multiplier


func _stand_point_for(crack: SiloCrack) -> Vector3:
	var silo := GameState.silo
	var out := crack.global_position - silo.global_position
	out.y = 0.0
	var floor_y := 0.1
	if crack.band == 1:
		floor_y = 8.1
	elif crack.band == 2:
		floor_y = 16.1
	return silo.global_position + out.normalized() * (silo.radius + 0.9) + Vector3.UP * floor_y


## Puts the crosshair (camera-center ray) on `point`, like a player would.
## The camera sits shoulder_offset.x to the side, so its yaw is turned asin(offset / distance) off
## the straight line from the farmer; pitch then settles in a few frames.
func _aim_camera_at(point: Vector3) -> void:
	var rig := _farmer.camera_rig
	# The rig catches up with a teleport only on the next frame, so measure from the farmer.
	var flat := point - _farmer.global_position
	flat.y = 0.0
	var side := rig.shoulder_offset.x * rig.shoulder_side
	rig.yaw = atan2(-flat.x, -flat.z) + asin(clampf(side / maxf(flat.length(), 0.01), -1.0, 1.0))
	for i in 6:
		await _frames(1)
		var dir := point - rig.camera.global_position
		rig.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())


func _first_robot(timeout: float, exclude: Robot = null, attacking_silo: bool = false) -> Robot:
	var found: Array[Robot] = [null]
	var look := func() -> bool:
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			var robot := node as Robot
			if robot == exclude:
				continue
			if attacking_silo and (robot.ai_state in [Robot.AiState.SEEK, Robot.AiState.FLEEING, Robot.AiState.STEALING]
					or robot.target_kind != Robot.TargetKind.SILO):
				continue
			found[0] = robot
			return true
		return false
	await _wait_until(look, timeout)
	return found[0]


func _kill_all_robots(spare: Robot = null) -> void:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		var robot := node as Robot
		if robot != spare:
			robot.take_damage(DamagePacket.create(99999.0, _farmer, robot.global_position))


## Waits (in physics frames) until `condition` is true. Returns seconds waited, or -1 on timeout.
func _wait_until(condition: Callable, timeout: float) -> float:
	var waited := 0.0
	while not condition.call():
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
		if waited > timeout:
			return -1.0
	return waited


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = keycode
		event.keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _section(title: String) -> void:
	print("\n== %s ==" % title)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	print(("  PASS  " if ok else "  FAIL  ") + what)
	if not ok:
		_failures.append(what)
