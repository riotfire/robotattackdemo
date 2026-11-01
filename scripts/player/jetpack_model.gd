class_name JetpackModel
extends Node3D
## Grandpa's Milk-Can Jetpack as worn (assets/Jetpack.glb). The farmer steps it on the 24 fps stop-motion tick: while
## thrusting both nozzles flicker, the pack rumbles on her back and each burn lets off smoke; near empty the flames sputter.

## Below this share of the tank the flames start cutting out.
const SPUTTER_FUEL: float = 0.25
const FLAME_LENGTH: Vector2 = Vector2(0.75, 1.25)
const FLAME_WIDTH: Vector2 = Vector2(0.85, 1.15)
const RUMBLE: float = 0.008
const RUMBLE_DEGREES: float = 1.2
const IGNITE_TICKS: int = 3
const SMOKE_EVERY: int = 6
const SMOKE_COLOR := Color(0.62, 0.6, 0.58)

var _burn_ticks: int = 0

@onready var _pack: Node3D = $Pack
@onready var _flames: Node3D = $Pack/Flames
@onready var _nozzles: Array[Node] = $Pack/Flames.get_children()


## The flames, which keep their own look when she flashes from a hit.
func is_flame(node: Node) -> bool:
	return _flames.is_ancestor_of(node)


func step(thrusting: bool, fuel_fraction: float) -> void:
	_flames.visible = thrusting
	if not thrusting:
		_burn_ticks = 0
		_pack.position = Vector3.ZERO
		_pack.rotation = Vector3.ZERO
		return
	_burn_ticks += 1
	var ignition := minf(1.0, float(_burn_ticks) / IGNITE_TICKS)
	var sputter := randf() > fuel_fraction / SPUTTER_FUEL
	for nozzle: Node3D in _nozzles:
		nozzle.visible = not sputter
		var width := randf_range(FLAME_WIDTH.x, FLAME_WIDTH.y)
		nozzle.scale = Vector3(width, randf_range(FLAME_LENGTH.x, FLAME_LENGTH.y) * ignition, width)
		if _burn_ticks % SMOKE_EVERY == 1:
			Fx.puff(self, nozzle.global_position, SMOKE_COLOR, 0.1, 0.3)
	_pack.position = Vector3(randf_range(-RUMBLE, RUMBLE), randf_range(-RUMBLE, RUMBLE), 0.0)
	_pack.rotation_degrees.z = randf_range(-RUMBLE_DEGREES, RUMBLE_DEGREES)
