extends GutTest
## Progress before wave five, no bell farming, conserved bounties, and the intermission loot window.

var _saved_parts: Dictionary = {}
var _saved_levels: Dictionary = {}
var _saved_survived: int = 0
var _saved_silo: Silo
var _saved_profile_path: String = ""
var _test_profile_path: String = ""
var _saved_records: Dictionary = {}


func before_each() -> void:
	_saved_profile_path = SaveManager.profile_path
	_test_profile_path = OS.get_temp_dir().path_join("gut_economy_%d.json" % OS.get_process_id())
	SaveManager.profile_path = _test_profile_path
	_saved_parts = GameState.parts.duplicate()
	_saved_levels = StatService.levels.duplicate()
	_saved_survived = GameState.waves_survived
	_saved_silo = GameState.silo
	_saved_records = SaveManager.records.duplicate(true)
	SaveManager.records["best_wave"] = 0
	SaveManager.records["foreman_bounties"] = []
	GameState.silo = null
	GameState.clear_parts()
	StatService.set_levels({})


func after_each() -> void:
	for part: StringName in _saved_parts:
		GameState.parts[part] = _saved_parts[part]
	GameState.waves_survived = _saved_survived
	GameState.silo = _saved_silo
	StatService.set_levels(_saved_levels)
	SaveManager.records = _saved_records
	SaveManager.profile_path = _saved_profile_path
	DirAccess.remove_absolute(_test_profile_path)


func test_earned_rare_progress_starts_before_the_foreman_and_settles_once() -> void:
	var director := _director(2)
	assert_true(director.clear_rewards_for(1).is_empty())
	assert_true(director.clear_rewards_for(3).is_empty())
	assert_eq(director._settle_clear_parts(), {&"cu": 2, &"au": 1, &"pc": 1} as Dictionary[StringName, int])
	assert_eq(GameState.parts[&"pc"], 1, "a wave-two clear guarantees progress before wave five")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_test_profile_path))
	assert_eq(saved["parts"]["pc"], 1.0, "the earned guarantee is persisted immediately")
	assert_true(director._settle_clear_parts().is_empty(), "the same wave cannot pay twice")
	assert_eq(GameState.parts[&"pc"], 1)
	director.wave = 4
	director._settle_clear_parts()
	assert_eq(GameState.parts[&"pc"], 2)
	var retry := _director(2)
	retry._settle_clear_parts()
	assert_eq(GameState.parts[&"pc"], 3, "actually clearing again on a retry still earns progress")


func test_bell_rewards_require_a_clear_and_do_not_scale_with_skipped_time() -> void:
	for duration: float in [10.0, 90.0, 120.0]:
		GameState.clear_parts()
		var director := _director(2)
		director.time_left = duration
		director.ring_bell()
		assert_eq(GameState.parts[&"al"], 0, "ringing is not an immediate deposit")
		director._settle_clear_parts()
		assert_eq(GameState.parts[&"al"], 5, "timer settings do not multiply income")
		assert_true(director._settle_clear_parts().is_empty())
	GameState.clear_parts()
	var failed := _director(1)
	failed.ring_bell()
	failed._on_game_over(&"silo")
	assert_eq(GameState.parts[&"al"], 0, "ringing and losing earns no Aluminium")
	StatService.grant(&"farmhand.early_bird", 3)
	var upgraded := _director(1)
	upgraded.ring_bell()
	upgraded._settle_clear_parts()
	assert_eq(GameState.parts[&"al"], 8, "existing Early Bird ranks retain their multiplier")
	# A cheap retry must not farm it (PHASE_CHECKPOINT_PROGRESSION_PLAN.md): only waves above the best pay.
	GameState.clear_parts()
	SaveManager.records["best_wave"] = 2
	var retry := _director(2)
	retry.ring_bell()
	retry._settle_clear_parts()
	assert_eq(GameState.parts[&"al"], 0, "a wave already beaten pays no Early Bird")


func test_foreman_rare_bounty_is_banked_without_duplicating_physical_loot() -> void:
	var robot := Robot.new()
	robot.is_foreman = true
	robot.wave = 3
	var physical := robot.roll_drops()
	robot.bank_guaranteed_parts(physical)
	assert_eq(GameState.parts[&"pc"], 2, "every third wave is a Foreman wave now: 2 Power Cells")
	assert_eq(GameState.parts[&"au"], 1, "and 1 Gold")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_test_profile_path))
	assert_eq(saved["parts"]["pc"], 2.0, "the Foreman bounty survives closing during battle")
	assert_eq(physical.get(&"pc", 0), 0, "banked cells cannot also appear as pickups")
	assert_eq(physical.get(&"au", 0), 0)
	assert_eq(physical[&"al"], 10)
	assert_eq(physical[&"cu"], 6)
	robot.bank_guaranteed_parts(physical)
	assert_eq(GameState.parts[&"pc"], 2, "resettling the same burst does not pay again")
	assert_eq(GameState.parts[&"au"], 1)
	robot.free()


