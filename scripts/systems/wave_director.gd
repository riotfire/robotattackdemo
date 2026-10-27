class_name WaveDirector
extends Node
## The wave loop (GDD 11.1): Intermission (90 s; the siren winds up for its last 3 s) -> Spawning -> Mop-up
## -> Cleared -> next Intermission. A wave clears as soon as nothing is left to come and nothing is alive,
## so an emptied attack never waits out a timer (FIRST_FIVE_WAVES_FUN_PLAN.md P1).
## Phases are 3 waves (PHASE_CHECKPOINT_PROGRESSION_PLAN.md): Lesson, Twist, Big Haul with the Foreman. A
## loss restarts the first wave of its phase with parts and upgrades kept (SaveManager.resume_wave).
##
## Waves 1-6 are the authored opening (OpeningWave, data/opening): fixed groups released by time or after an
## earlier group is beaten, a live cap, named roofs for the Lobbers, a 450 HP first Foreman whose defeat calls
## off the adds still to come, and one-time debut captions. Only the cosmetics and the actual lanes are seeded.
## From wave 7 each wave's threat budget (GDD 11.4) is spent over its spawn window (GDD 11.3) in a ramp-peak-
## lull-peak shape, from 2-5 lanes picked by the wave seed (GDD 11.6). Spawns are bought by type weight
## (Scout 55%, Grunt 35%, Heavy 10% with a per-wave cap, GDD 9.1); each then rolls its archetype's trio chance
## (GDD 9.6) and costs its threat per robot x group size. Every Big Haul adds a Foreman (GDD 11.2). Budget
## reservation makes roughly 25% of individual robots climbers: Roof Lobbers, and from wave 7 also Rung Runners
## for the silo ladder. The other picks use the attack grid's column weights; caps keep drones scarce. From
## wave 13 a share of small ground melee spawns come as Spitters (M2-B9, B10).
## Each wave rolls one robot family (RobotGenome, GDD 10) at the siren.
## Authoritative: in co-op this runs on the host only (GDD 18.8).
## A first run opens with Level 0 "Morning Chores" (TUTORIAL): no clock runs until the dinner bell is rung,
## and TutorialDirector teaches the farm with pictures in the meantime.

## TUTORIAL comes last so the other phases keep their numbers.
enum Phase { INTERMISSION, SIREN, SPAWNING, MOP_UP, CLEARED, GAME_OVER, TUTORIAL }

const GROUP: StringName = &"wave_director"

const PHASE_NAMES: PackedStringArray = ["Intermission", "Siren", "Attack", "Mop-up", "Cleared", "Game over", "Morning chores"]

## Where each lane comes from, by the landmark beside it (FIRST_FIVE_WAVES_FUN_PLAN.md: bearings tied to
## visible landmarks rather than lane numbers).
const LANE_NAMES: Dictionary[int, String] = {
	1: "the north, by the barn", 2: "the north, by the stables", 3: "the east, by the chicken coop",
	4: "the east, by the well", 5: "the south, by the water tower", 6: "the south, by the porch",
	7: "the west, by the house", 8: "the west, by the tool shed",
}
## Seconds before a raid group's release that its lane lights up and the HUD calls it.
const RAID_WARNING: float = 3.0
## Debut captions, shown once per profile (SaveManager.first_time) when an authored group with that intro arrives.
const INTROS: Dictionary[StringName, String] = {
	&"clanker": "NEW: Clankers. Tough and slow, and they come in pairs. Keep swinging, or buy the Rivet Pistol at the shed to soften them up from range.",
	&"thief": "A THIEF! The Nibbler with the $ is after a grain sack. Pop it before it reaches the corn.",
	&"foreman": "THE FOREMAN! Its plates shrug off shots from range. Watch it rear up, step out of the slam, then whack the glowing vent on its back.",
	&"roof_lobber": "NEW: a Roof Lobber is climbing the tool shed. Hop up the rain barrel and crates after it and bonk it.",
	&"rung_runner": "NEW: a Rung Runner is climbing the SILO LADDER! Shoot it on the rungs, meet it on the catwalk, or let a spring throw it off.",
	&"foreman_throws": "This Foreman throws dirt clods at anyone who keeps away, faster once it's hurt. Watch for the chalk circles and get in close.",
}
const OPENING_PATH := "res://data/opening/wave_%d.tres"

