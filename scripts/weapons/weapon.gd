class_name Weapon
extends Node3D
## Base for everything in the farmer's WeaponHolder (GDD 6, 18.4). Base stats come from a WeaponData
## resource and upgrades from StatService; the holder forwards trigger input. Weapons aim along the farmer's
## camera-center ray (GDD 5.3).
## Every shot goes down one path so mods see all of it: begin_shot() runs on_fire and plays the fire cue,
## resolve_shot() fires a hitscan ray or a pooled projectile, and deliver_hit() runs on_hit, lands the damage,
## then on_kill.

signal fired(shot: WeaponShot)
signal hit_landed(target: Node, packet: DamagePacket)
signal killed(target: Node, packet: DamagePacket)

## Collision layers a shot can hit: World, RobotHurtbox, Silo (GDD 18.6).
const SHOT_MASK: int = 1 | (1 << 4) | (1 << 5)
const ROBOT_HURTBOX_MASK: int = 1 << 4
## A semi-auto press made this long before the weapon is ready still fires once it is, so quick clicks
## during the cooldown aren't lost.
const PRESS_BUFFER: float = 0.15
## Most hurtboxes one hitscan ray checks before giving up (a piercing round meets eyes and bodies).
const MAX_RAY_HITS: int = 16

@export var data: WeaponData

var farmer: Farmer
## Installed mods, in the order their hooks run.
var mods: Array[WeaponMod] = []

var _press_buffer: float = 0.0

var display_name: String:
	get:
		return data.display_name if data != null else String(name)


func setup(owner_farmer: Farmer) -> void:
	farmer = owner_farmer


## Carried right now after its pegboard unlock (or always when unlock_flag is empty).
func is_available() -> bool:
	return data.unlock_flag == &"" or StatService.has_flag(data.unlock_flag)


## Called every physics step while this weapon is equipped and usable.
func trigger(just_pressed: bool, held: bool) -> void:
	if data.trigger_mode == WeaponData.TriggerMode.AUTO:
		if held:
			attack()
		return
	if just_pressed:
		_press_buffer = PRESS_BUFFER
	if _press_buffer > 0.0:
		_press_buffer = 0.0 if attack() else _press_buffer - get_physics_process_delta_time()


## One shot or swing, if the weapon is ready. Returns true if it happened.
func attack() -> bool:
	return false


func reload() -> void:
	pass


func ammo_text() -> String:
	return ""


func set_equipped(equipped: bool) -> void:
	visible = equipped
	_press_buffer = 0.0


# --- Stats ----------------------------------------------------------------------------------------

## Reads an upgradable stat. Weapons read upgrades only through here, so per-player stat profiles
## (co-op, the Daily Kit) only need to change this.
func stat(key: StringName, base: float) -> float:
	return base if key == &"" else StatService.get_stat(key, base)


## Damage per shot or swing after upgrades and Death From Above, before mods and weak points.
func damage_now() -> float:
	return stat(data.damage_stat, data.damage) * (farmer.damage_multiplier() if farmer != null else 1.0)


## Seconds between shots or swings.
func attack_interval() -> float:
	return 1.0 / maxf(0.01, stat(data.fire_rate_stat, data.fire_rate))


# --- Mods (GDD 6.3) -------------------------------------------------------------------------------

func mod_slot_count() -> int:
	var slots := data.mod_slots
	if data.gold_mod_slot_flag != &"" and StatService.has_flag(data.gold_mod_slot_flag):
		slots += 1
	return slots


## Returns false if every slot is taken or it's already installed.
func install_mod(mod: WeaponMod) -> bool:
	if mod == null or mod in mods or mods.size() >= mod_slot_count():
		return false
	mods.append(mod)
	return true


func remove_mod(mod: WeaponMod) -> void:
	mods.erase(mod)


# --- Shots ----------------------------------------------------------------------------------------

## Starts a shot or swing from `origin` along `direction` and lets on_fire mods change it. Weapons call it only once
## the shot or swing really happens (ammo spent, cooldown passed), so this is also where data.fire_cue plays.
func begin_shot(origin: Vector3, direction: Vector3) -> WeaponShot:
	var shot := WeaponShot.new()
	shot.weapon = self
	shot.origin = origin
	shot.direction = direction.normalized()
	shot.damage = damage_now()
	shot.max_range = data.max_range
	shot.pierce_left = roundi(stat(data.pierce_stat, data.pierce))
	shot.knockback = data.knockback
	for mod in mods:
		mod.on_fire(self, shot)
	if data.fire_cue != &"":
		AudioDirector.play_cue(data.fire_cue)
	fired.emit(shot)
	return shot


## Fires a gun's shot: a hitscan ray, or a pooled projectile if the weapon's data says so.
func resolve_shot(shot: WeaponShot) -> void:
	if data.uses_projectiles():
		ProjectilePool.of(self).launch(shot.origin, shot.direction * data.projectile_speed, data.projectile_gravity,
				shot.max_range / data.projectile_speed, SHOT_MASK, _shot_exclusions(), _on_shot_hit.bind(shot),
				data.projectile_color, data.projectile_radius)
		return
	var end := shot.origin + shot.direction * shot.max_range
	var from := shot.origin
	var exclude := _shot_exclusions()
	var space := get_world_3d().direct_space_state
	for i in MAX_RAY_HITS:
		var query := PhysicsRayQueryParameters3D.create(from, end, SHOT_MASK, exclude)
		query.collide_with_areas = true
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			break
		if not _on_shot_hit(hit, shot):
			end = hit["position"]
			break
		exclude.append(hit["rid"])
		from = hit["position"]
	Fx.tracer(self, shot.origin, end)


## Lands `packet` on `hurtbox`: on_hit mods, the damage, then on_kill mods if it destroyed the target.
## Returns true on a kill.
func deliver_hit(hurtbox: Hurtbox, packet: DamagePacket) -> bool:
	var target := hurtbox.receiver()
	packet.is_weak_point = packet.is_weak_point or hurtbox.is_weak_point
	for mod in mods:
		mod.on_hit(self, target, packet)
	var was_kill := hurtbox.hit(packet)
	hit_landed.emit(target, packet)
	if was_kill:
		for mod in mods:
			mod.on_kill(self, target, packet)
		killed.emit(target, packet)
	return was_kill


## A ray or projectile from `shot` hit something. Returns true to let the shot fly on through it: past a
## second hurtbox of a robot it already hit, or into the next robot while it has pierce left.
func _on_shot_hit(hit: Dictionary, shot: WeaponShot) -> bool:
	var at: Vector3 = hit["position"]
	var hurtbox := hit["collider"] as Hurtbox
	if hurtbox == null:
		Fx.puff(self, at, Color(0.8, 0.75, 0.65), 0.1, 0.2)
		return false
	var target := hurtbox.receiver()
	if target != null:
		if target in shot.hit_targets:
			return true
		shot.hit_targets.append(target)
	var packet := DamagePacket.create(shot.damage, farmer, at)
	if shot.knockback > 0.0:
		packet.knockback = Vector3(shot.direction.x, 0.0, shot.direction.z).normalized() * shot.knockback \
				+ Vector3.UP * shot.knockback * 0.3
	deliver_hit(hurtbox, packet)
	Fx.puff(self, at, Color(1.0, 0.95, 0.6) if not hurtbox.is_weak_point else Color(1.0, 0.3, 0.2), 0.15, 0.15)
	if shot.pierce_left > 0:
		shot.pierce_left -= 1
		return true
	return false


func _shot_exclusions() -> Array[RID]:
	var exclude: Array[RID] = []
	if farmer != null:
		exclude.append(farmer.get_rid())
	return exclude
