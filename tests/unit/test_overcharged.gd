extends GutTest
## Overcharged (GDD 10.3): x2 Power Cell chance, and robots explode on death. The blast hurts robots and
## farmers nearby; Overcharged robots it kills go off in turn, so a tight pack chains.

const NIBBLER := "res://data/robots/archetypes/nibbler.tres"
const THUMPER := "res://data/robots/archetypes/thumper.tres"
const OVERCHARGED := "res://data/robots/traits/overcharged.tres"


func after_each() -> void:
	Engine.time_scale = 1.0


func test_overcharged_doubles_the_power_cell_chance_and_sizes_its_blast() -> void:
	var world := _ground()
	var plain := _robot(world, NIBBLER, Vector3(-10.0, 0.0, 0.0), false)
	var charged := _robot(world, NIBBLER, Vector3(10.0, 0.0, 0.0), true)
	assert_almost_eq(charged.power_cell_chance(), plain.power_cell_chance() * 2.0, 0.0001)
	assert_eq(plain.death_blast_radius, 0.0, "plain robots don't blow up")
	assert_gt(charged.death_blast_radius, 0.0)
	var heavy := _robot(world, THUMPER, Vector3(0.0, 0.0, 20.0), true)
	assert_gt(heavy.death_blast_radius, charged.death_blast_radius, "bigger robots make bigger blasts")
	assert_gt(heavy.death_blast_damage, charged.death_blast_damage)


func test_a_kill_chains_through_a_pack_one_fuse_at_a_time() -> void:
	var world := _ground()
	var pack: Array[Robot] = []
	for i in 4:
		pack.append(_robot(world, NIBBLER, Vector3(i * 2.4, 0.0, 0.0), true))
	var bystander := _robot(world, NIBBLER, Vector3(30.0, 0.0, 0.0), true)
	var player := _stub_player(world, Vector3(-60.0, 0.0, 0.0))
	await wait_physics_frames(2)

	# Physics frame each robot died on, by its place in the pack (-1: still alive).
	var killed_at: Array[int] = [-1, -1, -1, -1]
	for i in pack.size():
		pack[i].destroyed.connect(func(_r: Robot, _killer: Node) -> void: killed_at[i] = Engine.get_physics_frames())
	pack[0].take_damage(DamagePacket.create(99999.0, player, pack[0].global_position))
	await wait_seconds(RobotExplosion.OVERCHARGED_FUSE * 6.0)

	assert_false(killed_at.has(-1), "the whole pack went up (death frames %s)" % [killed_at])
	for i in range(1, pack.size()):
		assert_gt(killed_at[i], killed_at[i - 1], "robot %d died after robot %d" % [i, i - 1])
	assert_gt(killed_at[3] - killed_at[0], 2 * int(RobotExplosion.OVERCHARGED_FUSE * 50.0),
			"the chain ripples one fuse per link instead of all at once")
	assert_true(is_instance_valid(bystander) and bystander.ai_state != Robot.AiState.DEAD, "robots out of range survive")


func test_chain_kills_credit_the_farmer_who_started_it() -> void:
	var world := _ground()
	var first := _robot(world, NIBBLER, Vector3.ZERO, true)
	var second := _robot(world, NIBBLER, Vector3(1.5, 0.0, 0.0), false)
	var player := _stub_player(world, Vector3(-60.0, 0.0, 0.0))
	await wait_physics_frames(2)
	var killers: Array[Node] = []
	var depths: Array[int] = []
	second.destroyed.connect(func(r: Robot, killer: Node) -> void:
		killers.append(killer)
		depths.append(r.chain_depth))
	first.take_damage(DamagePacket.create(99999.0, player, first.global_position))
	await wait_seconds(RobotExplosion.OVERCHARGED_FUSE + 0.2)
	assert_eq(killers, [player] as Array[Node], "a plain robot caught in the blast dies, credited to the farmer")
	assert_eq(depths, [1] as Array[int], "one blast deep")


func test_the_blast_hurts_farmers_in_range_and_pushes_them_away() -> void:
	var world := _ground()
	var robot := _robot(world, NIBBLER, Vector3.ZERO, true)
	var near := _stub_player(world, Vector3(1.5, 0.0, 0.0))
	var far := _stub_player(world, Vector3(20.0, 0.0, 0.0))
	await wait_physics_frames(2)
	robot.take_damage(DamagePacket.create(99999.0, near, robot.global_position))
	await wait_seconds(RobotExplosion.OVERCHARGED_FUSE + 0.2)
	var hits: Array = near.get(&"hits")
	assert_eq(hits.size(), 1, "the near farmer is hit once")
	if hits.size() == 1:
		var packet := hits[0] as DamagePacket
		assert_gt(packet.amount, 0.0)
		assert_gt(packet.knockback.x, 0.0, "and pushed away from the blast")
	assert_eq((far.get(&"hits") as Array).size(), 0, "farmers out of range are safe")


func test_escaping_or_cleared_overcharged_robots_do_not_blow_up() -> void:
	var world := _ground()
	var robot := _robot(world, NIBBLER, Vector3.ZERO, true)
	var neighbour := _robot(world, NIBBLER, Vector3(1.0, 0.0, 0.0), true)
	await wait_physics_frames(2)
	robot.kill(false)
	await wait_seconds(RobotExplosion.OVERCHARGED_FUSE + 0.2)
	assert_true(is_instance_valid(neighbour) and neighbour.ai_state != Robot.AiState.DEAD)


func _ground() -> Node3D:
	var world := Node3D.new()
	add_child_autofree(world)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	shape.shape = box
	body.add_child(shape)
	world.add_child(body)
	body.global_position = Vector3(0.0, -0.5, 0.0)
	return world


func _robot(world: Node3D, path: String, at: Vector3, overcharged: bool) -> Robot:
	# No drops: pickups need the game's current scene, which the test runner doesn't have.
	var archetype := (load(path) as RobotArchetype).duplicate() as RobotArchetype
	archetype.drop_al_min = 0
	archetype.drop_al_max = 0
	archetype.drop_al_class_bonus = 0
	archetype.drop_cu_chance = 0.0
	archetype.drop_au_chance = 0.0
	archetype.drop_pc_chance = 0.01
	archetype.steal_chance = 0.0
	var robot := archetype.scene.instantiate() as Robot
	var traits: Array[RobotTrait] = []
	if overcharged:
		traits.append(load(OVERCHARGED) as RobotTrait)
	robot.setup(archetype, 1, DifficultyCurve.new(), RandomNumberGenerator.new(), null, false, traits)
	world.add_child(robot)
	robot.agent.avoidance_enabled = false
	robot.ai_state = Robot.AiState.RECOVER
	robot.set(&"_attack_timer", 99999.0)
	robot.global_position = at
	return robot


## Stands in for a farmer: in the "players" group, records the damage it takes.
func _stub_player(world: Node3D, at: Vector3) -> Node3D:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar hits: Array = []\nfunc take_damage(packet: DamagePacket) -> void:\n\thits.append(packet)\n"
	script.reload()
	var player := Node3D.new()
	player.set_script(script)
	player.add_to_group(&"players")
	world.add_child(player)
	player.global_position = at
	return player
