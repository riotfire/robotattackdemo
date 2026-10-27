extends GutTest
## The Rung Runner (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md slice 2) on the real silo scene: it
## climbs the silo ladder, walks the first catwalk and bashes the silo there so its cracks open on the
## catwalk; two climb at once and the rest wait beside the foot; a catwalk barricade turns it the other way
## (and two make it smash one); a catwalk decoy pulls it; a spring throws it off and the fall hurts.
## Robots run with physics off, so each test drives _physics_process frame by frame.

const RUNNER := "res://data/robots/archetypes/rung_runner.tres"
const THUMPER := "res://data/robots/archetypes/thumper.tres"
const CURVE := "res://data/difficulty/default_difficulty.tres"
const SILO_SCENE := "res://scenes/farm/silo.tscn"
const SPRING := "res://data/defenses/spring_trap.tres"
const DECOY := "res://data/defenses/scarecrow_decoy.tres"
const BARRICADE := "res://data/defenses/scrap_barricade.tres"
const STEP := 1.0 / 60.0

var _world: Node3D
var _silo: Silo
var _silo_before: Silo
var _hits: Array[Vector3] = []
var _scene_before: Node = null


func before_each() -> void:
	_silo_before = GameState.silo
	_scene_before = get_tree().current_scene
	_world = Node3D.new()
	add_child_autofree(_world)
	get_tree().current_scene = _world
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
	_hits.clear()
	EventBus.silo_damaged.connect(_on_silo_damaged)


func after_each() -> void:
	EventBus.silo_damaged.disconnect(_on_silo_damaged)
	GameState.silo = _silo_before
	get_tree().current_scene = _scene_before


func _on_silo_damaged(_amount: float, at: Vector3) -> void:
	_hits.append(at)


func _runner(seed_value: int = 1) -> LadderRobot:
	var archetype := load(RUNNER) as RobotArchetype
	var robot := archetype.scene.instantiate() as LadderRobot
	robot.setup(archetype, 5, load(CURVE) as DifficultyCurve, RngService.make_rng([seed_value]))
	_world.add_child(robot)
	robot.global_position = robot._foot() + Vector3.UP * 0.05
	robot.set_physics_process(false)
	return robot


func _run(robots: Array, seconds: float, stop: Callable = Callable()) -> float:
	var steps := roundi(seconds / STEP)
	for i in steps:
		for robot: Robot in robots:
			if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
				robot._physics_process(STEP)
		if stop.is_valid() and stop.call():
			return i * STEP
	return -1.0


func _catwalk_site(id: StringName, degrees: float) -> DefenseSite:
	var ladder := _silo.get_node(^"Ladder") as Climbable
	var toward := ladder.global_position - _silo.global_position
	var angle := atan2(toward.x, toward.z) + deg_to_rad(degrees)
	var out := Vector3(sin(angle), 0.0, cos(angle))
	var site := DefenseSite.new()
	site.setup(null, id, &"catwalk", out)
	site.catwalk_angle = angle
	_world.add_child(site)
	site.global_position = _silo.global_position + out * LadderRobot.CATWALK_RADIUS + Vector3.UP * ladder.landings[0]
	return site


func _defense(path: String, site: DefenseSite, placed_by: Node = null) -> Defense:
	var definition := load(path) as DefenseDefinition
	var defense: Defense
	match definition.kind:
		DefenseDefinition.Kind.SPRING_TRAP:
			defense = SpringTrap.new()
		DefenseDefinition.Kind.DECOY:
			defense = ScarecrowDecoy.new()
		_:
			defense = ScrapBarricade.new()
	defense.setup(definition, site, placed_by)
	defense.active = true
	site.occupant = defense
	_world.add_child(defense)
	defense.global_position = site.global_position
	return defense


func _relative_angle(robot: LadderRobot) -> float:
	var ladder := _silo.get_node(^"Ladder") as Climbable
	var toward := ladder.global_position - _silo.global_position
	return angle_difference(atan2(toward.x, toward.z), robot._angle)


func test_the_rung_runner_matches_the_plan() -> void:
	var archetype := load(RUNNER) as RobotArchetype
	assert_eq(archetype.robot_type, RobotArchetype.RobotType.SCOUT, "a clearly marked light robot")
	assert_eq(archetype.robot_class, RobotArchetype.RobotClass.MELEE, "it bashes the silo up close, at catwalk height")
	assert_true(&"climb_hooks" in archetype.tells, "its climbing hooks read from the ground")
	assert_eq(archetype.silo_focus, 1.0, "it always goes for the ladder")
	assert_eq(archetype.trio_chance, 0.0, "always alone on the ladder")
	assert_almost_eq(archetype.threat_cost(), 2.0, 0.001)


func test_it_climbs_the_ladder_and_bashes_the_silo_at_catwalk_height() -> void:
	var robot := _runner()
	robot._start_climb()
	assert_eq(robot.travel, LadderRobot.Travel.CLIMB)
	var t := _run([robot], 8.0, func() -> bool: return robot.travel == LadderRobot.Travel.CATWALK)
	assert_gt(t, 3.0, "it climbs slower than the farmer (8 m at 2.2 m/s)")
	assert_almost_eq(robot.global_position.y - _silo.global_position.y, 8.05, 0.1, "it steps onto the first catwalk")
	_run([robot], 12.0, func() -> bool: return not _hits.is_empty())
	assert_false(robot.is_thief, "it never steals: its job is the ladder")
	assert_false(_hits.is_empty(), "it hits the silo up there")
	if not _hits.is_empty():
		assert_eq(_silo.hit_band(_hits[0]), 1, "at catwalk height, so cracks open on the catwalk")
	assert_almost_eq(absf(_relative_angle(robot)), LadderRobot.ATTACK_ANGLE, 0.1, "beside a catwalk crack socket")


