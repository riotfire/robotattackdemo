extends GutTest
## DifficultyCurve against the tables in GDD 11.3-11.6, 10.3 and Appendix A.

const CURVE_PATH := "res://data/difficulty/default_difficulty.tres"

var curve: DifficultyCurve


func before_each() -> void:
	curve = load(CURVE_PATH) as DifficultyCurve


func test_spawn_window_matches_gdd_table() -> void:
	var expected: Dictionary[int, float] = {1: 45.0, 5: 73.0, 10: 108.0, 15: 143.0, 20: 178.0, 25: 210.0, 40: 210.0}
	for wave in expected:
		assert_almost_eq(curve.spawn_window(wave), expected[wave], 0.001, "spawn window, wave %d" % wave)


func test_base_threat_budget_matches_gdd_table() -> void:
	var expected: Dictionary[int, int] = {1: 18, 2: 27, 5: 61, 10: 132, 15: 215, 20: 307, 30: 511, 40: 738, 60: 1242}
	for wave in expected:
		assert_eq(roundi(curve.base_threat_budget(wave)), expected[wave], "base budget, wave %d" % wave)


func test_big_haul_every_fifth_wave_multiplies_budget() -> void:
	for wave: int in [5, 10, 15, 60]:
		assert_true(curve.is_big_haul(wave), "wave %d is a Big Haul" % wave)
		assert_almost_eq(curve.threat_budget(wave), curve.base_threat_budget(wave) * 1.3, 0.001)
	for wave: int in [1, 4, 6, 11]:
		assert_false(curve.is_big_haul(wave), "wave %d is not a Big Haul" % wave)
		assert_almost_eq(curve.threat_budget(wave), curve.base_threat_budget(wave), 0.001)


func test_hp_multiplier_matches_gdd_table() -> void:
	var expected: Dictionary[int, float] = {1: 1.0, 10: 1.79, 20: 3.05, 30: 4.71, 40: 6.77, 60: 12.1}
	for wave in expected:
		assert_almost_eq(curve.hp_multiplier(wave), expected[wave], 0.01, "HP multiplier, wave %d" % wave)


func test_damage_multiplier_matches_gdd_table() -> void:
	var expected: Dictionary[int, float] = {1: 1.0, 10: 1.44, 20: 2.12, 30: 3.0, 40: 4.08, 60: 6.84}
	for wave in expected:
		assert_almost_eq(curve.damage_multiplier(wave), expected[wave], 0.01, "damage multiplier, wave %d" % wave)


func test_drop_multiplier() -> void:
	assert_almost_eq(curve.drop_multiplier(1), 1.0, 0.0001)
	assert_almost_eq(curve.drop_multiplier(11), 1.3, 0.0001)


func test_trait_count_steps() -> void:
	var expected: Dictionary[int, int] = {1: 0, 5: 0, 6: 1, 15: 1, 16: 2, 30: 2, 31: 3, 80: 3}
	for wave in expected:
		assert_eq(curve.trait_count(wave), expected[wave], "traits, wave %d" % wave)


func test_lane_count_steps() -> void:
	var expected: Dictionary[int, int] = {1: 2, 4: 2, 5: 3, 14: 3, 15: 4, 29: 4, 30: 5, 99: 5}
	for wave in expected:
		assert_eq(curve.lane_count(wave), expected[wave], "lanes, wave %d" % wave)


func test_spawn_schedule_is_sorted_and_inside_the_window() -> void:
	var times := curve.spawn_schedule(40, 100.0)
	assert_eq(times.size(), 40)
	for i in times.size():
		assert_between(times[i], 0.0, 100.0)
		if i > 0:
			assert_true(times[i] >= times[i - 1], "sorted at %d" % i)
	assert_eq(curve.spawn_schedule(0, 45.0).size(), 0, "no spawns, no times")


func test_spawn_schedule_opens_with_a_spawn_right_away() -> void:
	for count in [1, 3, 8, 40]:
		assert_eq(curve.spawn_schedule(count, 45.0)[0], 0.0, "first spawn at 0 s (%d spawns)" % count)


