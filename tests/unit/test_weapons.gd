extends GutTest
## The weapon framework (GDD 5.2, 6, 18.4; M2-A2): WeaponData, the WeaponHolder's switching and wheel,
## mod hooks and slots, and pooled projectiles.

const TEMP_PROFILE := "user://gut_weapons_profile.json"
const FARMER_SCENE := "res://scenes/player/farmer.tscn"

var _saved_levels: Dictionary = {}
var _saved_profile_path: String = ""


func before_each() -> void:
	_saved_profile_path = SaveManager.profile_path
	SaveManager.profile_path = TEMP_PROFILE
	_saved_levels = StatService.levels.duplicate()
	StatService.set_levels({})


func after_each() -> void:
	StatService.set_levels(_saved_levels)
	SaveManager.profile_path = _saved_profile_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PROFILE))


func test_weapon_data_matches_the_gdd_arsenal() -> void:
	var wrench := load("res://data/weapons/wrench.tres") as MeleeWeaponData
	assert_not_null(wrench, "the wrench is a MeleeWeaponData")
	assert_eq([wrench.slot, wrench.damage, wrench.fire_rate, wrench.max_range, wrench.combo_multiplier],
			[1, 25.0, 1.6, 2.2, 1.5], "wrench: slot 1, 25 damage, 1.6 swings/s, 2.2 m, 3rd hit x1.5")
	assert_eq(wrench.unlock_flag, &"", "the wrench is always carried")
	assert_eq(wrench.trigger_mode, WeaponData.TriggerMode.AUTO, "holding fire keeps swinging")
	var pistol := load("res://data/weapons/pistol.tres") as WeaponData
	assert_eq([pistol.slot, pistol.damage, pistol.fire_rate, pistol.magazine_size, pistol.reload_time, pistol.max_range],
			[2, 12.0, 4.0, 10, 1.1, 40.0], "pistol: slot 2, 12 damage, 4 shots/s, 10 rounds, 1.1 s reload, 40 m")
	assert_eq(pistol.unlock_flag, &"pistol.unlocked")
	assert_true(pistol.usable_on_zipline and not wrench.usable_on_zipline, "only the pistol works on a zipline without Zipline Grip 2")
	assert_false(pistol.uses_projectiles(), "the Rivet Pistol is hitscan")
	for data: WeaponData in [wrench, pistol]:
		for key: StringName in [data.damage_stat, data.fire_rate_stat]:
			assert_true(_catalog_modifies(key), "%s: some pegboard node modifies %s" % [data.display_name, key])


func test_wheel_slots_go_clockwise_from_the_top() -> void:
	assert_eq(WeaponHolder.slot_at(Vector2(0.0, -1.0)), 1, "up")
	assert_eq(WeaponHolder.slot_at(Vector2(0.87, -0.5)), 2, "up-right")
	assert_eq(WeaponHolder.slot_at(Vector2(0.87, 0.5)), 3, "down-right")
	assert_eq(WeaponHolder.slot_at(Vector2(0.0, 1.0)), 4, "down")
	assert_eq(WeaponHolder.slot_at(Vector2(-0.87, 0.5)), 5, "down-left")
	assert_eq(WeaponHolder.slot_at(Vector2(-0.87, -0.5)), 6, "up-left")
	assert_eq(WeaponHolder.slot_at(Vector2(-0.2, -0.98)), 1, "a little left of up is still slot 1")
	assert_eq(WeaponHolder.slot_at(Vector2(0.1, 0.1)), 0, "inside the deadzone")


