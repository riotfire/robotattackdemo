extends GutTest
## Sidearms on existing robots (M2-B9, GDD 9.3, 9.6): the Spitter role, Clanker bolt and Thumper clod throws
## at an out-of-reach farmer, and the Clanker's front arm guard. A hovering farmer is neither immune nor a lure.
## Robots run with physics off, so each test drives _physics_process frame by frame (no navmesh: they stand).

const NIBBLER := "res://data/robots/archetypes/nibbler.tres"
const SPITTER := "res://data/robots/archetypes/spitter.tres"
const CLANKER := "res://data/robots/archetypes/clanker.tres"
const THUMPER := "res://data/robots/archetypes/thumper.tres"
const CURVE := "res://data/difficulty/default_difficulty.tres"
const SILO_SCENE := "res://scenes/farm/silo.tscn"
const STEP := 1.0 / 60.0

var _world: Node3D
var _silo: Silo
var _silo_before: Silo
var _farmers: Array[Node3D] = []


## A farmer stand-in: takes hits, never dies, and has a velocity for aim lead.
class FakeFarmer:
	extends CharacterBody3D
	var hits: Array[float] = []

	func take_damage(packet: DamagePacket) -> void:
		hits.append(packet.amount)

	func is_alive() -> bool:
		return true


func before_each() -> void:
	_silo_before = GameState.silo
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
	# Shots at a farmer up high fly on for a while; land them so later tests start with an empty sky.
	for node in ProjectilePool.of(self).get_children():
		if node is Projectile and (node as Projectile).is_active:
			(node as Projectile).retire()
	for farmer in _farmers:
		GameState.unregister_player(farmer)
	_farmers.clear()
	AttackTokens.clear()
	GameState.silo = _silo_before


func _robot(path: String, wave: int, where: Vector3, squad: RobotSquad = null, seed_value: int = 1) -> Robot:
	var archetype := load(path) as RobotArchetype
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, wave, load(CURVE) as DifficultyCurve, RngService.make_rng([seed_value]), null, false, [], squad)
	_world.add_child(robot)
	robot.global_position = where
	robot.set_physics_process(false)
	return robot


func _farmer(where: Vector3) -> FakeFarmer:
	var farmer := FakeFarmer.new()
	farmer.add_to_group(&"players")
	_world.add_child(farmer)
	farmer.global_position = where
	GameState.register_player(farmer)
	_farmers.append(farmer)
	return farmer


func _run(robots: Array, seconds: float) -> void:
	for i in roundi(seconds / STEP):
		for robot: Robot in robots:
			robot._physics_process(STEP)


# --- The Spitter ----------------------------------------------------------------------------------------

func test_the_spitter_matches_the_plan() -> void:
	var spitter := load(SPITTER) as RobotArchetype
	assert_eq(spitter.robot_type, RobotArchetype.RobotType.SCOUT, "a role of the small ground robot")
	assert_eq(spitter.robot_class, RobotArchetype.RobotClass.RANGED)
	assert_eq([spitter.base_hp, spitter.move_speed, spitter.silo_focus, spitter.distractibility, spitter.distract_range],
			[30.0, 7.0, 0.6, 0.6, 12.0])
	assert_almost_eq(spitter.threat_cost(), 2.5, 0.001, "small x ranged")
	assert_true(&"pea_shooter" in spitter.tells)
	var pea := spitter.ranged_attack()
	assert_eq(pea.kind, AttackProfile.Kind.STRAIGHT)
	assert_eq([pea.charge_time, pea.interval, pea.damage_vs_farmer, pea.damage_vs_silo, pea.speed],
			[0.8, 2.2, 3.0, 5.0, 14.0])
	var hit := _silo.global_position + Vector3.UP * pea.aim_height_silo
	assert_gte(_silo.hit_band(hit), 1, "peas aim at catwalk height, so they open high cracks")


func test_small_melee_spawns_become_spitters_by_the_curve_share() -> void:
	var director := WaveDirector.new()
	director.curve = load(CURVE) as DifficultyCurve
	director.spitter_archetype = load(SPITTER) as RobotArchetype
	var nibbler := load(NIBBLER) as RobotArchetype
	var clanker := load(CLANKER) as RobotArchetype
	for case: Array in [[12, 0.0], [13, 0.10], [18, 0.20], [30, 0.40]]:
		var rng := RngService.make_rng([5, case[0]])
		director.set(&"_wave_rng", rng)
		var spitters := 0
		for i in 2000:
			if director.roll_role(case[0], nibbler, 100.0) == director.spitter_archetype:
				spitters += 1
		assert_almost_eq(spitters / 2000.0, float(case[1]), 0.03, "wave %d Spitter share" % case[0])
	var rng := RngService.make_rng([5])
	director.set(&"_wave_rng", rng)
	var state := rng.state
	director.roll_role(12, nibbler, 100.0)
	assert_eq(rng.state, state, "no roll before wave 13, so earlier waves build the same spawns")
	for i in 200:
		assert_eq(director.roll_role(30, clanker, 100.0), clanker, "only small melee spawns become Spitters")
	assert_eq(director.roll_role(30, nibbler, 2.4), nibbler, "a Spitter needs the budget for one")
	director.free()


