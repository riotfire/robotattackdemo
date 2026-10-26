class_name Pickup
extends Node3D
## Parts and grain sacks on the ground (GDD 12.3, 3.3). Parts burst out as springy clay bits, then
## magnetize to a farmer within 3 m (Scrap Magnet adds range) and bank instantly. Parts remain through
## battle and intermission; Scrap Vac takes a share and clears leftovers when the next battle starts.
## Grain sacks don't magnetize: walk over one to return its grain. Unclaimed sacks burst after 20 s
## (Sack Tracker: they roll home on their own after 5 s).
## Lightweight scripted nodes, not rigid bodies (GDD 18.4).

const GROUP: StringName = &"pickups"
const GRAIN: StringName = &"grain"
const PART_LIFETIME: float = INF
const SACK_LIFETIME: float = 20.0
const SACK_AUTO_RETURN: float = 5.0
const BLINK_TIME: float = 5.0
const BASE_MAGNET_RADIUS: float = 3.0
const COLLECT_RADIUS: float = 0.7
const SACK_COLLECT_RADIUS: float = 1.4
const GRAVITY: float = 18.0
## At most this many bits per part type; bigger drops stack into fewer, worth more.
const MAX_BITS: int = 6

signal collected(pickup: Pickup, collector: Node3D)

const COLORS: Dictionary[StringName, Color] = {
	&"al": Color(0.82, 0.84, 0.88), &"cu": Color(0.9, 0.5, 0.22), &"au": Color(1.0, 0.8, 0.2),
	&"pc": Color(0.06, 0.38, 1.0), &"grain": Color(0.78, 0.62, 0.38),
}

var kind: StringName = &"al"
var amount: int = 1
## Tutorial parts stay put until the player finds them.
var lifetime: float = PART_LIFETIME
var tutorial_display: bool = false

var _velocity: Vector3 = Vector3.ZERO
var _ground_y: float = 0.0
var _age: float = 0.0
var _landed: bool = false
var _magnet_speed: float = 0.0
var _target: Node3D = null
var _visual: Node3D
var _sweep_warning: bool = false
var _settled: bool = false


static func spawn_parts(context: Node, at: Vector3, parts: Dictionary) -> void:
	var rng := RngService.stream(RngService.STREAM_COSMETIC)
	for part: StringName in parts:
		var total := int(parts[part])
		if total <= 0:
			continue
		var bits := mini(total, MAX_BITS)
		for i in bits:
			var value := floori(float(total) / bits) + (1 if i < total % bits else 0)
			var pickup := Pickup.new()
			pickup.kind = part
			pickup.amount = value
			pickup._velocity = Vector3(rng.randf_range(-3.0, 3.0), rng.randf_range(4.0, 7.0), rng.randf_range(-3.0, 3.0))
			_add(context, pickup, at)


static func spawn_grain(context: Node, at: Vector3, bushels: float) -> Pickup:
	var pickup := Pickup.new()
	pickup.kind = GRAIN
	pickup.amount = roundi(bushels)
	pickup._velocity = Vector3(0.0, 3.0, 0.0)
	_add(context, pickup, at)
	return pickup


static func _add(context: Node, pickup: Pickup, at: Vector3) -> void:
	var parent := context.get_tree().current_scene
	parent.add_child(pickup)
	pickup.global_position = at
	pickup.reset_physics_interpolation()


func _ready() -> void:
	add_to_group(GROUP)
	if kind != GRAIN:
		EventBus.siren_started.connect(_on_siren_started)
	_visual = Node3D.new()
	add_child(_visual)
	if tutorial_display:
		_visual.scale = Vector3.ONE * 1.8
	var color := COLORS.get(kind, Color.WHITE) as Color
	if kind in [&"al", &"cu", &"au", &"pc"]:
		_visual.add_child(PickupVisuals.create(kind, color))
		_visual.position.y = 0.16
	else:  # a grain sack
		var sack := SphereMesh.new()
		sack.radius = 0.32
		sack.height = 0.5
		Clay.part(_visual, sack, color, Transform3D(Basis(), Vector3(0.0, 0.25, 0.0)))
	_ground_y = _find_ground(global_position)


