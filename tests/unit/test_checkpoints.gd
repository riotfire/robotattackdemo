extends GutTest
## The playtest-simulation package (PLAYTEST_SIMULATION_REPORT.md section 6, scenario d): the authored six-wave
## opening's rosters, milestones that never hand over an item, the wave-9 jetpack milestone, the checkpoint
## and its save, and the tighter shotgun.

const CURVE := "res://data/difficulty/default_difficulty.tres"

var _levels: Dictionary = {}
var _parts: Dictionary = {}
var _records: Dictionary = {}
var _granted: Array[String] = []


func before_each() -> void:
	_levels = StatService.levels.duplicate()
	_parts = GameState.parts.duplicate()
	_records = SaveManager.records.duplicate(true)
	_granted = SaveManager.granted_rewards.duplicate()
	StatService.set_levels({&"attack.wrench": 1})
	SaveManager.granted_rewards.clear()
	SaveManager.records["best_wave"] = 0


func after_each() -> void:
	StatService.set_levels(_levels)
	for key: StringName in _parts:
		GameState.parts[key] = _parts[key]
	SaveManager.records = _records
	SaveManager.granted_rewards = _granted


func _opening(wave: int) -> OpeningWave:
	return load("res://data/opening/wave_%d.tres" % wave) as OpeningWave


func _count(opening: OpeningWave, id: StringName, role: StringName = &"*") -> int:
	var total := 0
	for group in opening.groups:
		for i in group.archetype_ids.size():
			if group.archetype_ids[i] == id and (role == &"*" or group.roles[i] == role):
				total += group.counts[i]
	return total


func test_phase_one_is_the_wrench_and_the_roofs() -> void:
	var first := _opening(1)
	assert_eq([first.robot_count(), _count(first, &"nibbler"), first.live_cap, first.main_lanes], [15, 15, 4, 1],
			"wave 1: 15 Nibblers, at most 4 alive, one lane")
	var sizes := first.groups.map(func(g: OpeningGroup) -> int: return g.robot_count())
	assert_true(sizes.has(1) and sizes.has(2) and sizes.max() == 2, "in singles and pairs (%s)" % [sizes])
	for i in range(1, first.groups.size()):
		assert_lte(first.groups[i].release_time - first.groups[i - 1].release_time, 6.0,
				"they keep coming: group %d follows within 6 s" % i)
	assert_eq(first.lane_pool, PackedInt32Array([1, 2]), "the lane in front of the farmer's start")
	var second := _opening(2)
	assert_eq(second.groups[0].archetype_ids, [&"roof_lobber"] as Array[StringName], "wave 2: the first Lobber, first")
	assert_eq(second.groups[0].roof, &"ToolShed", "on the tool shed, the short climb from the rain barrel")
	assert_eq([_count(second, &"roof_lobber"), _count(second, &"nibbler"), _count(second, &"clanker")], [2, 12, 0],
			"two Lobbers and a steady stream of Nibblers")
	assert_eq(second.groups.filter(func(g: OpeningGroup) -> bool: return g.roof == &"ToolShed").size(), 2,
			"both Lobbers on the tool shed")
	assert_eq(StatService.milestone_wave(StatService.PISTOL_ID), 2, "and clearing it opens the pistol")
	var third := _opening(3)
	assert_true(third.has_foreman() and third.foreman_hp == 350.0 and third.foreman_cancels_adds,
			"wave 3: the 350 HP first Foreman, whose defeat calls off the adds")
	assert_eq([_count(third, &"nibbler"), _count(third, &"clanker")], [4, 0], "with only 4 Nibblers")
	assert_eq(third.groups[0].archetype_ids, [&"thumper"] as Array[StringName], "it enters alone, first")
	assert_gte(third.groups[1].release_time, 15.0, "adds only after the first slam lesson")


