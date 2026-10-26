extends GutTest
## Save migration and round-trip (GDD 14, 18.4), and wave spawn buying (GDD 9.1, 11.4).

const ARCHETYPES: Array[String] = [
	"res://data/robots/archetypes/nibbler.tres",
	"res://data/robots/archetypes/clanker.tres",
	"res://data/robots/archetypes/thumper.tres",
]


func test_migrates_a_v0_profile() -> void:
	var old := {"al": 12, "cu": 3, "jetpack": true, "upgrades": {"attack.pistol": 1}}
	var migrated := SaveManager.migrate(old)
	assert_eq(int(migrated["schema_version"]), SaveManager.SCHEMA_VERSION)
	assert_eq(int(migrated["parts"]["al"]), 12)
	assert_eq(int(migrated["parts"]["pc"]), 0)
	assert_true(bool(migrated["unlocks"]["jetpack"]))
	assert_eq(int(migrated["upgrades"]["attack.pistol"]), 1, "unrelated data survives")


func test_current_profile_is_left_alone() -> void:
	var data := {"schema_version": 1, "parts": {"al": 5}, "unlocks": {"jetpack": false}}
	assert_eq(SaveManager.migrate(data), data)


func test_profile_round_trip() -> void:
	var path := SaveManager.profile_path
	var levels := StatService.levels.duplicate()
	var parts := GameState.parts.duplicate()
	var test_profile := OS.get_temp_dir().path_join("gut_profile_%d.json" % OS.get_process_id())
	SaveManager.use_profile(test_profile, true)
	GameState.add_parts({&"al": 42, &"au": 3})
	StatService.grant(&"attack.pistol")
	GameState.jetpack_unlocked = true
	SaveManager.save_profile()
	SaveManager.apply(SaveManager._default_profile())
	assert_eq(GameState.parts[&"al"], 0)
	SaveManager.load_profile()
	assert_eq(GameState.parts[&"al"], 42)
	assert_eq(GameState.parts[&"au"], 3)
	assert_eq(StatService.level_of(&"attack.pistol"), 1)
	assert_true(GameState.jetpack_unlocked)
	DirAccess.remove_absolute(test_profile)
	SaveManager.profile_path = path
	StatService.set_levels(levels)
	for key: StringName in parts:
		GameState.parts[key] = parts[key]


func test_heavy_cap() -> void:
	assert_eq(WaveDirector.heavy_cap_for(6), 1)
	assert_eq(WaveDirector.heavy_cap_for(13), 1)
	assert_eq(WaveDirector.heavy_cap_for(14), 2)
	assert_eq(WaveDirector.heavy_cap_for(30), 4)


func test_spawn_buying_spends_the_budget_within_the_rules() -> void:
	var director := WaveDirector.new()
	director.curve = load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	for path in ARCHETYPES:
		director.archetypes.append(load(path) as RobotArchetype)
	for wave in range(1, 25):
		director.set(&"_wave_rng", RngService.make_rng([99, wave]))
		var events: Array = director.call(&"_build_spawn_events", wave)
		var spent := 0.0
		var heavies := 0
		for event: WaveDirector.SpawnEvent in events:
			spent += event.threat_cost()
			assert_lte(event.archetype.unlock_wave, wave, "wave %d: %s is unlocked" % [wave, event.archetype.id])
			assert_true(event.robot_count() in [1, 3], "wave %d: groups are solo or trios" % wave)
			if not event.archetype.can_form_trio():
				assert_eq(event.robot_count(), 1, "wave %d: a %s is always solo" % [wave, event.archetype.id])
			if event.archetype.robot_type == RobotArchetype.RobotType.HEAVY:
				heavies += 1
		var budget := director.curve.threat_budget(wave)
		assert_lte(spent, budget + 0.01, "wave %d stays in budget" % wave)
		assert_lt(budget - spent, 2.0, "wave %d spends all it can" % wave)
		assert_lte(heavies, WaveDirector.heavy_cap_for(wave), "wave %d respects the Heavy cap" % wave)
	director.set(&"_wave_rng", RngService.make_rng([99, 7]))
	var first: Array = director.call(&"_build_spawn_events", 7)
	director.set(&"_wave_rng", RngService.make_rng([99, 7]))
	var second: Array = director.call(&"_build_spawn_events", 7)
	assert_eq(first.map(func(e: WaveDirector.SpawnEvent) -> String: return "%s x%d" % [e.archetype.id, e.robot_count()]),
			second.map(func(e: WaveDirector.SpawnEvent) -> String: return "%s x%d" % [e.archetype.id, e.robot_count()]),
			"same seed, same wave, same groups")
	director.free()


func _full_roster_director() -> WaveDirector:
	var director := WaveDirector.new()
	director.curve = load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	for id in ["nibbler", "clanker", "thumper", "roof_lobber", "drone"]:
		director.archetypes.append(load("res://data/robots/archetypes/%s.tres" % id) as RobotArchetype)
	director.foreman_archetype = load("res://data/robots/archetypes/thumper.tres") as RobotArchetype
	director.spitter_archetype = load("res://data/robots/archetypes/spitter.tres") as RobotArchetype
	return director


