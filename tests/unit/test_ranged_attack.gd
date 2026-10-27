extends GutTest
## The shared ranged attack (M2-B7, delivers M2-A4): AttackProfile data, RangedAttack's charge-fire-recover
## loop, telegraphs, farmer attack tokens, the projectile cap and the incoming-shot event.

const DRONE := "res://data/robots/archetypes/drone.tres"
const LOBBER := "res://data/robots/archetypes/roof_lobber.tres"
const SILO_SCENE := "res://scenes/farm/silo.tscn"
const STEP := 1.0 / 60.0

var _world: Node3D
var _silo: Silo
var _silo_before: Silo
var _scene_before: Node


func before_each() -> void:
	_silo_before = GameState.silo
	_scene_before = get_tree().current_scene
	AttackTokens.clear()
	_world = Node3D.new()
	add_child_autofree(_world)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	ground.add_child(shape)
	_world.add_child(ground)
	ground.position = Vector3(0.0, -0.5, 0.0)
	_silo = (load(SILO_SCENE) as PackedScene).instantiate() as Silo
	_world.add_child(_silo)


func after_each() -> void:
	AttackTokens.clear()
	GameState.silo = _silo_before
	get_tree().current_scene = _scene_before


## A drone parked at `where` with physics off, so the test drives its RangedAttack frame by frame. Wave 5
## keeps the opening's unscaled charge, lead and volley (M2-B10 scales them from wave 6).
func _shooter(where: Vector3 = Vector3(20.0, 14.0, 0.0), profile_id: StringName = &"", wave: int = 5) -> VerticalRobot:
	var archetype := load(DRONE) as RobotArchetype
	var robot := archetype.scene.instantiate() as VerticalRobot
	robot.setup(archetype, wave, DifficultyCurve.new(), RngService.make_rng([1]))
	_world.add_child(robot)
	robot.global_position = where
	robot.set_physics_process(false)
	if not profile_id.is_empty():
		robot.ranged.profile = load(AttackProfile.resource_path_for(profile_id)) as AttackProfile
	return robot


func _fake_farmer(where: Vector3) -> Node3D:
	var farmer := Node3D.new()
	farmer.add_to_group(&"players")
	_world.add_child(farmer)
	farmer.global_position = where
	return farmer


