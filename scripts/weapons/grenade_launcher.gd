class_name GrenadeLauncher
extends Pistol
## Slow lob with a wide blast. Each shell is valuable against groups of tougher robots. Shells arc onto
## the point under the crosshair (up to max_range), so the blast lands where the player aims.

## Horizontal speed of the lob; longer throws take longer and arc higher.
const LOB_SPEED: float = 24.0
const MIN_FLIGHT_TIME: float = 0.25
const MAX_FLIGHT_TIME: float = 1.9

@export var blast_radius: float = 5.0


func blast_radius_now() -> float:
	return stat(&"grenade.blast_radius", blast_radius)


func fire() -> bool:
	if _reload_left > 0.0 or _cooldown > 0.0 or farmer == null:
		return false
	if ammo <= 0:
		reload()
		return false
	ammo -= 1
	_cooldown = attack_interval()
	var from := _muzzle.global_position
	var aim_point := farmer.get_aim_point(data.max_range)
	var shot := begin_shot(from, aim_point - from)
	var shell := GrenadeProjectile.new()
	shell.weapon = self
	shell.source = farmer
	shell.damage = shot.damage
	shell.radius = blast_radius_now()
	var target := from + shot.direction * minf(from.distance_to(aim_point), shot.max_range)
	shell.velocity = lob_velocity(from, target, shell.gravity)
	get_tree().current_scene.add_child(shell)
	shell.global_position = from
	shell.reset_physics_interpolation()
	if ammo == 0:
		reload()
	return true


## Launch velocity that carries a shell from `from` onto `to` under `gravity`. Steep upward aims are
## flattened so a shot into the sky goes up a few metres and comes back down, not off the map.
static func lob_velocity(from: Vector3, to: Vector3, gravity: float) -> Vector3:
	var offset := to - from
	var flat := Vector2(offset.x, offset.z).length()
	offset.y = minf(offset.y, flat + 4.0)
	var time := clampf(flat / LOB_SPEED, MIN_FLIGHT_TIME, MAX_FLIGHT_TIME)
	return offset / time + Vector3.UP * 0.5 * gravity * time