@export var curve: DifficultyCurve
@export var archetypes: Array[RobotArchetype] = []
## The Heavy that debuts as the Big Haul Foreman. M1 only has the melee class, so it's always the
## Thumper; the Boiler and Longneck take over once they exist (GDD 11.2, M2-B14).
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
## Preparation between waves, siren included. 90 s, so there is time to walk to the shed to shop, build
## defenses where you want them and get back (playtest feedback 2026-10-26: shopping from a menu anywhere took
## the fun out of crossing the farm). The dinner bell rings it early. Try other lengths with the console's
## `intermission <s>`.
@export var intermission_time: float = 90.0
@export var siren_lead_time: float = 3.0
## Pause on the "Cleared" jingle before the next intermission starts.
@export var cleared_hold_time: float = 2.0
## Mop-up seconds before the last robots get a see-through marker (GDD 9.6).
@export var straggler_time: float = 20.0
## Live robot cap; extra spawns wait in the queue (GDD 11.4: 60 on PC, 40 on Steam Deck).
@export var live_robot_cap: int = 60
## Ready is a small reward for clearing the wave, independent of skipped time or timer settings. It pays only
## for a wave above the profile's best, so a cheap retry can't farm it (PHASE_CHECKPOINT_PROGRESSION_PLAN.md).
@export var early_bird_base_al: float = 5.0
## Predictable rare progress before the first walls. Legitimate repeat attempts can earn it again.
@export var salvage_reward_interval: int = 2
@export var salvage_clear_parts: Dictionary[StringName, int] = {&"cu": 2, &"au": 1, &"pc": 1}
## Play the authored opening (data/opening) for waves 1 to curve.opening_last_wave.
@export var use_authored_opening: bool = true

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
## The authored wave being played, or null for a generated one.
var opening: OpeningWave = null

var _running: bool = false
var _schedule: PackedFloat32Array = PackedFloat32Array()
var _events: Array[SpawnEvent] = []
var _wave_rng: RandomNumberGenerator
var _lanes: Dictionary[int, LaneMarker] = {}
var _stragglers_marked: bool = false
var _ready_bonus_wave: int = 0
var _settled_clear_waves: Dictionary[int, bool] = {}
## Authored waves: one entry per OpeningGroup, and the lane each slot uses this wave.
var _groups: Array[GroupState] = []
var _slot_lanes: PackedInt32Array = PackedInt32Array()
var _openings: Dictionary[int, OpeningWave] = {}


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


## An authored group's progress through one wave.
class GroupState:
	var group: OpeningGroup
	var released: bool = false
	var cancelled: bool = false
	var warned: bool = false
	var robots: Array[Robot] = []
	## Attack-clock time its robots were all gone, or -1.
	var resolved_at: float = -1.0

	func _init(opening_group: OpeningGroup) -> void:
		group = opening_group

	func done() -> bool:
		return released or cancelled

	func alive() -> int:
		var count := 0
		for robot in robots:
			if is_instance_valid(robot) and robot.ai_state != Robot.AiState.DEAD:
				count += 1
		return count


func _ready() -> void:
	add_to_group(GROUP)
	EventBus.game_over.connect(_on_game_over)
	EventBus.robot_destroyed.connect(_on_robot_destroyed)


## `tutorial` opens with Level 0 instead of the first intermission. `start_wave` is the phase checkpoint the
## run starts from: the waves before it count as cleared for this run's records.
func start_run(tutorial: bool = false, start_wave: int = 1) -> void:
	_ready_bonus_wave = 0
	_settled_clear_waves.clear()
	_lanes.clear()
	if curve != null:
		GameState.curve = curve
	_load_opening()
	for node in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		var lane := node as LaneMarker
		_lanes[lane.lane_index] = lane
	_running = true
	var first := 1 if tutorial else maxi(1, start_wave)
	GameState.start_wave = first
	GameState.waves_survived = first - 1
	_set_wave(first)
	if tutorial:
		_enter_tutorial()
	else:
		_enter_intermission(intermission_seconds())


## The preparation time for each intermission.
func intermission_seconds() -> float:
	return intermission_time


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
			# The queue is spent: mop-up starts now, not when the window would have ended.
			if spawns_done >= spawns_total:
				_set_phase(Phase.MOP_UP)
				_check_clear()
		Phase.MOP_UP:
			spawn_clock += delta
			mop_up_time += delta
			_spawn_due()
			var live := live_robot_count()
			Robot.hive_period = 4 if live <= 3 else (8 if live <= 8 else 12)
			if not _check_clear() and mop_up_time >= straggler_time and not _stragglers_marked:
				_mark_stragglers()
		Phase.CLEARED:
			time_left -= delta
			if time_left <= 0.0:
				_set_wave(wave + 1)
				_enter_intermission(intermission_seconds())


