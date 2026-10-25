extends GutTest
## Behavior variables and groups (M2-B6, GDD 9.2, 9.6, 11.7): distraction, every return-to-silo rule, heist
## crews and trio rates. RobotTargeting is plain logic, so these drive it with hand-made Senses.

const NIBBLER := "res://data/robots/archetypes/nibbler.tres"
const CLANKER := "res://data/robots/archetypes/clanker.tres"
const THUMPER := "res://data/robots/archetypes/thumper.tres"
const DRONE := "res://data/robots/archetypes/drone.tres"
const SEEDS := 1000

var _farmer: Node3D


func before_each() -> void:
	_farmer = Node3D.new()
	add_child_autofree(_farmer)


## A silo-focused robot whose archetype is `archetype` with `overrides` applied.
func _targeting(overrides: Dictionary = {}, path: String = NIBBLER) -> RobotTargeting:
	var archetype := (load(path) as RobotArchetype).duplicate() as RobotArchetype
	archetype.silo_focus = 1.0
	for key: String in overrides:
		var value: Variant = overrides[key]
		if value is Array:
			var triggers: Array[StringName] = []
			triggers.assign(value)
			value = triggers
		archetype.set(key, value)
	return RobotTargeting.new(archetype, RngService.make_rng([7]))


func _senses(distance: float, extra: Dictionary = {}) -> RobotTargeting.Senses:
	var senses := RobotTargeting.Senses.new()
	senses.farmer = _farmer
	senses.farmer_distance = distance
	senses.distance_from_silo = 6.0
	for key: String in extra:
		senses.set(key, extra[key])
	return senses


## Runs `seconds` of physics frames at 60 fps.
func _run(targeting: RobotTargeting, seconds: float, senses: RobotTargeting.Senses) -> void:
	for i in roundi(seconds * 60.0):
		targeting.tick(1.0 / 60.0, senses)


# --- Distraction -------------------------------------------------------------------------------------

func test_near_trigger_switches_on_the_once_a_second_roll() -> void:
	var targeting := _targeting({"distractibility": 1.0, "commit_time": 0.0})
	_run(targeting, 0.9, _senses(5.0))
	assert_false(targeting.on_farmer(), "no roll before the first second")
	_run(targeting, 0.2, _senses(5.0))
	assert_true(targeting.on_farmer(), "a farmer within distract_range pulls it off the silo")
	assert_eq(targeting.farmer, _farmer)


func test_distractibility_sets_the_chance_per_roll() -> void:
	var switched := 0
	for i in SEEDS:
		var archetype := (load(NIBBLER) as RobotArchetype).duplicate() as RobotArchetype
		archetype.silo_focus = 1.0
		archetype.commit_time = 0.0
		var targeting := RobotTargeting.new(archetype, RngService.make_rng([11, i]))
		_run(targeting, 1.05, _senses(5.0))
		switched += 1 if targeting.on_farmer() else 0
	assert_almost_eq(switched / float(SEEDS), 0.3, 0.05, "a Nibbler's 0.3 distractibility, rolled once")


func test_triggers_only_count_when_listed_and_in_range() -> void:
	var targeting := _targeting({"distractibility": 1.0, "commit_time": 0.0, "distract_triggers": [&"repairing"]})
	_run(targeting, 3.0, _senses(5.0))
	assert_false(targeting.on_farmer(), "near isn't one of its triggers")
	_run(targeting, 3.0, _senses(30.0, {"farmer_repairing": true}))
	assert_false(targeting.on_farmer(), "repairing out of range doesn't count")
	_run(targeting, 1.1, _senses(5.0, {"farmer_repairing": true}))
	assert_true(targeting.on_farmer(), "a farmer repairing within range does")

	var drone := _targeting({"distractibility": 1.0, "commit_time": 0.0}, DRONE)
	drone.archetype.distract_triggers = [&"airborne"]
	_run(drone, 3.0, _senses(10.0))
	assert_false(drone.on_farmer(), "a drone ignores a farmer on the ground")
	_run(drone, 1.1, _senses(10.0, {"farmer_airborne": true}))
	assert_true(drone.on_farmer(), "and goes after one in the air")


