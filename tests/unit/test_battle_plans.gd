extends GutTest
## Battle plans (M2-B11): the table, the roll rules over 1,000 simulated waves, and the director's use of them.

const ContentTables := preload("res://tools/content_tables.gd")

var library: Array[BattlePlan] = []
var have: Array[StringName] = [&"nibbler", &"clanker", &"drone", &"roof_lobber"]


func before_each() -> void:
	library = ContentTables.new().battle_plans()


func _roll(wave: int, recent: Dictionary, seed_value: int, ids: Array[StringName] = have) -> Array[BattlePlan]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return BattlePlan.choose(library, wave, recent, ids, rng)


func test_the_plan_table_has_the_eight_plans() -> void:
	var ids := library.map(func(plan: BattlePlan) -> StringName: return plan.id)
	for id: StringName in [&"rush", &"rooftop", &"heist", &"sky_raid", &"barrage", &"swarm", &"pincer", &"siege"]:
		assert_has(ids, id)


func test_no_plans_before_wave_8() -> void:
	for wave in range(1, 8):
		assert_eq(_roll(wave, {}, wave).size(), 0, "wave %d has no plan" % wave)


func test_plans_respect_their_first_wave_and_no_repeat_within_3_waves_before_stacking() -> void:
	var recent := {}
	for wave in range(8, 1008):
		var chosen := _roll(wave, recent, wave * 7919)
		assert_eq(chosen.size(), BattlePlan.plan_count(wave), "wave %d rolls its plan count" % wave)
		var ids: Array[StringName] = []
		for plan in chosen:
			assert_lte(plan.first_wave, wave, "%s is not early at wave %d" % [plan.id, wave])
			assert_does_not_have(ids, plan.id, "no plan twice in wave %d" % wave)
			assert_ne(plan.id, &"siege", "Siege waits for the Longneck")
			# Stacked waves (31+) use 2 of the 7 plans a wave, so 3 waves can't all stay fresh: they repeat only then.
			for back in range(1, BattlePlan.REPEAT_GAP + 1) if wave < BattlePlan.STACK_WAVE else []:
				assert_does_not_have(recent.get(wave - back, []), plan.id, "%s repeats within %d waves at %d" % [plan.id, back, wave])
			ids.append(plan.id)
		recent[wave] = ids


func test_two_plans_stack_from_wave_31() -> void:
	assert_eq(BattlePlan.plan_count(30), 1)
	assert_eq(BattlePlan.plan_count(31), 2)


func test_siege_rolls_once_the_longneck_exists_and_wave_16_is_reached() -> void:
	var with_longneck: Array[StringName] = have.duplicate()
	with_longneck.append(&"longneck")
	var seen := false
	for seed_value in 200:
		for plan in _roll(16, {}, seed_value, with_longneck):
			seen = seen or plan.id == &"siege"
		for plan in _roll(15, {}, seed_value, with_longneck):
			assert_ne(plan.id, &"siege", "no Siege before wave 16")
	assert_true(seen, "Siege can roll at wave 16 with a Longneck")


func test_every_plan_gets_picked() -> void:
	var seen: Dictionary[StringName, bool] = {}
	for seed_value in 400:
		for plan in _roll(40, {}, seed_value):
			seen[plan.id] = true
	for id: StringName in [&"rush", &"rooftop", &"heist", &"sky_raid", &"barrage", &"swarm", &"pincer"]:
		assert_true(seen.has(id), "%s rolls" % id)


# --- The director -----------------------------------------------------------------------------------

func _director(wave_number: int, plan_ids: Array[StringName]) -> WaveDirector:
	var director := WaveDirector.new()
	director.curve = load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	director.wave = wave_number
	for id in ["nibbler", "clanker", "thumper", "drone", "roof_lobber"]:
		director.archetypes.append(load("res://data/robots/archetypes/%s.tres" % id) as RobotArchetype)
	for plan in library:
		if plan.id in plan_ids:
			director.plans.append(plan)
	director._wave_rng = RngService.wave_stream(RngService.STREAM_SPAWNS, wave_number)
	autofree(director)
	return director


func _count(events: Array[WaveDirector.SpawnEvent], matches: Callable) -> int:
	var total := 0
	for event in events:
		if matches.call(event.archetype):
			total += event.robot_count()
	return total


func test_swarm_buys_only_small_robots_and_climbers() -> void:
	var events := _director(12, [&"swarm"])._build_spawn_events(12)
	assert_gt(events.size(), 0)
	for event in events:
		var archetype := event.archetype
		assert_true(archetype.robot_type == RobotArchetype.RobotType.SCOUT or archetype.id == &"roof_lobber",
				"%s isn't small" % archetype.id)


func test_swarm_brings_more_robots_than_no_plan() -> void:
	var plain := 0
	var swarm := 0
	var any_robot := func(_a: RobotArchetype) -> bool: return true
	for wave in range(12, 40):
		plain += _count(_director(wave, [])._build_spawn_events(wave), any_robot)
		swarm += _count(_director(wave, [&"swarm"])._build_spawn_events(wave), any_robot)
	assert_gt(swarm, plain, "Swarm sends more robots")


func test_sky_raid_allows_more_drones() -> void:
	var drone := func(a: RobotArchetype) -> bool: return a.id == &"drone"
	var plain := 0
	var raid := 0
	for wave in range(10, 30):
		plain += _count(_director(wave, [])._build_spawn_events(wave), drone)
		raid += _count(_director(wave, [&"sky_raid"])._build_spawn_events(wave), drone)
	assert_gt(raid, plain, "Sky Raid sends more Drones")


func test_rooftop_lifts_the_roof_lobber_cap() -> void:
	var director := _director(10, [&"rooftop"])
	assert_eq(director._plan_rooftop_cap(WaveDirector.rooftop_live_cap_for(10)), 3)
	assert_eq(_director(10, [])._plan_rooftop_cap(2), 2, "no plan leaves the cap alone")


func test_plan_title_joins_stacked_plans() -> void:
	var title := _director(31, [&"barrage", &"pincer"]).plan_title()
	assert_true(title.contains("Barrage") and title.contains("Pincer") and title.contains(" + "), title)
	assert_eq(_director(10, []).plan_title(), "")
