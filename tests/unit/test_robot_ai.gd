extends GutTest
## Robot AI on LimboAI behavior trees (M2-A3, GDD 9.6): every melee robot runs the melee tree, squads
## share a blackboard, Clankers land their first hits clank-clank-CLANK, followers keep formation only while
## the leader is far from the target, and a farmer perched out of reach is waited for at the foot of the
## perch, then given up on.

const ARCHETYPES := ["res://data/robots/archetypes/nibbler.tres", "res://data/robots/archetypes/clanker.tres",
		"res://data/robots/archetypes/thumper.tres"]
const NIBBLER := "res://data/robots/archetypes/nibbler.tres"
const CLANKER := "res://data/robots/archetypes/clanker.tres"
const MELEE_TREE := "res://data/robots/behaviors/melee.tres"
const FARM_NAVMESH_PATH := "res://scenes/farm/farm_navmesh.res"


## A stand-in farmer that logs which robot hit it on which physics frame.
class Dummy:
	extends Node3D

	var hits: Array[Array] = []

	func take_damage(packet: DamagePacket) -> void:
		hits.append([packet.source, Engine.get_physics_frames()])

	func is_alive() -> bool:
		return true

	## The physics frames on which `robot` hit.
	func hit_frames(robot: Node) -> Array[int]:
		var frames: Array[int] = []
		for hit in hits:
			if hit[0] == robot:
				frames.append(hit[1] as int)
		return frames


func test_every_melee_robot_runs_the_melee_tree(params: String = use_parameters(ARCHETYPES)) -> void:
	var world := _flat_world()
	var robot := _robot(load(params) as RobotArchetype, world, Vector3.ZERO)
	assert_eq(robot.bt_player.behavior_tree.resource_path, MELEE_TREE, "%s runs the melee tree" % robot.archetype.display_name)
	assert_eq(robot.bt_player.update_mode, BTPlayer.MANUAL, "ticked by the robot, in step with its body")
	var board := robot.bt_player.blackboard
	assert_true(board.has_var(&"target_perched") and board.has_var(&"perch_stand"), "the tree's blackboard plan is filled in")
	robot.target_kind = Robot.TargetKind.CHUTE
	assert_eq(board.get_var(&"target_kind"), Robot.TargetKind.CHUTE, "target_kind is bound: the property shows in the blackboard")
	board.set_var(&"target_kind", Robot.TargetKind.SILO)
	assert_eq(robot.target_kind, Robot.TargetKind.SILO, "and blackboard writes reach the property")
	assert_eq(board.get_var(&"squad_index"), robot.squad_index, "the debugger sees the body's squad slot")
	robot.ai_state = Robot.AiState.RECOVER
	assert_eq(board.get_var(&"ai_state"), Robot.AiState.RECOVER, "the debugger sees current action state")
	assert_null(board.get_parent(), "a robot outside a squad has no squad scope")


func test_squad_members_share_the_squad_blackboard() -> void:
	var world := _flat_world()
	var squad := RobotSquad.new()
	var robots := _squad(squad, world, [Vector3(0, 0, 0), Vector3(-3, 0, 3), Vector3(3, 0, 3)])
	for robot in robots:
		assert_eq(robot.bt_player.blackboard.get_parent(), squad.blackboard, "member %d's blackboard has the squad's as parent" % robot.squad_index)
	assert_eq(robots[2].bt_player.blackboard.get_var(&"squad_leader"), robots[0], "members read the leader from the squad scope")
	assert_eq(robots[1].bt_player.blackboard.get_var(&"squad_beats"), RobotSquad.BEATS, "and the rhythm")
	robots[0].kill()
	assert_eq(robots[2].bt_player.blackboard.get_var(&"squad_leader"), robots[1], "when the leader falls, the next member leads")


func test_a_clanker_squad_lands_its_first_hits_clank_clank_clank() -> void:
	var world := _flat_world()
	var dummy := Dummy.new()
	world.add_child(dummy)
	var squad := RobotSquad.new()
	# All three in reach of the farmer from the first tick, far enough apart that avoidance leaves them be.
	var spots: Array[Vector3] = []
	for i in 3:
		spots.append(Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 3.0) * 1.5)
	var robots := _squad(squad, world, spots, dummy)
	var start := Engine.get_physics_frames()
	await wait_physics_frames(200)
	var archetype := robots[0].archetype
	var beat := roundi(archetype.attack_interval / RobotSquad.BEATS * Engine.physics_ticks_per_second)
	var interval := roundi(archetype.attack_interval * Engine.physics_ticks_per_second)
	var first: Array[int] = []
	for robot in robots:
		var frames := dummy.hit_frames(robot)
		assert_gt(frames.size(), 1, "squad member %d hits twice in 200 frames" % robot.squad_index)
		if frames.size() < 2:
			return
		first.append(frames[0])
		# Later hits keep the member's place in the bar: one per interval (+1 frame to pick the next attack).
		assert_almost_eq(frames[1] - frames[0], interval, 2, "member %d hits again one interval later" % robot.squad_index)
	assert_almost_eq(first[0] - start, roundi(archetype.attack_windup * Engine.physics_ticks_per_second), 3,
			"the leader hits after one windup")
	assert_almost_eq(first[1] - first[0], beat, 1, "clank: member 1 lands one beat after the leader")
	assert_almost_eq(first[2] - first[1], beat, 1, "CLANK: member 2 lands one beat after member 1")


