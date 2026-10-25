extends GutTest
## Checks that the new purchases change targeting and movement, rather than merely changing stats.

const FARMER_SCENE := "res://scenes/player/farmer.tscn"

var _saved_levels: Dictionary = {}


func before_each() -> void:
	_saved_levels = StatService.levels.duplicate()
	StatService.set_levels({})


func after_each() -> void:
	Input.action_release(&"air_dash")
	Input.action_release(&"ground_pound")
	StatService.set_levels(_saved_levels)


func test_shotgun_fires_a_short_cone_in_one_shell() -> void:
	var farmer := _farmer()
	StatService.grant(&"attack.pistol")
	StatService.grant(&"attack.shotgun")
	var shotgun := farmer.weapons.get_weapon(&"shotgun") as Shotgun
	var directions: Array[Vector3] = []
	shotgun.fired.connect(func(shot: WeaponShot) -> void: directions.append(shot.direction))
	var before := shotgun.ammo
	assert_true(shotgun.fire())
	assert_eq(shotgun.ammo, before - 1, "seven pellets consume one shell")
	assert_eq(directions.size(), Shotgun.PELLETS)
	for direction in directions:
		assert_gte(direction.dot(directions[0]), cos(deg_to_rad(Shotgun.SPREAD_DEGREES + 0.5)),
				"every pellet stays inside the short cone")
	assert_gt(directions[0].distance_to(directions[1]), 0.01, "pellets do not all follow one ray")


func test_radial_blast_hits_each_robot_once_even_with_multiple_hurtboxes() -> void:
	var near := _target(Vector3.ZERO, true)
	var far := _target(Vector3(2.0, 0.0, 0.0), false)
	await wait_physics_frames(2)
	var count := AreaAttack.hit_robots(near, Vector3.ZERO, 4.0, 90.0, null)
	assert_eq(count, 2)
	assert_eq(near.hits, 1, "body and eye hurtboxes belong to one robot")
	assert_eq(far.hits, 1)
	assert_gt(near.health.current, 0.0)
	assert_lt(near.health.current, far.health.current, "the center of the blast takes more damage")


func test_rifle_reaches_a_target_beyond_pistol_range() -> void:
	var target := _target(Vector3(0.0, 0.0, -70.0), false)
	var rifle := Weapon.new()
	rifle.data = load("res://data/weapons/rifle.tres") as WeaponData
	add_child_autofree(rifle)
	await wait_physics_frames(2)
	rifle.resolve_shot(rifle.begin_shot(Vector3.ZERO, Vector3.FORWARD))
	assert_eq(target.hits, 1, "the rifle reaches across the farm")
	assert_almost_eq(target.health.current, 445.0, 0.001)
	rifle.data = load("res://data/weapons/pistol.tres") as WeaponData
	rifle.resolve_shot(rifle.begin_shot(Vector3.ZERO, Vector3.FORWARD))
	assert_eq(target.hits, 1, "the pistol cannot hit the same distant target")


func test_shotgun_pattern_has_an_inner_ring() -> void:
	var inner := 0
	for i in range(1, Shotgun.PELLETS):
		assert_lte(Shotgun.pellet_offset(i).length(), 1.0 + 0.001, "no pellet leaves the cone")
		if Shotgun.pellet_offset(i).length() < 0.6:
			inner += 1
	assert_eq(inner, 3, "half the ring pellets sit close to the aim line")


func test_rifle_round_punches_through_one_robot_and_counts_each_robot_once() -> void:
	var first := _target(Vector3(0.0, 0.0, -10.0), true)
	var second := _target(Vector3(0.0, 0.0, -20.0), false)
	var third := _target(Vector3(0.0, 0.0, -30.0), false)
	var rifle := Weapon.new()
	rifle.data = load("res://data/weapons/rifle.tres") as WeaponData
	add_child_autofree(rifle)
	await wait_physics_frames(2)
	rifle.resolve_shot(rifle.begin_shot(Vector3(0.0, 0.3, 0.0), Vector3.FORWARD))
	assert_eq(first.hits, 1, "the eye and body of one robot take one hit")
	assert_eq(second.hits, 1, "the round passes through to the next robot")
	assert_eq(third.hits, 0, "base pierce stops after the second robot")
	StatService.set_levels({&"attack.pistol": 1, &"attack.rifle": 1, &"attack.rifle_pierce": 1})
	rifle.resolve_shot(rifle.begin_shot(Vector3.ZERO, Vector3.FORWARD))
	assert_eq(third.hits, 1, "Punch-Through reaches one robot further")


func test_semi_auto_press_during_cooldown_is_buffered() -> void:
	var farmer := _farmer()
	StatService.grant(&"attack.pistol")
	var pistol := farmer.weapons.get_weapon(&"pistol") as Pistol
	await wait_physics_frames(1)
	assert_true(pistol.fire())
	var before := pistol.ammo
	pistol.trigger(true, true)
	assert_eq(pistol.ammo, before, "still on cooldown")
	pistol._cooldown = 0.0
	pistol.trigger(false, true)
	assert_eq(pistol.ammo, before - 1, "the early click fires once the pistol is ready")
	pistol._cooldown = 0.0
	pistol.trigger(false, true)
	assert_eq(pistol.ammo, before - 1, "one click is one shot")