func test_two_climb_at_once_and_the_rest_wait_beside_the_foot() -> void:
	var a := _runner(1)
	var b := _runner(2)
	var c := _runner(3)
	a._start_climb()
	_run([a], 1.5)
	assert_true(b._ladder_has_room(), "a second may follow once the first is a gap up")
	b._start_climb()
	assert_false(c._ladder_has_room(), "no third on the ladder")
	c.travel = LadderRobot.Travel.QUEUE
	var wait := c._wait_spot()
	assert_gt(Vector2(wait.x - c._foot().x, wait.z - c._foot().z).length(), 2.0, "it waits beside the foot, not on it")


func test_a_catwalk_barricade_turns_it_the_other_way() -> void:
	var robot := _runner()
	robot._start_climb()
	_run([robot], 8.0, func() -> bool: return robot.travel == LadderRobot.Travel.CATWALK)
	# Block the side it was heading for, then let it choose again.
	var heading := signf(angle_difference(robot._angle, robot._goal_angle))
	var blocked := _catwalk_site(&"block", 28.0 * heading)
	var first := _defense(BARRICADE, blocked) as ScrapBarricade
	robot._pick_side()
	assert_eq(signf(angle_difference(robot._angle, robot._goal_angle)), -heading, "it takes the other way round")
	var other := _catwalk_site(&"other", -28.0 * heading)
	var second := _defense(BARRICADE, other) as ScrapBarricade
	robot._pick_side()
	var smashed := func() -> bool: return first.hp < first.max_hp or second.hp < second.max_hp
	_run([robot], 6.0, smashed)
	assert_true(smashed.call(), "with both ways shut it smashes a barricade")
	assert_true(_hits.is_empty(), "instead of the silo")


func test_a_catwalk_decoy_pulls_it_and_a_spring_on_the_way_throws_it() -> void:
	var robot := _runner()
	robot._start_climb()
	_run([robot], 8.0, func() -> bool: return robot.travel == LadderRobot.Travel.CATWALK)
	var decoy_site := _catwalk_site(&"decoy", 60.0)
	var decoy := _defense(DECOY, decoy_site) as ScarecrowDecoy
	var spring_site := _catwalk_site(&"spring", 30.0)
	var owner_node := Node.new()
	add_child_autofree(owner_node)
	_defense(SPRING, spring_site, owner_node)
	var springs: Array = [spring_site.occupant]
	var flew := [false]
	var watch := func() -> bool:
		for spring: SpringTrap in springs:
			spring._physics_process(STEP)
		flew[0] = flew[0] or robot.ai_state == Robot.AiState.LAUNCHED
		return flew[0]
	_run([robot], 6.0, watch)
	assert_true(robot.target_defense == decoy or flew[0], "the decoy pulls it along the catwalk")
	assert_true(flew[0], "and the spring on the way throws it off")
	assert_eq(robot.launched_by, owner_node, "the throw remembers who placed the trap")


func test_a_spring_never_throws_a_heavy_but_takes_its_stomp() -> void:
	var archetype := load(THUMPER) as RobotArchetype
	var heavy := archetype.scene.instantiate() as Robot
	heavy.setup(archetype, 8, load(CURVE) as DifficultyCurve, RngService.make_rng([1]))
	_world.add_child(heavy)
	heavy.set_physics_process(false)
	var site := DefenseSite.new()
	site.setup(null, &"gate", &"ground", Vector3.FORWARD)
	_world.add_child(site)
	var spring := _defense(SPRING, site) as SpringTrap
	heavy.global_position = spring.global_position
	assert_false(heavy.launchable(), "large robots are too heavy to throw")
	assert_false(spring.fire(heavy), "it doesn't fly")
	assert_lt(spring.hp, spring.max_hp, "it stomps the spring instead")
	assert_false(spring.is_ready(), "and the spring resets")


func test_fall_damage_is_capped_and_a_short_hop_is_free() -> void:
	assert_eq(Robot.fall_damage(1.5), 0.0, "a ground throw mostly delays")
	assert_gt(Robot.fall_damage(6.0), 20.0)
	assert_eq(Robot.fall_damage(40.0), Robot.FALL_DAMAGE_CAP, "a long fall is capped")


func test_a_fatal_landing_is_one_kill_for_the_trap_owner() -> void:
	var robot := _runner()
	var owner_node := Node.new()
	add_child_autofree(owner_node)
	var kills: Array[Node] = []
	var on_destroyed := func(_robot: Node3D, killer: Node) -> void: kills.append(killer)
	EventBus.robot_destroyed.connect(on_destroyed)
	robot.global_position = _silo.global_position + Vector3(0.0, 11.0, 8.0)
	robot.health.current = 10.0
	assert_true(robot.launch(Vector3(0.0, 2.0, 3.0), owner_node))
	_run([robot], 4.0, func() -> bool: return robot.ai_state == Robot.AiState.DEAD)
	EventBus.robot_destroyed.disconnect(on_destroyed)
	assert_eq(kills, [owner_node], "credited to the owner, exactly once")


func test_loot_never_lands_outside_the_farm() -> void:
	var robot := _runner()
	var far := robot.safe_drop_point(Vector3(150.0, -3.0, 0.0))
	assert_lte(Vector2(far.x, far.z).length(), 96.5, "pulled back inside the corn")
	assert_gte(far.y, _silo.global_position.y, "and never under the farm")