func test_followers_keep_formation_only_while_the_leader_is_far_from_the_target() -> void:
	var world := _flat_world()
	var dummy := Dummy.new()
	world.add_child(dummy)
	dummy.global_position = Vector3(3, 0, -4)
	var squad := RobotSquad.new()
	var robots := _squad(squad, world, [Vector3(3, 0, 16), Vector3(1, 0, 18), Vector3(5, 0, 18)], dummy)
	var leader := robots[0]
	var follower := robots[1]
	follower.set(&"_repath_timer", 0.0)
	await wait_physics_frames(2)
	var slot := leader.global_position + Basis(Vector3.UP, leader.model.rotation.y) \
			* RobotSquad.formation_offset(1, follower.type_scale())
	assert_almost_eq(follower.agent.target_position, slot, Vector3.ONE * 0.05,
			"with the leader 20 m from the target, the follower heads for its slot behind it")
	# The leader closes in: the follower breaks formation on the next tick (checked every tick, not only
	# when the formation branch starts).
	leader.global_position = Vector3(3, 0, 2)
	leader.reset_physics_interpolation()
	follower.set(&"_repath_timer", 0.0)
	await wait_physics_frames(2)
	assert_almost_eq(follower.agent.target_position, dummy.global_position, Vector3.ONE * 0.05,
			"with the leader within 8 m of the target, the follower makes for the target itself")


func test_perched_out_of_reach() -> void:
	assert_false(PerchQuery.is_perched(Vector3.ZERO, Vector3(0, 2.4, 0)), "2.4 m up is in reach")
	assert_true(PerchQuery.is_perched(Vector3.ZERO, Vector3(0, 2.6, 0)), "2.6 m up is perched")
	assert_true(PerchQuery.is_perched(Vector3(0, 0.2, 0), Vector3(3, 4.0, 1)), "the porch roof from the porch floor")
	assert_eq(PerchQuery.stand_spot(Vector3(3, 4, 1), 0.2), Vector3(3, 0.2, 1), "the stand spot is below the farmer, on the robot's level")


## Buildings narrower and wider than they are tall: on the wide one the nearest navmesh below the farmer is
## the roof, which robots can't reach.
func test_robots_wait_at_the_foot_of_a_perch_then_give_up(params: Array = use_parameters([
		[Vector3(10, 5, 10), Vector3(1, 5, 2), Vector3(-9, 0, 9)],
		[Vector3(24, 3, 24), Vector3(0, 3, 0), Vector3(-15, 0, 8)]])) -> void:
	var size: Vector3 = params[0]
	var perch: Vector3 = params[1]
	var start: Vector3 = params[2]
	var nav := NavigationRegion3D.new()
	add_child_autofree(nav)
	_box(nav, Vector3(60, 1, 60), Vector3(0, -0.5, 0))
	_box(nav, size, Vector3(0, size.y / 2.0, 0))
	nav.navigation_mesh = (load(FARM_NAVMESH_PATH) as NavigationMesh).duplicate() as NavigationMesh
	nav.bake_navigation_mesh(false)
	await wait_physics_frames(2)
	var dummy := Dummy.new()
	nav.add_child(dummy)
	dummy.global_position = perch
	var robot := _robot(load(NIBBLER) as RobotArchetype, nav, start, dummy)
	# The give-up clock starts on the first tick; look just before it runs out.
	var give_up := robot.archetype.give_up_time
	await wait_physics_frames(roundi((give_up - 0.2) * Engine.physics_ticks_per_second))
	var board := robot.bt_player.blackboard
	assert_true(board.get_var(&"target_perched"), "the farmer %.0f m up is perched" % perch.y)
	assert_eq(robot.target_kind, Robot.TargetKind.PLAYER, "still after the farmer before %.1f s" % give_up)
	assert_lt(robot.global_position.y, 0.5, "the robot stays on the ground")
	# The foot of the perch: just outside the wall nearest the farmer.
	var wall_gap := minf(absf(absf(robot.global_position.x) - size.x / 2.0),
			absf(absf(robot.global_position.z) - size.z / 2.0))
	var flat := Vector2(robot.global_position.x - perch.x, robot.global_position.z - perch.z).length()
	assert_lt(wall_gap, 1.5, "it reaches the foot of a wall instead of targeting the isolated roof")
	assert_lt(flat, Vector2(start.x - perch.x, start.z - perch.z).length(), "it approaches the perch")
	assert_lt(Vector2(robot.velocity.x, robot.velocity.z).length(), 0.5, "and stands there")
	await wait_physics_frames(roundi(0.4 * Engine.physics_ticks_per_second))
	assert_eq(robot.target_kind, Robot.TargetKind.SILO, "it gives up after %.1f s and goes back to the silo" % give_up)
	assert_false(board.get_var(&"target_perched"), "and stops waiting")


