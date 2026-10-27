class_name HeavyRobot
extends Robot
## A Heavy melee robot, the Thumper (GDD 9.3): rears up, then slams. The slam hits its target and sends
## a shockwave ring along the ground that the farmer can jump over. Weak point: the back vent (x2).
## Knockback doesn't move it.
##
## The authored opening's Foremen (OpeningWave, `authored`) fight by fixed, readable rules
## (FIRST_FIVE_WAVES_FUN_PLAN.md): a clear AUTHORED_WINDUP rear-up before every slam, then AUTHORED_RECOVERY
## of recovery while the back vent glows and takes VENT_OPEN_MULTIPLIER instead of x2: the punish window.
## They wear plates, so they can't be kited (playtest feedback 2026-10-26: the second Foreman died to a pistol
## from a safe distance): a hit landed from more than PLATE_RANGE away does only PLATED_SHARE of its damage,
## unless it goes into the open vent during the punish window. Close-range hits (the wrench, the maul, the
## shotgun up close) do full damage, and during the punish window one from behind counts as a vent hit.
## With `throw_phase` (wave 6, M2-B14's ranged phase) it also lobs dirt clods (thumper_clod, with a chalk
## circle) at a farmer who keeps out of slam range, from the start: one every CLOD_PERIOD, and every
## CLOD_PERIOD_HURT once it is below half health.

const AUTHORED_WINDUP: float = 1.2
const AUTHORED_RECOVERY: float = 2.5
const VENT_MULTIPLIER: float = 2.0
const VENT_OPEN_MULTIPLIER: float = 3.0
const CLOD_PERIOD: float = 4.5
const CLOD_PERIOD_HURT: float = 2.5
## Hits from farther than this count as ranged against an authored Foreman's plates.
const PLATE_RANGE: float = 6.0
const PLATED_SHARE: float = 0.3
## A ranged hit this close to the open vent gets past the plates.
const VENT_HIT_RADIUS: float = 0.9
## A hit from this close, behind it, during the punish window counts as a vent hit. Pressed against its back
## the wrench's swing passes under the vent box and lands on the body (tests/unit/test_foreman_melee.gd).
const BACK_WHACK_RANGE: float = 3.5
const BACK_WHACK_HALF_ANGLE: float = 70.0
## The clods are for a farmer who keeps away; one this close gets slammed instead.
const CLOD_MIN_RANGE: float = 6.0

## Set by the WaveDirector before the robot enters the tree.
var authored: bool = false
var throw_phase: bool = false

var _vent: Hurtbox = null
var _vent_glow: MeshInstance3D = null
var _vent_open: bool = false
var _clod: RangedAttack = null
var _clod_wait: float = 0.0
var _phase_called: bool = false
var _clods_called: bool = false
var _plates_called: bool = false


func _ready() -> void:
	super._ready()
	_vent = get_node_or_null(^"Model/VentHurtbox") as Hurtbox
	if authored:
		_build_vent_glow()
	if throw_phase:
		_make_clod_throw()


func windup_time() -> float:
	return AUTHORED_WINDUP if authored else super.windup_time()


func recover_time() -> float:
	return AUTHORED_RECOVERY if authored else super.recover_time()


func _on_windup_started() -> void:
	Fx.puff(self, global_position + Vector3.UP * 0.2, Color(0.8, 0.75, 0.65), 0.6, 0.3)


func _on_recover_started() -> void:
	if authored:
		_set_vent_open(true)


func _ai_step(delta: float) -> Vector3:
	var desired := super._ai_step(delta)
	if _vent_open and ai_state != AiState.RECOVER:
		_set_vent_open(false)
	_update_clod_phase(delta)
	return desired


## An authored Foreman's plates: a ranged hit that misses the open vent does PLATED_SHARE of its damage. A
## close hit from behind while the vent is open is a vent hit, so the wrench alone can win the fight.
func take_damage(packet: DamagePacket) -> void:
	if back_whack(packet):
		packet.amount *= VENT_OPEN_MULTIPLIER
		packet.is_weak_point = true
	elif plated_hit(packet):
		packet.amount *= PLATED_SHARE
		Fx.puff(self, packet.position, RobotFactory.METAL, 0.2, 0.12)
		Fx.callout(self, packet.position, "PLATED", Color(0.75, 0.8, 0.85), 32)
		if not _plates_called and SaveManager.first_time("foreman_plates"):
			_plates_called = true
			EventBus.hud_message.emit("Its plates shrug off shots from range! Get in close and hit the vent.", 4.0)
	super.take_damage(packet)


## True when `packet` is a hit the plates blunt: an authored Foreman, hit from farther than PLATE_RANGE, and
## not in the open vent.
func plated_hit(packet: DamagePacket) -> bool:
	if not authored or not is_foreman or not is_instance_valid(packet.source) or not packet.source is Node3D:
		return false
	var from := (packet.source as Node3D).global_position - global_position
	from.y = 0.0
	if from.length() <= PLATE_RANGE:
		return false
	if not _vent_open or _vent == null:
		return true
	var shape := _vent.get_node_or_null(^"Shape") as Node3D
	var vent_at := shape.global_position if shape != null else _vent.global_position
	return packet.position.distance_to(vent_at) > VENT_HIT_RADIUS