func test_hurt_rolls_at_once_but_only_from_within_range() -> void:
	var targeting := _targeting({"distractibility": 1.0, "commit_time": 0.0, "distract_triggers": [&"hurt"]})
	targeting.tick(0.01, _senses(30.0))
	targeting.on_hurt(_farmer, 30.0)
	assert_false(targeting.on_farmer(), "a hit from beyond distract_range doesn't count")
	targeting.on_hurt(_farmer, 4.0)
	assert_true(targeting.on_farmer(), "a hit from up close switches it straight away")
	var deaf := _targeting({"distractibility": 1.0, "commit_time": 0.0, "distract_triggers": [&"near"]})
	deaf.on_hurt(_farmer, 4.0)
	assert_false(deaf.on_farmer(), "without the hurt trigger a hit doesn't distract")


func test_commit_time_stops_flip_flopping() -> void:
	var targeting := _targeting({"distractibility": 1.0, "commit_time": 3.0, "chase_time": 1.0})
	_run(targeting, 1.1, _senses(5.0))
	assert_true(targeting.on_farmer())
	_run(targeting, 1.1, _senses(5.0))
	assert_false(targeting.on_farmer(), "chase time sent it back")
	_run(targeting, 2.0, _senses(5.0))
	assert_false(targeting.on_farmer(), "still committed to the silo")
	_run(targeting, 2.2, _senses(5.0))
	assert_true(targeting.on_farmer(), "after commit_time it can be distracted again")


func test_thieves_and_unreachable_farmers_are_never_distracted() -> void:
	var thief := _targeting({"distractibility": 1.0, "commit_time": 0.0})
	thief.can_be_distracted = false
	_run(thief, 3.0, _senses(2.0))
	thief.on_hurt(_farmer, 2.0)
	assert_false(thief.on_farmer(), "a thief keeps going for its sack")
	var targeting := _targeting({"distractibility": 1.0, "commit_time": 0.0})
	_run(targeting, 3.0, _senses(5.0, {"farmer_reachable": false, "farmer_airborne": true}))
	assert_false(targeting.on_farmer(), "hovering out of reach is no lure")


# --- Return rules ------------------------------------------------------------------------------------

func _chasing(overrides: Dictionary) -> RobotTargeting:
	var targeting := _targeting(overrides)
	targeting.switch_to_farmer(_farmer)
	return targeting


func test_returns_when_the_farmer_goes_down() -> void:
	var targeting := _chasing({"chase_time": 0.0, "leash_range": 0.0})
	var gone := RobotTargeting.Senses.new()
	targeting.farmer = null
	targeting.tick(0.1, gone)
	assert_false(targeting.on_farmer())
	assert_eq(targeting.last_return, RobotTargeting.Return.FARMER_DOWN)


func test_returns_after_chase_time_once_engaged() -> void:
	var targeting := _chasing({"chase_time": 6.0, "leash_range": 0.0})
	_run(targeting, 10.0, _senses(40.0))
	assert_true(targeting.on_farmer(), "the chase clock waits until it is within distract_range")
	_run(targeting, 5.9, _senses(3.0))
	assert_true(targeting.on_farmer())
	_run(targeting, 0.2, _senses(3.0))
	assert_false(targeting.on_farmer())
	assert_eq(targeting.last_return, RobotTargeting.Return.CHASE_TIME)


func test_returns_when_led_past_the_leash() -> void:
	var targeting := _chasing({"chase_time": 0.0, "leash_range": 25.0})
	var senses := _senses(3.0)
	senses.distance_from_silo = 24.0
	_run(targeting, 2.0, senses)
	assert_true(targeting.on_farmer())
	senses.distance_from_silo = 26.0
	targeting.tick(0.02, senses)
	assert_false(targeting.on_farmer())
	assert_eq(targeting.last_return, RobotTargeting.Return.LEASH)


