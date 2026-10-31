extends GutTest
## Pegboard data and stat stacking (GDD 12.4, 13, 18.4).

var _saved_levels: Dictionary = {}
var _saved_parts: Dictionary = {}
var _saved_profile_path: String = ""
var _test_profile_path: String = ""


func before_each() -> void:
	# Purchases autosave, so point SaveManager at a throwaway file instead of the player's profile.
	_saved_profile_path = SaveManager.profile_path
	_test_profile_path = OS.get_temp_dir().path_join("gut_upgrades_%d.json" % OS.get_process_id())
	SaveManager.profile_path = _test_profile_path
	_saved_levels = StatService.levels.duplicate()
	_saved_parts = GameState.parts.duplicate()
	StatService.set_levels({})


func after_each() -> void:
	StatService.set_levels(_saved_levels)
	for key: StringName in _saved_parts:
		GameState.parts[key] = _saved_parts[key]
	SaveManager.profile_path = _saved_profile_path
	DirAccess.remove_absolute(_test_profile_path)


func test_pistol_damage_uses_aluminium_throughout_with_reachable_rare_finishers() -> void:
	var curve := (StatService.catalog[&"attack.pistol_damage"] as UpgradeNode).cost_curve
	var al: Array[int] = [15, 19, 23, 29, 37, 46, 57, 72, 89, 112]
	var cu: Array[int] = [3, 4, 5, 6, 7, 9, 11]
	var au: Array[int] = [1, 1, 2, 2]
	for level in range(1, 11):
		var cost := curve.cost(level)
		assert_eq(cost.get(&"al", 0), al[level - 1], "Al at level %d" % level)
		assert_eq(cost.get(&"cu", 0), cu[level - 4] if level >= 4 else 0, "Cu at level %d" % level)
		assert_eq(cost.get(&"au", 0), au[level - 7] if level >= 7 else 0, "Au at level %d" % level)
	assert_eq(curve.cost(9).get(&"pc", 0), 1)
	assert_eq(curve.cost(10).get(&"pc", 0), 2)


func test_modifier_kinds() -> void:
	assert_almost_eq(StatModifier.make(&"x", StatModifier.Kind.FLAT, 10.0).value_at(3), 30.0, 0.0001)
	assert_almost_eq(StatModifier.make(&"x", StatModifier.Kind.ADD_PCT, 0.12).value_at(5), 0.6, 0.0001)
	assert_almost_eq(StatModifier.make(&"x", StatModifier.Kind.MUL, 1.2).value_at(3), 1.728, 0.0001)
	assert_almost_eq(StatModifier.make(&"x", StatModifier.Kind.MAX, 25.0).value_at(1), 25.0, 0.0001)
	var early_bird := StatModifier.make(&"x", StatModifier.Kind.ADD_PCT, 0.0, PackedFloat32Array([0.25, 0.5, 0.75]))
	assert_almost_eq(early_bird.value_at(2), 0.5, 0.0001)
	assert_almost_eq(early_bird.value_at(0), 0.0, 0.0001)


func test_fuel_tank_compounds_like_gdd_table() -> void:
	var expected: Array[float] = [1.2, 1.44, 1.73, 2.07, 2.49, 2.99, 3.58, 4.30, 5.16, 6.19, 7.43]
	for level in 11:
		StatService.set_levels({&"travel.jetpack": 1, &"travel.fuel_tank": level})
		assert_almost_eq(StatService.get_stat(&"jetpack.flight_time", 1.2), expected[level], 0.01, "Fuel Tank %d" % level)