func test_holder_switches_and_equips_new_unlocks() -> void:
	var farmer := _spawn_farmer()
	var holder := farmer.weapons
	var wrench := holder.get_weapon(&"wrench")
	var pistol := holder.get_weapon(&"pistol")
	assert_eq(holder.weapons, [wrench, pistol] as Array[Weapon], "ordered by slot")
	assert_eq(holder.current, wrench, "a fresh profile starts with the wrench")
	assert_false(holder.equip(pistol), "the pistol can't be equipped before it's bought")
	assert_eq(holder.current, wrench)

	StatService.grant(&"attack.pistol")
	assert_eq(holder.current, pistol, "buying the pistol puts it in hand")
	assert_true(holder.equip_slot(1))
	assert_eq(holder.current, wrench, "slot 1 is the wrench")
	assert_true(holder.swap_to_previous())
	assert_eq(holder.current, pistol, "a tap swaps back to the last weapon")
	assert_true(holder.swap_to_previous())
	assert_eq(holder.current, wrench, "and again")
	StatService.grant(&"travel.comfy_boots")
	assert_eq(holder.current, wrench, "other purchases leave the wrench in hand")
	holder.cycle(1)
	assert_eq(holder.current, pistol, "the mouse wheel cycles to the next weapon")

	assert_eq(holder.weapon_at(Vector2(0.0, 1.0)), pistol, "pointing at empty slot 4 picks the nearest weapon")
	assert_eq(holder.weapon_at(Vector2(-0.87, -0.5)), wrench, "slot 6 is next to slot 1")
	assert_null(holder.weapon_at(Vector2.ZERO), "nothing inside the deadzone")

	StatService.set_levels({})
	assert_eq(holder.current, wrench, "losing the pistol (profile reset) falls back to the wrench")
	assert_false(holder.swap_to_previous(), "no swapping back to a weapon you don't have")


func test_mod_hooks_run_in_order_and_report_kills() -> void:
	var weapon := autofree(_bare_weapon()) as Weapon
	var target := _Target.new()
	add_child_autofree(target)
	var box := _hurtbox(target, false)
	var first := _Doubler.new()
	var second := _Doubler.new()
	assert_true(weapon.install_mod(first))
	assert_false(weapon.install_mod(_Doubler.new()), "one mod slot")
	assert_false(weapon.install_mod(first), "a mod installs once")

	var shot := weapon.begin_shot(Vector3.ZERO, Vector3(0.0, 0.0, -2.0))
	assert_eq(first.fired, 1, "on_fire runs for each shot")
	assert_almost_eq(shot.damage, 20.0, 0.001, "on_fire can change the shot's damage (10 -> 20)")
	assert_almost_eq(shot.direction.length(), 1.0, 0.001, "direction is normalized")

	var killed := weapon.deliver_hit(box, DamagePacket.create(15.0, null, Vector3.ZERO))
	assert_false(killed)
	assert_almost_eq(target.health.current, 70.0, 0.001, "on_hit doubles 15 to 30 before it lands")
	assert_eq([first.hits, first.kills], [1, 0])
	killed = weapon.deliver_hit(box, DamagePacket.create(50.0, null, Vector3.ZERO))
	assert_true(killed, "a hit that empties the target's health is a kill")
	assert_eq([first.hits, first.kills], [2, 1], "on_kill runs once")
	killed = weapon.deliver_hit(box, DamagePacket.create(50.0, null, Vector3.ZERO))
	assert_false(killed, "hitting a wreck isn't another kill")
	assert_eq(first.kills, 1)

	weapon.remove_mod(first)
	weapon.data.gold_mod_slot_flag = &"pistol.unlocked"
	StatService.grant(&"attack.pistol")
	assert_eq(weapon.mod_slot_count(), 2, "the Gold Mod Slot flag adds a slot")
	assert_true(weapon.install_mod(first) and weapon.install_mod(second))
	weapon.deliver_hit(_hurtbox(target, true), DamagePacket.create(1.0, null, Vector3.ZERO))
	assert_true(first.saw_weak_point, "on_hit already knows it's a weak point")


func test_projectile_shots_hit_through_the_pool() -> void:
	var weapon := _bare_weapon()
	weapon.data.projectile_speed = 60.0
	add_child_autofree(weapon)
	var target := _Target.new()
	add_child_autofree(target)
	target.position = Vector3(0.0, 0.0, -12.0)
	_hurtbox(target, false)
	await wait_physics_frames(2)

	weapon.resolve_shot(weapon.begin_shot(Vector3.ZERO, Vector3.FORWARD))
	var pool := ProjectilePool.of(weapon)
	assert_eq(pool.active_count(), 1, "the shot is a live projectile")
	await wait_physics_frames(6)
	assert_eq(target.hits.size(), 0, "it takes time to fly 12 m at 60 m/s")
	await wait_physics_frames(20)
	assert_eq(target.hits.size(), 1, "it hits the target once")
	assert_almost_eq(target.health.current, 90.0, 0.001)
	assert_eq(pool.active_count(), 0, "and goes back to the pool")
	pool.queue_free()


