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


func test_thief_chance_hits_the_share_after_the_farmer_roll() -> void:
	# Scouts roll for the farmer first, so the steal roll is scaled up to land on the same overall share.
	var farmer_chance := 0.3
	var overall := (1.0 - farmer_chance) * curve.thief_chance(1, farmer_chance)
	assert_almost_eq(overall, curve.thief_share(1), 0.0001)


func test_archetype_costs_follow_type_and_class() -> void:
	var archetype := RobotArchetype.new()
	archetype.robot_type = RobotArchetype.RobotType.GRUNT
	archetype.robot_class = RobotArchetype.RobotClass.SHORT_RANGE
	assert_almost_eq(archetype.threat_cost(), 7.5, 0.0001)
	archetype.robot_type = RobotArchetype.RobotType.HEAVY
	archetype.robot_class = RobotArchetype.RobotClass.LONG_RANGE
	assert_almost_eq(archetype.threat_cost(), 22.4, 0.0001)