func test_spitters_appear_in_built_waves_from_wave_thirteen() -> void:
	var director := WaveDirector.new()
	director.curve = load(CURVE) as DifficultyCurve
	director.spitter_archetype = load(SPITTER) as RobotArchetype
	for path in [NIBBLER, CLANKER, THUMPER]:
		director.archetypes.append(load(path) as RobotArchetype)
	var seen := {}
	for wave in range(1, 32):
		director.set(&"_wave_rng", RngService.make_rng([41, wave]))
		var events: Array = director.call(&"_build_spawn_events", wave)
		for event: WaveDirector.SpawnEvent in events:
			if event.archetype.id == &"spitter":
				seen[wave] = true
				assert_gte(wave, 13, "no Spitters before wave 13")
				assert_true(event.robot_count() in [1, 3], "Spitters come solo or as a trio")
	assert_gt(seen.size(), 5, "Spitters show up in later waves")
	director.free()


func test_a_spitter_stands_off_shoots_and_hops_every_three_shots() -> void:
	var spitter := _robot(SPITTER, 13, Vector3(_silo.wall_point_toward(Vector3(1, 0, 0), 0.0).x + 14.0, 0.0, 0.0)) as SpitterRobot
	spitter.target_kind = Robot.TargetKind.SILO
	spitter.stand_distance = 14.0
	_run([spitter], STEP * 2)
	assert_eq(spitter.move, SpitterRobot.Move.SHOOT, "at its stand-off distance it stops to shoot")
	assert_eq(spitter.ranged.state, RangedAttack.State.CHARGING, "and charges a pea")
	assert_eq(spitter.ranged.target, _silo)
	var fired: Array[int] = [0]
	spitter.ranged.fired.connect(func() -> void: fired[0] += 1)
	var pool := ProjectilePool.of(spitter)
	var launched := pool.active_count()
	for i in roundi(6.0 / STEP):
		spitter._physics_process(STEP)
		if spitter.move == SpitterRobot.Move.HOP:
			break
	assert_eq(fired[0], 3, "three peas from one spot")
	assert_gt(pool.active_count(), launched, "peas are in the air")
	assert_eq(spitter.move, SpitterRobot.Move.HOP, "then it hops to a new spot")
	var center := Vector3(_silo.global_position.x, 0.0, _silo.global_position.z)
	var here := Vector3(spitter.global_position.x, 0.0, spitter.global_position.z) - center
	var there := Vector3(spitter._spot.x, 0.0, spitter._spot.z) - center
	assert_almost_eq(there.length(), here.length(), 0.05, "at the same distance")
	assert_almost_eq(rad_to_deg(here.angle_to(there)), spitter.hop_angle_degrees, 0.5, "around the silo")


func test_a_spitter_backs_off_once() -> void:
	var spitter := _robot(SPITTER, 13, Vector3(30.0, 0.0, 0.0)) as SpitterRobot
	var farmer := _farmer(Vector3(27.0, 0.0, 0.0))
	_run([spitter], STEP)
	assert_eq(spitter.move, SpitterRobot.Move.BACK_OFF, "a farmer within 5 m makes it back off")
	assert_almost_eq(spitter._spot.distance_to(Vector3(34.0, 0.0, 0.0)), 0.0, 0.01, "4 m straight away")
	_run([spitter], spitter.reposition_timeout + STEP)
	assert_ne(spitter.move, SpitterRobot.Move.BACK_OFF)
	_run([spitter], 1.0)
	assert_ne(spitter.move, SpitterRobot.Move.BACK_OFF, "only once: after that it holds its ground")
	assert_true(spitter.backed_off)
	farmer.queue_free()


func test_a_spitter_trio_fires_a_staggered_three_beat_volley() -> void:
	var squad := RobotSquad.new()
	var spitters: Array = []
	var wall_x := _silo.wall_point_toward(Vector3(1, 0, 0), 0.0).x
	for i in 3:
		var robot := _robot(SPITTER, 13, Vector3(wall_x + 14.0, 0.0, -2.0 + 2.0 * i), squad) as SpitterRobot
		robot.target_kind = Robot.TargetKind.SILO
		robot.stand_distance = 14.0
		spitters.append(robot)
	var first_shot: Array[float] = [-1.0, -1.0, -1.0]
	# Lambdas copy plain locals, so the clock lives in an array they share.
	var clock: Array[float] = [0.0]
	for i in 3:
		var index := i
		(spitters[i] as SpitterRobot).ranged.fired.connect(func() -> void:
			if first_shot[index] < 0.0:
				first_shot[index] = clock[0])
	for step in roundi(3.5 / STEP):
		clock[0] += STEP
		_run(spitters, STEP)
	var beat := (spitters[0] as SpitterRobot).ranged.profile.interval / 3.0
	assert_gt(first_shot[2], 0.0, "all three fire")
	assert_almost_eq(first_shot[1] - first_shot[0], beat, 0.05, "the second a beat after the leader")
	assert_almost_eq(first_shot[2] - first_shot[1], beat, 0.05, "the third a beat after that")