## Boss-specific timing and vent hooks must survive replacing the base melee decision loop.
func test_authored_foreman_keeps_its_telegraph_and_punish_window() -> void:
	var world := _flat_world()
	var dummy := Dummy.new()
	world.add_child(dummy)
	dummy.position = Vector3(0.0, 0.0, -1.5)
	var archetype := (load(ARCHETYPES[2]) as RobotArchetype).duplicate() as RobotArchetype
	# Shockwaves require a gameplay current_scene; the real-farm smoke test covers them.
	archetype.shockwave_damage = 0.0
	var robot := archetype.scene.instantiate() as HeavyRobot
	robot.setup(archetype, 3, DifficultyCurve.new(), RngService.make_rng([7]), null, true)
	robot.authored = true
	world.add_child(robot)
	robot.set_physics_process(false)
	robot.target_player = dummy
	robot.target_kind = Robot.TargetKind.PLAYER
	robot._ai_step(0.01)
	assert_eq(robot.ai_state, Robot.AiState.WINDUP)
	robot._ai_step(HeavyRobot.AUTHORED_WINDUP - 0.01)
	assert_eq(dummy.hits.size(), 0, "no hit before the authored telegraph finishes")
	robot._ai_step(0.02)
	assert_eq(dummy.hits.size(), 1, "one slam after the full telegraph")
	assert_true(robot.vent_open(), "the recovery hook opens the weak point")
	robot._ai_step(HeavyRobot.AUTHORED_RECOVERY - 0.01)
	assert_true(robot.vent_open(), "the full authored punish window remains")
	robot._ai_step(0.02)
	assert_false(robot.vent_open(), "the window closes when recovery ends")


## Tree tasks hold no private attack timers that could resume an interrupted windup after a spring.
func test_launch_interrupts_a_windup_and_recovery_starts_a_fresh_attack() -> void:
	var world := _flat_world()
	var dummy := Dummy.new()
	world.add_child(dummy)
	dummy.position = Vector3(0.0, 0.0, -1.0)
	var robot := _robot(load(NIBBLER) as RobotArchetype, world, Vector3.ZERO, dummy)
	robot.set_physics_process(false)
	robot._ai_step(0.01)
	assert_eq(robot.ai_state, Robot.AiState.WINDUP)
	assert_true(robot.launch(Vector3(0.0, 5.0, 0.0), null))
	robot._ai_step(1.0)
	assert_eq(dummy.hits.size(), 0, "a launched robot cannot complete its old attack")
	robot._land_from_launch()
	robot._process_launch(Robot.LAUNCH_RECOVERY + 0.01)
	robot._ai_step(0.01)
	assert_eq(robot.ai_state, Robot.AiState.WINDUP, "after getting up it starts a fresh telegraph")
	assert_almost_eq(robot._attack_timer, robot.windup_time(), 0.001)
	robot._ai_step(robot.windup_time() + 0.01)
	assert_eq(dummy.hits.size(), 1, "only the fresh attack lands")


# --- Helpers --------------------------------------------------------------------------------------

## Ground to stand on, no navmesh.
func _flat_world() -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	_box(world, Vector3(80, 1, 80), Vector3(0, -0.5, 0))
	return world


## A robot spawned through its current scene and setup API, chasing `target` if given.
func _robot(archetype: RobotArchetype, parent: Node3D, at: Vector3, target: Node3D = null,
		squad: RobotSquad = null) -> Robot:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, 1, DifficultyCurve.new(), rng, null, false, [], squad, &"calm")
	robot.position = at
	parent.add_child(robot)
	robot.reset_physics_interpolation()
	if target != null:
		robot.target_player = target
		robot.targeting.switch_to_farmer(target)
		robot.target_kind = Robot.TargetKind.PLAYER
	return robot


func _squad(squad: RobotSquad, parent: Node3D, spots: Array, target: Node3D = null) -> Array[Robot]:
	var robots: Array[Robot] = []
	for spot: Vector3 in spots:
		robots.append(_robot(load(CLANKER) as RobotArchetype, parent, spot, target, squad))
	return robots


func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = center
