class_name WaveDirector
extends Node
## The wave loop (GDD 11.1): Intermission (90 s; the siren winds up for its last 3 s) -> Spawning -> Mop-up
## -> Cleared -> next Intermission. Each wave's threat budget (GDD 11.4) is spent over its spawn window
## (GDD 11.3) in a ramp-peak-lull-peak shape, from 2-5 lanes picked by the wave seed (GDD 11.6).
## Each wave rolls one robot family (RobotGenome, GDD 10) at the siren. Spawns are bought by type weight
## (Scout 55%, Grunt 35%, Heavy 10% with a per-wave cap, GDD 9.1); each spawn then rolls its archetype's
## trio chance (GDD 9.6) and costs its threat per robot x group size (GDD 11.4). Every Big Haul wave adds a
## Foreman (GDD 11.2). From wave 6 the attack grid's columns (melee, ranged, flight) get their own spawn
## shares (DifficultyCurve.column_weights); from wave 7 a share of small ground melee spawns come as
## Spitters instead (DifficultyCurve.spitter_share, M2-B9, B10).
## Authoritative: in co-op this runs on the host only (GDD 18.8).
## A first run opens with Level 0 "Morning Chores" (TUTORIAL): no clock runs until the dinner bell is rung,
## and TutorialDirector teaches the farm with pictures in the meantime.

## TUTORIAL comes last so the other phases keep their numbers.
enum Phase { INTERMISSION, SIREN, SPAWNING, MOP_UP, CLEARED, GAME_OVER, TUTORIAL }

const GROUP: StringName = &"wave_director"

const PHASE_NAMES: PackedStringArray = ["Intermission", "Siren", "Attack", "Mop-up", "Cleared", "Game over", "Morning chores"]

@export var curve: DifficultyCurve
@export var archetypes: Array[RobotArchetype] = []
## The Heavy that debuts as the Big Haul Foreman. M1 only has the melee class, so it's always the
## Thumper; the Boiler and Longneck take over at waves 10 and 15 once they exist (GDD 11.2).
@export var foreman_archetype: RobotArchetype
## The Spitter: a role of the small ground melee robot, not picked on its own. A spawn that picks a small
## melee archetype becomes a Spitter group with chance DifficultyCurve.spitter_share (M2-B9).
@export var spitter_archetype: RobotArchetype
@export var gene_library: GeneLibrary
@export var robots_parent: Node3D
## Spawn-event weights by RobotArchetype.RobotType (GDD 9.1).
@export var type_weights: PackedFloat32Array = [0.55, 0.35, 0.10]
## The Foreman arrives at this fraction of the spawn window.
@export var foreman_spawn_at: float = 0.45
## GDD target is 30 s (ROADMAP D1). Builds keep 90 s until the Hub pegboard and pinned-goals
## quick-buy land (M2-H3, M2-G1). Try other lengths with the console's `intermission <s>`.
@export var intermission_time: float = 90.0
@export var siren_lead_time: float = 3.0
## Pause on the "Cleared" jingle before the next intermission starts.
@export var cleared_hold_time: float = 2.0
## Mop-up seconds before the last robots get a see-through marker (GDD 9.6).
@export var straggler_time: float = 20.0
## Live robot cap; extra spawns wait in the queue (GDD 11.4: 60 on PC, 40 on Steam Deck).
@export var live_robot_cap: int = 60
## Wave progression and early-bird settings (GDD 2.4, 5.4).
## Early Bird bonus for ringing the bell early: Al per second skipped x (1 + wave / 10) (GDD 11.1).
@export var early_bird_al_per_second: float = 1.0

var phase: Phase = Phase.INTERMISSION
## Aluminium the dinner bell pays for finishing Level 0's chores (set by TutorialDirector).
var tutorial_bonus_al: int = 0
var wave: int = 0
## Countdown for Intermission, Siren and Cleared.
var time_left: float = 0.0
var spawn_clock: float = 0.0
var spawn_window: float = 0.0
var spawns_total: int = 0
var spawns_done: int = 0
var mop_up_time: float = 0.0
var active_lanes: PackedInt32Array = PackedInt32Array()
## This wave's robot family; rolled at the siren.
var genome: RobotGenome = null
var genome_history: Array[RobotGenome] = []