func _check_clear() -> bool:
	if spawns_done >= spawns_total and live_robot_count() == 0:
		_enter_cleared()
		return true
	return false


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
	opening = authored_wave(wave)
	if opening != null:
		_pick_opening_lanes()
	else:
		active_lanes = _pick_lanes(curve.lane_count(wave))
	_roll_family()
	_set_lanes_active(true)
	_set_phase(Phase.SIREN)
	EventBus.siren_started.emit(wave, active_lanes)
	var names := PackedStringArray()
	for lane in active_lanes:
		names.append(lane_name(lane))
	var haul := "  BIG HAUL!" if curve.is_big_haul(wave) else ""
	EventBus.hud_message.emit("INCOMING! Wave %d from %s%s" % [wave, " and ".join(names), haul], 4.0)


## The wave's family name card (GDD 10.2): rolled once per wave, logged in the Almanac.
func _roll_family() -> void:
	if gene_library == null or (genome != null and genome.wave == wave):
		return
	genome = RobotGenome.roll(GameState.run_seed, wave, gene_library, genome_history, curve)
	genome_history.append(genome)
	SaveManager.log_family(genome.family_code, genome.family_name, wave)
	EventBus.family_revealed.emit(genome)


func _enter_spawning() -> void:
	# Sweep only the previous battle's pickups, after the whole collection intermission and before
	# emitting wave_started or creating anything belonging to the new battle.
	var vacuumed := _scrap_vac()
	# The intermission autosave happened before manual collection and this sweep. Persist both now.
	SaveManager.save_profile()
	if vacuumed > 0:
		EventBus.hud_message.emit("Scrap Vac banked +%d leftover parts" % vacuumed, 2.0)
	_groups.clear()
	_events.clear()
	if opening != null:
		for group in opening.groups:
			_groups.append(GroupState.new(group))
		spawn_window = _opening_window(opening)
		spawns_total = _groups.size()
	else:
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
	var best_before := int(SaveManager.records.get("best_wave", 0))
	GameState.waves_survived = maxi(GameState.waves_survived, wave)
	var grain_added := 0.0
	if GameState.silo != null:
		grain_added = GameState.silo.add_grain(GameState.silo.harvest_bonus_amount())
	var rewards := _settle_clear_parts(best_before)
	if curve.is_big_haul(wave):
		SaveManager.record_phase_attempt(curve.phase_of(wave), GameState.attempt, true)
	_set_lanes_active(false)
	_set_phase(Phase.CLEARED)
	EventBus.wave_cleared.emit(wave)
	var reward_text := PackedStringArray()
	for part: StringName in rewards:
		reward_text.append("+%d %s" % [rewards[part], String(part).to_upper()])
	var salvage := "   Salvage " + ", ".join(reward_text) if not reward_text.is_empty() else ""
	EventBus.hud_message.emit("Wave %d cleared!  Harvest +%d grain%s" % [wave, roundi(grain_added), salvage], 3.0)
	# First-completion milestones (the jetpack blueprint). They announce; they never hand over an item.
	for text in MilestoneRewards.reconcile(maxi(best_before, wave)):
		EventBus.reward_granted.emit(text)
	SaveManager.save_profile()


func clear_rewards_for(wave_number: int) -> Dictionary[StringName, int]:
	if wave_number <= 0 or salvage_reward_interval <= 0 or wave_number % salvage_reward_interval != 0:
		return {}
	return salvage_clear_parts.duplicate()


## A repeated phase callback cannot pay twice, and ringing then losing/restarting pays nothing. The Early
## Bird bonus pays only for a wave above the profile's best (`best_before`, the best before this clear).
func _settle_clear_parts(best_before: int = -1) -> Dictionary[StringName, int]:
	if _settled_clear_waves.has(wave):
		return {}
	_settled_clear_waves[wave] = true
	if best_before < 0:
		best_before = int(SaveManager.records.get("best_wave", 0))
	var rewards := clear_rewards_for(wave)
	if _ready_bonus_wave == wave and wave > best_before:
		rewards[&"al"] = floori(early_bird_base_al * StatService.get_stat(&"economy.early_bird", 1.0))
	_ready_bonus_wave = 0
	if not rewards.is_empty():
		GameState.add_parts(rewards)
		SaveManager.save_profile()
	return rewards


