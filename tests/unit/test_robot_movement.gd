extends GutTest
## Robot movement against farm geometry (regression for M2-A0).
##
## Robots used to stop dead at building corners, most often the Stables' south-west corner: a robot stuck
## for 2 s or more showed up on about a third of all smoke-test seeds. A robot steers for its next waypoint
## as soon as it is within path_desired_distance (about 1 m) of the corner waypoint, so it heads at a point
## behind the corner, and its capsule (Clanker 0.6 m) is wider than the navmesh's 0.5 m clearance. It meets
## the wall a few degrees off head-on, and under CharacterBody3D.wall_min_slide_angle (15° by default)
## move_and_slide() stops instead of sliding. Each case rebuilds that corner and steers like the agent.

const ARCHETYPES := ["res://data/robots/archetypes/nibbler.tres", "res://data/robots/archetypes/clanker.tres",
		"res://data/robots/archetypes/thumper.tres"]
## The corner's next waypoint from the smoke-test trace (seed 2), relative to the corner: past it, along
## the west wall. From the start spot below, steering at it means hitting the south wall ~12° off head-on.
const WAYPOINT := Vector3(-1.7, 0.0, 8.2)


func test_robots_slide_round_a_building_corner_they_clip(params: String = use_parameters(ARCHETYPES)) -> void:
	var world := Node3D.new()
	add_child_autofree(world)
	_box(world, Vector3(40.0, 1.0, 40.0), Vector3(0.0, -0.5, 0.0))
	# A building whose south-west corner is at the origin: south wall along z = 0, west wall along x = 0.
	_box(world, Vector3(28.0, 6.0, 8.0), Vector3(14.0, 3.0, 4.0))

	var archetype := load(params) as RobotArchetype
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, 1, DifficultyCurve.new(), RandomNumberGenerator.new())
	world.add_child(robot)
	# Drive it by hand: no navmesh or avoidance here, and RECOVER keeps the state machine from steering.
	robot.agent.avoidance_enabled = false
	robot.ai_state = Robot.AiState.RECOVER
	robot.set(&"_attack_timer", 999.0)
	var radius := ((robot.get_node(^"CollisionShape3D") as CollisionShape3D).shape as CapsuleShape3D).radius
	robot.global_position = Vector3(0.19, 0.0, -radius - 0.02)
	robot.reset_physics_interpolation()

	for i in 120:
		await wait_physics_frames(1)
		var to_waypoint := WAYPOINT - robot.global_position
		to_waypoint.y = 0.0
		robot.call(&"_on_velocity_computed", to_waypoint.normalized() * robot.move_speed())
	assert_gt(robot.global_position.z, 1.0,
			"a %s slides round the corner instead of stopping at the wall (now at %s)" % [archetype.display_name, robot.global_position])


func _box(parent: Node3D, size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = center