func test_returns_when_the_farmer_stays_out_of_reach() -> void:
	var targeting := _chasing({"chase_time": 0.0, "leash_range": 0.0, "give_up_time": 3.0})
	var senses := _senses(3.0, {"farmer_reachable": false})
	_run(targeting, 2.9, senses)
	assert_true(targeting.on_farmer())
	senses.farmer_reachable = true
	_run(targeting, 0.5, senses)
	senses.farmer_reachable = false
	_run(targeting, 2.9, senses)
	assert_true(targeting.on_farmer(), "coming back into reach resets the clock")
	_run(targeting, 0.2, senses)
	assert_false(targeting.on_farmer())
	assert_eq(targeting.last_return, RobotTargeting.Return.UNREACHABLE)


func test_hunters_roll_from_silo_focus() -> void:
	var hunters := 0
	var nibbler := load(NIBBLER) as RobotArchetype
	for i in SEEDS:
		hunters += 1 if RobotTargeting.new(nibbler, RngService.make_rng([3, i])).hunter else 0
	assert_almost_eq(hunters / float(SEEDS), 1.0 - nibbler.silo_focus, 0.04, "silo focus 0.7: 30% hunt the farmer")


## With M1's values (switch when hurt from within 10 m, give up after 3 s out of reach, nothing else) the
## new rules reproduce the old melee targeting.
func test_m1_values_behave_as_before() -> void:
	var m1 := {"distractibility": 1.0, "distract_triggers": [&"hurt"], "distract_range": 10.0, "commit_time": 0.0,
			"chase_time": 0.0, "leash_range": 0.0, "give_up_time": 3.0}
	var targeting := _targeting(m1, CLANKER)
	_run(targeting, 5.0, _senses(2.0, {"farmer_repairing": true, "farmer_airborne": true}))
	assert_false(targeting.on_farmer(), "a farmer standing close by doesn't distract")
	targeting.on_hurt(_farmer, 9.5)
	assert_true(targeting.on_farmer(), "a hit from within 10 m switches it at once")
	var far := _senses(60.0)
	far.distance_from_silo = 80.0
	_run(targeting, 30.0, far)
	assert_true(targeting.on_farmer(), "it chases for as long as it takes")
	_run(targeting, 3.1, _senses(3.0, {"farmer_reachable": false}))
	assert_false(targeting.on_farmer(), "and gives up 3 s after the farmer gets out of reach")


# --- Groups ------------------------------------------------------------------------------------------

func _director(wave_seed: int) -> WaveDirector:
	var director := WaveDirector.new()
	director.curve = load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	director.set(&"_wave_rng", RngService.make_rng([5, wave_seed]))
	return director


func test_trio_rates_over_a_thousand_seeds() -> void:
	var director := _director(0)
	var curve := director.curve
	for case: Array in [[NIBBLER, 1], [NIBBLER, 3], [NIBBLER, 15], [CLANKER, 2], [CLANKER, 20]]:
		var archetype := load(case[0]) as RobotArchetype
		var wave: int = case[1]
		var trios := 0
		for i in SEEDS:
			director.set(&"_wave_rng", RngService.make_rng([5, wave, i]))
			trios += 1 if director.roll_group_size(wave, archetype, 1000.0) == 3 else 0
		assert_almost_eq(trios / float(SEEDS), curve.trio_chance(wave, archetype), 0.04,
				"%s trios in wave %d" % [archetype.id, wave])
	director.free()


func test_large_robots_flyers_and_foremen_are_always_solo() -> void:
	var director := _director(0)
	for path in [THUMPER, DRONE]:
		var archetype := (load(path) as RobotArchetype).duplicate() as RobotArchetype
		archetype.trio_chance = 1.0
		for i in SEEDS:
			director.set(&"_wave_rng", RngService.make_rng([9, i]))
			assert_eq(director.roll_group_size(20, archetype, 1000.0), 1, "%s never forms a trio" % archetype.id)
	assert_eq(WaveDirector.SpawnEvent.new(load(NIBBLER) as RobotArchetype, true, 3).robot_count(), 1,
			"the Foreman always comes alone")
	director.free()