var _running: bool = false
var _schedule: PackedFloat32Array = PackedFloat32Array()
var _events: Array[SpawnEvent] = []
var _wave_rng: RandomNumberGenerator
var _lanes: Dictionary[int, LaneMarker] = {}
var _stragglers_marked: bool = false


## One spawn: a single robot, a trio, or the Foreman. Authored waves can set the group size directly.
class SpawnEvent:
	var archetype: RobotArchetype
	var foreman: bool
	var group_size: int

	func _init(robot_archetype: RobotArchetype, is_foreman: bool = false, size: int = 1) -> void:
		archetype = robot_archetype
		foreman = is_foreman
		group_size = size

	func robot_count() -> int:
		return 1 if foreman else maxi(1, group_size)

	func threat_cost() -> float:
		return archetype.threat_cost() * robot_count()


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.game_over.connect(_on_game_over)


## `tutorial` opens with Level 0 instead of the first intermission.
func start_run(tutorial: bool = false) -> void:
	_lanes.clear()
	for node in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		var lane := node as LaneMarker
		_lanes[lane.lane_index] = lane
	_running = true
	_set_wave(1)
	if tutorial:
		_enter_tutorial()
	else:
		_enter_intermission(intermission_time)


func _physics_process(delta: float) -> void:
	if not _running:
		return
	match phase:
		Phase.INTERMISSION:
			time_left -= delta
			if time_left <= siren_lead_time:
				_enter_siren(time_left)
		Phase.SIREN:
			time_left -= delta
			if time_left <= 0.0:
				_enter_spawning()
		Phase.SPAWNING:
			spawn_clock += delta
			_spawn_due()
			if spawn_clock >= spawn_window:
				_set_phase(Phase.MOP_UP)
		Phase.MOP_UP:
			spawn_clock += delta
			mop_up_time += delta
			_spawn_due()
			var live := live_robot_count()
			Robot.hive_period = 4 if live <= 3 else (8 if live <= 8 else 12)
			if spawns_done >= spawns_total and live_robot_count() == 0:
				_enter_cleared()
			elif mop_up_time >= straggler_time and not _stragglers_marked:
				_mark_stragglers()
		Phase.CLEARED:
			time_left -= delta
			if time_left <= 0.0:
				_set_wave(wave + 1)
				_enter_intermission(intermission_time)


# --- Phases ---------------------------------------------------------------------------------------

func _enter_intermission(duration: float) -> void:
	time_left = duration
	Robot.hive_period = 12
	_set_lanes_active(false)
	_set_phase(Phase.INTERMISSION)


func _enter_tutorial() -> void:
	time_left = 0.0
	Robot.hive_period = 12
	_set_lanes_active(false)
	_set_phase(Phase.TUTORIAL)


## Level 0 is over: wave 1's siren winds up (bonus Al is the tutorial's Early Bird reward).
func finish_tutorial(bonus_al: int = 0) -> void:
	if phase != Phase.TUTORIAL:
		return
	# Ringing the bell early skips the lesson but must still leave the farmer able to fight wave 1.
	if not StatService.has_flag(&"wrench.owned"):
		StatService.grant(&"attack.wrench")
	if bonus_al > 0:
		GameState.add_parts({&"al": bonus_al})
	SaveManager.tutorial_completed = true
	SaveManager.save_profile()
	_enter_siren(siren_lead_time)
	EventBus.tutorial_finished.emit()


func _enter_siren(remaining: float) -> void:
	time_left = remaining
	_wave_rng = RngService.wave_stream(RngService.STREAM_SPAWNS, wave)
	active_lanes = _pick_lanes(curve.lane_count(wave))
	_roll_family()
	_set_lanes_active(true)
	_set_phase(Phase.SIREN)
	EventBus.siren_started.emit(wave, active_lanes)
	var lane_names := PackedStringArray()
	for lane in active_lanes:
		lane_names.append(str(lane))
	var haul := "  BIG HAUL!" if curve.is_big_haul(wave) else ""
	EventBus.hud_message.emit("INCOMING! Wave %d from lanes %s%s" % [wave, ", ".join(lane_names), haul], 4.0)