func test_spawn_schedule_is_wave_shaped_not_even() -> void:
	var times := curve.spawn_schedule(60, 100.0)
	var opening := 0
	var big_peak := 0
	var lull := 0
	for t in times:
		if t < 16.0:
			opening += 1
		elif t >= 50.0 and t < 60.0:
			lull += 1
		elif t >= 70.0 and t < 86.0:
			big_peak += 1
	assert_gt(big_peak, opening * 2, "the second peak is much denser than the opening ramp")
	assert_gt(big_peak, lull * 2, "there is a lull before the bigger peak")


func test_nibbler_costs_two_threat() -> void:
	var nibbler := load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype
	assert_almost_eq(nibbler.threat_cost(), 2.0, 0.0001)
	assert_eq(floori(curve.threat_budget(1) / nibbler.threat_cost()), 9, "wave 1 buys 9 Nibblers")


func test_thief_share_starts_at_ten_percent_and_creeps_up() -> void:
	assert_almost_eq(curve.thief_share(1), 0.10, 0.0001, "wave 1 thieves")
	assert_true(curve.thief_share(6) > curve.thief_share(5), "the share rises each wave")
	assert_almost_eq(curve.thief_share(200), curve.thief_share_cap, 0.0001, "the share is capped")


func test_thief_chance_hits_the_share_after_the_silo_focus_roll() -> void:
	# Scouts roll silo focus first, so the steal roll is scaled up to land on the same overall share.
	var silo_focus := 0.7
	var overall := silo_focus * curve.thief_chance(1, silo_focus)
	assert_almost_eq(overall, curve.thief_share(1), 0.0001)


func test_thieving_family_raises_the_share_up_to_its_cap() -> void:
	assert_almost_eq(curve.thief_share(1, true), 0.15, 0.0001, "x1.5 in wave 1")
	assert_almost_eq(curve.thief_share(200, true), curve.thieving_share_cap, 0.0001, "capped at 60%")
	var silo_focus := 0.7
	var overall := silo_focus * curve.thief_chance(10, silo_focus, true)
	assert_almost_eq(overall, curve.thief_share(10, true), 0.0001, "the steal roll still lands on the share")


func test_archetype_costs_follow_size_and_attack_style() -> void:
	# Per robot (GDD 11.4): Small 2, Medium 4, Large 14; melee x1.0, ranged x1.25, flight x1.6.
	var archetype := RobotArchetype.new()
	archetype.robot_type = RobotArchetype.RobotType.GRUNT
	assert_almost_eq(archetype.threat_cost(), 4.0, 0.0001, "a solo Clanker costs twice a Nibbler")
	archetype.robot_class = RobotArchetype.RobotClass.RANGED
	assert_almost_eq(archetype.threat_cost(), 5.0, 0.0001)
	archetype.robot_type = RobotArchetype.RobotType.HEAVY
	archetype.robot_class = RobotArchetype.RobotClass.FLIGHT
	assert_almost_eq(archetype.threat_cost(), 22.4, 0.0001)


func test_small_ground_trio_chance_steps_up_then_climbs() -> void:
	var nibbler := load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype
	assert_almost_eq(curve.trio_chance(1, nibbler), 0.4, 0.001, "40% in wave 1")
	assert_almost_eq(curve.trio_chance(2, nibbler), 0.4, 0.001, "40% in wave 2")
	assert_almost_eq(curve.trio_chance(3, nibbler), 0.6, 0.001, "60% from wave 3")
	assert_almost_eq(curve.trio_chance(15, nibbler), 0.7, 0.001, "70% by wave 15")
	assert_almost_eq(curve.trio_chance(40, nibbler), 0.7, 0.001, "and no higher")
	assert_true(curve.trio_chance(9, nibbler) > 0.6 and curve.trio_chance(9, nibbler) < 0.7, "climbing in between")
	var clanker := load("res://data/robots/archetypes/clanker.tres") as RobotArchetype
	assert_almost_eq(curve.trio_chance(2, clanker), 0.15, 0.001, "medium robots rarely form trios")
	assert_almost_eq(curve.trio_chance(30, clanker), 0.15, 0.001, "at any wave")


