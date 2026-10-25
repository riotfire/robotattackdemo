class_name Silo
extends StaticBody3D
## The main objective (GDD 3.3) and its crack/leak model (the CrackManager role in GDD 18.4).
##
## Every `crack_every_fraction` of max Structure lost opens a crack on a free socket, and that crack
## holds that much Structure in its repair pool. Hits near an open crack grow it Small -> Medium -> Large.
## Repairing drains a crack's pool back into Structure and closes the crack at 0. While all crack slots
## are full, further damage is added to the nearest crack's pool so it stays repairable.

const DAMAGE_STATES: PackedStringArray = ["Pristine", "Cracked", "Split", "Busted", "Critical"]

@export var max_structure: float = 1000.0
@export var max_grain: float = 1000.0
@export_range(0.01, 1.0) var crack_every_fraction: float = 0.1
@export var max_active_cracks: int = 10
## Bushels per second for Small, Medium, Large (GDD 3.3).
@export var leak_rates: PackedFloat32Array = [0.6, 1.2, 2.0]
## Nearby hits needed to grow Small -> Medium and Medium -> Large.
@export var hits_to_grow: PackedInt32Array = [3, 4]
@export var nearby_hit_radius: float = 2.5
## Chance a new crack opens in the height band the hit landed in (GDD 3.3, decision R-D3), so ground robots
## open low cracks and ranged and flying robots open high ones.
@export_range(0.0, 1.0) var hit_band_weight: float = 0.7
## How the rest is shared between the other bands: ground level, catwalk 1, catwalk 2.
@export var band_weights: PackedFloat32Array = [0.5, 0.3, 0.2]
## New cracks stay at ground level up to this wave while the player learns to repair (the opening plan).
@export var ground_only_until_wave: int = 2
@export var radius: float = 4.0
## Bushels per wave cleared (GDD 3.3); Harvest Helpers add to it.
@export var harvest_bonus: float = 40.0
@export var pristine_color: Color = Color(0.78, 0.2, 0.15)
@export var critical_color: Color = Color(0.3, 0.14, 0.12)

var structure: float = 0.0
var grain: float = 0.0

var _crack_counter: float = 0.0
var _cracks: Array[SiloCrack] = []
var _sockets: Array[Marker3D] = []
var _occupied: Dictionary[int, SiloCrack] = {}
## Average socket height of each band above the silo base; -1 for a band with no sockets.
var _band_heights: PackedFloat32Array = [-1.0, -1.0, -1.0]
var _body_material: ShaderMaterial

@onready var _cracks_root: Node3D = $Cracks
@onready var _sockets_root: Node3D = $CrackSockets
@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _chute: Marker3D = get_node_or_null(^"Chute") as Marker3D


func _ready() -> void:
	# Rivet Count and Bigger Silo raise the caps. Grain starts at the base 1000 and the Harvest Bonus
	# fills any extra capacity over the run (GDD 13.6).
	var base_grain := max_grain
	max_structure = StatService.get_stat(&"silo.max_structure", max_structure)
	max_grain = StatService.get_stat(&"silo.max_grain", max_grain)
	structure = max_structure
	grain = minf(base_grain, max_grain)
	for child in _sockets_root.get_children():
		if child is Marker3D:
			_sockets.append(child)
	_measure_bands()
	# Its own clay copy so the paint can darken with damage (GDD 3.3 damage states).
	_body_material = Clay.shared().duplicate() as ShaderMaterial
	_body_material.set_shader_parameter(&"albedo_color", pristine_color)
	_body_mesh.material_override = _body_material
	GameState.silo = self


func _exit_tree() -> void:
	if GameState.silo == self:
		GameState.silo = null


func _physics_process(delta: float) -> void:
	if GameState.is_game_over:
		return
	var leak := total_leak_rate()
	if leak > 0.0:
		grain = maxf(0.0, grain - leak * delta)
		if grain <= 0.0:
			GameState.trigger_game_over(&"grain")


