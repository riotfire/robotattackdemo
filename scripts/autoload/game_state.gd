extends Node
## Current run state (GDD 18.2): wave, seeds, parts, registered players and the silo.
## Parts and unlocks are "persistent" for the session only; SaveManager arrives in M1 (GDD 14).
## Co-op rule (GDD 18.8): there is no player singleton. Players register here; robots ask for the nearest one.

const PART_KEYS: Array[StringName] = [&"al", &"cu", &"au", &"pc"]
const PART_NAMES: Dictionary[StringName, String] = {
	&"al": "Aluminium",
	&"cu": "Copper",
	&"au": "Gold",
	&"pc": "Power Cells",
}
const WAVES_PER_PHASE: int = 5

var run_seed: int = 0
## The wave currently being fought, or the next one during an intermission.
var wave: int = 0
var waves_survived: int = 0
## Wave the run started at (checkpoint starts, GDD 14.2). Runs from wave 1 count as Full Harvest.
var start_wave: int = 1
var is_game_over: bool = false
var game_over_reason: StringName = &""

## Banked the instant they're collected (GDD 12.3). Survives scene reloads.
var parts: Dictionary[StringName, int] = {&"al": 0, &"cu": 0, &"au": 0, &"pc": 0}
## Kept forever once earned (GDD 5.4). Stored as the free "travel.jetpack" pegboard node, so jetpack
## upgrades can require it.
var jetpack_unlocked: bool:
	get:
		return StatService.level_of(&"travel.jetpack") > 0
	set(value):
		StatService.grant(&"travel.jetpack", 1 if value else 0)
var god_mode: bool = false

var silo: Silo = null
var players: Array[Node3D] = []


func start_run(seed_value: int = -1) -> void:
	if seed_value < 0:
		seed_value = randi()
	run_seed = seed_value
	RngService.start_run(run_seed)
	wave = 0
	waves_survived = 0
	is_game_over = false
	game_over_reason = &""
	EventBus.run_started.emit(run_seed)


static func phase_of(wave_number: int) -> int:
	return floori(float(wave_number - 1) / WAVES_PER_PHASE) + 1


static func wave_in_phase(wave_number: int) -> int:
	return posmod(wave_number - 1, WAVES_PER_PHASE) + 1


func register_player(player: Node3D) -> void:
	if player in players:
		return
	players.append(player)
	EventBus.player_registered.emit(player)


func unregister_player(player: Node3D) -> void:
	players.erase(player)
	EventBus.player_unregistered.emit(player)


## Nearest living player to a point, or null.
func get_nearest_player(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for player in players:
		if not is_instance_valid(player) or (player.has_method("is_alive") and not player.call("is_alive")):
			continue
		var d := from.distance_squared_to(player.global_position)
		if d < best_distance:
			best_distance = d
			best = player
	return best


func add_parts(delta_parts: Dictionary) -> void:
	for key: StringName in delta_parts:
		if parts.has(key):
			parts[key] = maxi(0, parts[key] + int(delta_parts[key]))
	EventBus.parts_changed.emit(parts)


func unlock_jetpack() -> void:
	if jetpack_unlocked:
		return
	jetpack_unlocked = true
	EventBus.jetpack_unlocked.emit()


func trigger_game_over(reason: StringName) -> void:
	if is_game_over:
		return
	is_game_over = true
	game_over_reason = reason
	EventBus.game_over.emit(reason)