func _on_game_over(_reason: StringName) -> void:
	_running = false
	if wave > 0:
		SaveManager.record_phase_attempt(curve.phase_of(wave), GameState.attempt, false)
		SaveManager.resume_wave = curve.phase_first_wave(wave)
	_set_phase(Phase.GAME_OVER)


func _set_phase(new_phase: Phase) -> void:
	phase = new_phase
	EventBus.wave_phase_changed.emit(phase, wave)


func _set_wave(new_wave: int) -> void:
	wave = new_wave
	GameState.wave = new_wave


# --- The authored opening -------------------------------------------------------------------------

## The authored wave for `wave_number`, or null when it is generated.
func authored_wave(wave_number: int) -> OpeningWave:
	if not use_authored_opening or wave_number > curve.opening_last_wave:
		return null
	if _openings.is_empty():
		_load_opening()
	return _openings.get(wave_number)


func _load_opening() -> void:
	_openings.clear()
	if not use_authored_opening or curve == null:
		return
	for wave_number in range(1, curve.opening_last_wave + 1):
		var path := OPENING_PATH % wave_number
		if ResourceLoader.exists(path):
			var authored := load(path) as OpeningWave
			if authored != null:
				_openings[wave_number] = authored


## The main lanes from the wave's lane pool (any lane if it's empty), then a third direction for raids: the
## lane farthest from the main ones.
## Slots map to lanes for the whole wave; only the main lanes light up at the siren.
func _pick_opening_lanes() -> void:
	var pool: Array[int] = []
	for lane in opening.lane_pool:
		if _lanes.has(lane):
			pool.append(lane)
	if pool.is_empty():
		pool.assign(_lanes.keys())
	pool.sort()
	_shuffle(pool)
	var others: Array[int] = []
	others.assign(_lanes.keys())
	others.sort()
	_shuffle(others)
	var mains: Array[int] = []
	for lane in pool:
		if mains.size() < mini(opening.main_lanes, 2):
			mains.append(lane)
	# Slot 2, the raid, comes from the far side: the lane farthest round the farm from the main lanes. With
	# the main lanes on the silo ladder's side, that splits the pressure between the ladder and the far wall.
	var far := -1
	var far_gap := -1
	for lane in others:
		if lane in mains:
			continue
		var gap := 99
		for taken in mains:
			gap = mini(gap, _lane_gap(lane, taken))
		if gap > far_gap:
			far = lane
			far_gap = gap
	_slot_lanes = PackedInt32Array(mains)
	if _slot_lanes.size() < 2:
		# A lone main lane still has a slot 1 for its groups: another side, not the raid's.
		var second := -1
		for lane in others:
			if lane in mains or lane == far:
				continue
			var apart := _lane_gap(lane, far) >= 2 and (mains.is_empty() or _lane_gap(lane, mains[0]) >= 2)
			if apart or second == -1:
				second = lane
				if apart:
					break
		_slot_lanes.append(second if second != -1 else far)
	_slot_lanes.append(far if far != -1 else _slot_lanes[0])
	active_lanes = PackedInt32Array()
	for i in mini(opening.main_lanes, _slot_lanes.size()):
		active_lanes.append(_slot_lanes[i])
	active_lanes.sort()


## Lanes apart around the farm (1-8 wrap), so the third direction really is another side.
static func _lane_gap(a: int, b: int) -> int:
	var gap := absi(a - b) % 8
	return mini(gap, 8 - gap)


func _shuffle(values: Array[int]) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j := _wave_rng.randi_range(0, i)
		var swap := values[i]
		values[i] = values[j]
		values[j] = swap


## The authored "attack" clock: until the last timed group is due (groups waiting on others come after).
func _opening_window(authored: OpeningWave) -> float:
	var last := 0.0
	for group in authored.groups:
		if group.after_group < 0:
			last = maxf(last, group.release_time)
	return last + 10.0