func test_a_spitter_can_shoot_a_farmer_up_high() -> void:
	var spitter := _robot(SPITTER, 13, Vector3(30.0, 0.0, 0.0)) as SpitterRobot
	var farmer := _farmer(Vector3(30.0, 9.0, 12.0))
	spitter.backed_off = true
	spitter.targeting.switch_to_farmer(farmer)
	spitter.stand_distance = 16.0
	_run([spitter], STEP * 2)
	assert_eq(spitter.ranged.target, farmer, "a farmer on a roof or in the air is in its sights")
	assert_true(spitter.targeting.on_farmer())


# --- Throws at an out-of-reach farmer --------------------------------------------------------------------

func test_a_clanker_throws_two_telegraphed_bolts_then_goes_back_to_the_silo() -> void:
	var clanker := _robot(CLANKER, 13, Vector3(20.0, 0.0, 0.0))
	var farmer := _farmer(Vector3(22.0, 5.0, 0.0))
	clanker.targeting.switch_to_farmer(farmer)
	var throw := clanker.get_node(^"Throw") as RangedAttack
	assert_eq(throw.profile.id, &"clanker_bolt")
	_run([clanker], Robot.THROW_DELAY - 0.1)
	assert_eq(throw.state, RangedAttack.State.READY, "a moment out of reach (a jump) draws no throw")
	_run([clanker], 0.2)
	assert_eq(throw.state, RangedAttack.State.CHARGING, "then it winds up a bolt")
	assert_not_null(throw.telegraph, "with a chalk circle where it lands")
	if throw.telegraph != null:
		assert_eq(throw.telegraph.kind, &"landing_circle")
	assert_true((clanker.get_node(^"Model/ThrowCharge") as Node3D).visible, "and the glow in its hand")
	_run([clanker], 3.6)
	assert_true(clanker.targeting.on_farmer(), "the give-up clock holds while it throws")
	_run([clanker], 3.0)
	assert_eq(clanker.throws_done(), 2, "two throws")
	assert_false(clanker.targeting.on_farmer(), "then back to the silo")
	assert_eq(clanker.targeting.last_return, RobotTargeting.Return.UNREACHABLE)
	_run([clanker], 4.0)
	assert_eq(clanker.throws_done(), 2, "and no more")


func test_a_thumper_lobs_clods_with_splash() -> void:
	var thumper := _robot(THUMPER, 13, Vector3(20.0, 0.0, 0.0))
	var farmer := _farmer(Vector3(24.0, 7.0, 0.0))
	thumper.targeting.switch_to_farmer(farmer)
	var throw := thumper.get_node(^"Throw") as RangedAttack
	assert_eq(throw.profile.id, &"thumper_clod")
	assert_eq(throw.profile.kind, AttackProfile.Kind.LOB, "a lob, so it never leads")
	assert_almost_eq(throw.profile.damage_vs_farmer, 15.0, 0.001)
	assert_almost_eq(throw.profile.splash_radius, 2.0, 0.001)
	var pool := ProjectilePool.of(thumper)
	var launched := pool.active_count()
	_run([thumper], Robot.THROW_DELAY + throw.profile.effective_charge_time(thumper.charge_multiplier) + 0.1)
	assert_gt(pool.active_count(), launched, "a clod is in the air")
	assert_eq(thumper.throws_done(), 1)


func test_throwing_starts_at_wave_thirteen() -> void:
	var clanker := _robot(CLANKER, 12, Vector3(20.0, 0.0, 0.0))
	assert_null(clanker.get_node_or_null(^"Throw"), "no throw in wave 12")
	var pouch := clanker.get_node(^"Model/Pose/Kit/bolt_pouch") as Node3D
	assert_false(pouch.visible, "and no bolt pouch to promise one")
	var farmer := _farmer(Vector3(22.0, 5.0, 0.0))
	clanker.targeting.switch_to_farmer(farmer)
	_run([clanker], clanker.archetype.give_up_time + 0.1)
	assert_false(clanker.targeting.on_farmer(), "it gives up as before")
	assert_true((_robot(CLANKER, 13, Vector3(-20.0, 0.0, 0.0)).get_node(^"Model/Pose/Kit/bolt_pouch") as Node3D).visible,
			"the pouch shows once it throws")