## The wave's family name card (GDD 10.2): rolled once per wave, logged in the Almanac.
func _roll_family() -> void:
	if gene_library == null or (genome != null and genome.wave == wave):
		return
	genome = RobotGenome.roll(GameState.run_seed, wave, gene_library, genome_history, curve)
	genome_history.append(genome)
	SaveManager.log_family(genome.family_code, genome.family_name, wave)
	EventBus.family_revealed.emit(genome)


func _enter_spawning() -> void:
	spawn_window = curve.spawn_window(wave)
	_events = _build_spawn_events(wave)
	_schedule = curve.spawn_schedule(_events.size(), spawn_window * curve.spawn_window_fraction)
	if curve.is_big_haul(wave) and foreman_archetype != null:
		var at := spawn_window * foreman_spawn_at
		var index := _schedule.bsearch(at)
		_schedule.insert(index, at)
		_events.insert(index, SpawnEvent.new(foreman_archetype, true))
	spawns_total = _events.size()
	spawns_done = 0
	spawn_clock = 0.0
	mop_up_time = 0.0
	_stragglers_marked = false
	_set_phase(Phase.SPAWNING)
	EventBus.wave_started.emit(wave)


func _enter_cleared() -> void:
	time_left = cleared_hold_time
	GameState.waves_survived = maxi(GameState.waves_survived, wave)
	var grain_added := 0.0
	if GameState.silo != null:
		grain_added = GameState.silo.add_grain(GameState.silo.harvest_bonus_amount())
	var vacuumed := _scrap_vac()
	_set_lanes_active(false)
	_set_phase(Phase.CLEARED)
	EventBus.wave_cleared.emit(wave)
	var vac_text := "   Scrap Vac +%d parts" % vacuumed if vacuumed > 0 else ""
	EventBus.hud_message.emit("Wave %d cleared!  Harvest +%d grain%s" % [wave, roundi(grain_added), vac_text], 3.0)
func _on_game_over(_reason: StringName) -> void:
	_running = false
	_set_phase(Phase.GAME_OVER)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	EventBus.wave_phase_changed.emit(phase, wave)


func _set_wave(new_wave: int) -> void:
	wave = new_wave
	GameState.wave = new_wave


# --- Spawning -------------------------------------------------------------------------------------

## Buys spawn events with the wave's threat budget: unlocked, affordable archetypes picked by type
## weight, with a per-wave cap on Heavies. Seeded, so every peer builds the same list.
func _build_spawn_events(wave_number: int) -> Array[SpawnEvent]:
	var available: Array[RobotArchetype] = []
	for archetype in archetypes:
		if archetype != null and archetype.unlock_wave <= wave_number:
			available.append(archetype)
	var events: Array[SpawnEvent] = []
	var budget := curve.threat_budget(wave_number)
	var heavies := 0
	var heavy_cap := heavy_cap_for(wave_number)
	var rooftop_count := 0
	var drone_count := 0
	# Give each new vertical threat a guaranteed introduction on its unlock wave.
	for archetype in available:
		if wave_number == archetype.unlock_wave \
				and (archetype.id == &"roof_lobber" or archetype.id == &"drone"):
			if archetype.threat_cost() <= budget:
				events.append(SpawnEvent.new(archetype))
				budget -= archetype.threat_cost()
				if archetype.id == &"roof_lobber":
					rooftop_count += 1
				else:
					drone_count += 1
	while not available.is_empty():
		var options: Array[RobotArchetype] = []
		var total_weight := 0.0
		for archetype in available:
			var is_heavy := archetype.robot_type == RobotArchetype.RobotType.HEAVY
			var at_cap := (archetype.id == &"roof_lobber" and rooftop_count >= rooftop_cap_for(wave_number)) \
					or (archetype.id == &"drone" and drone_count >= (1 if wave_number < 8 else 3))
			if archetype.threat_cost() <= budget + 0.001 and not (is_heavy and heavies >= heavy_cap) and not at_cap:
				options.append(archetype)
		if options.is_empty():
			break
		var weights := option_weights(options, wave_number)
		for weight in weights:
			total_weight += weight
		var roll := _wave_rng.randf() * total_weight
		var pick := options[options.size() - 1]
		for i in options.size():
			roll -= weights[i]
			if roll <= 0.0:
				pick = options[i]
				break
		pick = roll_role(wave_number, pick, budget)
		var event := SpawnEvent.new(pick, false, roll_group_size(wave_number, pick, budget))
		events.append(event)
		budget -= event.threat_cost()
		if pick.robot_type == RobotArchetype.RobotType.HEAVY:
			heavies += 1
		if pick.id == &"roof_lobber":
			rooftop_count += event.robot_count()
		elif pick.id == &"drone":
			drone_count += event.robot_count()
	return events