func _step(attack: RangedAttack, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		attack.step(STEP)


# --- Unchanged behavior --------------------------------------------------------------------------------

func test_drone_and_lobber_profiles_keep_their_m1_numbers() -> void:
	var drone := (load(DRONE) as RobotArchetype).ranged_attack()
	assert_eq(drone.kind, AttackProfile.Kind.STRAIGHT)
	assert_eq([drone.charge_time, drone.interval, drone.damage_vs_farmer, drone.damage_vs_silo, drone.speed,
			drone.gravity, drone.attack_range], [0.9, 2.8, 4.0, 8.0, 20.0, 0.0, 32.0], "the drone's shot")
	var lobber := (load(LOBBER) as RobotArchetype).ranged_attack()
	assert_eq(lobber.kind, AttackProfile.Kind.LOB)
	assert_eq([lobber.charge_time, lobber.interval, lobber.damage_vs_farmer, lobber.damage_vs_silo, lobber.speed,
			lobber.gravity, lobber.attack_range], [1.1, 3.6, 6.0, 12.0, 20.0, 6.0, 24.0], "the lobber's lob")


func test_lobber_finds_and_climbs_a_roof_when_gameplay_is_nested_under_another_scene() -> void:
	_world.reparent(get_tree().root)
	get_tree().current_scene = _world
	var main := Node3D.new()
	main.name = "NestedMain"
	main.position = Vector3(35.0, 2.0, -20.0)
	main.rotation.y = 0.4
	_world.add_child(main)
	var farm := Node3D.new()
	farm.name = "Farm"
	main.add_child(farm)
	var region := Node3D.new()
	region.name = "NavRegion"
	farm.add_child(region)
	_silo.reparent(region)
	GameState.silo = _silo
	var building := Node3D.new()
	building.name = "ToolShed"
	building.position = Vector3(12.0, 0.0, 5.0)
	region.add_child(building)
	var archetype := load(LOBBER) as RobotArchetype
	var robot := archetype.scene.instantiate() as VerticalRobot
	robot.setup(archetype, 3, DifficultyCurve.new(), RngService.make_rng([31]))
	var entry := building.to_global(Vector3(5.2, 0.0, 0.0))
	robot.position = main.to_local(entry)
	main.add_child(robot)
	robot.set_physics_process(false)
	assert_eq(robot.travel, VerticalRobot.Travel.APPROACH, "a wrapper must not trigger the ground-combat fallback")
	assert_eq(robot.get(&"_roof_index"), 0, "the silo's farm supplies the ToolShed roof")
	var chosen_entry: Vector3 = robot.get(&"_entry")
	assert_almost_eq(chosen_entry.distance_to(entry), 0.0, 0.001, "roof approach uses the nested building's global transform")
	robot._physics_process(STEP)
	assert_eq(robot.travel, VerticalRobot.Travel.CLIMB, "arriving at the selected building starts climbing")
	for i in 1200:
		if robot.travel == VerticalRobot.Travel.PERCHED:
			break
		robot._physics_process(STEP)
	assert_eq(robot.travel, VerticalRobot.Travel.PERCHED)
	var roof_top := building.to_global(Vector3(3.3, 4.05, 0.0))
	assert_almost_eq(robot.global_position.distance_to(roof_top), 0.0, 0.05, "it reaches the actual elevated roof instead of parking on the ground")


func test_lobber_retains_standalone_scene_roof_lookup_without_a_registered_silo() -> void:
	_world.reparent(get_tree().root)
	get_tree().current_scene = _world
	GameState.silo = null
	var farm := Node3D.new()
	farm.name = "Farm"
	_world.add_child(farm)
	var region := Node3D.new()
	region.name = "NavRegion"
	farm.add_child(region)
	var building := Node3D.new()
	building.name = "ToolShed"
	region.add_child(building)
	var archetype := load(LOBBER) as RobotArchetype
	var robot := archetype.scene.instantiate() as VerticalRobot
	robot.setup(archetype, 3, DifficultyCurve.new(), RngService.make_rng([32]))
	_world.add_child(robot)
	robot.set_physics_process(false)
	assert_eq(robot.travel, VerticalRobot.Travel.APPROACH)
	assert_eq(robot.get(&"_roof_index"), 0, "standalone scene roots still supply their farm roofs")


func test_launch_matches_the_m1_trajectory() -> void:
	var robot := _shooter()
	for profile_id in [&"drone_shot", &"lobber_lob"]:
		robot.ranged.profile = load(AttackProfile.resource_path_for(profile_id)) as AttackProfile
		var profile := robot.ranged.profile
		for case: Array in [[Vector3(20, 14, 0), Vector3(0, 9, 0)], [Vector3(3, 4, 2), Vector3(-6, 1, 9)]]:
			var from: Vector3 = case[0]
			var to: Vector3 = case[1]
			# VerticalRobot._throw_projectile in M1:
			var offset := to - from
			var flight := maxf(0.35, Vector2(offset.x, offset.z).length() / profile.speed)
			var expected := offset / flight
			expected.y += 0.5 * profile.gravity * flight
			var shot := robot.ranged.launch(from, to)
			assert_almost_eq((shot[0] as Vector3).distance_to(expected), 0.0, 0.0001, "%s velocity" % profile_id)
			assert_almost_eq(float(shot[1]), flight, 0.0001, "%s flight time" % profile_id)


func test_charge_then_fire_then_recover_on_m1_timing() -> void:
	var robot := _shooter()
	var attack := robot.ranged
	var fired: Array[float] = []
	var clock := 0.0
	var pool := ProjectilePool.of(robot)
	var launched := pool.active_count()
	for i in roundi(6.0 / STEP):
		attack.step(STEP)
		clock += STEP
		if pool.active_count() > launched:
			fired.append(clock)
		launched = pool.active_count()
	assert_gte(fired.size(), 2, "the drone fires twice in 6 s")
	assert_almost_eq(fired[0], 0.9, 0.05, "first shot after the 0.9 s charge")
	assert_almost_eq(fired[1] - fired[0], 2.8, 0.05, "then one every 2.8 s")


# --- Every profile with its telegraph ----------------------------------------------------------------

func test_a_test_robot_fires_every_profile_with_its_telegraph() -> void:
	var ids := PackedStringArray()
	for file_name in DirAccess.get_files_at(RobotArchetype.ATTACK_DIR):
		if file_name.get_extension() == "tres":
			ids.append(file_name.get_basename())
	assert_true(ids.size() >= 4, "straight, lob, rail and bomb profiles exist")
	for id in ids:
		var robot := _shooter(Vector3(18.0, 14.0, 0.0), StringName(id))
		var attack := robot.ranged
		var farmer := _fake_farmer(Vector3(12.0, 0.0, 6.0))
		attack.target_provider = func() -> Node3D: return farmer
		attack.step(STEP)
		assert_eq(attack.state, RangedAttack.State.CHARGING, "%s starts charging" % id)
		var muzzle := robot.get_node(^"Model/ChargingProjectile") as Node3D
		assert_true(muzzle.visible, "%s glows while it charges" % id)
		var expected := attack.profile.telegraph()
		if expected.is_empty():
			assert_null(attack.telegraph, "%s: a straight shot shows only the glow" % id)
		else:
			assert_not_null(attack.telegraph, "%s shows a telegraph" % id)
			assert_eq(attack.telegraph.kind, expected, "%s shows its %s" % [id, expected])
		var launched := ProjectilePool.of(robot).active_count()
		_step(attack, attack.profile.effective_charge_time() + STEP)
		assert_gt(ProjectilePool.of(robot).active_count(), launched, "%s fires" % id)
		assert_false(muzzle.visible, "%s's glow goes out when it fires" % id)
		if not expected.is_empty() and expected != &"aim_line":
			assert_true(attack.telegraph != null and attack.telegraph.locked, "%s's marker stays put while the shot flies" % id)
		robot.queue_free()
		farmer.queue_free()
		await wait_physics_frames(1)


func test_the_wave_three_lobber_shows_where_it_will_land() -> void:
	var lobber := load(LOBBER) as RobotArchetype
	assert_eq(lobber.ranged_attack().telegraph(), &"landing_circle")
	var robot := _shooter(Vector3(16.0, 6.0, 0.0), &"lobber_lob")
	var farmer := _fake_farmer(Vector3(10.0, 0.0, 4.0))
	robot.ranged.target_provider = func() -> Node3D: return farmer
	robot.ranged.step(STEP)
	await wait_physics_frames(2)
	robot.ranged.step(STEP)
	var circle := robot.ranged.telegraph
	assert_not_null(circle)
	assert_almost_eq(Vector2(circle.global_position.x - 10.0, circle.global_position.z - 4.0).length(), 0.0, 0.05,
			"the chalk circle sits under the farmer")
	assert_almost_eq(circle.global_position.y, 0.04, 0.05, "on the ground")
	farmer.global_position = Vector3(6.0, 0.0, 4.0)
	robot.ranged.step(STEP)
	assert_almost_eq(circle.global_position.x, 6.0, 0.05, "it follows the farmer while the lob charges")


func test_charge_time_never_drops_under_the_floor() -> void:
	var profile := (load(DRONE) as RobotArchetype).ranged_attack()
	assert_almost_eq(profile.effective_charge_time(0.1), AttackProfile.MIN_CHARGE_TIME, 0.0001)
	assert_almost_eq(profile.effective_charge_time(0.8), 0.72, 0.0001)


# --- Fairness: tokens, the projectile cap, warnings -----------------------------------------------------

func test_tokens_cap_how_many_robots_shoot_the_farmer() -> void:
	var farmer := _fake_farmer(Vector3(10.0, 0.0, 0.0))
	var robots: Array[VerticalRobot] = []
	for i in 4:
		var robot := _shooter(Vector3(18.0 + i, 14.0, float(i)))
		robot.ranged.token_limit = 2
		robot.ranged.target_provider = func() -> Node3D: return farmer
		robot.ranged.step(STEP)
		robots.append(robot)
	var at_farmer := robots.filter(func(r: VerticalRobot) -> bool: return r.ranged.target == farmer).size()
	assert_eq(at_farmer, 2, "no more than 2 robots shoot the farmer at once")
	assert_eq(AttackTokens.count(farmer), 2)
	assert_true(robots.filter(func(r: VerticalRobot) -> bool: return r.ranged.target == _silo).size() == 2,
			"the rest shoot the silo")
	robots[0].ranged.cancel()
	assert_eq(AttackTokens.count(farmer), 1, "a cancelled charge hands its token back")
	robots[1].kill()
	assert_eq(AttackTokens.count(farmer), 0, "so does a destroyed robot")


func test_tokens_come_back_once_the_shot_is_done() -> void:
	var farmer := _fake_farmer(Vector3(10.0, 0.0, 0.0))
	var robot := _shooter()
	robot.ranged.target_provider = func() -> Node3D: return farmer
	robot.ranged.step(STEP)
	assert_eq(AttackTokens.count(farmer), 1, "charging at the farmer takes a token")
	_step(robot.ranged, 0.9 + STEP)
	assert_eq(AttackTokens.count(farmer), 1, "held while the shot flies")
	await wait_seconds(2.5)
	_step(robot.ranged, 0.1)
	assert_eq(AttackTokens.count(farmer), 0, "given back when it has landed or missed")


func test_no_new_shot_while_the_sky_is_full() -> void:
	var robot := _shooter()
	var pool := ProjectilePool.of(robot)
	var parked: Array[Projectile] = []
	for i in RangedAttack.MAX_PROJECTILES:
		var p := pool.launch(Vector3(0.0, 50.0 + i, 0.0), Vector3.ZERO, 0.0, 30.0, 0, [], Callable())
		RangedAttack._flying.append([p, p.launches])
		parked.append(p)
	assert_eq(RangedAttack.projectiles_in_flight(), RangedAttack.MAX_PROJECTILES)
	robot.ranged.step(STEP)
	assert_eq(robot.ranged.state, RangedAttack.State.READY, "holds fire at the cap")
	parked[0].retire()
	robot.ranged.step(STEP)
	assert_eq(robot.ranged.state, RangedAttack.State.CHARGING, "fires again once one lands")
	for p in parked:
		p.retire()


func test_a_shot_at_the_farmer_announces_itself() -> void:
	var farmer := _fake_farmer(Vector3(10.0, 0.0, 0.0))
	var robot := _shooter()
	var heard: Array = []
	var listener := func(shooter: Node3D, at: Node3D, impact: float, off_screen: bool) -> void:
		heard.append([shooter, at, impact, off_screen])
	EventBus.robot_shot_incoming.connect(listener)
	robot.ranged.target_provider = func() -> Node3D: return farmer
	robot.ranged.step(STEP)
	EventBus.robot_shot_incoming.disconnect(listener)
	assert_eq(heard.size(), 1, "one warning per shot at the farmer")
	if heard.size() == 1:
		assert_eq(heard[0][0], robot)
		assert_eq(heard[0][1], farmer)
		assert_gt(float(heard[0][2]), 0.9, "it lands after the charge plus the flight")


func test_attack_tokens_track_holders() -> void:
	var farmer := Node.new()
	var a := RefCounted.new()
	var b := RefCounted.new()
	var c := RefCounted.new()
	assert_true(AttackTokens.acquire(farmer, a, 2))
	assert_true(AttackTokens.acquire(farmer, a, 2), "asking again keeps the same token")
	assert_true(AttackTokens.acquire(farmer, b, 2))
	assert_false(AttackTokens.acquire(farmer, c, 2), "none left for a third")
	AttackTokens.release(a)
	assert_true(AttackTokens.acquire(farmer, c, 2))
	farmer.free()


func test_farmer_tokens_by_phase() -> void:
	var curve := load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	assert_eq(curve.farmer_attack_tokens(1), 2, "2 in the opening")
	assert_eq(curve.farmer_attack_tokens(6), 2, "through the six-wave opening")
	assert_eq(curve.farmer_attack_tokens(7), 3, "3 from wave 7")
	assert_eq(curve.farmer_attack_tokens(16), 4, "4 from wave 16")
	assert_eq(curve.farmer_attack_tokens(31), 5, "5 from wave 31")


# --- Attack scaling (M2-B10) -----------------------------------------------------------------------------

func _moving_farmer(where: Vector3, velocity: Vector3) -> CharacterBody3D:
	var farmer := CharacterBody3D.new()
	farmer.add_to_group(&"players")
	_world.add_child(farmer)
	farmer.global_position = where
	farmer.velocity = velocity
	return farmer


func test_the_wave_sets_charge_lead_tokens_and_volley() -> void:
	var curve := load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	var archetype := load(DRONE) as RobotArchetype
	for wave in [5, 12, 24]:
		var robot := archetype.scene.instantiate() as VerticalRobot
		robot.setup(archetype, wave, curve, RngService.make_rng([1]))
		_world.add_child(robot)
		robot.set_physics_process(false)
		assert_eq(robot.ranged.charge_multiplier, curve.charge_multiplier(wave), "wave %d charge" % wave)
		assert_eq(robot.ranged.aim_lead, curve.aim_lead(wave), "wave %d lead" % wave)
		assert_eq(robot.ranged.token_limit, curve.farmer_attack_tokens(wave), "wave %d tokens" % wave)
		assert_eq(robot.ranged.volley_count(), curve.volley_size(wave), "wave %d drone volley" % wave)
		robot.queue_free()


func test_charge_multiplier_shortens_the_charge() -> void:
	var robot := _shooter()
	robot.ranged.charge_multiplier = 0.7
	var pool := ProjectilePool.of(robot)
	var launched := pool.active_count()
	_step(robot.ranged, 0.63 - STEP)
	assert_eq(pool.active_count(), launched, "not before 0.9 x 0.7 s")
	_step(robot.ranged, 2.0 * STEP)
	assert_gt(pool.active_count(), launched, "fires after the scaled charge")


func test_straight_shots_lead_a_moving_farmer_and_lobs_never_do() -> void:
	var farmer := _moving_farmer(Vector3(10.0, 0.0, 0.0), Vector3(0.0, 0.0, 5.0))
	var robot := _shooter(Vector3(20.0, 14.0, 0.0), &"drone_shot")
	var still := robot.ranged.aim_point(farmer)
	assert_almost_eq(still.z, 0.0, 0.0001, "no lead at 0")
	robot.ranged.aim_lead = 0.6
	var led := robot.ranged.aim_point(farmer)
	var flight := Vector3(20.0, 14.0, 0.0).distance_to(Vector3(10.0, 1.0, 0.0)) / robot.ranged.profile.speed
	assert_gt(led.z, 0.0, "a straight shot aims ahead of the farmer")
	assert_almost_eq(led.z, 5.0 * flight * 0.6, 0.35, "by the lead share of its travel during the flight")
	robot.ranged.profile = load(AttackProfile.resource_path_for(&"lobber_lob")) as AttackProfile
	assert_almost_eq(robot.ranged.aim_point(farmer).z, 0.0, 0.0001, "a lob never leads")


func test_a_volley_fires_several_shots_per_attack() -> void:
	var robot := _shooter()
	robot.ranged.volley_override = 3
	var pool := ProjectilePool.of(robot)
	var launched := pool.active_count()
	_step(robot.ranged, 0.9 + 2.0 * robot.ranged.profile.volley_gap + 5.0 * STEP)
	assert_eq(pool.active_count() - launched, 3, "three shots, volley_gap apart")
	assert_eq(robot.ranged.state, RangedAttack.State.RECOVER)
