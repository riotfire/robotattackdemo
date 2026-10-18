extends GutTest
## Robot movement against farm geometry (regression for M2-A0).
##
## Robots used to stop dead at building corners, most often the Stables' south-west corner: a robot stuck
## for 2 s or more showed up on about a third of all smoke-test seeds. A robot steers for its next waypoint
## as soon as it is within path_desired_distance (about 1 m) of the corner waypoint, so it heads at a point
## behind the corner, and its capsule (Clanker 0.6 m) is wider than the navmesh's 0.5 m clearance. It meets
## the wall a few degrees off head-on, and under CharacterBody3D.wall_min_slide_angle (15° by default)
## move_and_slide() stops instead of sliding. Each case rebuilds that corner and steers like the agent.
##
## Robots also got pinned for good against the Home porch (3 of 102 seeds). Its floor is 0.2 m tall and the
## navmesh was baked with agent_max_climb 0.25, so paths ran straight over it, but a capsule of radius r on
## a 45° floor_max_angle only steps about r * (1 - cos 45°): 0.10 m for a Nibbler, 0.18 m for a Clanker and
## 0.24 m for a Thumper. Head-on, sliding doesn't help. The porch test rebuilds the porch, bakes it with the
## farm navmesh's settings and walks each robot along the agent's path.

const ARCHETYPES := ["res://data/robots/archetypes/nibbler.tres", "res://data/robots/archetypes/clanker.tres",
		"res://data/robots/archetypes/thumper.tres"]
## The corner's next waypoint from the smoke-test trace (seed 2), relative to the corner: past it, along
## the west wall. From the start spot below, steering at it means hitting the south wall ~12° off head-on.
const WAYPOINT := Vector3(-1.7, 0.0, 8.2)
const FARM_NAVMESH_PATH := "res://scenes/farm/farm_navmesh.res"
## Start and goal of each porch route, in farm coordinates. The first two pass the places the stall probe
## found robots pinned: head-on into the porch floor's west end, and across the ramp's side where it is
## 0.12 m tall. The third climbs to a farmer on the porch, which must stay reachable up the ramp.
const PORCH_ROUTES: Array[Array] = [
	[Vector3(-38.5, 0.0, 28.0), Vector3(-21.5, 0.0, 28.0)],
	[Vector3(-34.0, 0.0, 31.3), Vector3(-26.0, 0.0, 31.3)],
	[Vector3(-38.5, 0.0, 28.0), Vector3(-34.0, 0.2, 28.75)],
]


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


func test_robots_follow_the_farm_navmesh_past_the_porch() -> void:
	# The Home porch as tools/build_graybox_farm.gd builds it: a 0.2 m floor along the house's south wall,
	# and a 3 m ramp down from the middle of its front edge.
	var nav := NavigationRegion3D.new()
	add_child_autofree(nav)
	_box(nav, Vector3(60.0, 1.0, 60.0), Vector3(-30.0, -0.5, 25.0))
	_box(nav, Vector3(14.0, 7.0, 10.0), Vector3(-30.0, 3.5, 22.0))
	_box(nav, Vector3(14.0, 0.2, 3.5), Vector3(-30.0, 0.1, 28.75))
	_box(nav, Vector3(3.0, 0.2, 2.02), Vector3(-30.0, 0.0, 31.49), atan2(0.2, 2.0))
	# Bake a copy with the farm's settings, as PropScatter does at run start.
	nav.navigation_mesh = (load(FARM_NAVMESH_PATH) as NavigationMesh).duplicate() as NavigationMesh
	nav.bake_navigation_mesh(false)
	await wait_physics_frames(2)

	# Robots only collide with the world, so every type walks every route at once.
	var robots: Array[Robot] = []
	var routes: Array[Array] = []
	for path: String in ARCHETYPES:
		var archetype := load(path) as RobotArchetype
		for route in PORCH_ROUTES:
			var robot := archetype.scene.instantiate() as Robot
			robot.setup(archetype, 1, DifficultyCurve.new(), RandomNumberGenerator.new())
			nav.add_child(robot)
			# Steer by hand as in the corner test, but along the agent's path.
			robot.agent.avoidance_enabled = false
			robot.ai_state = Robot.AiState.RECOVER
			robot.set(&"_attack_timer", 999.0)
			robot.global_position = route[0]
			robot.reset_physics_interpolation()
			robot.agent.target_position = route[1]
			robots.append(robot)
			routes.append(route)

	# Long enough for a Thumper to walk round the porch (about 500 frames); a pinned robot never arrives.
	for i in 900:
		await get_tree().physics_frame
		var walking := false
		for robot in robots:
			if robot.agent.is_navigation_finished():
				continue
			walking = true
			var to_next := robot.agent.get_next_path_position() - robot.global_position
			to_next.y = 0.0
			robot.call(&"_on_velocity_computed", to_next.normalized() * robot.move_speed())
		if not walking:
			break
	for r in robots.size():
		var robot := robots[r]
		var goal: Vector3 = routes[r][1]
		# The agent finishes within path_desired_distance of its last waypoint (1.68 m for a Thumper).
		assert_lt(Vector2(goal.x - robot.global_position.x, goal.z - robot.global_position.z).length(),
				robot.agent.path_desired_distance + 0.25, "a %s walks from %s round the porch to %s (stopped at %s)" % [
				robot.archetype.display_name, routes[r][0], goal, robot.global_position])


## A box collider. `tilt` turns it about X; positive tilt drops its +Z end, like the farm tool's ramps.
func _box(parent: Node3D, size: Vector3, center: Vector3, tilt: float = 0.0) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_transform = Transform3D(Basis(Vector3.RIGHT, tilt), center)