## Each option's pick weight: its type weight x spawn_weight (GDD 9.1). From wave 6 these are rescaled so
## each attack-grid column present among the options gets its DifficultyCurve.column_weights share.
func option_weights(options: Array[RobotArchetype], wave_number: int) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	var column_totals := PackedFloat32Array([0.0, 0.0, 0.0])
	for archetype in options:
		var weight := type_weights[int(archetype.robot_type)] * archetype.spawn_weight
		weights.append(weight)
		column_totals[int(archetype.robot_class)] += weight
	var shares := curve.column_weights(wave_number)
	if shares.size() < 3:
		return weights
	var present := 0.0
	for column in 3:
		if column_totals[column] > 0.0:
			present += shares[column]
	if present <= 0.0:
		return weights
	for i in options.size():
		var column := int(options[i].robot_class)
		weights[i] = weights[i] / column_totals[column] * shares[column] / present
	return weights


## A small ground melee pick becomes a Spitter with chance DifficultyCurve.spitter_share (from wave 7), if
## the budget covers one. Rolled from the wave's spawn stream only when the share is above 0, so earlier
## waves build the same spawns as before.
func roll_role(wave_number: int, pick: RobotArchetype, budget: float) -> RobotArchetype:
	if spitter_archetype == null or pick.robot_type != RobotArchetype.RobotType.SCOUT \
			or pick.robot_class != RobotArchetype.RobotClass.MELEE:
		return pick
	var share := curve.spitter_share(wave_number)
	if share <= 0.0 or _wave_rng.randf() >= share or spitter_archetype.threat_cost() > budget + 0.001:
		return pick
	return spitter_archetype


## 3 when this spawn rolls a trio (GDD 9.6) and the budget still covers three, otherwise 1. Rolled from
## the wave's spawn stream, so every peer builds the same groups.
func roll_group_size(wave_number: int, archetype: RobotArchetype, budget: float) -> int:
	var chance := curve.trio_chance(wave_number, archetype)
	if chance <= 0.0:
		return 1
	var trio := _wave_rng.randf() < chance
	return 3 if trio and archetype.threat_cost() * 3.0 <= budget + 0.001 else 1


## Roof Lobbers per wave beyond their guaranteed debut. Wave 4 leans on the rooftops: each Lobber costs more
## threat than a ground robot, so more of them means fewer robots on the ground in that wave.
static func rooftop_cap_for(wave_number: int) -> int:
	if wave_number == 4:
		return 3
	return 1 if wave_number < 10 else 2


## Regular Heavies per wave (the Foreman doesn't count): 1, plus 1 every 8 waves.
static func heavy_cap_for(wave_number: int) -> int:
	return 1 + floori(maxf(0.0, wave_number - 6.0) / 8.0)


func _pick_lanes(count: int) -> PackedInt32Array:
	var ids: Array[int] = []
	ids.assign(_lanes.keys())
	ids.sort()
	for i in range(ids.size() - 1, 0, -1):
		var j := _wave_rng.randi_range(0, i)
		var swap := ids[i]
		ids[i] = ids[j]
		ids[j] = swap
	var picked := PackedInt32Array(ids.slice(0, mini(count, ids.size())))
	picked.sort()
	return picked


func _spawn_due() -> void:
	while spawns_done < spawns_total and _schedule[spawns_done] <= spawn_clock and live_robot_count() < live_robot_cap:
		_spawn_event(_events[spawns_done])
		spawns_done += 1