func test_large_robots_flyers_and_foremen_never_form_trios() -> void:
	for path in ["res://data/robots/archetypes/thumper.tres", "res://data/robots/archetypes/drone.tres"]:
		var archetype := (load(path) as RobotArchetype).duplicate() as RobotArchetype
		archetype.trio_chance = 1.0
		archetype.trio_chance_late = 1.0
		for wave in [1, 10, 40]:
			assert_eq(curve.trio_chance(wave, archetype), 0.0, "%s in wave %d" % [archetype.id, wave])
	var nibbler := load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype
	assert_eq(curve.trio_chance(10, nibbler, true), 0.0, "a Foreman is always solo")


# --- Attack scaling (M2-B10, robot attack variety plan "Scaling from wave 6") ----------------------------

func test_waves_one_to_five_keep_every_attack_knob_at_its_m1_value() -> void:
	for wave in range(1, 6):
		assert_eq(curve.attack_phase(wave), 0, "wave %d is the opening" % wave)
		assert_eq(curve.farmer_attack_tokens(wave), 2)
		assert_eq(curve.charge_multiplier(wave), 1.0)
		assert_eq(curve.aim_lead(wave), 0.0)
		assert_eq(curve.volley_size(wave), 1)
		assert_eq(curve.spitter_share(wave), 0.0)
		assert_true(curve.column_weights(wave).is_empty(), "wave %d keeps the plain type weights" % wave)
		assert_false(curve.throws_at_unreachable(wave))
		assert_false(curve.arm_guard_up(wave))


func test_attack_phases_follow_the_waves_per_phase_steps() -> void:
	assert_eq([curve.attack_phase(6), curve.attack_phase(15), curve.attack_phase(16), curve.attack_phase(30),
			curve.attack_phase(31), curve.attack_phase(80)], [1, 1, 2, 2, 3, 3])


func test_farmer_tokens_are_three_four_five_by_phase() -> void:
	assert_eq([curve.farmer_attack_tokens(6), curve.farmer_attack_tokens(15)], [3, 3])
	assert_eq([curve.farmer_attack_tokens(16), curve.farmer_attack_tokens(30)], [4, 4])
	assert_eq([curve.farmer_attack_tokens(31), curve.farmer_attack_tokens(60)], [5, 5])


func test_charge_multiplier_shrinks_by_phase_but_never_under_the_floor() -> void:
	assert_almost_eq(curve.charge_multiplier(6), 0.9, 0.0001)
	assert_almost_eq(curve.charge_multiplier(16), 0.8, 0.0001)
	assert_almost_eq(curve.charge_multiplier(31), 0.7, 0.0001)
	for file_name in DirAccess.get_files_at(RobotArchetype.ATTACK_DIR):
		if file_name.get_extension() != "tres":
			continue
		var profile := load(RobotArchetype.ATTACK_DIR.path_join(file_name)) as AttackProfile
		for wave in [6, 16, 31, 100]:
			assert_gte(profile.effective_charge_time(curve.charge_multiplier(wave)), AttackProfile.MIN_CHARGE_TIME,
					"%s at wave %d still charges at least 0.45 s" % [profile.id, wave])


func test_aim_lead_waits_for_wave_ten() -> void:
	for wave in range(6, 10):
		assert_eq(curve.aim_lead(wave), 0.0, "wave %d: no lead" % wave)
	assert_almost_eq(curve.aim_lead(10), 0.3, 0.0001)
	assert_almost_eq(curve.aim_lead(15), 0.3, 0.0001)
	assert_almost_eq(curve.aim_lead(16), 0.6, 0.0001)
	assert_almost_eq(curve.aim_lead(40), 0.6, 0.0001)


func test_volley_size_grows_from_wave_sixteen() -> void:
	assert_eq([curve.volley_size(6), curve.volley_size(15)], [1, 1])
	assert_eq([curve.volley_size(16), curve.volley_size(23)], [2, 2], "2-3 in the middle phase: 2 first")
	assert_eq([curve.volley_size(24), curve.volley_size(31), curve.volley_size(70)], [3, 3, 3])


