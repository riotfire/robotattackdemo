extends GutTest
## Intermission construction and the starter defenses (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md):
## free placement (anywhere with floor that doesn't overlap the world, a robot or another copy), reservation,
## one job at a time, capacity and the queue limit, cancel and run-end refunds that settle once, the siren
## cutoff, moving, repairing and dismantling a copy, and how springs, decoys and barricades treat robots on the
## ground. Uses the real silo scene (its catwalk is real floor) on a flat ground slab.

const CURVE := "res://data/difficulty/default_difficulty.tres"
const SILO_SCENE := "res://scenes/farm/silo.tscn"
const NIBBLER := "res://data/robots/archetypes/nibbler.tres"
const CLANKER := "res://data/robots/archetypes/clanker.tres"
const STEP := 1.0 / 60.0

var _world: Node3D
var _silo: Silo
var _silo_before: Silo
var _director: WaveDirector
var _manager: ConstructionManager
var _workshop: DefenseWorkshop
var _farmer: Farmer
var _saved_intros: Array[String] = []
var _saved_profile: String
var _levels: Dictionary = {}
var _parts: Dictionary = {}


func before_each() -> void:
	_saved_intros = SaveManager.seen_intros.duplicate()
	_saved_profile = SaveManager.profile_path
	SaveManager.profile_path = OS.get_temp_dir().path_join("gut_defenses_%d.json" % OS.get_process_id())
	_silo_before = GameState.silo
	_levels = StatService.levels.duplicate()
	_parts = GameState.parts.duplicate()
	_world = Node3D.new()
	add_child_autofree(_world)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var slab := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	slab.shape = box
	slab.position = Vector3.DOWN * 0.5
	ground.add_child(slab)
	_world.add_child(ground)
	_silo = (load(SILO_SCENE) as PackedScene).instantiate() as Silo
	_world.add_child(_silo)
	GameState.silo = _silo
	_director = WaveDirector.new()
	_director.curve = load(CURVE) as DifficultyCurve
	_director.phase = WaveDirector.Phase.INTERMISSION
	_world.add_child(_director)
	_manager = ConstructionManager.new()
	_manager.director = _director
	_world.add_child(_manager)
	_workshop = DefenseWorkshop.new()
	_world.add_child(_workshop)
	_workshop.position = Vector3(45.0, 0.0, 0.0)
	_manager.workshop = _workshop
	_farmer = (load("res://scenes/player/farmer.tscn") as PackedScene).instantiate() as Farmer
	_world.add_child(_farmer)
	_farmer.set_physics_process(false)
	_farmer.global_position = Vector3(-80.0, 0.0, -80.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_manager.set_physics_process(false)
	StatService.grant(&"build.spring_trap")
	StatService.grant(&"build.decoy")
	StatService.grant(&"build.barricade")
	for key in GameState.PART_KEYS:
		GameState.parts[key] = 0
	GameState.parts[&"al"] = 100


func after_each() -> void:
	_manager.settle_run_end()
	DirAccess.remove_absolute(SaveManager.profile_path)
	SaveManager.profile_path = _saved_profile
	SaveManager.seen_intros = _saved_intros
	StatService.set_levels(_levels)
	for key: StringName in _parts:
		GameState.parts[key] = _parts[key]
	GameState.silo = _silo_before


func _spring() -> DefenseDefinition:
	return _manager.definition(&"spring_trap")


func _barricade() -> DefenseDefinition:
	return _manager.definition(&"scrap_barricade")


func _decoy() -> DefenseDefinition:
	return _manager.definition(&"scarecrow_decoy")


func _work(seconds: float) -> void:
	for i in roundi(seconds / STEP):
		_manager._physics_process(STEP)


## A spot on the open ground.
func _ground(definition: DefenseDefinition, at: Vector3, out: Vector3 = Vector3.FORWARD) -> ConstructionManager.Spot:
	return _manager.spot_at(at, out, definition)


## A spot on the silo's first catwalk, `degrees` around from +Z.
func _catwalk(definition: DefenseDefinition, degrees: float) -> ConstructionManager.Spot:
	var angle := deg_to_rad(degrees)
	var at := _silo.global_position + Vector3(sin(angle), 0.0, cos(angle)) * LadderRobot.CATWALK_RADIUS + Vector3.UP * 8.0
	return _manager.spot_at(at, Vector3.FORWARD, definition, at.y)


## Queues a paid copy at the workbench, then walks away so assembly runs unassisted.
func _queue(definition: DefenseDefinition) -> DefenseSite:
	_farmer.global_position = _workshop.interaction_point()
	assert_eq(_manager.craft(definition, _farmer), "", "%s queued at the stables" % definition.display_name)
	var site := _manager.jobs[-1].site if not _manager.jobs.is_empty() else null
	_farmer.global_position = Vector3(-80.0, 0.0, -80.0)
	return site


## Behavior fixtures go through the full workshop → pickup → deployment lifecycle.
func _place(definition: DefenseDefinition, spot: ConstructionManager.Spot) -> DefenseSite:
	var stock := _queue(definition)
	_work(definition.assembly_time + 0.1)
	_farmer.global_position = stock.global_position
	assert_true(_manager.pick_up(stock, _farmer))
	_manager._stop_placing()
	assert_eq(_manager.put_down(spot), "", "%s deployed" % definition.display_name)
	_farmer.global_position = Vector3(-80.0, 0.0, -80.0)
	return _manager.sites[-1]


func test_the_starter_defenses_match_the_plan() -> void:
	var spring := _spring()
	var decoy := _decoy()
	var wall := _barricade()
	assert_eq([spring.cost_al, spring.capacity, spring.assembly_time], [12, 2, 10.0], "spring: 12 Al, 2 capacity, 10 s")
	assert_eq([decoy.cost_al, decoy.capacity, decoy.assembly_time], [6, 1, 5.0], "decoy: 6 Al, 1 capacity, 5 s")
	assert_eq([wall.cost_al, wall.capacity, wall.assembly_time], [8, 2, 8.0], "barricade: 8 Al, 2 capacity, 8 s")
	for definition in [spring, decoy, wall]:
		assert_eq((definition as DefenseDefinition).cost().keys(), [&"al"], "base copies cost only Aluminium")
	assert_eq(_manager.capacity_total(), 8, "a capacity of eight")
	assert_eq(_manager.sites.size(), 0, "no marked build spots: the farm starts empty")


func test_a_copy_goes_anywhere_with_floor_that_nothing_occupies() -> void:
	var open := _ground(_spring(), Vector3(17.0, 0.0, -23.0))
	assert_eq([open.problem, open.kind], ["", &"ground"], "any open patch of ground")
	assert_almost_eq(open.position.y, 0.0, 0.01, "it sits on the floor")
	assert_ne(_ground(_spring(), Vector3(2.0, 0.0, 0.0)).problem, "", "not inside the silo")
	assert_ne(_ground(_spring(), Vector3(300.0, 0.0, 0.0)).problem, "", "not where there is no floor")
	_place(_spring(), open)
	assert_string_contains(_ground(_decoy(), Vector3(17.5, 0.0, -23.0)).problem, "Too close", "not on top of another copy")
	assert_eq(_ground(_decoy(), Vector3(19.5, 0.0, -23.0)).problem, "", "but right beside it")
	var wall := _ground(_barricade(), Vector3(17.0, 0.0, -26.0), Vector3.FORWARD)
	assert_eq(wall.problem, "", "a wall clear of the spring")
	var across := _ground(_barricade(), Vector3(16.5, 0.0, -23.0), Vector3.RIGHT)
	assert_string_contains(across.problem, "Too close", "a wall whose length would cross the spring")


func test_the_catwalk_is_the_ring_the_climbers_walk() -> void:
	var spot := _catwalk(_spring(), 120.0)
	assert_eq([spot.problem, spot.kind], ["", &"catwalk"])
	var out := spot.position - _silo.global_position
	out.y = 0.0
	assert_almost_eq(out.length(), LadderRobot.CATWALK_RADIUS, 0.01, "snapped onto the ring")
	assert_almost_eq(spot.launch.dot(out.normalized()), 1.0, 0.01, "a catwalk spring throws off the edge")
	var site := _place(_spring(), spot)
	assert_almost_eq(site.catwalk_angle, deg_to_rad(120.0), 0.01, "climbers find it by its angle")
	var roof := _manager.spot_at(Vector3(0.0, 16.0, LadderRobot.CATWALK_RADIUS), Vector3.FORWARD, _barricade(), 16.0)
	assert_string_contains(roof.problem, "can't go", "a barricade never goes on a roof or the upper ring")


func test_a_blueprint_reserves_its_cost_and_one_job_works_at_a_time() -> void:
	var east := _queue(_spring())
	assert_eq(GameState.parts[&"al"], 88, "the whole cost is reserved at once")
	_queue(_barricade())
	assert_eq(_manager.capacity_used(), 4, "jobs reserve capacity too")
	_work(5.0)
	assert_almost_eq(_manager.jobs[0].fraction(), 0.5, 0.02, "the first job advances")
	assert_eq(_manager.jobs[1].done, 0.0, "the one behind it waits")
	_work(5.5)
	assert_true(east.occupant.ready_for_pickup and not east.occupant.active, "a finished copy waits inactive for pickup")
	assert_eq(_manager.jobs.size(), 1, "the next job takes over")


func test_capacity_and_the_queue_limit_refuse_more() -> void:
	for i in 3:
		_queue(_decoy())
	assert_ne(_manager.placement_problem(_decoy(), _ground(_decoy(), Vector3(29.0, 0.0, 0.0))), "",
			"one active job and two waiting at most")
	_work(16.0)
	_queue(_spring())
	_queue(_spring())
	_work(25.0)
	assert_eq(_manager.capacity_used(), 7)
	assert_string_contains(_manager.placement_problem(_spring(), _ground(_spring(), Vector3(40.0, 0.0, 10.0))), "capacity",
			"capacity caps automation")


func test_cancelling_refunds_only_the_unbuilt_share() -> void:
	var site := _queue(_spring())
	var refund := _manager.cancel(site)
	assert_eq(refund.get(&"al", 0), 12, "nothing built yet: everything back")
	assert_eq(GameState.parts[&"al"], 100)
	assert_eq(_manager.sites.size(), 0, "and the spot is gone with it")
	site = _queue(_spring())
	_work(5.0)
	refund = _manager.cancel(site)
	assert_eq(refund.get(&"al", 0), 6, "half built: the unbuilt half back, the work is lost")
	assert_eq(GameState.parts[&"al"], 94)
	assert_true(_manager.deployed().is_empty() and _manager.jobs.is_empty())


func test_nothing_is_free() -> void:
	GameState.parts[&"al"] = 11
	assert_string_contains(_manager.placement_problem(_spring(), _catwalk(_spring(), 28.0)), "Need 12 Al",
			"every copy costs its parts, the first one too")
	StatService.set_levels({})
	GameState.parts[&"al"] = 100
	assert_eq(_manager.placement_problem(_spring(), _catwalk(_spring(), 28.0)), "",
			"a new profile can build directly, without learning")


func test_the_siren_freezes_unfinished_work_until_the_next_intermission() -> void:
	var east := _queue(_spring())
	_work(4.0)
	_director.phase = WaveDirector.Phase.SIREN
	_manager._on_wave_phase_changed(WaveDirector.Phase.SIREN, 1)
	var before := _manager.jobs[0].done
	_work(10.0)
	assert_eq(_manager.jobs[0].done, before, "no work during the siren or the battle")
	assert_false(east.occupant.active, "the ghost does nothing in battle")
	assert_ne(_manager.placement_problem(_decoy(), _catwalk(_decoy(), -28.0)), "", "nothing new can be placed")
	_director.phase = WaveDirector.Phase.INTERMISSION
	_work(6.5)
	assert_true(east.occupant.ready_for_pickup and not east.occupant.active, "it finishes at the pickup rack next intermission")


func test_the_run_end_refunds_unfinished_work_once() -> void:
	_queue(_spring())
	_work(2.5)
	_manager.settle_run_end()
	assert_eq(GameState.parts[&"al"], 88 + 9, "a quarter built: three quarters of 12 Al back")
	_manager.settle_run_end()
	assert_eq(GameState.parts[&"al"], 97, "never twice")


func test_a_finished_copy_moves_without_parts_and_snaps_back_at_the_siren() -> void:
	var east := _place(_spring(), _catwalk(_spring(), 28.0))
	_work(10.5)
	var copy := east.occupant
	var al := GameState.parts[&"al"]
	assert_true(_manager.pick_up(east))
	assert_eq(_manager.in_hand, copy, "it goes into the farmer's hands")
	assert_eq(_manager.put_down(_catwalk(_spring(), -28.0)), "")
	assert_eq(GameState.parts[&"al"], al, "moving costs no parts")
	assert_almost_eq(_manager.jobs[0].work, 5.0, 0.01, "but takes half the assembly time again")
	var west := _manager.jobs[0].site
	_work(5.5)
	assert_true(west.occupant == copy and copy.active)
	await get_tree().process_frame
	assert_false(is_instance_valid(east), "the old spot is cleared once the move is done")
	assert_true(_manager.pick_up(west))
	_director.phase = WaveDirector.Phase.SIREN
	_manager._on_wave_phase_changed(WaveDirector.Phase.SIREN, 1)
	assert_true(_manager.in_hand == null and west.occupant == copy and copy.active, "the siren puts it back where it was")


func test_cancelling_a_move_puts_the_copy_back() -> void:
	var east := _place(_spring(), _catwalk(_spring(), 28.0))
	_work(10.5)
	var copy := east.occupant
	_manager.pick_up(east)
	_manager.put_down(_catwalk(_spring(), -28.0))
	_manager.cancel(_manager.jobs[0].site)
	assert_true(east.occupant == copy and copy.active and copy.site == east, "back where it stood, finished")
	assert_eq(_manager.deployed().size(), 1)


func test_dismantling_and_repairing_never_pay_or_heal_for_free() -> void:
	var east := _place(_spring(), _catwalk(_spring(), 28.0))
	_work(10.5)
	var copy := east.occupant
	copy.take_damage(DamagePacket.create(copy.max_hp * 0.5, null, copy.global_position))
	assert_eq(_manager.repair_cost(copy), 3, "half broken: 3 Al to repair")
	assert_eq(_manager.salvage_value(copy), 3, "and only 3 Al to dismantle")
	assert_true(_manager.repair(east))
	assert_eq(copy.condition(), 1.0)
	var salvage := _manager.dismantle(east)
	assert_eq(salvage, 6, "dismantling a whole copy returns half its price")
	assert_lt(salvage, _spring().cost_al, "rebuilding always costs more than it returns")


func test_a_broken_copy_stays_spent_and_frees_its_capacity() -> void:
	var east := _place(_spring(), _catwalk(_spring(), 28.0))
	_work(10.5)
	var al := GameState.parts[&"al"]
	var copy := east.occupant
	copy.take_damage(DamagePacket.create(999.0, null, copy.global_position))
	await get_tree().process_frame
	assert_true(_manager.deployed().is_empty(), "nothing stands there any more")
	assert_eq(_manager.capacity_used(), 0)
	assert_eq(GameState.parts[&"al"], al, "no refund for a broken copy")


func test_a_ground_barricade_blocks_the_way_to_the_silo() -> void:
	var site := _place(_barricade(), _ground(_barricade(), Vector3(0.0, 0.0, -10.0), Vector3.FORWARD))
	_work(8.5)
	var wall := site.occupant as ScrapBarricade
	assert_true(wall.active)
	var outside := Vector3(0.5, 0.0, -10.6)
	assert_true(wall.blocks(outside, _silo.global_position, 1.0), "between a robot outside and the silo")
	assert_false(wall.blocks(Vector3(6.0, 0.0, -10.6), _silo.global_position, 1.0), "not for a robot well to the side")
	assert_false(wall.blocks(Vector3(0.0, 0.0, -20.0), _silo.global_position, 1.0), "nor one still far out")


func test_a_ground_decoy_lures_a_few_but_never_thieves_or_foremen() -> void:
	var site := _place(_decoy(), _ground(_decoy(), Vector3(0.0, 0.0, -10.0)))
	_work(5.5)
	var decoy := site.occupant as ScarecrowDecoy
	var robots: Array[Robot] = []
	for i in 5:
		var archetype := load(NIBBLER) as RobotArchetype
		var robot := archetype.scene.instantiate() as Robot
		robot.setup(archetype, 5, load(CURVE) as DifficultyCurve, RngService.make_rng([i]), null, false, [], null, &"calm")
		_world.add_child(robot)
		robot.set_physics_process(false)
		robot.global_position = Vector3(i * 1.0, 0.0, -14.0)
		robot.target_kind = Robot.TargetKind.SILO
		robots.append(robot)
	robots[0].is_thief = true
	decoy._physics_process(1.0)
	var lured := robots.filter(func(robot: Robot) -> bool: return robot.target_defense == decoy).size()
	assert_eq(lured, 3, "it holds three at once")
	assert_ne(robots[0].target_defense, decoy, "never a thief")
	var archetype := load(CLANKER) as RobotArchetype
	var boss := archetype.scene.instantiate() as Robot
	boss.setup(archetype, 5, load(CURVE) as DifficultyCurve, RngService.make_rng([9]), null, true)
	_world.add_child(boss)
	boss.set_physics_process(false)
	assert_false(boss.can_be_lured_by(decoy), "never a Foreman")
	robots[1]._update_defense_target(decoy.definition.lure_time + 0.1)
	assert_ne(robots[1].target_defense, decoy, "each lure runs out")
	assert_false(robots[1].can_be_lured_by(decoy), "and it ignores decoys for a while after")


func test_crafting_and_pickup_require_a_visit_to_the_stables() -> void:
	var al := GameState.parts[&"al"]
	assert_string_contains(_manager.craft(_spring(), _farmer), "stables")
	assert_eq(GameState.parts[&"al"], al, "remote attempts cost nothing")
	assert_string_contains(_manager.place(_spring(), _catwalk(_spring(), 28.0), _farmer), "stables")
	var stock := _queue(_spring())
	assert_false(_manager.pick_up(stock, _farmer), "unfinished copies cannot be collected")
	_work(10.1)
	assert_false(_manager.pick_up(stock, _farmer), "finished copies cannot be collected remotely")
	assert_eq(_manager.capacity_used(), 2, "ready stock still reserves capacity")
	_farmer.global_position = stock.global_position
	Input.action_press(&"interact")
	assert_true(_manager.collect_stock(stock, _farmer))
	_manager._update_placing()
	assert_true(_manager.in_hand != null, "the pickup press cannot also confirm a placement")
	Input.action_release(&"interact")
	assert_true(_manager.is_placing() and _manager.in_hand != null, "pickup starts carrying and placement")
	var blocked := _catwalk(_spring(), 28.0)
	blocked.problem = "Something is in the way"
	assert_ne(_manager.put_down(blocked), "")
	assert_eq(_manager.capacity_used(), 2, "invalid placement doesn't duplicate capacity")
	assert_eq(_manager.put_down(_catwalk(_spring(), 28.0)), "")
	assert_eq(GameState.parts[&"al"], al - 12, "pay once at the workbench, never again on placement")
	assert_true(_manager.jobs.is_empty(), "a finished kit needs no second assembly")
	assert_true(_manager.sites[-1].occupant.active)


func test_cancel_or_siren_returns_a_carried_kit_to_the_pickup_rack() -> void:
	var stock := _queue(_spring())
	_work(10.1)
	_farmer.global_position = stock.global_position
	assert_true(_manager.collect_stock(stock, _farmer))
	_manager._cancel_placing()
	assert_true(stock.occupant.ready_for_pickup and not stock.occupant.active)
	assert_eq(_manager.capacity_used(), 2)
	assert_true(_manager.collect_stock(stock, _farmer))
	_director.phase = WaveDirector.Phase.SIREN
	_manager._on_wave_phase_changed(WaveDirector.Phase.SIREN, 1)
	assert_true(_manager.in_hand == null and stock.occupant.ready_for_pickup and not stock.occupant.active)
	assert_false(_manager.is_placing())
	assert_eq(GameState.parts[&"al"], 88, "returning a finished kit creates no refund")


func test_direct_building_has_no_learning_fee_and_only_ready_items_appear() -> void:
	StatService.set_levels({})
	var entries := _manager._recipe_entries(_farmer)
	for entry in entries:
		assert_false(String(entry.get("text", "")).contains("Learn"))
	assert_eq(entries.filter(func(entry: Dictionary) -> bool: return String(entry.get("text", "")).begins_with("BUILD")).size(), 3)
	var before := GameState.parts[&"al"]
	var stock := _queue(_spring())
	assert_eq(GameState.parts[&"al"], before - 12, "only the physical copy is paid for")
	assert_false(stock.occupant.visible, "no pickup model is shown before assembly finishes")
	assert_false(stock.can_interact(_farmer), "unfinished stock has no pickup prompt")
	_work(10.1)
	assert_true(stock.occupant.visible and stock.occupant.ready_for_pickup)
	assert_string_contains(stock.occupant._hp_label.text, "Spring Trap READY")


func test_defense_upgrades_are_bought_at_the_stables_only() -> void:
	GameState.parts[&"cu"] = 100
	_farmer.global_position = _workshop.interaction_point()
	_manager._buy_workshop_upgrade(_farmer, &"build.coil_springs")
	assert_eq(StatService.level_of(&"build.coil_springs"), 1)
	_farmer.global_position = Vector3(-80.0, 0.0, -80.0)
	var before := GameState.parts.duplicate()
	_manager._buy_workshop_upgrade(_farmer, &"build.coil_springs")
	assert_eq(StatService.level_of(&"build.coil_springs"), 1, "remote upgrades are refused")
	assert_eq(GameState.parts, before)