## Spawns one event in one lane. Squads share a lane and start in a triangle (GDD 11.6).
func _spawn_event(event: SpawnEvent) -> void:
	if active_lanes.is_empty() or robots_parent == null:
		return
	var lane := _lanes[active_lanes[_wave_rng.randi_range(0, active_lanes.size() - 1)]]
	var center := lane.spawn_position(_wave_rng.randf_range(-1.0, 1.0))
	var count := event.robot_count()
	var squad := RobotSquad.new() if count > 1 else null
	var bonus: Array[RobotTrait] = []
	if event.foreman and gene_library != null and genome != null:
		bonus = gene_library.pick_traits(_wave_rng, 1, genome.traits)
	var type_scale := RobotFactory.TYPE_SCALES[int(event.archetype.robot_type)]
	for i in count:
		var offset := lane.global_basis * RobotSquad.formation_offset(i, type_scale)
		_spawn_robot(event.archetype, center + offset, event.foreman, bonus, squad)
	if event.foreman:
		EventBus.hud_message.emit("FOREMAN INCOMING: %s!" % _last_foreman_title(), 3.0)


func _spawn_robot(archetype: RobotArchetype, where: Vector3, foreman: bool, bonus: Array[RobotTrait], squad: RobotSquad) -> void:
	var map := robots_parent.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		where = NavigationServer3D.map_get_closest_point(map, where)
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, wave, curve, _wave_rng, genome, foreman, bonus, squad)
	robot.position = robots_parent.to_local(where) + Vector3.UP * 0.1
	robots_parent.add_child(robot)
	robot.reset_physics_interpolation()


func _last_foreman_title() -> String:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		var robot := node as Robot
		if robot.is_foreman:
			return robot.foreman_title
	return "the Foreman"


## Scrap Vac (GDD 11.1, 13.8): banks a share of the parts left lying around and clears them.
func _scrap_vac() -> int:
	var fraction := minf(1.0, StatService.get_stat(&"pickups.scrap_vac", 0.5))
	var rng := RngService.stream(RngService.STREAM_DROPS)
	var banked := 0
	for node in get_tree().get_nodes_in_group(Pickup.GROUP):
		banked += (node as Pickup).vacuum(fraction, rng)
	return banked


func _set_lanes_active(active: bool) -> void:
	for id in _lanes:
		_lanes[id].set_active(active and id in active_lanes)


func _mark_stragglers() -> void:
	_stragglers_marked = true
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		(node as Robot).mark_straggler()


func live_robot_count() -> int:
	return get_tree().get_nodes_in_group(Robot.GROUP).size()


## Robots still waiting to spawn this wave.
func robots_to_come() -> int:
	if phase not in [Phase.SPAWNING, Phase.MOP_UP]:
		return 0
	var count := 0
	for i in range(spawns_done, spawns_total):
		count += _events[i].robot_count()
	return count


# --- Debug and "ring the bell" ----------------------------------------------------------------------

## Skips the rest of the intermission (GDD 11.1 "Ring the bell early"), paying the Early Bird bonus.
func ring_bell() -> void:
	if phase == Phase.TUTORIAL:
		finish_tutorial(tutorial_bonus_al)
	elif phase == Phase.INTERMISSION:
		var skipped := maxf(0.0, time_left - siren_lead_time)
		var bonus := floori(skipped * early_bird_al_per_second * (1.0 + wave / 10.0)
				* StatService.get_stat(&"economy.early_bird", 1.0))
		if bonus > 0:
			GameState.add_parts({&"al": bonus})
			EventBus.hud_message.emit("Early Bird! +%d Aluminium" % bonus, 2.0)
		_enter_siren(siren_lead_time)
	elif phase == Phase.SIREN:
		time_left = 0.0


## Debug: drop the current wave and go straight to the siren for wave n.
func skip_to_wave(n: int) -> void:
	if not _running:
		return
	clear_robots(false)
	GameState.waves_survived = maxi(GameState.waves_survived, n - 1)
	_set_wave(maxi(1, n))
	_events.clear()
	spawns_total = 0
	spawns_done = 0
	_enter_siren(siren_lead_time)


func clear_robots(award_drops: bool) -> void:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		(node as Robot).kill(award_drops)


func phase_name() -> String:
	return PHASE_NAMES[phase]