func test_phase_two_splits_the_pressure() -> void:
	var lesson := _opening(4)
	assert_eq([_count(lesson, &"clanker"), _count(lesson, &"nibbler", &"thief")], [2, 1],
			"wave 4: a Clanker pair for the new pistol and exactly one teaching thief")
	var thief_group := lesson.groups[2]
	assert_eq([thief_group.after_group, thief_group.after_delay], [1, 6.0], "the thief waits for the pair, then a respite")
	assert_eq(lesson.groups.filter(func(g: OpeningGroup) -> bool: return g.roof == &"Barn").size(), 1,
			"a Lobber on the barn roof, at the end of the silo dome's cable")
	var twist := _opening(5)
	assert_eq(twist.lane_pool, PackedInt32Array([5, 6]), "wave 5's main lane is on the silo ladder's side")
	assert_eq(_count(twist, &"rung_runner"), 2, "two Rung Runners")
	assert_eq(twist.groups[0].archetype_ids, [&"rung_runner"] as Array[StringName], "the first climbs first")
	var raids := twist.groups.filter(func(g: OpeningGroup) -> bool: return g.lane_slot == 2)
	assert_eq(raids.size(), 2, "two raids from the far side")
	assert_true(raids.all(func(g: OpeningGroup) -> bool: return g.announce), "both announced")
	assert_lte(raids[0].release_time, twist.groups[0].release_time + 10.0, "the first while the first Runner climbs")
	assert_eq(_count(twist, &"nibbler", &"thief"), 1, "one thief at most")
	var haul := _opening(6)
	assert_true(haul.has_foreman() and haul.foreman_hp == 900.0 and haul.foreman_throw_phase,
			"wave 6: the second Foreman at 900 HP (not the curve's ~1,700), throwing clods")
	assert_eq(haul.groups[0].lane_slot, 2, "from the far side")
	assert_eq([_count(haul, &"roof_lobber"), _count(haul, &"rung_runner")], [1, 2], "while climbers take the ladder")


func test_the_opening_saves_drones_spitters_and_heavies_for_later() -> void:
	for wave in range(1, 7):
		var opening := _opening(wave)
		assert_eq(opening.wave, wave)
		assert_eq(_count(opening, &"drone") + _count(opening, &"spitter"), 0, "wave %d: no flyers or Spitters" % wave)
		assert_eq(_count(opening, &"thumper") - _count(opening, &"thumper", &"foreman"), 0, "wave %d: no regular Heavies" % wave)
		assert_eq(opening.spawn_distance, 45.0, "wave %d: arrivals burst out of the crops 45 m out" % wave)


func test_clearing_waves_never_hands_over_an_item() -> void:
	var levels := StatService.levels.duplicate()
	var parts := GameState.parts.duplicate()
	for wave in range(0, 9):
		var messages := MilestoneRewards.reconcile(wave)
		assert_eq(messages.size(), 1 if wave == 2 else 0, "wave %d: only wave 2 announces something (the pistol blueprint)" % wave)
	assert_eq(StatService.levels, levels, "no weapon, tool or recipe is granted: they're bought at the shed")
	assert_eq(GameState.parts, parts, "and no parts either")
	for id: StringName in [&"attack.pistol", &"attack.shotgun", &"attack.maul", &"build.spring_trap"]:
		assert_not_null(StatService.catalog[id].cost_curve, "%s has a price" % id)
	assert_eq(MilestoneRewards.reconcile(9).size(), 1, "wave 9 announces the jetpack blueprint, once")
	assert_eq(StatService.levels, levels, "which still has to be built at the shed")
	assert_true(MilestoneRewards.reconcile(20).is_empty())


func test_no_gun_before_the_first_roof_lobber_is_beaten() -> void:
	GameState.add_parts({&"al": 200, &"cu": 50})
	SaveManager.records["best_wave"] = 1
	assert_false(StatService.can_purchase(StatService.PISTOL_ID), "the pistol waits for wave 2 (the first Lobber)")
	for gun: StringName in [&"attack.shotgun", &"attack.rifle", &"attack.grenade"]:
		assert_true(StatService.catalog[gun].prerequisites.any(func(r: UpgradeRequirement) -> bool: return r.node_id == StatService.PISTOL_ID),
				"%s needs the pistol, so it waits too" % gun)
	assert_true(StatService.can_purchase(&"attack.maul"), "melee upgrades don't wait")
	SaveManager.records["best_wave"] = 2
	assert_true(StatService.can_purchase(StatService.PISTOL_ID), "from wave 3's intermission on, it's 20 Al at the shed")


func test_the_jetpack_is_a_wave_nine_milestone() -> void:
	GameState.add_parts({&"al": 200, &"cu": 50})
	SaveManager.records["best_wave"] = 8
	assert_false(StatService.can_purchase(StatService.JETPACK_ID), "not before wave 9 has ever been cleared")
	SaveManager.records["best_wave"] = 9
	assert_true(StatService.can_purchase(StatService.JETPACK_ID), "from any later run once it has")