func take_damage(packet: DamagePacket) -> void:
	if GameState.is_game_over or structure <= 0.0:
		return
	# Silo Plating (GDD 8.2).
	var reduced := packet.amount * (1.0 - clampf(StatService.get_stat(&"silo.damage_reduction", 0.0), 0.0, 0.9))
	var amount := minf(reduced, structure)
	if amount <= 0.0:
		return
	structure -= amount
	EventBus.silo_damaged.emit(amount, packet.position)

	var near := nearest_crack(packet.position, nearby_hit_radius)
	if near != null and near.register_hit(hits_to_grow):
		EventBus.crack_resized.emit(near)

	var threshold := max_structure * crack_every_fraction
	_crack_counter += amount
	var stop_chance := clampf(StatService.get_stat(&"silo.crack_stop_chance", 0.0), 0.0, 0.9)
	while _crack_counter >= threshold:
		# Crack Stoppers: the Structure still goes into an existing crack's pool, just without a new leak.
		var stopped := not _cracks.is_empty() and stop_chance > 0.0 \
				and RngService.stream(RngService.STREAM_SILO).randf() < stop_chance
		if not stopped and _cracks.size() < max_active_cracks and _open_crack(packet.position, threshold):
			_crack_counter -= threshold
		else:
			var target := near if near != null else nearest_crack(packet.position, INF)
			if target != null:
				target.pool += _crack_counter
				target.max_pool = maxf(target.max_pool, target.pool)
			_crack_counter = 0.0

	_update_damage_visual()
	if structure <= 0.0:
		GameState.trigger_game_over(&"silo")


## Level 0: the silo springs a leak on a given socket (a Small crack holding `pool_amount` Structure),
## so the first thing the farmer learns is that a crack costs Structure and Grain until it is patched.
func open_tutorial_crack(socket_index: int, pool_amount: float) -> SiloCrack:
	if socket_index < 0 or socket_index >= _sockets.size() or _occupied.has(socket_index):
		return null
	structure = maxf(0.0, max_structure - pool_amount)
	_open_crack_at(socket_index, pool_amount)
	_update_damage_visual()
	return _occupied.get(socket_index)


## Spends `seconds` of wrench time on a crack. Returns the Structure restored.
func repair_crack(crack: SiloCrack, seconds: float) -> float:
	if crack == null or not is_instance_valid(crack) or GameState.is_game_over:
		return 0.0
	var restored := crack.repair(seconds)
	structure = minf(max_structure, structure + restored)
	if crack.pool <= 0.0:
		_close_crack(crack)
	_update_damage_visual()
	return restored


func add_grain(amount: float) -> float:
	var before := grain
	grain = minf(max_grain, grain + amount)
	return grain - before


## A thief takes up to `amount` bushels (GDD 3.3). Returns what it got.
func steal_grain(amount: float) -> float:
	if GameState.is_game_over:
		return 0.0
	var taken := minf(amount, grain)
	grain -= taken
	if grain <= 0.0:
		GameState.trigger_game_over(&"grain")
	return taken


## Where thieves stand to grab a sack: `standoff` meters out from the grain chute.
func chute_position(standoff: float) -> Vector3:
	var at := _chute.global_position if _chute != null else global_position + Vector3.RIGHT * radius
	var out := at - global_position
	out.y = 0.0
	return global_position + out.normalized() * (radius + standoff)


func harvest_bonus_amount() -> float:
	return StatService.get_stat(&"silo.harvest_bonus", harvest_bonus)


func get_cracks() -> Array[SiloCrack]:
	return _cracks


func total_leak_rate() -> float:
	var total := 0.0
	for crack in _cracks:
		total += crack.leak_rate(leak_rates)
	# Leak Plugs: -8% per level (GDD 13.6).
	return total * maxf(0.0, StatService.get_stat(&"silo.leak_rate", 1.0))


func structure_fraction() -> float:
	return structure / max_structure


func grain_fraction() -> float:
	return grain / max_grain


## 0 Pristine ... 4 Critical (GDD 3.3 damage states).
func damage_state() -> int:
	var f := structure_fraction()
	if f > 0.8:
		return 0
	if f > 0.6:
		return 1
	if f > 0.4:
		return 2
	if f > 0.2:
		return 3
	return 4


func nearest_crack(at: Vector3, max_distance: float) -> SiloCrack:
	var best: SiloCrack = null
	var best_distance := max_distance
	for crack in _cracks:
		var d := crack.global_position.distance_to(at)
		if d <= best_distance:
			best_distance = d
			best = crack
	return best


## The point on the silo wall facing `from`, at the given height above the silo base.
func wall_point_toward(from: Vector3, height: float) -> Vector3:
	var flat := from - global_position
	flat.y = 0.0
	var dir := flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	return global_position + dir * radius + Vector3.UP * height


