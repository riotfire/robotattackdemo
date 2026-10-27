class_name Shotgun
extends Pistol
## Seven fixed pellet rays. Strong against a nearby cluster, with spread and a short reach.
## One pellet flies straight; the other six alternate between an inner and the outer ring. The inner ring is
## tight enough that at the 5-10 m testers fight from, the centre pellet and the three inner ones all land on
## one small robot (PLAYTEST_SIMULATION_REPORT.md finding 8: the old 11-degree cone landed 1-2 of 7 there),
## and the outer ring still spreads across a group.

const PELLETS: int = 7
const SPREAD_DEGREES: float = 9.0
## Inner ring's share of the full spread: 2.25 degrees, 0.24 m off the aim line at 6 m.
const INNER_RING: float = 0.25


func fire() -> bool:
	if _reload_left > 0.0 or _cooldown > 0.0 or farmer == null:
		return false
	if ammo <= 0:
		reload()
		return false
	ammo -= 1
	_cooldown = attack_interval()
	var from := _muzzle.global_position
	var forward := (farmer.get_aim_point(data.max_range) - from).normalized()
	var camera_basis := farmer.camera_rig.camera.global_basis
	var spread := tan(deg_to_rad(SPREAD_DEGREES))
	for i in PELLETS:
		var direction := (forward + (camera_basis.x * pellet_offset(i).x + camera_basis.y * pellet_offset(i).y) * spread).normalized()
		resolve_shot(begin_shot(from, direction))
	if ammo == 0:
		reload()
	return true


## Pellet `index`'s offset from the aim line, as a fraction of the full spread.
static func pellet_offset(index: int) -> Vector2:
	if index == 0:
		return Vector2.ZERO
	var ring := INNER_RING if index % 2 == 1 else 1.0
	return Vector2.from_angle(TAU * float(index - 1) / float(PELLETS - 1)) * ring