func test_climbers_replace_ground_budget_and_make_one_quarter_of_individual_robots() -> void:
	var director := _full_roster_director()
	for seed_value in range(32):
		for wave_number in range(1, 41):
			director.set(&"_wave_rng", RngService.make_rng([seed_value, wave_number]))
			var events: Array = director.call(&"_build_spawn_events", wave_number)
			var climbers := 0
			# The bonus Foreman is spawned separately, but still counts as an individual for composition.
			var other_robots := 1 if director.curve.is_big_haul(wave_number) else 0
			var spent := 0.0
			var drones := 0
			for event: WaveDirector.SpawnEvent in events:
				spent += event.threat_cost()
				if event.archetype.id == &"roof_lobber":
					climbers += event.robot_count()
				else:
					other_robots += event.robot_count()
				if event.archetype.id == &"drone":
					drones += event.robot_count()
			var label := "seed %d wave %d" % [seed_value, wave_number]
			assert_lte(spent, director.curve.threat_budget(wave_number) + 0.001, "%s stays in the existing budget" % label)
			assert_lte(drones, WaveDirector.drone_cap_for(wave_number), "%s keeps drones scarce" % label)
			if wave_number < 3:
				assert_eq(climbers, 0, "%s preserves the melee introduction" % label)
			else:
				assert_eq(climbers, director.curve.climber_count(wave_number, other_robots),
						"%s reserves climbers using robot counts, not event counts" % label)
				var target := 0.25 * float(climbers + other_robots)
				assert_almost_eq(float(climbers), target, 0.5, "%s is within half a robot of 25%%" % label)
			if wave_number == 5:
				assert_eq(drones, 1, "%s keeps the guaranteed single-drone debut" % label)
	director.free()


func test_climber_composition_is_deterministic_and_not_a_single_wave_end_cluster() -> void:
	var director := _full_roster_director()
	var describe := func(events: Array) -> Array:
		return events.map(func(event: WaveDirector.SpawnEvent) -> String:
			return "%s x%d" % [event.archetype.id, event.robot_count()])
	for wave_number in [3, 4, 5, 6, 15, 40]:
		director.set(&"_wave_rng", RngService.make_rng([31, wave_number]))
		var first: Array = director.call(&"_build_spawn_events", wave_number)
		director.set(&"_wave_rng", RngService.make_rng([31, wave_number]))
		var second: Array = director.call(&"_build_spawn_events", wave_number)
		assert_eq(describe.call(first), describe.call(second), "wave %d repeats from its seed" % wave_number)
		var first_half := 0
		var second_half := 0
		for i in first.size():
			if first[i].archetype.id == &"roof_lobber":
				if i < first.size() / 2:
					first_half += 1
				else:
					second_half += 1
		assert_gt(first_half, 0, "wave %d introduces climbers before the midpoint" % wave_number)
		assert_gt(second_half, 0, "wave %d also has climbers after the midpoint" % wave_number)
	director.free()


func test_live_climber_cap_defers_climbers_but_allows_due_ground_events() -> void:
	var director := _full_roster_director()
	director.wave = 3
	director.spawn_clock = 1.0
	director.spawns_total = 3
	director.set(&"_schedule", PackedFloat32Array([0.0, 1.0, 2.0]))
	var events: Array[WaveDirector.SpawnEvent] = [
		WaveDirector.SpawnEvent.new(director.archetypes[3]),
		WaveDirector.SpawnEvent.new(director.archetypes[0]),
		WaveDirector.SpawnEvent.new(director.archetypes[3]),
	]
	director.set(&"_events", events)
	var cap := WaveDirector.rooftop_live_cap_for(3)
	assert_eq(director.call(&"_next_due_event_index", cap - 1), 0, "a free rooftop slot admits its due climber")
	assert_eq(director.call(&"_next_due_event_index", cap), 1, "a full rooftop skips to the due ground event")
	director.spawns_done = 2
	assert_eq(director.call(&"_next_due_event_index", cap - 1), -1, "future climbers wait for their scheduled time")
	director.spawn_clock = 2.0
	assert_eq(director.call(&"_next_due_event_index", cap), -1, "a full rooftop defers the last climber")
	assert_eq(director.call(&"_next_due_event_index", cap - 1), 2, "it resumes when a rooftop slot frees")
	director.free()


func test_tutorial_flag_defaults_by_history() -> void:
	var path := SaveManager.profile_path
	var done := SaveManager.tutorial_completed
	var levels := StatService.levels.duplicate()
	SaveManager.apply({})
	assert_false(SaveManager.tutorial_completed, "a brand-new profile still has Level 0 to do")
	assert_false(StatService.has_flag(&"wrench.owned"), "a new player collects parts for the wrench")
	SaveManager.apply({"records": {"best_wave": 4}})
	assert_true(SaveManager.tutorial_completed, "a profile from before Level 0 that has played skips it")
	assert_true(StatService.has_flag(&"wrench.owned"), "an existing player keeps the starting wrench")
	SaveManager.apply({"records": {"best_wave": 4}, "tutorial_completed": false})
	assert_false(SaveManager.tutorial_completed, "an explicit flag wins")
	SaveManager.tutorial_completed = true
	assert_true(bool(SaveManager.to_dictionary()["tutorial_completed"]), "the flag is saved")
	SaveManager.tutorial_completed = done
	StatService.set_levels(levels)
	SaveManager.profile_path = path


func test_tutorial_phase_keeps_the_other_phase_numbers() -> void:
	assert_eq(WaveDirector.Phase.INTERMISSION, 0)
	assert_eq(WaveDirector.Phase.GAME_OVER, 5)
	assert_eq(WaveDirector.PHASE_NAMES.size(), WaveDirector.Phase.size())
	assert_eq(AudioDirector.state_for_phase(WaveDirector.Phase.TUTORIAL, 1), &"intermission", "Level 0 plays the field theme")