func _spawn_due_opening() -> void:
	for state in _groups:
		if state.released and state.resolved_at < 0.0 and state.alive() == 0:
			state.resolved_at = spawn_clock
	for i in _groups.size():
		var state := _groups[i]
		if state.done():
			continue
		var due := _release_time(state)
		if state.group.announce and not state.warned and due >= 0.0 and spawn_clock >= due - RAID_WARNING:
			state.warned = true
			_announce_raid(state.group)
		if due < 0.0 or spawn_clock < due:
			continue
		var count := state.group.robot_count()
		var live := live_robot_count()
		if live > 0 and (live + count > opening.live_cap or live + count > live_robot_cap):
			# Wait for room; never dump a queue all at once.
			break
		_release_group(state)
	spawns_done = 0
	for state in _groups:
		if state.done():
			spawns_done += 1


## When a group is due: its release time, or after_delay after its after_group was beaten. -1: not yet known.
func _release_time(state: GroupState) -> float:
	if state.group.after_group < 0:
		return state.group.release_time
	var other := _groups[state.group.after_group] if state.group.after_group < _groups.size() else null
	if other == null or other.cancelled:
		return 0.0
	if other.resolved_at < 0.0:
		return -1.0
	return other.resolved_at + state.group.after_delay


func _release_group(state: GroupState) -> void:
	state.released = true
	var group := state.group
	var lane_index := _slot_lanes[mini(group.lane_slot, _slot_lanes.size() - 1)] if not _slot_lanes.is_empty() else 0
	var lane := _lanes.get(lane_index) as LaneMarker
	if lane == null or robots_parent == null:
		return
	if lane_index not in active_lanes:
		active_lanes.append(lane_index)
		_set_lanes_active(true)
	var center := _authored_spawn_point(lane, opening.spawn_distance)
	var slot := 0
	for m in group.archetype_ids.size():
		var archetype := archetype_by_id(group.archetype_ids[m])
		if archetype == null:
			push_warning("Opening wave %d names an unknown archetype %s" % [wave, group.archetype_ids[m]])
			continue
		var role := group.roles[m] if m < group.roles.size() else &""
		var foreman := role == &"foreman"
		var count := group.counts[m] if m < group.counts.size() else 1
		var squad := RobotSquad.new() if count > 1 else null
		var type_scale := RobotFactory.TYPE_SCALES[int(archetype.robot_type)]
		for i in count:
			var offset := lane.global_basis * (RobotSquad.formation_offset(i, type_scale) + Vector3.RIGHT * (slot * 1.6))
			# Authored waves are calm unless a member is the teaching thief or the Foreman.
			var spawn_role := role if not role.is_empty() else &"calm"
			var robot := _spawn_robot(archetype, center + offset, foreman, [], squad, spawn_role,
					opening.foreman_hp if foreman else 0.0, group.roof)
			if robot != null:
				state.robots.append(robot)
		slot += 1
		if foreman:
			EventBus.hud_message.emit("FOREMAN INCOMING: %s!" % _last_foreman_title(), 3.0)
	Fx.puff(robots_parent, center + Vector3.UP * 0.6, Color(0.6, 0.45, 0.3), 1.2, 0.4)
	if not group.intro.is_empty() and INTROS.has(group.intro) and SaveManager.first_time(String(group.intro)):
		EventBus.hud_message.emit(INTROS[group.intro], 7.0)


## Authored arrivals burst out of the crop rows along their lane, `distance` from the silo (the corn sits
## at ~100 m), snapped onto the navmesh.
func _authored_spawn_point(lane: LaneMarker, distance: float) -> Vector3:
	var center := GameState.silo.global_position if GameState.silo != null else Vector3.ZERO
	var out := lane.global_position - center
	out.y = 0.0
	var dir := out.normalized() if out.length_squared() > 0.01 else Vector3.FORWARD
	var lateral := lane.global_basis.x * _wave_rng.randf_range(-1.5, 1.5)
	var where := center + dir * distance + lateral
	var map := robots_parent.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		where = NavigationServer3D.map_get_closest_point(map, where)
	return where


func _announce_raid(group: OpeningGroup) -> void:
	var lane_index := _slot_lanes[mini(group.lane_slot, _slot_lanes.size() - 1)] if not _slot_lanes.is_empty() else 0
	if lane_index > 0 and lane_index not in active_lanes:
		active_lanes.append(lane_index)
		_set_lanes_active(true)
	EventBus.hud_message.emit("RAID! More robots from %s!" % lane_name(lane_index), 3.0)