func _physics_process(delta: float) -> void:
	_age += delta
	var expires_after := SACK_LIFETIME if kind == GRAIN else lifetime
	if kind == GRAIN and _age >= SACK_AUTO_RETURN and StatService.has_flag(&"grain.sack_tracker"):
		_return_grain()
		return
	if _age >= expires_after:
		if kind == GRAIN:
			EventBus.hud_message.emit("A grain sack burst: %d bushels lost" % amount, 2.0)
		queue_free()
		return
	_visual.visible = (not _sweep_warning and _age < expires_after - BLINK_TIME) or int(_age * 8.0) % 2 == 0
	if tutorial_display:
		_visual.position.y = 0.3 + sin(_age * 4.0) * 0.12
	elif kind != GRAIN and _landed:
		_visual.position.y = 0.16 + (sin(_age * 3.0) * 0.035 if StopMotionClock.enabled else 0.0)

	if _target != null and is_instance_valid(_target):
		_magnet_speed += 30.0 * delta
		var goal := _target.global_position + Vector3.UP * 0.9
		global_position = global_position.move_toward(goal, (6.0 + _magnet_speed) * delta)
		if global_position.distance_to(goal) <= COLLECT_RADIUS:
			_collect()
		return

	if not _landed:
		_velocity.y -= GRAVITY * delta
		var next := global_position + _velocity * delta
		if next.y <= _ground_y:
			next.y = _ground_y
			_velocity = Vector3(_velocity.x * 0.5, -_velocity.y * 0.35, _velocity.z * 0.5)
			if _velocity.y < 1.0:
				_landed = true
		global_position = next
	else:
		_visual.rotation.y += delta * 2.0

	for player in GameState.players:
		if not is_instance_valid(player):
			continue
		var d := player.global_position.distance_to(global_position)
		if kind == GRAIN:
			if d <= SACK_COLLECT_RADIUS:
				_return_grain()
				return
		elif d <= BASE_MAGNET_RADIUS + StatService.get_stat(&"pickups.magnet_radius", 0.0):
			_target = player
			return


## Sends the pickup flying to `who` at once, whatever the distance (Level 0's Dummy-Bot drop mustn't be missed).
func attract_to(who: Node3D) -> void:
	_target = who


func _collect() -> void:
	if _settled or is_queued_for_deletion():
		return
	_settled = true
	remove_from_group(GROUP)
	GameState.add_parts({kind: amount})
	collected.emit(self, _target)
	queue_free()


func _return_grain() -> void:
	if _settled or is_queued_for_deletion():
		return
	_settled = true
	remove_from_group(GROUP)
	var silo := GameState.silo
	if silo != null:
		var added := silo.add_grain(float(amount))
		EventBus.grain_returned.emit(added)
		EventBus.hud_message.emit("Grain sack returned: +%d bushels" % roundi(added), 1.5)
	queue_free()


## Scrap Vac: banks a share at the next battle's start and removes it. Returns parts banked.
func vacuum(fraction: float, rng: RandomNumberGenerator) -> int:
	if kind == GRAIN or _settled or is_queued_for_deletion():
		return 0
	_settled = true
	remove_from_group(GROUP)
	var exact := amount * clampf(fraction, 0.0, 1.0)
	var banked := floori(exact) + (1 if rng.randf() < exact - floorf(exact) else 0)
	if banked > 0:
		GameState.add_parts({kind: banked})
	queue_free()
	return banked


func _on_siren_started(_wave: int, _lanes: PackedInt32Array) -> void:
	_sweep_warning = true


func _find_ground(from: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 0.5, from + Vector3.DOWN * 40.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return (hit["position"] as Vector3).y + 0.12 if not hit.is_empty() else 0.12
