extends GutTest
## Time of day and weather (GDD 4.6, 4.7, 11.2): preset order and phase stepping, seeded rolls, the Morning Fog
## range hook for long-range robots, and every preset x weather combination on a bare Environment.

const TABLE_PATH := "res://data/environment/environment_table.tres"
const SKY_SHADER_PATH := "res://shaders/painted_sky.gdshader"
const PRESET_IDS: Array[StringName] = [&"dawn", &"morning", &"noon", &"golden_hour", &"dusk", &"moonlit_night"]
const WEATHER_IDS: Array[StringName] = [&"clear", &"breezy", &"drizzle", &"morning_fog"]
## Spawn ring distance (GDD 4.7): every weather's fog must hide it.
const SPAWN_RING := 110.0

var table: EnvironmentTable


func before_each() -> void:
	table = load(TABLE_PATH) as EnvironmentTable


func after_each() -> void:
	Weather.current = null


func test_six_presets_in_gdd_order() -> void:
	assert_eq(table.presets.size(), 6)
	for i in table.presets.size():
		assert_eq(table.presets[i].id, PRESET_IDS[i])
		assert_ne(table.presets[i].display_name, "", "%s has a display name" % PRESET_IDS[i])


func test_four_weathers_with_roll_weights() -> void:
	assert_eq(table.weathers.size(), 4)
	for i in table.weathers.size():
		assert_eq(table.weathers[i].id, WEATHER_IDS[i])
		assert_gt(table.weathers[i].weight, 0.0, "%s can be rolled" % WEATHER_IDS[i])


func test_time_advances_one_step_per_phase() -> void:
	for start in 6:
		for wave in range(1, 6):
			assert_eq(table.preset_index(start, wave), start, "phase 1 keeps the starting preset")
		assert_eq(table.preset_index(start, 6), (start + 1) % 6, "wave 6 starts phase 2")
		assert_eq(table.preset_index(start, 10), (start + 1) % 6)
		assert_eq(table.preset_index(start, 30), (start + 5) % 6)
		assert_eq(table.preset_index(start, 31), start, "Moonlit Night wraps back to Dawn after six phases")
	# Start-phase checkpoints (GDD 14.2): the run opens on its rolled preset, whatever the first wave is.
	assert_eq(table.preset_index(2, 11, 11), 2)
	assert_eq(table.preset_index(2, 16, 11), 3)
	assert_eq(table.preset_index(5, 16, 11), 0)


func test_same_seed_gives_the_same_sky() -> void:
	for seed_value: int in [1, 2, 3, 1234, 664607717]:
		RngService.start_run(seed_value)
		var first := TimeOfDay.roll_for_run(table)
		RngService.start_run(seed_value)
		var again := TimeOfDay.roll_for_run(table)
		assert_true(first.equals(again), "seed %d rolls the same preset, weather and variation" % seed_value)


func test_seeds_cover_every_preset_and_weather() -> void:
	var presets_seen: Dictionary[int, int] = {}
	var weathers_seen: Dictionary[int, int] = {}
	var runs := 400
	for seed_value in runs:
		RngService.start_run(seed_value)
		var roll := TimeOfDay.roll_for_run(table)
		presets_seen[roll.start_index] = presets_seen.get(roll.start_index, 0) + 1
		weathers_seen[roll.weather_index] = weathers_seen.get(roll.weather_index, 0) + 1
		assert_between(roll.sun_bearing_offset, -table.sun_bearing_jitter, table.sun_bearing_jitter)
	assert_eq(presets_seen.size(), 6, "every preset can start a run")
	assert_eq(weathers_seen.size(), 4, "every weather can be rolled")
	var total_weight := 0.0
	for weather in table.weathers:
		total_weight += weather.weight
	for i in table.weathers.size():
		var expected := table.weathers[i].weight / total_weight
		var share := float(weathers_seen.get(i, 0)) / runs
		assert_almost_eq(share, expected, 0.07, "%s rolls about %d%% of runs" % [table.weathers[i].id, roundi(expected * 100.0)])


func test_environment_roll_leaves_other_streams_alone() -> void:
	var streams: Array[StringName] = [RngService.STREAM_SPAWNS, RngService.STREAM_GENOME, RngService.STREAM_COSMETIC,
			RngService.STREAM_FARM, RngService.STREAM_DROPS, RngService.STREAM_SILO]
	RngService.start_run(77)
	var untouched: Array[int] = []
	for stream in streams:
		untouched.append(RngService.stream(stream).randi())
	RngService.start_run(77)
	TimeOfDay.roll_for_run(table)
	for i in streams.size():
		assert_eq(RngService.stream(streams[i]).randi(), untouched[i], "%s is unchanged by the environment roll" % streams[i])
	assert_eq(RngService.wave_stream(RngService.STREAM_SPAWNS, 3).randi(),
			RngService.make_rng([77, 3, RngService.STREAM_SPAWNS]).randi(), "lane and spawn rolls are unchanged")