func test_spitter_share_starts_at_wave_seven_and_caps_at_forty_percent() -> void:
	assert_eq(curve.spitter_share(6), 0.0)
	assert_almost_eq(curve.spitter_share(7), 0.10, 0.0001)
	assert_almost_eq(curve.spitter_share(8), 0.12, 0.0001, "+2 points a wave")
	assert_almost_eq(curve.spitter_share(16), 0.28, 0.0001)
	assert_almost_eq(curve.spitter_share(22), 0.40, 0.0001)
	assert_almost_eq(curve.spitter_share(50), 0.40, 0.0001, "capped")


func test_column_weights_by_phase() -> void:
	assert_eq(curve.column_weights(6), PackedFloat32Array([0.60, 0.28, 0.12]))
	assert_eq(curve.column_weights(16), PackedFloat32Array([0.52, 0.30, 0.18]))
	assert_eq(curve.column_weights(31), PackedFloat32Array([0.45, 0.33, 0.22]))


func test_the_director_gives_each_column_its_share() -> void:
	var director := WaveDirector.new()
	director.curve = curve
	var options: Array[RobotArchetype] = []
	for id in ["nibbler", "clanker", "thumper", "roof_lobber", "drone"]:
		options.append(load("res://data/robots/archetypes/%s.tres" % id) as RobotArchetype)
	var plain := director.option_weights(options, 4)
	for i in options.size():
		assert_almost_eq(plain[i], director.type_weights[int(options[i].robot_type)] * options[i].spawn_weight, 0.0001,
				"wave 4: %s keeps its type weight" % options[i].id)
	for wave in [6, 16, 31]:
		var weights := director.option_weights(options, wave)
		var shares := PackedFloat32Array([0.0, 0.0, 0.0])
		var total := 0.0
		for i in options.size():
			shares[int(options[i].robot_class)] += weights[i]
			total += weights[i]
		for column in 3:
			assert_almost_eq(shares[column] / total, curve.column_weights(wave)[column], 0.0001,
					"wave %d column %d share" % [wave, column])
		assert_almost_eq(weights[1] / weights[0], plain[1] / plain[0], 0.0001,
				"within a column the type weights still decide")
	var melee_only: Array[RobotArchetype] = [options[0], options[1]]
	var weights := director.option_weights(melee_only, 6)
	assert_almost_eq(weights[0] + weights[1], 1.0, 0.0001, "a missing column's share goes to the others")
	director.free()


func test_waves_one_to_six_build_the_same_spawns_with_or_without_spitters() -> void:
	var director := WaveDirector.new()
	director.curve = curve
	for id in ["nibbler", "clanker", "thumper", "roof_lobber", "drone"]:
		director.archetypes.append(load("res://data/robots/archetypes/%s.tres" % id) as RobotArchetype)
	var describe := func(events: Array) -> Array:
		return events.map(func(e: WaveDirector.SpawnEvent) -> String: return "%s x%d" % [e.archetype.id, e.robot_count()])
	for wave in range(1, 7):
		director.spitter_archetype = null
		director.set(&"_wave_rng", RngService.make_rng([17, wave]))
		var without: Array = describe.call(director.call(&"_build_spawn_events", wave))
		director.spitter_archetype = load("res://data/robots/archetypes/spitter.tres") as RobotArchetype
		director.set(&"_wave_rng", RngService.make_rng([17, wave]))
		var with: Array = describe.call(director.call(&"_build_spawn_events", wave))
		assert_eq(with, without, "wave %d is untouched by the Spitter role" % wave)
	director.free()


func test_throws_from_wave_seven_and_the_arm_guard_from_wave_six() -> void:
	assert_false(curve.throws_at_unreachable(6))
	assert_true(curve.throws_at_unreachable(7))
	assert_false(curve.arm_guard_up(5))
	assert_true(curve.arm_guard_up(6))