## Distance from a point to the silo wall, ignoring height.
func distance_to_wall(from: Vector3) -> float:
	var flat := from - global_position
	flat.y = 0.0
	return flat.length() - radius


## Returns false when no socket may take a new crack (all full, or no free ground socket early on).
func _open_crack(hit_position: Vector3, pool_amount: float) -> bool:
	var socket_index := _pick_socket(hit_position)
	_open_crack_at(socket_index, pool_amount)
	return socket_index >= 0


func _open_crack_at(socket_index: int, pool_amount: float) -> void:
	if socket_index < 0:
		return
	var socket := _sockets[socket_index]
	var crack := SiloCrack.new()
	crack.name = "Crack_%02d" % socket_index
	crack.setup(socket_index, int(socket.get_meta(&"band", 0)), pool_amount)
	_cracks_root.add_child(crack)
	crack.global_transform = socket.global_transform
	_cracks.append(crack)
	_occupied[socket_index] = crack
	EventBus.crack_opened.emit(crack)


func _close_crack(crack: SiloCrack) -> void:
	_cracks.erase(crack)
	_occupied.erase(crack.socket_index)
	EventBus.crack_closed.emit(crack)
	crack.queue_free()


## The height band (0 ground, 1 catwalk 1, 2 catwalk 2) whose sockets are nearest the height of `at`.
func hit_band(at: Vector3) -> int:
	var height := at.y - global_position.y
	var best := 0
	var best_gap := INF
	for band in 3:
		if _band_heights[band] >= 0.0 and absf(height - _band_heights[band]) < best_gap:
			best_gap = absf(height - _band_heights[band])
			best = band
	return best


## Picks a band by weight, then the free socket in that band that faces the hit most directly. The hit's
## own band gets hit_band_weight and the other bands share the rest by band_weights; only bands with a
## free socket count. Up to ground_only_until_wave, only ground sockets do. -1 when none is free.
func _pick_socket(hit_position: Vector3) -> int:
	var free_by_band: Array[Array] = [[], [], []]
	for i in _sockets.size():
		if not _occupied.has(i):
			var band := clampi(int(_sockets[i].get_meta(&"band", 0)), 0, 2)
			free_by_band[band].append(i)
	var bands := [0] if GameState.wave <= ground_only_until_wave else [0, 1, 2]
	var hit := hit_band(hit_position)
	var others := 0.0
	for band: int in bands:
		if band != hit and not free_by_band[band].is_empty():
			others += band_weights[band]
	var weights := PackedFloat32Array([0.0, 0.0, 0.0])
	var total_weight := 0.0
	for band: int in bands:
		if free_by_band[band].is_empty():
			continue
		if band == hit:
			weights[band] = hit_band_weight
		elif others > 0.0:
			weights[band] = (1.0 - hit_band_weight) * band_weights[band] / others
		total_weight += weights[band]
	if total_weight <= 0.0:
		# Only the hit's band is free and its weight is 0, or nothing is free.
		for band: int in bands:
			if not free_by_band[band].is_empty():
				weights[band] = 1.0
				total_weight += 1.0
		if total_weight <= 0.0:
			return -1
	var rng := RngService.stream(RngService.STREAM_SILO)
	var roll := rng.randf() * total_weight
	var chosen_band := -1
	for band: int in bands:
		if weights[band] <= 0.0:
			continue
		chosen_band = band
		roll -= weights[band]
		if roll <= 0.0:
			break
	var hit_dir := hit_position - global_position
	hit_dir.y = 0.0
	var best := -1
	var best_dot := -INF
	for i: int in free_by_band[chosen_band]:
		var socket_dir := _sockets[i].global_position - global_position
		socket_dir.y = 0.0
		var d := socket_dir.normalized().dot(hit_dir.normalized())
		if d > best_dot:
			best_dot = d
			best = i
	return best


func _measure_bands() -> void:
	var sums := PackedFloat32Array([0.0, 0.0, 0.0])
	var counts := PackedInt32Array([0, 0, 0])
	for socket in _sockets:
		var band := clampi(int(socket.get_meta(&"band", 0)), 0, 2)
		sums[band] += socket.global_position.y - global_position.y
		counts[band] += 1
	for band in 3:
		_band_heights[band] = sums[band] / counts[band] if counts[band] > 0 else -1.0


func _update_damage_visual() -> void:
	if _body_material != null:
		_body_material.set_shader_parameter(&"albedo_color", critical_color.lerp(pristine_color, structure_fraction()))