func test_grenade_lob_lands_on_the_aim_point() -> void:
	var gravity := 18.0
	for target: Vector3 in [Vector3(0.0, 0.0, -6.0), Vector3(12.0, -1.0, -20.0), Vector3(0.0, 4.0, -40.0)]:
		var velocity := GrenadeLauncher.lob_velocity(Vector3.ZERO, target, gravity)
		var flat := Vector2(target.x, target.z).length()
		var time := clampf(flat / GrenadeLauncher.LOB_SPEED, GrenadeLauncher.MIN_FLIGHT_TIME, GrenadeLauncher.MAX_FLIGHT_TIME)
		var landed := velocity * time + Vector3.DOWN * 0.5 * gravity * time * time
		assert_almost_eq(landed.distance_to(target), 0.0, 0.01, "lands on %s" % target)


func test_lobbed_grenade_detonates_when_its_fuse_expires() -> void:
	var target := _target(Vector3.ZERO, false)
	var shell := GrenadeProjectile.new()
	shell.damage = 90.0
	shell.radius = 5.0
	shell.fuse = 0.01
	shell.velocity = Vector3.ZERO
	add_child_autofree(shell)
	await wait_physics_frames(3)
	assert_eq(target.hits, 1, "a missed shell still bursts after its fuse")
	assert_lt(target.health.current, 500.0)


func test_maul_hits_front_and_scythe_clears_full_circle() -> void:
	var farmer := _farmer()
	StatService.grant(&"attack.maul")
	StatService.grant(&"attack.scythe")
	var front := _target(Vector3(0.0, 0.0, -2.0), false)
	var back := _target(Vector3(0.0, 0.0, 2.0), false)
	await wait_physics_frames(2)
	var maul := farmer.weapons.get_weapon(&"maul") as SweepWeapon
	maul._swing_forward = Vector3.FORWARD
	maul._land_swing()
	assert_eq(front.hits, 1)
	assert_eq(back.hits, 0, "the heavy swing does not hit behind the farmer")
	var scythe := farmer.weapons.get_weapon(&"scythe") as SweepWeapon
	scythe._swing_forward = Vector3.FORWARD
	scythe._land_swing()
	assert_eq(front.hits, 2)
	assert_eq(back.hits, 1, "the scythe reaches behind the farmer")


func test_jetpack_unlocks_air_dash_and_ground_pound_actions() -> void:
	var farmer := _farmer()
	farmer.global_position = Vector3(0.0, 8.0, 0.0)
	farmer.jetpack.refill()
	var full := farmer.jetpack.fuel
	assert_false(farmer.movement.try_air_dash(Vector3.FORWARD), "the locked dash does not activate")
	StatService.grant(&"travel.jetpack")
	StatService.grant(&"travel.air_dash")
	assert_true(farmer.movement.try_air_dash(Vector3.FORWARD))
	farmer.movement.physics_step(1.0 / 60.0, Vector2.ZERO, Vector3.FORWARD)
	assert_gt(farmer.movement._dash_left, 0.0)
	assert_lt(farmer.velocity.z, -20.0)
	assert_lt(farmer.jetpack.fuel, full, "dashing costs fuel")
	StatService.grant(&"travel.ground_pound")
	assert_true(farmer.movement.try_ground_pound())
	farmer.movement.physics_step(1.0 / 60.0, Vector2.ZERO, Vector3.FORWARD)
	assert_true(farmer.movement._pounding)
	assert_lte(farmer.velocity.y, -farmer.movement.ground_pound_speed)


func _farmer() -> Farmer:
	var farmer := (load(FARMER_SCENE) as PackedScene).instantiate() as Farmer
	farmer.set_physics_process(false)
	add_child_autofree(farmer)
	return farmer


func _target(at: Vector3, second_box: bool) -> _Target:
	var target := _Target.new()
	add_child_autofree(target)
	target.global_position = at
	_add_box(target, Vector3.ZERO, false)
	if second_box:
		_add_box(target, Vector3(0.0, 0.3, 0.0), true)
	return target


func _add_box(target: _Target, offset: Vector3, weak: bool) -> void:
	var box := Hurtbox.new()
	box.collision_layer = Weapon.ROBOT_HURTBOX_MASK
	box.collision_mask = 0
	box.is_weak_point = weak
	box.position = offset
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.45
	shape.shape = sphere
	box.add_child(shape)
	target.add_child(box)
	box.owner = target


class _Target:
	extends Node3D
	var health: HealthComponent
	var hits: int = 0

	func _init() -> void:
		health = HealthComponent.new()
		health.max_health = 500.0
		add_child(health)

	func take_damage(packet: DamagePacket) -> void:
		hits += 1
		health.apply_damage(packet.amount)