func _on_robot_destroyed(robot: Node3D, _killer: Node) -> void:
	var foe := robot as Robot
	if opening == null or foe == null or not foe.is_foreman or not opening.foreman_cancels_adds:
		return
	if phase not in [Phase.SPAWNING, Phase.MOP_UP]:
		return
	# The Foreman is down: call off the adds still to come and mark the survivors at once.
	for state in _groups:
		if not state.released:
			state.cancelled = true
	spawns_done = spawns_total
	_mark_stragglers()


func archetype_by_id(id: StringName) -> RobotArchetype:
	for archetype in archetypes:
		if archetype != null and archetype.id == id:
			return archetype
	if foreman_archetype != null and foreman_archetype.id == id:
		return foreman_archetype
	return null


static func lane_name(lane_index: int) -> String:
	return LANE_NAMES.get(lane_index, "lane %d" % lane_index)


# --- Spawning -------------------------------------------------------------------------------------

## Buys spawn events with the wave's threat budget. From climber_first_wave, reserve the cost of enough
## climbers to make roughly 25% of individual robots climbers, including the bonus Foreman in the denominator:
## Roof Lobbers, and from ladder_climber_first_wave a share of Rung Runners for the silo ladder. This replaces
## ground purchases inside the regular budget; it never adds a second vertical budget. All other archetypes
## retain their weighted picks, group rolls and caps. Seeded on every peer.
func _build_spawn_events(wave_number: int) -> Array[SpawnEvent]:
	var available: Array[RobotArchetype] = []
	var climber: RobotArchetype = null
	var ladder: RobotArchetype = null
	for archetype in archetypes:
		if archetype == null or archetype.unlock_wave > wave_number:
			continue
		if archetype.id == &"roof_lobber" and wave_number >= curve.climber_first_wave and curve.climber_target_share > 0.0:
			climber = archetype
		elif archetype.scene != null and archetype.id == &"rung_runner":
			ladder = archetype
		else:
			available.append(archetype)
	if wave_number < curve.ladder_climber_first_wave:
		ladder = null
	var events: Array[SpawnEvent] = []
	var budget := curve.threat_budget(wave_number)
	var heavies := 0
	var heavy_cap := heavy_cap_for(wave_number)
	var drone_count := 0
	var other_robots := 1 if curve.is_big_haul(wave_number) and foreman_archetype != null else 0
	# The Drone still has a guaranteed solo introduction; climbers use the reserved share instead.
	for archetype in available:
		if wave_number == archetype.unlock_wave and archetype.id == &"drone":
			if archetype.threat_cost() + _climber_reserve(wave_number, other_robots + 1, climber) <= budget:
				events.append(SpawnEvent.new(archetype))
				budget -= archetype.threat_cost()
				other_robots += 1
				drone_count += 1
	while not available.is_empty():
		var options: Array[RobotArchetype] = []
		var total_weight := 0.0
		var single_budget := budget - _climber_reserve(wave_number, other_robots + 1, climber)
		for archetype in available:
			var is_heavy := archetype.robot_type == RobotArchetype.RobotType.HEAVY
			var at_cap := archetype.id == &"drone" and drone_count >= drone_cap_for(wave_number)
			if archetype.threat_cost() <= single_budget + 0.001 and not (is_heavy and heavies >= heavy_cap) and not at_cap:
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
		pick = roll_role(wave_number, pick, single_budget)
		var trio_budget := budget - _climber_reserve(wave_number, other_robots + 3, climber)
		var event := SpawnEvent.new(pick, false, roll_group_size(wave_number, pick, trio_budget))
		events.append(event)
		budget -= event.threat_cost()
		other_robots += event.robot_count()
		if pick.robot_type == RobotArchetype.RobotType.HEAVY:
			heavies += 1
		if pick.id == &"drone":
			drone_count += event.robot_count()
	if climber != null:
		var count := mini(maxi(1, curve.climber_count(wave_number, other_robots)), floori(budget / climber.threat_cost()))
		var ladders := curve.ladder_climber_count(wave_number, count) if ladder != null else 0
		events = _interleave_climbers(events, climber, count - ladders, ladder, ladders)
	return events


func _climber_reserve(wave_number: int, other_robots: int, climber: RobotArchetype) -> float:
	return 0.0 if climber == null else float(maxi(1, curve.climber_count(wave_number, other_robots))) * climber.threat_cost()