func test_pool_recycles_projectiles_and_lets_them_pierce() -> void:
	var pool := ProjectilePool.new()
	pool.prewarm = 2
	add_child_autofree(pool)
	var near := _Target.new()
	var far := _Target.new()
	for target: _Target in [near, far]:
		add_child_autofree(target)
		_hurtbox(target, false)
	near.position = Vector3(0.0, 0.0, -4.0)
	far.position = Vector3(0.0, 0.0, -8.0)
	await wait_physics_frames(2)

	var hits: Array[Node] = []
	var pierce := func(hit: Dictionary) -> bool:
		var box := hit["collider"] as Hurtbox
		hits.append(box.receiver())
		return true
	var first := pool.launch(Vector3.ZERO, Vector3.FORWARD * 100.0, 0.0, 0.3, Weapon.ROBOT_HURTBOX_MASK, [], pierce)
	await wait_physics_frames(25)
	assert_eq(hits, [near, far] as Array[Node], "returning true flies on through each target")
	assert_false(first.is_active, "it retires when its lifetime runs out")
	assert_eq(pool.active_count(), 0)
	var second := pool.launch(Vector3.ZERO, Vector3.UP * 10.0, 0.0, 0.1, Weapon.ROBOT_HURTBOX_MASK, [], Callable())
	assert_eq(second, first, "the next launch reuses the retired projectile")
	assert_eq(pool.total_count(), 2, "no new projectiles were made")


# --- Helpers --------------------------------------------------------------------------------------

func _spawn_farmer() -> Farmer:
	var farmer := (load(FARMER_SCENE) as PackedScene).instantiate() as Farmer
	add_child_autofree(farmer)
	farmer.set_physics_process(false)
	return farmer


func _bare_weapon() -> Weapon:
	var weapon := Weapon.new()
	weapon.data = WeaponData.new()
	weapon.data.damage = 10.0
	return weapon


func _hurtbox(target: Node3D, weak_point: bool) -> Hurtbox:
	var box := Hurtbox.new()
	box.collision_layer = Weapon.ROBOT_HURTBOX_MASK
	box.collision_mask = 0
	box.is_weak_point = weak_point
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	shape.shape = sphere
	box.add_child(shape)
	target.add_child(box)
	box.owner = target
	return box


func _catalog_modifies(key: StringName) -> bool:
	for node: UpgradeNode in StatService.catalog.values():
		for effect in node.effects:
			if effect.stat == key:
				return true
	return false


## Something to shoot: a HealthComponent with 100 HP behind take_damage().
class _Target:
	extends Node3D

	var health: HealthComponent
	var hits: Array[DamagePacket] = []

	func _init() -> void:
		health = HealthComponent.new()
		health.max_health = 100.0
		add_child(health)

	func take_damage(packet: DamagePacket) -> void:
		hits.append(packet)
		health.apply_damage(packet.amount)


## Doubles every shot's damage and every hit's packet, and counts its hooks.
class _Doubler:
	extends WeaponMod

	var fired: int = 0
	var hits: int = 0
	var kills: int = 0
	var saw_weak_point: bool = false

	func on_fire(_weapon: Weapon, shot: WeaponShot) -> void:
		fired += 1
		shot.damage *= 2.0

	func on_hit(_weapon: Weapon, _target: Node, packet: DamagePacket) -> void:
		hits += 1
		packet.amount *= 2.0
		saw_weak_point = saw_weak_point or packet.is_weak_point

	func on_kill(_weapon: Weapon, _target: Node, _packet: DamagePacket) -> void:
		kills += 1