func test_the_checkpoint_and_its_records_round_trip() -> void:
	var path := SaveManager.profile_path
	var test_profile := OS.get_temp_dir().path_join("gut_checkpoint_%d.json" % OS.get_process_id())
	SaveManager.profile_path = test_profile
	SaveManager.resume_wave = 7
	SaveManager.seen_intros = ["rung_runner"]
	SaveManager.record_foreman_bounty(3)
	SaveManager.records["phase_attempts"] = {}
	SaveManager.record_phase_attempt(2, 3, true)
	SaveManager.save_profile()
	SaveManager.resume_wave = 1
	SaveManager.seen_intros = []
	SaveManager.load_profile()
	assert_eq(SaveManager.resume_wave, 7)
	assert_eq(SaveManager.seen_intros, ["rung_runner"] as Array[String])
	assert_true(SaveManager.foreman_bounty_paid(3))
	assert_eq(SaveManager.phase_attempts(2), {"latest": 3, "best": 3})
	assert_false(SaveManager.first_time("rung_runner"), "a debut caption shows once per profile")
	DirAccess.remove_absolute(test_profile)
	SaveManager.profile_path = path


func test_a_full_harvest_needs_no_retries() -> void:
	var start := GameState.start_wave
	var retried := GameState.retried
	var survived := GameState.waves_survived
	SaveManager.records["best_full_harvest_wave"] = 0
	GameState.start_wave = 1
	GameState.waves_survived = 5
	GameState.retried = true
	SaveManager._record_run()
	assert_eq(int(SaveManager.records["best_full_harvest_wave"]), 0, "a phase 1 retry starts at wave 1 but isn't one")
	GameState.retried = false
	SaveManager._record_run()
	assert_eq(int(SaveManager.records["best_full_harvest_wave"]), 5)
	GameState.start_wave = start
	GameState.retried = retried
	GameState.waves_survived = survived


func test_the_shotgun_inner_ring_lands_on_a_small_robot_at_six_metres() -> void:
	var spread := tan(deg_to_rad(Shotgun.SPREAD_DEGREES))
	var inner := 6.0 * spread * Shotgun.pellet_offset(1).length()
	var outer := 6.0 * spread * Shotgun.pellet_offset(2).length()
	assert_lt(inner, 0.36, "the centre and three inner pellets hit a Nibbler-sized body at 6 m (%.2f m off)" % inner)
	assert_gt(outer, 0.6, "the outer ring still spreads across a group (%.2f m off)" % outer)


func test_an_authored_foreman_shrugs_off_ranged_hits_but_not_the_open_vent() -> void:
	var archetype := load("res://data/robots/archetypes/thumper.tres") as RobotArchetype
	var foreman := archetype.scene.instantiate() as HeavyRobot
	foreman.setup(archetype, 6, load(CURVE) as DifficultyCurve, RngService.make_rng([3]), null, true, [], null, &"", 900.0)
	foreman.authored = true
	add_child_autofree(foreman)
	foreman.set_physics_process(false)
	var shooter := Node3D.new()
	add_child_autofree(shooter)
	shooter.global_position = foreman.global_position + Vector3(0.0, 0.0, 15.0)
	var hp := foreman.health.current
	foreman.take_damage(DamagePacket.create(100.0, shooter, foreman.global_position + Vector3.UP))
	assert_almost_eq(hp - foreman.health.current, 100.0 * HeavyRobot.PLATED_SHARE, 0.01, "a shot from 15 m mostly bounces off")
	shooter.global_position = foreman.global_position + Vector3(0.0, 0.0, 2.0)
	hp = foreman.health.current
	foreman.take_damage(DamagePacket.create(100.0, shooter, foreman.global_position + Vector3.UP))
	assert_almost_eq(hp - foreman.health.current, 100.0, 0.01, "up close every hit counts")
	shooter.global_position = foreman.global_position + Vector3(0.0, 0.0, 15.0)
	foreman._set_vent_open(true)
	var vent := foreman.get_node(^"Model/VentHurtbox/Shape") as Node3D
	hp = foreman.health.current
	foreman.take_damage(DamagePacket.create(100.0, shooter, vent.global_position))
	assert_almost_eq(hp - foreman.health.current, 100.0, 0.01, "a long shot into the open vent gets past the plates")
	var plain := archetype.scene.instantiate() as HeavyRobot
	plain.setup(archetype, 6, load(CURVE) as DifficultyCurve, RngService.make_rng([4]))
	add_child_autofree(plain)
	plain.set_physics_process(false)
	hp = plain.health.current
	plain.take_damage(DamagePacket.create(10.0, shooter, plain.global_position + Vector3.UP))
	assert_almost_eq(hp - plain.health.current, 10.0, 0.01, "an ordinary Thumper has no plates")
