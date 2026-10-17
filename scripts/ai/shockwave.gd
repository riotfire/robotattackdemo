class_name Shockwave
extends Node3D
## The ring a Thumper's slam sends along the ground (GDD 9.3). It expands to max_radius over `duration`
## and hits each farmer once if the ring passes under their feet while they're on the ground.
## Jumping (or standing on anything higher than the ring) avoids it.

const BAND: float = 0.7
const MAX_HEIGHT: float = 0.6

var damage: float = 10.0
var max_radius: float = 8.0
var duration: float = 0.8
var source: Node = null

var _age: float = 0.0
var _hit: Array[Node3D] = []
var _ring: MeshInstance3D


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 32
	torus.ring_segments = 6
	_ring = Clay.part(self, torus, Color(0.85, 0.78, 0.62), Transform3D.IDENTITY, 0.2)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(0.1, 0.4, 0.1)


func _physics_process(delta: float) -> void:
	_age += delta
	var t := clampf(_age / duration, 0.0, 1.0)
	var radius := max_radius * t
	_ring.scale = Vector3(radius, 0.4, radius)
	for player in GameState.players:
		if not is_instance_valid(player) or player in _hit:
			continue
		var offset := player.global_position - global_position
		var flat := Vector2(offset.x, offset.z).length()
		if absf(flat - radius) <= BAND and offset.y < MAX_HEIGHT and player.has_method("take_damage"):
			_hit.append(player)
			var packet := DamagePacket.create(damage, source if is_instance_valid(source) else null, player.global_position)
			packet.knockback = Vector3(offset.x, 0.0, offset.z).normalized() * 6.0 + Vector3.UP * 3.0
			player.call("take_damage", packet)
	if t >= 1.0:
		queue_free()
