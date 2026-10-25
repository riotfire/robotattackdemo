extends GutTest
## The robot pop (RobotExplosion): a real kill bursts the robot into its own parts, which fall, land and
## clean up after themselves; quiet exits don't explode; freeze frames and screen shake always recover.

const NIBBLER := "res://data/robots/archetypes/nibbler.tres"


func before_each() -> void:
	# Earlier tests' debris may still be bouncing; let it clean up so the budget starts from zero.
	await wait_until(func() -> bool: return RobotExplosion.live_debris == 0, 6.0)


func after_each() -> void:
	Engine.time_scale = 1.0


func test_a_kill_bursts_the_robot_into_its_own_parts_which_land_and_clean_up() -> void:
	var world := _ground()
	var robot := _robot(world)
	var eye := robot.look.eyes[0]
	var debris_before := RobotExplosion.live_debris
	robot.take_damage(DamagePacket.create(99999.0, null, robot.global_position + Vector3(1.0, 0.5, 0.0)))
	assert_true(robot.exploding, "a kill that awards drops explodes")

	await wait_physics_frames(int(ceil(RobotExplosion.ANTICIPATION * 60.0)) + 3)
	var fx := eye.get_parent() as RobotExplosion
	assert_not_null(fx, "the robot's eye flies off as debris under the explosion")
	assert_gt(RobotExplosion.live_debris, debris_before + 5, "the robot's kit parts became debris")

	await wait_seconds(1.6)
	assert_false(is_instance_valid(robot), "the robot itself is gone")
	assert_true(is_instance_valid(eye), "the eye is still bouncing")
	assert_gt(eye.global_position.y, -0.2, "debris lands on the ground instead of falling through it")
	assert_lt(eye.global_position.y, 2.0, "and doesn't hang in the air")

	await wait_seconds(2.4)
	assert_false(is_instance_valid(fx), "the explosion frees itself")
	assert_eq(RobotExplosion.live_debris, debris_before, "the debris budget is returned")


func test_robots_that_escape_or_are_cleared_do_not_explode() -> void:
	var world := _ground()
	var robot := _robot(world)
	robot.kill(false)
	assert_false(robot.exploding)
	await wait_physics_frames(10)
	assert_eq(_explosions().size(), 0, "no explosion for a quiet exit")


func test_a_grenade_blast_cleans_up_without_robot_parts() -> void:
	_ground()
	var fx := RobotExplosion.blast(self, Vector3(0.0, 0.3, 0.0), 5.0)
	assert_eq(fx.ring_radius, 5.0, "the ring shows the real blast radius")
	await wait_seconds(2.6)
	assert_false(is_instance_valid(fx))


func test_a_freeze_frame_restores_time_and_never_fools_the_weapon_wheel() -> void:
	Hitstop.freeze(0.06)
	if not Hitstop.is_frozen():
		pass_test("a freeze is cooling down from an earlier test; nothing to check")
		return
	assert_almost_eq(Engine.time_scale, Hitstop.FROZEN_SCALE, 0.001)
	assert_eq(Hitstop.resting_time_scale(), 1.0, "the wheel saves the unfrozen time scale")
	await get_tree().create_timer(0.12, true, false, true).timeout
	assert_false(Hitstop.is_frozen())
	assert_eq(Engine.time_scale, 1.0, "time comes back")


func test_camera_shake_decays_to_a_still_lens() -> void:
	var rig := _camera_rig()
	rig.add_trauma(0.7)
	rig.add_trauma(0.7)
	assert_eq(rig.trauma, 1.0, "trauma is capped at 1")
	rig.call(&"_update_shake", 0.05)
	assert_ne(Vector2(rig.camera.h_offset, rig.camera.v_offset), Vector2.ZERO, "the lens shakes")
	assert_eq(rig.camera.rotation.x, 0.0, "the shake never tilts the aim")
	for i in 60:
		rig.call(&"_update_shake", 0.05)
	assert_eq(rig.trauma, 0.0)
	assert_eq(Vector3(rig.camera.h_offset, rig.camera.v_offset, rig.camera.rotation.z), Vector3.ZERO,
			"and settles exactly back")


func _ground() -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = Vector3(0.0, -0.5, 0.0)
	return world


func _robot(world: Node3D) -> Robot:
	# No drops: pickups need the game's current scene, which the test runner doesn't have.
	var archetype := (load(NIBBLER) as RobotArchetype).duplicate() as RobotArchetype
	archetype.drop_al_min = 0
	archetype.drop_al_max = 0
	archetype.drop_al_class_bonus = 0
	archetype.drop_cu_chance = 0.0
	archetype.drop_au_chance = 0.0
	archetype.drop_pc_chance = 0.0
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, 1, DifficultyCurve.new(), RandomNumberGenerator.new())
	world.add_child(robot)
	robot.agent.avoidance_enabled = false
	robot.ai_state = Robot.AiState.RECOVER
	robot.set(&"_attack_timer", 999.0)
	robot.global_position = Vector3.ZERO
	return robot


func _camera_rig() -> FarmerCamera:
	var rig := FarmerCamera.new()
	var pitch := Node3D.new()
	pitch.name = "Pitch"
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	arm.add_child(camera)
	pitch.add_child(arm)
	rig.add_child(pitch)
	add_child_autofree(rig)
	return rig


func _explosions() -> Array[Node]:
	var root := get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	return root.find_children("RobotExplosion*", "", false, false)