## Spread solo climbers over the existing attack rather than putting a new cluster at its start or end.
## Rung Runners take every other climber slot from the middle out, so both routes stay in play.
func _interleave_climbers(events: Array[SpawnEvent], climber: RobotArchetype, count: int,
		ladder: RobotArchetype = null, ladder_count: int = 0) -> Array[SpawnEvent]:
	var total := count + ladder_count
	var kinds: Array[RobotArchetype] = []
	for i in total:
		kinds.append(climber)
	if ladder != null:
		# Fill from the middle outward: middle, middle - 1, middle + 1, ...
		var placed := 0
		var middle := floori(total * 0.5)
		for step in total * 2:
			if placed >= ladder_count:
				break
			var half := floori(step * 0.5)
			var at := middle + (half if step % 2 == 0 else -(half + 1))
			if at >= 0 and at < total and kinds[at] != ladder:
				kinds[at] = ladder
				placed += 1
	var mixed: Array[SpawnEvent] = []
	var inserted := 0
	for i in range(events.size() + 1):
		while inserted < total and float(i) >= (float(inserted) + 0.5) * events.size() / maxi(1, total):
			mixed.append(SpawnEvent.new(kinds[inserted]))
			inserted += 1
		if i < events.size():
			mixed.append(events[i])
	return mixed


## Each option's pick weight: its type weight x spawn_weight (GDD 9.1). After the opening these are rescaled
## so each present column gets its DifficultyCurve.column_weights share of weighted picks. The climber
## reservation and drone/Heavy caps determine the final roster, rather than these being final robot shares.
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


## A small ground melee pick becomes a Spitter with chance DifficultyCurve.spitter_share (from wave 13), if
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


## A quarter of the wave may climb, but only a few Roof Lobbers may be alive at once. The rest wait while
## due ground events proceed, so the new composition cannot create an opening pile-up or jam all lanes.
## 3 from wave 5, phase 2's rooftop twist.
static func rooftop_live_cap_for(wave_number: int) -> int:
	if wave_number < 5:
		return 2
	if wave_number <= 15:
		return 3
	return 4 if wave_number <= 30 else 5


## Rung Runners alive at once in generated waves; the ladder itself admits two at a time.
static func ladder_live_cap_for(wave_number: int) -> int:
	return 2 if wave_number <= 15 else 3


## Keep flight as a rare supporting threat: none before phase 3 (wave 7), one on its debut wave, two for the
## rest of phase 3, three from phase 4's Sky Raid (PHASE_CHECKPOINT_PROGRESSION_PLAN.md step 3).
static func drone_cap_for(wave_number: int) -> int:
	if wave_number < 7:
		return 0
	if wave_number == 7:
		return 1
	return 2 if wave_number < 10 else 3


## Regular Heavies per wave (the Foreman doesn't count): 1 from their debut, plus 1 every three phases,
## stepping on phase starts (16, 25, ...).
static func heavy_cap_for(wave_number: int) -> int:
	return 1 + floori(maxf(0.0, wave_number - 7.0) / 9.0)


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
	if opening != null:
		_spawn_due_opening()
		return
	while spawns_done < spawns_total and _schedule[spawns_done] <= spawn_clock and live_robot_count() < live_robot_cap:
		var rooftop_live := 0
		var ladder_live := 0
		for node in get_tree().get_nodes_in_group(Robot.GROUP):
			var robot := node as Robot
			if robot.archetype != null and robot.archetype.id == &"roof_lobber":
				rooftop_live += 1
			elif robot is LadderRobot:
				ladder_live += 1
		var index := _next_due_event_index(rooftop_live, ladder_live)
		if index < 0:
			break
		if index != spawns_done:
			var waiting := _events[spawns_done]
			_events[spawns_done] = _events[index]
			_events[index] = waiting
		_spawn_event(_events[spawns_done])
		spawns_done += 1


## A capped climber can wait without preventing another already-due ground event from entering.
func _next_due_event_index(rooftop_live: int, ladder_live: int = 0) -> int:
	for i in range(spawns_done, spawns_total):
		if _schedule[i] > spawn_clock:
			break
		var id := _events[i].archetype.id
		if id == &"roof_lobber" and rooftop_live >= rooftop_live_cap_for(wave):
			continue
		if id == &"rung_runner" and ladder_live >= ladder_live_cap_for(wave):
			continue
		return i
	return -1


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


