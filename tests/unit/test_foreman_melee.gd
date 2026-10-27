extends GutTest
## The authored Foreman can be beaten with the wrench alone: during the punish window a close hit from
## behind is a vent hit (x3), even pressed against its back where the swing passes under the vent box.

const THUMPER := "res://data/robots/archetypes/thumper.tres"
const CURVE := "res://data/difficulty/default_difficulty.tres"
const WRENCH := "res://data/weapons/wrench.tres"

var _world: Node3D


func before_each() -> void:
	_world = Node3D.new()
	add_child_autofree(_world)


func _foreman(hp: float) -> HeavyRobot:
	var archetype := load(THUMPER) as RobotArchetype
	var robot := archetype.scene.instantiate() as HeavyRobot
	robot.setup(archetype, 3, load(CURVE) as DifficultyCurve, RngService.make_rng([1]), null, true, [], null, &"", hp)
	robot.authored = true
	_world.add_child(robot)
	robot.global_position = Vector3.ZERO
	robot.model.rotation.y = 0.0
	robot.set_physics_process(false)
	return robot


## Damage a 25-point body hit from `at` does to `robot`.
func _hit_from(robot: HeavyRobot, at: Vector3) -> float:
	var source := Node3D.new()
	_world.add_child(source)
	source.global_position = at
	var before := robot.health.current
	robot.take_damage(DamagePacket.create(25.0, source, robot.global_position + Vector3.UP))
	source.free()
	return before - robot.health.current


func test_a_close_hit_from_behind_is_a_vent_hit_while_it_glows() -> void:
	var robot := _foreman(1000.0)
	# The model faces -Z, so its back (and vent) is on +Z. 1.2 m is as close as the two capsules allow.
	assert_eq(_hit_from(robot, Vector3(0.0, 0.0, 1.2)), 25.0, "vent closed: an ordinary body hit")
	robot.call(&"_set_vent_open", true)
	for distance: float in [1.2, 2.0, 3.0]:
		assert_eq(_hit_from(robot, Vector3(0.0, 0.0, distance)), 75.0, "vent open: x3 from %.1f m behind" % distance)
	assert_eq(_hit_from(robot, Vector3(1.0, 0.0, 1.0)), 75.0, "from behind and to one side")
	assert_eq(_hit_from(robot, Vector3(0.0, 0.0, -1.5)), 25.0, "but not from the front")
	assert_eq(_hit_from(robot, Vector3(0.0, 0.0, 5.0)), 25.0, "and not from beyond wrench range")


func test_the_first_foreman_falls_to_the_wrench_in_two_punish_windows() -> void:
	var melee := load(WRENCH) as MeleeWeaponData
	var opening := load("res://data/opening/wave_3.tres") as OpeningWave
	# Three swings fit in the 2.5 s punish window at 1.6 swings/s, one of them the x1.5 finisher.
	var per_window := melee.damage * HeavyRobot.VENT_OPEN_MULTIPLIER * (2.0 + melee.combo_multiplier)
	assert_lte(ceili(opening.foreman_hp / per_window), 2,
			"%.0f HP against %.0f per window" % [opening.foreman_hp, per_window])