func test_no_free_token_means_no_throw() -> void:
	var clanker := _robot(CLANKER, 13, Vector3(20.0, 0.0, 0.0))
	var farmer := _farmer(Vector3(22.0, 5.0, 0.0))
	var throw := clanker.get_node(^"Throw") as RangedAttack
	var holders: Array[RefCounted] = []
	for i in throw.token_limit:
		holders.append(RefCounted.new())
		AttackTokens.acquire(farmer, holders[i], throw.token_limit)
	clanker.targeting.switch_to_farmer(farmer)
	_run([clanker], clanker.archetype.give_up_time + 0.1)
	assert_eq(clanker.throws_done(), 0, "it doesn't throw at the silo instead")
	assert_false(clanker.targeting.on_farmer(), "it gives up on the usual clock")


func test_a_hovering_farmer_is_neither_immune_nor_a_lure() -> void:
	var clanker := _robot(CLANKER, 13, Vector3(20.0, 0.0, 0.0))
	var eager := clanker.archetype.duplicate() as RobotArchetype
	eager.distractibility = 1.0
	eager.commit_time = 0.0
	clanker.archetype = eager
	clanker.targeting.archetype = eager
	var farmer := _farmer(Vector3(22.0, 5.0, 0.0))
	clanker.targeting.switch_to_farmer(farmer)
	_run([clanker], 6.6)
	assert_eq(clanker.throws_done(), 2, "not immune: it throws at the hovering farmer")
	assert_false(clanker.targeting.on_farmer())
	for i in 5:
		clanker.take_damage(DamagePacket.create(1.0, farmer, clanker.global_position))
		_run([clanker], 1.1)
	assert_false(clanker.targeting.on_farmer(), "not a lure: hits from out of reach don't pull it back")
	assert_eq(clanker.throws_done(), 2, "and it doesn't throw again")
	farmer.global_position = Vector3(22.0, 0.0, 0.0)
	_run([clanker], 0.1)
	clanker.take_damage(DamagePacket.create(1.0, farmer, clanker.global_position))
	assert_true(clanker.targeting.on_farmer(), "back on the ground, the farmer is fair game again")


# --- The Clanker's arm guard -----------------------------------------------------------------------------

func _hit_from(robot: Robot, offset: Vector3) -> float:
	var attacker := Node3D.new()
	_world.add_child(attacker)
	attacker.global_position = robot.global_position + offset
	var before := robot.health.current
	robot.take_damage(DamagePacket.create(10.0, attacker, robot.global_position + Vector3.UP))
	attacker.free()
	return before - robot.health.current


func test_the_clanker_arm_guard_halves_damage_from_the_front() -> void:
	var clanker := _robot(CLANKER, 13, Vector3(20.0, 0.0, 0.0))
	clanker.model.rotation.y = 0.0  # facing -Z
	assert_almost_eq(_hit_from(clanker, Vector3(0.0, 0.0, -5.0)), 5.0, 0.001, "-50% from straight ahead")
	assert_almost_eq(_hit_from(clanker, Vector3(2.0, 1.0, -5.0)), 5.0, 0.001, "and a little to the side")
	assert_almost_eq(_hit_from(clanker, Vector3(5.0, 0.0, 0.0)), 10.0, 0.001, "full damage from the flank")
	assert_almost_eq(_hit_from(clanker, Vector3(0.0, 0.0, 5.0)), 10.0, 0.001, "and from behind")
	clanker.model.rotation.y = PI * 0.5  # facing -X
	assert_almost_eq(_hit_from(clanker, Vector3(-5.0, 0.0, 0.0)), 5.0, 0.001, "the guard turns with it")
	assert_true((clanker.get_node(^"Model/Pose/Kit/arm_guard") as Node3D).visible, "the guard plate shows")


func test_the_arm_guard_waits_for_wave_thirteen_and_is_the_clankers_alone() -> void:
	var opening := _robot(CLANKER, 12, Vector3(20.0, 0.0, 0.0))
	opening.model.rotation.y = 0.0
	assert_almost_eq(_hit_from(opening, Vector3(0.0, 0.0, -5.0)), 10.0, 0.001, "until phase 5 it is the M1 Clanker")
	assert_false((opening.get_node(^"Model/Pose/Kit/arm_guard") as Node3D).visible, "with no plate")
	var nibbler := _robot(NIBBLER, 10, Vector3(-20.0, 0.0, 0.0))
	nibbler.model.rotation.y = 0.0
	assert_almost_eq(_hit_from(nibbler, Vector3(0.0, 0.0, -5.0)), 10.0, 0.001, "Nibblers have no guard")