func test_morning_fog_shortens_only_long_range() -> void:
	for weather in table.weathers:
		Weather.current = weather
		var fog := weather.id == &"morning_fog"
		assert_almost_eq(Weather.engagement_range_multiplier(RobotArchetype.RobotClass.LONG_RANGE), 0.8 if fog else 1.0, 0.0001,
				"%s: long-range multiplier" % weather.id)
		assert_eq(Weather.engagement_range_multiplier(RobotArchetype.RobotClass.MELEE), 1.0, "%s: melee unchanged" % weather.id)
		assert_eq(Weather.engagement_range_multiplier(RobotArchetype.RobotClass.SHORT_RANGE), 1.0, "%s: short-range unchanged" % weather.id)
	Weather.current = table.weathers[WEATHER_IDS.find(&"morning_fog")]
	assert_almost_eq(Weather.engagement_range(50.0, RobotArchetype.RobotClass.LONG_RANGE), 40.0, 0.001,
			"a Longneck's 50 m siege range becomes 40 m in fog")


func test_no_weather_is_neutral() -> void:
	Weather.current = null
	assert_eq(Weather.engagement_range_multiplier(RobotArchetype.RobotClass.LONG_RANGE), 1.0)


func test_every_preset_and_weather_composes_and_applies() -> void:
	var env := Environment.new()
	env.sky = Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = load(SKY_SHADER_PATH)
	env.sky.sky_material = sky_material
	var sun := DirectionalLight3D.new()
	for preset in table.presets:
		for weather in table.weathers:
			var label := "%s + %s" % [preset.id, weather.id]
			var look := AtmosphereLook.compose(preset, weather)
			look.apply(env, sun)
			assert_almost_eq(env.fog_depth_end, weather.fog_end, 0.001, label)
			assert_eq(sun.light_color, look.sun_color, label)
			assert_gt(sun.light_energy, 0.0, label + ": the key light stays on")
			assert_eq(sky_material.get_shader_parameter(&"zenith_color"), look.zenith_color, label)
			assert_between(look.cloud_coverage, 0.0, 1.0, label)
			assert_true(env.glow_enabled == (look.glow_intensity > 0.001), label)
	sun.free()


func test_fog_always_hides_the_spawn_ring() -> void:
	for weather in table.weathers:
		var amount := pow(clampf((SPAWN_RING - weather.fog_begin) / (weather.fog_end - weather.fog_begin), 0.0, 1.0), weather.fog_curve)
		assert_gt(amount, 0.7, "%s: %d%% fog at the 110 m spawn ring (GDD 4.7)" % [weather.id, roundi(amount * 100.0)])
		assert_lte(weather.fog_end, 125.0, "%s: fully fogged by 125 m" % weather.id)


func test_morning_fog_boosts_eye_glow() -> void:
	var fog := table.weathers[WEATHER_IDS.find(&"morning_fog")]
	for preset in table.presets:
		var clear := AtmosphereLook.compose(preset)
		var foggy := AtmosphereLook.compose(preset, fog)
		assert_gt(foggy.glow_intensity, clear.glow_intensity, "%s: eye glows are boosted in fog (GDD 4.6)" % preset.id)
		assert_lt(foggy.fog_begin, clear.fog_begin, "%s: fog starts closer" % preset.id)


func test_run_variation_shifts_the_sky() -> void:
	var roll := EnvironmentTable.Roll.new()
	roll.sun_bearing_offset = 12.0
	roll.cloud_offset = Vector2(0.25, 0.5)
	var preset := table.presets[0]
	var look := AtmosphereLook.compose(preset, null, roll)
	assert_almost_eq(look.sun_bearing, fposmod(preset.sun_bearing + 12.0, 360.0), 0.001)
	assert_eq(look.cloud_offset, Vector2(0.25, 0.5))


func test_blend_goes_from_one_look_to_the_next() -> void:
	var a := AtmosphereLook.compose(table.presets[4])
	var b := AtmosphereLook.compose(table.presets[5])
	var start := a.blend(b, 0.0)
	var end := a.blend(b, 1.0)
	assert_eq(start.sun_color, a.sun_color)
	assert_eq(end.sun_color, b.sun_color)
	assert_almost_eq(end.exposure, b.exposure, 0.0001)
	assert_almost_eq(a.blend(b, 0.5).exposure, (a.exposure + b.exposure) * 0.5, 0.0001)
	a.sun_bearing = 350.0
	b.sun_bearing = 10.0
	assert_almost_eq(fposmod(a.blend(b, 0.5).sun_bearing + 180.0, 360.0), 180.0, 0.01, "the light swings the short way past north")