func test_the_foreman_bounty_pays_once_per_foreman_wave_on_a_profile() -> void:
	var first := Robot.new()
	first.is_foreman = true
	first.wave = 3
	first.archetype = load("res://data/robots/archetypes/thumper.tres") as RobotArchetype
	first.bank_guaranteed_parts(first.roll_drops())
	assert_true(SaveManager.foreman_bounty_paid(3))
	var again := Robot.new()
	again.is_foreman = true
	again.wave = 3
	again.archetype = first.archetype
	assert_ne(again.roll_drops(), Robot.FOREMAN_DROPS, "a retry's Foreman drops the Heavy's own table")
	var pc := GameState.parts[&"pc"]
	again.bank_guaranteed_parts(again.roll_drops())
	assert_eq(GameState.parts[&"pc"], pc, "and banks no second bounty")
	var next := Robot.new()
	next.is_foreman = true
	next.wave = 6
	assert_eq(next.roll_drops(), Robot.FOREMAN_DROPS, "the next Foreman wave pays its own first bounty")
	for robot in [first, again, next]:
		robot.free()


func test_ordinary_robot_loot_still_requires_collection() -> void:
	var robot := Robot.new()
	var physical: Dictionary[StringName, int] = {&"al": 3, &"cu": 1, &"au": 1, &"pc": 1}
	robot.bank_guaranteed_parts(physical)
	assert_eq(GameState.parts[&"pc"], 0)
	assert_eq(physical[&"pc"], 1)
	robot.free()


func test_parts_survive_a_long_battle_but_grain_keeps_its_objective_timer() -> void:
	var part := _part(7)
	part.set(&"_age", 300.0)
	part._physics_process(0.01)
	assert_false(part.is_queued_for_deletion(), "old parts remain for the following intermission")
	var sack := Pickup.new()
	sack.kind = Pickup.GRAIN
	sack.amount = 20
	add_child_autofree(sack)
	sack.set(&"_age", 21.0)
	sack._physics_process(0.01)
	assert_true(sack.is_queued_for_deletion(), "grain sacks retain their burst deadline")


func test_clear_preserves_parts_and_next_battle_sweeps_only_the_old_pickups() -> void:
	StatService.grant(&"farmhand.scrap_vac", 5)
	var director := _director(1)
	add_child(director)
	var old := _part(7)
	director._enter_cleared()
	assert_false(old.is_queued_for_deletion(), "the clear jingle does not consume collectible parts")
	director._enter_intermission(90.0)
	assert_false(old.is_queued_for_deletion())
	director._enter_siren(3.0)
	assert_false(old.is_queued_for_deletion(), "the siren leaves a final collection opportunity")
	var new_pickups: Array[Pickup] = []
	var on_started := func(_wave: int) -> void: new_pickups.append(_part(4))
	EventBus.wave_started.connect(on_started, CONNECT_ONE_SHOT)
	director._enter_spawning()
	assert_true(old.is_queued_for_deletion())
	assert_eq(GameState.parts[&"al"], 7, "a fully upgraded Vac banks the old loot exactly once")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_test_profile_path))
	assert_eq(saved["parts"]["al"], 7.0, "the next-battle sweep is saved after its deposit")
	assert_eq(old.vacuum(1.0, RngService.make_rng([99])), 0, "a queued pickup cannot be swept twice")
	assert_eq(GameState.parts[&"al"], 7)
	assert_eq(new_pickups.size(), 1)
	assert_false(new_pickups[0].is_queued_for_deletion(), "new-battle loot is outside the old sweep")


func _director(wave_number: int) -> WaveDirector:
	var director := WaveDirector.new()
	director.curve = load("res://data/difficulty/default_difficulty.tres") as DifficultyCurve
	director.wave = wave_number
	# No tree registration: these tests exercise transactions, not a second running wave loop.
	autofree(director)
	return director


func _part(amount: int) -> Pickup:
	var pickup := Pickup.new()
	pickup.kind = &"al"
	pickup.amount = amount
	pickup.position = Vector3(1000.0, 1.0, 1000.0)
	add_child_autofree(pickup)
	return pickup
