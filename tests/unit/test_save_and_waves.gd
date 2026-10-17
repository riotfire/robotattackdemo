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
	SaveManager.use_profile("user://gut_profile.json", true)
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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://gut_profile.json"))
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
			spent += event.archetype.threat_cost()
			assert_lte(event.archetype.unlock_wave, wave, "wave %d: %s is unlocked" % [wave, event.archetype.id])
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
	assert_eq(first.map(func(e: WaveDirector.SpawnEvent) -> StringName: return e.archetype.id),
			second.map(func(e: WaveDirector.SpawnEvent) -> StringName: return e.archetype.id), "same seed, same wave")
	director.free()