func test_a_trio_only_forms_when_the_budget_covers_three() -> void:
	var director := _director(0)
	var nibbler := (load(NIBBLER) as RobotArchetype).duplicate() as RobotArchetype
	nibbler.trio_chance = 1.0
	assert_eq(director.roll_group_size(1, nibbler, 6.0), 3)
	assert_eq(director.roll_group_size(1, nibbler, 5.0), 1, "two robots' budget left: a solo")
	director.free()


func test_trio_followers_share_the_leaders_rolls() -> void:
	var nibbler := load(NIBBLER) as RobotArchetype
	var curve := DifficultyCurve.new()
	for i in 200:
		var rng := RngService.make_rng([21, i])
		var squad := RobotSquad.new()
		var trio: Array[Robot] = []
		for slot in 3:
			var robot := nibbler.scene.instantiate() as Robot
			robot.setup(nibbler, 6, curve, rng, null, false, [], squad)
			trio.append(robot)
		assert_true(trio[1].targeting == trio[0].targeting and trio[2].targeting == trio[0].targeting,
				"one RobotTargeting for the trio")
		for robot in trio:
			robot.free()


func test_a_thief_trio_is_a_heist_crew() -> void:
	var nibbler := (load(NIBBLER) as RobotArchetype).duplicate() as RobotArchetype
	nibbler.silo_focus = 1.0
	var curve := DifficultyCurve.new()
	curve.thief_share_base = 1.0
	curve.thief_share_cap = 1.0
	var squad := RobotSquad.new()
	var rng := RngService.make_rng([4])
	var trio: Array[Robot] = []
	for slot in 3:
		var robot := nibbler.scene.instantiate() as Robot
		robot.setup(nibbler, 6, curve, rng, null, false, [], squad)
		trio.append(robot)
	assert_true(trio[0].is_thief and trio[0].target_kind == Robot.TargetKind.CHUTE, "the leader carries the sack")
	assert_eq(squad.heist_leader, trio[0])
	for robot in [trio[1], trio[2]]:
		assert_false(robot.is_thief, "escorts carry no sack, so the crew counts as one thief")
		assert_true(robot.is_escort and robot.target_kind == Robot.TargetKind.ESCORT, "the other two escort it")
	trio[0].targeting.on_hurt(_farmer, 2.0)
	assert_false(trio[0].targeting.on_farmer(), "the thief isn't distracted by a hit")
	# The thief is destroyed: its escorts carry on as an ordinary pair.
	trio[0].ai_state = Robot.AiState.DEAD
	trio[1].call(&"_update_escort")
	assert_false(trio[1].is_escort, "no thief, no escort")
	assert_eq(trio[1].target_kind, Robot.TargetKind.SILO, "back on the silo")
	assert_true(trio[1].targeting.can_be_distracted, "and distractible again")
	for robot in trio:
		robot.free()


func test_the_thief_share_counts_groups_not_robots() -> void:
	# Every spawn event rolls one thief at most, so the share of thief events matches the curve's share.
	var nibbler := load(NIBBLER) as RobotArchetype
	var curve := load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	var thieves := 0
	for i in SEEDS:
		var rng := RngService.make_rng([8, i])
		var squad := RobotSquad.new()
		var group: Array[Robot] = []
		for slot in 3:
			var robot := nibbler.scene.instantiate() as Robot
			robot.setup(nibbler, 10, curve, rng, null, false, [], squad)
			group.append(robot)
		thieves += group.filter(func(r: Robot) -> bool: return r.is_thief).size()
		for robot in group:
			robot.free()
	assert_almost_eq(thieves / float(SEEDS), curve.thief_share(10), 0.04, "one thief per heist crew")