func _spawn_robot(archetype: RobotArchetype, where: Vector3, foreman: bool, bonus: Array[RobotTrait], squad: RobotSquad,
		role: StringName = &"", foreman_hp: float = 0.0, roof: StringName = &"") -> Robot:
	var map := robots_parent.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		where = NavigationServer3D.map_get_closest_point(map, where)
	var robot := archetype.scene.instantiate() as Robot
	robot.setup(archetype, wave, curve, _wave_rng, genome, foreman, bonus, squad, role, foreman_hp)
	if robot is VerticalRobot and not roof.is_empty():
		(robot as VerticalRobot).forced_roof = roof
	if foreman and robot is HeavyRobot and opening != null:
		# The opening's Foremen fight by fixed rules (HeavyRobot); set before _ready builds the vent glow.
		(robot as HeavyRobot).authored = true
		(robot as HeavyRobot).throw_phase = opening.foreman_throw_phase
	robot.position = robots_parent.to_local(where) + Vector3.UP * 0.1
	robots_parent.add_child(robot)
	robot.reset_physics_interpolation()
	return robot


func _last_foreman_title() -> String:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		var robot := node as Robot
		if robot.is_foreman:
			return robot.foreman_title
	return "the Foreman"


## Scrap Vac: banks a share of leftover parts at the next battle's start and clears the remainder.
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
	if opening != null:
		for state in _groups:
			if not state.done():
				count += state.group.robot_count()
		return count
	for i in range(spawns_done, spawns_total):
		count += _events[i].robot_count()
	return count


## The authored wave's title for the HUD, or "".
func wave_title() -> String:
	var authored := authored_wave(wave)
	return authored.title if authored != null else ""


## What this wave asks of the player, for the HUD during its intermission and siren.
func wave_hint() -> String:
	var authored := authored_wave(wave)
	return authored.hint if authored != null else ""


# --- Debug and "ring the bell" ----------------------------------------------------------------------

## Skips preparation and records readiness; the small Early Bird bonus is paid after this wave clears.
func ring_bell() -> void:
	if phase == Phase.TUTORIAL:
		finish_tutorial(tutorial_bonus_al)
	elif phase == Phase.INTERMISSION:
		_ready_bonus_wave = wave
		var paid := wave > int(SaveManager.records.get("best_wave", 0))
		EventBus.hud_message.emit("Early Bird bonus on wave clear" if paid else "Ready! Here they come", 2.0)
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
	_groups.clear()
	spawns_total = 0
	spawns_done = 0
	_enter_siren(siren_lead_time)


## Enemy lab: every robot the game can field, as (label, archetype, role, foreman) rows for the pause menu.
func lab_roster() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for archetype in archetypes:
		if archetype != null and archetype.scene != null:
			rows.append({"label": archetype.display_name, "archetype": archetype, "role": &"", "foreman": false})
	if spitter_archetype != null and spitter_archetype.scene != null:
		rows.append({"label": spitter_archetype.display_name, "archetype": spitter_archetype, "role": &"", "foreman": false})
	if foreman_archetype != null and foreman_archetype.scene != null:
		rows.append({"label": "Foreman", "archetype": foreman_archetype, "role": &"", "foreman": true})
	return rows


## Debug: drops one robot in front of the first farmer (climbers use the nearest lane so they find their route).
func spawn_lab_robot(archetype: RobotArchetype, foreman: bool = false) -> Robot:
	if archetype == null or archetype.scene == null or robots_parent == null:
		return null
	var farmer := GameState.players[0] as Farmer if not GameState.players.is_empty() else null
	var where := Vector3.FORWARD * 12.0
	if farmer != null:
		where = farmer.global_position + Vector3(-sin(farmer.facing_yaw), 0.0, -cos(farmer.facing_yaw)) * 12.0
	if (archetype.id == &"roof_lobber" or archetype.id == &"rung_runner") and not _lanes.is_empty():
		var best: LaneMarker = null
		for lane in _lanes.values():
			if best == null or farmer != null and lane.global_position.distance_to(farmer.global_position) < best.global_position.distance_to(farmer.global_position):
				best = lane
		where = best.spawn_position(0.0)
	var bonus: Array[RobotTrait] = []
	return _spawn_robot(archetype, where, foreman, bonus, null)


func clear_robots(award_drops: bool) -> void:
	for node in get_tree().get_nodes_in_group(Robot.GROUP):
		(node as Robot).kill(award_drops)


func phase_name() -> String:
	return PHASE_NAMES[phase]