func test_stacks_add_multiply_and_take_max() -> void:
	StatService.set_levels({&"travel.comfy_boots": 5, &"defend.armor_overalls": 1, &"defend.armor_vest": 1,
			&"travel.jetpack": 1, &"travel.quick_refill": 4, &"defend.hearty_breakfast": 2})
	assert_almost_eq(StatService.get_stat(&"player.run_speed", 7.0), 8.05, 0.0001, "+3% x5 run speed")
	assert_almost_eq(StatService.get_stat(&"player.armor", 0.0), 50.0, 0.0001, "armor tiers take the best tier")
	assert_almost_eq(StatService.get_stat(&"jetpack.recharge_delay", 0.5), 0.25, 0.0001, "Quick Refill 4 cuts the delay")
	assert_almost_eq(StatService.get_stat(&"jetpack.recharge_speed", 1.0), 1.6, 0.0001)
	assert_almost_eq(StatService.get_stat(&"player.max_hp", 100.0), 120.0, 0.0001)
	assert_almost_eq(StatService.get_stat(&"silo.leak_rate", 1.0), 1.0, 0.0001, "unowned stats keep their base")


func test_flags_respect_their_level() -> void:
	StatService.set_levels({&"travel.comfy_boots": 3})
	assert_false(StatService.has_flag(&"pistol.unlocked"), "not owned, not on")
	StatService.set_levels({&"travel.comfy_boots": 3, &"attack.pistol": 1})
	assert_true(StatService.has_flag(&"pistol.unlocked"), "level 1 turns the flag on")


## DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md: the paid jump-height and zipline-speed ranks are retired
## and prior purchases compensated, at the higher of the two historical prices, exactly once.
func test_retired_ranks_are_refunded_once() -> void:
	var levels := {"travel.springy_soles": 3, "travel.zipline_grip": 2, "travel.comfy_boots": 1}
	var refund := RetiredUpgrades.refund(levels)
	assert_eq(refund, {&"al": 15 + 20 + 27 + 25 + 34, &"cu": 10} as Dictionary[StringName, int])
	assert_eq(levels.keys(), ["travel.comfy_boots"], "the retired levels are gone, the rest kept")
	assert_true(RetiredUpgrades.refund(levels).is_empty(), "nothing left to refund twice")
	assert_false(StatService.catalog.has(&"travel.springy_soles") or StatService.catalog.has(&"travel.zipline_grip"),
			"they are off the pegboard")


func test_the_tool_shed_has_no_defense_tools_or_upgrades() -> void:
	var board := PegboardUI.new()
	add_child_autofree(board)
	GameState.parts[&"al"] = 500
	assert_false(board._tabs.has(UpgradeNode.Branch.BUILD))
	for id: StringName in StatService.catalog:
		if StatService.catalog[id].branch == UpgradeNode.Branch.BUILD:
			assert_null(board.peg_button(id), "defense pegs are absent from the shed")
			assert_false(board.buy(id), "the shed API also refuses defense purchases")
	assert_eq(GameState.parts[&"al"], 500)


func test_purchase_spends_parts_and_checks_prerequisites() -> void:
	GameState.parts[&"al"] = 100
	assert_false(StatService.can_purchase(&"attack.pistol_damage"), "needs the pistol first")
	assert_true(StatService.purchase(&"attack.pistol"))
	assert_eq(GameState.parts[&"al"], 80, "the pistol costs 20 Al")
	assert_true(StatService.has_flag(&"pistol.unlocked"))
	assert_false(StatService.purchase(&"attack.pistol"), "unlocks are bought once")
	assert_true(StatService.purchase(&"attack.pistol_damage"))
	assert_eq(GameState.parts[&"al"], 65)
	GameState.parts[&"al"] = 0
	assert_false(StatService.purchase(&"attack.pistol_damage"), "can't buy without the parts")


func test_catalog_is_complete_and_consistent() -> void:
	var purchasable := 0
	for id in StatService.catalog:
		var node := StatService.catalog[id]
		assert_eq(node.id, id)
		assert_gt(node.max_level, 0, "%s has levels" % id)
		for requirement in node.prerequisites:
			assert_true(StatService.catalog.has(requirement.node_id), "%s requires a real node (%s)" % [id, requirement.node_id])
		if node.cost_curve == null:
			continue
		purchasable += 1
		for level in range(1, node.max_level + 1):
			assert_false(node.cost_curve.cost(level).is_empty(), "%s level %d has a cost" % [id, level])
	assert_gte(purchasable, 40, "the tool shed includes the new weapon and jetpack combat choices")
