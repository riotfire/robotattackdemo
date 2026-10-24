class_name SiloCrack
extends Node3D
## One crack on the silo (GDD 3.3): a grain spout that leaks by size until repaired.
## Built at runtime on a crack socket. Local +Z points out of the silo wall.

enum Size { SMALL, MEDIUM, LARGE }

const SIZE_NAMES: PackedStringArray = ["Small", "Medium", "Large"]
const BAND_NAMES: PackedStringArray = ["ground", "catwalk 1", "catwalk 2"]
const CRACK_EXTENTS: Array[Vector2] = [Vector2(0.5, 0.25), Vector2(0.9, 0.45), Vector2(1.4, 0.7)]
const SPOUT_AMOUNTS: PackedInt32Array = [10, 20, 36]
## Seconds of wrenching to work a crack down one size (Small closes, Medium -> Small, Large -> Medium).
const STAGE_SECONDS: PackedFloat32Array = [1.2, 2.1, 2.4]

var socket_index: int = -1
var band: int = 0
var size: Size = Size.SMALL
## Structure this crack still owes the silo. Repair drains it; the crack closes at 0.
var pool: float = 0.0
var max_pool: float = 0.0

var _hits_since_resize: int = 0
## Wrench time already spent on the current size.
var _stage_progress: float = 0.0
var _highlighted: bool = false
var _crack_mesh: MeshInstance3D
var _spout: CPUParticles3D
var _beacon: Label3D

static var _crack_material: StandardMaterial3D
static var _highlight_material: StandardMaterial3D
static var _grain_material: StandardMaterial3D


func setup(index: int, band_index: int, initial_pool: float) -> void:
	socket_index = index
	band = band_index
	pool = initial_pool
	max_pool = initial_pool


func _ready() -> void:
	_ensure_materials()
	_crack_mesh = MeshInstance3D.new()
	_crack_mesh.name = "CrackMesh"
	_crack_mesh.mesh = BoxMesh.new()
	_crack_mesh.position = Vector3(0.0, 0.0, 0.02)
	add_child(_crack_mesh)

	_spout = CPUParticles3D.new()
	_spout.name = "GrainSpout"
	_spout.position = Vector3(0.0, 0.0, 0.08)
	_spout.lifetime = 1.1
	_spout.direction = Vector3(0.0, -0.2, 1.0)
	_spout.spread = 14.0
	_spout.initial_velocity_min = 1.6
	_spout.initial_velocity_max = 2.6
	_spout.gravity = Vector3(0.0, -9.8, 0.0)
	_spout.scale_amount_min = 0.6
	_spout.scale_amount_max = 1.2
	var pellet := BoxMesh.new()
	pellet.size = Vector3(0.08, 0.08, 0.08)
	pellet.material = _grain_material
	_spout.mesh = pellet
	add_child(_spout)

	_beacon = Label3D.new()
	_beacon.name = "Beacon"
	_beacon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_beacon.no_depth_test = true
	_beacon.fixed_size = true
	_beacon.pixel_size = 0.0018
	_beacon.font_size = 22
	_beacon.outline_size = 6
	_beacon.position = Vector3(0.0, 0.7, 0.4)
	add_child(_beacon)
	_update_visual()


## A hit landed near this crack. Returns true if the crack grew.
func register_hit(hits_to_grow: PackedInt32Array) -> bool:
	if size == Size.LARGE:
		return false
	_hits_since_resize += 1
	if _hits_since_resize >= hits_to_grow[size]:
		_hits_since_resize = 0
		_stage_progress = 0.0
		size = (size + 1) as Size
		_update_visual()
		return true
	return false


## Spends `seconds` of wrench time. Each size takes its own STAGE_SECONDS, then the crack drops one size
## (closing at Small); the pool drains in step so Structure comes back evenly. Returns the Structure restored.
func repair(seconds: float) -> float:
	var left := seconds
	var before := pool
	var remaining := repair_seconds_left()
	while left > 0.0 and pool > 0.0:
		var step := minf(left, STAGE_SECONDS[size] - _stage_progress)
		_stage_progress += step
		left -= step
		if _stage_progress >= STAGE_SECONDS[size] - 0.0001:
			_stage_progress = 0.0
			if size == Size.SMALL:
				pool = 0.0
				break
			size = (size - 1) as Size
			_hits_since_resize = 0
			_update_visual()
	if pool > 0.0 and remaining > 0.0:
		pool = before * (repair_seconds_left() / remaining)
	return before - pool


## Wrench seconds still needed to close this crack.
func repair_seconds_left() -> float:
	var total := -_stage_progress
	for stage in range(size + 1):
		total += STAGE_SECONDS[stage]
	return total


func repair_fraction() -> float:
	var full := 0.0
	for stage in range(size + 1):
		full += STAGE_SECONDS[stage]
	return 1.0 - repair_seconds_left() / full if pool > 0.0 else 1.0


func leak_rate(rates: PackedFloat32Array) -> float:
	return rates[size]


func describe() -> String:
	return "%s crack (%s)" % [SIZE_NAMES[size], BAND_NAMES[band]]


func set_highlighted(on: bool) -> void:
	if on == _highlighted:
		return
	_highlighted = on
	_update_visual()


func _update_visual() -> void:
	if _crack_mesh == null:
		return
	var extents := CRACK_EXTENTS[size]
	(_crack_mesh.mesh as BoxMesh).size = Vector3(extents.x, extents.y, 0.06)
	_crack_mesh.material_override = _highlight_material if _highlighted else _crack_material
	_spout.amount = SPOUT_AMOUNTS[size]
	_beacon.text = "! %s" % SIZE_NAMES[size].to_upper()
	_beacon.modulate = Color(1.0, 0.85, 0.2) if size == Size.SMALL else (Color(1.0, 0.55, 0.15) if size == Size.MEDIUM else Color(1.0, 0.25, 0.2))


static func _ensure_materials() -> void:
	if _crack_material != null:
		return
	_crack_material = StandardMaterial3D.new()
	_crack_material.albedo_color = Color(0.12, 0.07, 0.05)
	_highlight_material = StandardMaterial3D.new()
	_highlight_material.albedo_color = Color(0.2, 0.1, 0.05)
	_highlight_material.emission_enabled = true
	_highlight_material.emission = Color(1.0, 0.75, 0.2)
	_highlight_material.emission_energy_multiplier = 0.8
	_grain_material = StandardMaterial3D.new()
	_grain_material.albedo_color = Color(0.95, 0.78, 0.3)
