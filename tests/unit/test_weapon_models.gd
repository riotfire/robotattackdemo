extends GutTest
## The textured weapons and jetpack on the farmer: what they are built from, how they ride the rig, and how they move.

const FARMER_SCENE := "res://scenes/player/farmer.tscn"

var _saved_levels: Dictionary = {}


func before_each() -> void:
	_saved_levels = StatService.levels.duplicate()
	StatService.set_levels({})


func after_each() -> void:
	StatService.set_levels(_saved_levels)


func test_the_modelled_weapons_use_their_glbs_and_muzzles_sit_at_the_barrel_end() -> void:
	var farmer := _farmer()
	var holder := farmer.weapons
	for entry: Array in [["Wrench/Pivot/Body", "Wrench"], ["Pistol/Body", "Pistol"], ["Shotgun/Body", "Shotgun"],
			["Scythe/Pivot/Body", "Scyth"]]:
		assert_eq(holder.get_node(entry[0]).scene_file_path, "res://assets/%s.glb" % entry[1])
	for gun: String in ["Pistol", "Shotgun"]:
		var body: Node3D = holder.get_node("%s/Body" % gun)
		var mesh := body.get_child(0) as MeshInstance3D
		var far_end := (body.transform * mesh.transform * mesh.get_aabb()).position.z
		var muzzle: Node3D = holder.get_node("%s/Muzzle" % gun)
		assert_almost_eq(muzzle.position.z, far_end, 0.05, "%s muzzle is at the barrel end" % gun)
		assert_lt(body.position.z, 0.0, "%s model reaches forward of the grip" % gun)


func test_weapons_ride_the_hand_and_the_jetpack_rides_the_chest() -> void:
	var farmer := _farmer()
	var mabel := _mabel(farmer)
	var skeleton := mabel._skeleton
	for clip: StringName in [&"Idle_3", &"Dead"]:
		mabel._play(clip, 1.0)
		for i in 12:
			mabel.step_pose(farmer)
		var hand := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(MabelModel.HAND))
		assert_lt(farmer.weapons.global_position.distance_to(hand.origin), 0.15, "%s: weapon in hand" % clip)
		var chest := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(MabelModel.CHEST))
		assert_lt(farmer.jetpack_model.global_position.distance_to(chest.origin), 0.4, "%s: pack on chest" % clip)


func test_an_aimed_pistol_points_straight_ahead_in_the_stance() -> void:
	StatService.grant(&"attack.pistol")
	var farmer := _farmer()
	var mabel := _mabel(farmer)
	farmer.weapons.equip(farmer.weapons.get_weapon(&"pistol"))
	farmer.is_aiming = true
	for i in 6:
		mabel.step_pose(farmer)
	assert_eq(mabel._current, &"Aim_Idle")
	assert_true(farmer.weapons.current.pistol_stance)
	var barrel := -farmer.weapons.basis.z
	assert_gt(barrel.dot(Vector3.FORWARD), 0.99, "barrel forward, got %s" % barrel)


func test_firing_kicks_the_gun_model() -> void:
	StatService.grant(&"attack.pistol")
	var farmer := _farmer()
	var pistol := farmer.weapons.get_weapon(&"pistol") as Pistol
	var rest: Transform3D = pistol.get_node("Body").transform
	pistol.kick()
	assert_false((pistol.get_node("Body") as Node3D).transform.is_equal_approx(rest), "the model jumps back")
	pistol.kick()
	assert_true(pistol._body_rest.is_equal_approx(rest), "a second kick returns to the same rest")


func test_the_scythe_whirls_her_all_the_way_round_and_stands_her_back() -> void:
	StatService.grant(&"attack.scythe")
	var farmer := _farmer()
	var mabel := _mabel(farmer)
	var scythe := farmer.weapons.get_weapon(&"scythe") as SweepWeapon
	farmer.weapons.equip(scythe)
	assert_true(scythe.attack())
	var pose: Node3D = mabel.get_parent()
	var highest := 0.0
	for i in int(ceil(MabelModel.SPIN_TIME / MabelModel.TICK)) + 1:
		mabel.step_pose(farmer)
		highest = maxf(highest, pose.rotation.y)
		if i == 2:
			assert_lt(absf(farmer.weapons.basis.z.y), 0.2, "the pole is held out level, not upright")
	assert_gt(highest, TAU * 0.85, "she turned nearly the full circle before the last step")
	assert_eq(pose.rotation.y, 0.0, "she ends facing where she started")


func test_a_quick_bonk_puts_the_gun_away_for_the_swing() -> void:
	StatService.grant(&"attack.pistol")
	var farmer := _farmer()
	var pistol := farmer.weapons.get_weapon(&"pistol")
	var wrench := farmer.weapons.get_weapon(&"wrench") as Wrench
	farmer.weapons.equip(pistol)
	assert_true(wrench.swing())
	assert_true(wrench.visible)
	assert_false(pistol.visible)
	wrench._end_swing()
	assert_false(wrench.visible)
	assert_true(pistol.visible)


func test_the_flames_burn_only_while_thrusting_and_thrust_holds_the_flight_pose() -> void:
	var farmer := _farmer()
	var mabel := _mabel(farmer)
	var flames: Node3D = farmer.jetpack_model.get_node("Pack/Flames")
	farmer.jetpack_model.step(true, 1.0)
	assert_true(flames.visible)
	farmer.jetpack_model.step(false, 1.0)
	assert_false(flames.visible)
	farmer.state = Farmer.State.JETPACKING
	mabel.step_pose(farmer)
	assert_eq(mabel._current, &"Jet_Fly")


func _farmer() -> Farmer:
	var farmer := (load(FARMER_SCENE) as PackedScene).instantiate() as Farmer
	farmer.set_physics_process(false)
	add_child_autofree(farmer)
	return farmer


func _mabel(farmer: Farmer) -> MabelModel:
	farmer.set_rigged_model(true)
	return farmer.get_node("Model/Pose/Mabel") as MabelModel