## True when `packet` is a body hit from within BACK_WHACK_RANGE behind an authored Foreman whose vent is open.
func back_whack(packet: DamagePacket) -> bool:
	if not authored or not is_foreman or not _vent_open or packet.is_weak_point:
		return false
	if not is_instance_valid(packet.source) or not packet.source is Node3D:
		return false
	var from := (packet.source as Node3D).global_position - global_position
	from.y = 0.0
	if from.length() > BACK_WHACK_RANGE or from.length_squared() < 0.0001:
		return false
	var back := model.global_basis.z
	back.y = 0.0
	return back.normalized().dot(from.normalized()) >= cos(deg_to_rad(BACK_WHACK_HALF_ANGLE))


## True while the authored punish window is open (the vent glows and takes x3).
func vent_open() -> bool:
	return _vent_open


func _set_vent_open(open: bool) -> void:
	_vent_open = open
	if _vent != null:
		_vent.damage_multiplier = VENT_OPEN_MULTIPLIER if open else VENT_MULTIPLIER
	if _vent_glow != null:
		var material := _vent_glow.material_override as StandardMaterial3D
		if material != null:
			material.emission_energy_multiplier = 2.5 if open else 0.6
			material.albedo_color = Color(1.0, 0.45, 0.1, 1.0) if open else Color(0.5, 0.25, 0.08)


func _deal_hit() -> void:
	super._deal_hit()
	if archetype.shockwave_damage > 0.0:
		var ground := global_position
		var wave_ring := Shockwave.new()
		wave_ring.damage = archetype.shockwave_damage * damage_multiplier
		wave_ring.max_radius = archetype.shockwave_radius
		wave_ring.duration = archetype.shockwave_time
		wave_ring.source = self
		get_tree().current_scene.add_child(wave_ring)
		wave_ring.global_position = Vector3(ground.x, ground.y + 0.05, ground.z)
		FarmerCamera.shake_at(ground, 0.3, 4.0, 25.0)


func _windup_pose_scale() -> Vector3:
	return Vector3(0.92, 1.15, 0.92)


# --- The clod-throw phase ---------------------------------------------------------------------------

func _make_clod_throw() -> void:
	var profile := load(AttackProfile.resource_path_for(&"thumper_clod")) as AttackProfile
	if profile == null:
		return
	var hand := RobotFactory.ARM_WEAPON + Vector3(0.0, 0.25, -0.2)
	var muzzle := make_muzzle(hand * type_scale(), profile.color, profile.projectile_radius * 1.2, "ClodCharge")
	_clod = make_ranged_attack(profile, muzzle, "ClodThrow")
	_clod.silo_fallback = false
	_clod.target_provider = _clod_target
	_clod.fired.connect(_on_clod_fired)


func _on_clod_fired() -> void:
	_clod_wait = CLOD_PERIOD_HURT if health.fraction() < 0.5 else CLOD_PERIOD
	if not _clods_called:
		_clods_called = true
		if SaveManager.first_time("foreman_clods"):
			EventBus.hud_message.emit("It throws dirt clods at anyone who keeps away! Watch for the chalk circles.", 4.0)


func _clod_target() -> Node3D:
	if _clod_wait > 0.0 or ai_state == AiState.WINDUP:
		return null
	var farmer := GameState.get_nearest_player(global_position)
	if farmer == null or not _is_living(farmer):
		return null
	var distance := farmer.global_position.distance_to(global_position)
	if distance < CLOD_MIN_RANGE or distance > _clod.profile.attack_range:
		return null
	return farmer


func _update_clod_phase(delta: float) -> void:
	if _clod == null:
		return
	_clod_wait = maxf(0.0, _clod_wait - delta)
	if health.fraction() < 0.5 and not _phase_called:
		_phase_called = true
		_clod_wait = minf(_clod_wait, CLOD_PERIOD_HURT)
		EventBus.hud_message.emit("The Foreman's angry: the clods come faster!", 3.0)
	if ai_state in [AiState.SEEK, AiState.RECOVER] or _clod.state != RangedAttack.State.READY:
		_clod.step(delta)


## A hot orange ring over the vent: the window to hit it.
func _build_vent_glow() -> void:
	if _vent == null:
		return
	var shape := _vent.get_node_or_null(^"Shape") as CollisionShape3D
	_vent_glow = MeshInstance3D.new()
	_vent_glow.name = "VentGlow"
	var plate := BoxMesh.new()
	plate.size = Vector3(0.78, 0.66, 0.08)
	_vent_glow.mesh = plate
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.45, 0.1)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.5, 0.1)
	material.emission_energy_multiplier = 2.5
	_vent_glow.material_override = material
	_vent_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.add_child(_vent_glow)
	_vent_glow.position = (shape.position if shape != null else Vector3(0.0, 1.74, 0.95)) + Vector3(0.0, 0.0, 0.22)
	material.emission_energy_multiplier = 0.6
	material.albedo_color = Color(0.5, 0.25, 0.08)
