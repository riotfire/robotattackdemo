class_name TutorialDirector
extends Node
## Level 0 "Morning Chores": an untimed prologue that walks a new player round the farm's stations by doing the
## chores that matter. The same HUD used during waves explains each action and shows its progress. A low floor
## ring and a trail of glowing pebbles lead the player to the next place without replacing the normal UI.
##
##   1. SILO     A crack leaks grain. Hold Interact beside it with the wrench until it seals.
##   2. DUMMY    Grandpa's spring-loaded Dummy-Bot pops up on a hay bale. Swing the wrench; it drops a little Aluminium
##               and its spring bonks you for 20 (so you have a reason for the next step).
##   3. PORCH    Stand on the Home porch until the normal HP bar is full: this is where you heal.
##   4. PRACTICE Stop one slow Nibbler with the wrench. If it lands a hit, repair the resulting leak.
##   5. CATWALK  Climb the silo ladder to the top. A short camera sweep lights up the chicken house,
##               the water tower and the 8 robot lanes in the corn.
##   6. ZIPLINE  Already on top of the silo, ride the zipline down to the barn roof.
##   7. BELL     Hold Interact on the dinner bell to start a melee-only wave 1. The shed opens after wave 1.
## The bell works from the start, so a player who just wants to play can skip: no bonus, same siren.
## Runs only while WaveDirector is in its TUTORIAL phase (a profile that hasn't finished it yet).

enum Step { INTRO, SILO, DUMMY, PORCH, PRACTICE, REPAIR, CATWALK, ZIPLINE, BELL, DONE }

## The ground-level silo socket facing the farmer's spawn.
const CRACK_SOCKET: int = 0
const CRACK_POOL: float = 100.0
const DUMMY_POSITION := Vector3(-18.0, 0.0, 17.0)
const STARTER_AL: int = 5
## Standing on the silo's cap; the dome peaks at about 24 m.
const SILO_TOP_HEIGHT: float = 23.0
const PRACTICE_POSITION := Vector3(-12.0, 0.0, 8.0)
const EARLY_BIRD_AL: int = 5
## How long the camera lingers on each vista target.
const VISTA_SECONDS: float = 1.5
const GOLD := Color(1.0, 0.8, 0.25)
const GREEN := Color(0.45, 0.9, 0.45)
const RED := Color(1.0, 0.35, 0.25)
const SKY := Color(0.55, 0.85, 1.0)

var step: Step = Step.INTRO

var _main: Node
var _farmer: Farmer
var _director: WaveDirector
var _hud: Hud
var _silo: Silo
var _shed: ToolShed
var _bell: DinnerBell
var _zipline: Zipline
var _zip_ridden: bool = false
var _heal_zone: HealZone
var _farm: Node3D

var _marker: TutorialMarker
var _retired: Array[TutorialMarker] = []
var _vista_lessons: PackedStringArray = PackedStringArray()
var _trail: TutorialTrail
var _crack: SiloCrack
var _dummy: TutorialDummy
var _practice_robot: Robot
var _practice_crack: SiloCrack
var _practice_trail_left: float = 0.0
var _al_before_pop: int = 0
var _dummy_dead_time: float = -1.0
var _bonked: bool = false
var _porch_time: float = 0.0
var _vista_time: float = -1.0
var _vista_cam: Camera3D
var _vista_yaw: float = 0.0
var _vista_targets: Array[Vector3] = []
var _vista_step: int = -1
var _finished: bool = false


## Called by Main once the farmer exists and the wave director sits in TUTORIAL.
func begin(main: Node) -> void:
	_main = main
	_farmer = GameState.players[0] as Farmer if not GameState.players.is_empty() else null
	_director = main.get_node(^"WaveDirector") as WaveDirector
	_hud = main.get_node_or_null(^"HUD") as Hud
	_farm = main.get_node(^"Farm") as Node3D
	_silo = GameState.silo
	_heal_zone = _farm.get_node_or_null(^"PorchHealZone") as HealZone
	_bell = _farm.get_node_or_null(^"DinnerBell") as DinnerBell
	_zipline = _farm.get_node_or_null(^"Ziplines/Z1_SiloToBarn") as Zipline
	_shed = get_tree().get_first_node_in_group(ToolShed.GROUP_SHED) as ToolShed
	if _farmer == null or _silo == null or _shed == null or _bell == null or _heal_zone == null or _director == null:
		push_warning("TutorialDirector: the farm is missing a station; skipping Level 0.")
		_director.finish_tutorial()
		queue_free()
		return
	_trail = TutorialTrail.new()
	_trail.name = "Trail"
	add_child(_trail)
	_trail.setup(_farmer)
	_shed.tutorial_locked = true
	EventBus.crack_closed.connect(_on_crack_closed)
	EventBus.silo_damaged.connect(_on_silo_damaged)
	EventBus.wave_phase_changed.connect(_on_phase_changed)
	_go(Step.SILO)


func _exit_tree() -> void:
	_drop_vista_cam()
	if _farmer != null and is_instance_valid(_farmer):
		_farmer.input.enabled = true


# --- Steps ----------------------------------------------------------------------------------------

func _go(next: Step) -> void:
	step = next
	_retire_marker()
	EventBus.tutorial_step_changed.emit(int(next))
	match next:
		Step.SILO:
			_begin_silo()
		Step.DUMMY:
			_begin_dummy()
		Step.PORCH:
			_begin_porch()
		Step.PRACTICE:
			_begin_practice()
		Step.REPAIR:
			_begin_repair()
		Step.CATWALK:
			_begin_catwalk()
		Step.ZIPLINE:
			_begin_zipline()
		Step.BELL:
			_begin_bell()


func _begin_silo() -> void:
	_lesson("This silo holds the grain. A leak drains it.\nHold Interact at the crack to seal it.")
	_action("Follow the trail to the silo leak")
	_crack = _silo.open_tutorial_crack(CRACK_SOCKET, CRACK_POOL)
	if _crack == null:
		_go(Step.DUMMY)
		return
	var stand := _crack.global_position + _crack.global_basis.z * 1.5
	stand.y = 0.0
	_show(TutorialMarker.create(stand, GOLD, 1.4))
	_trail.set_goal(stand)


func _begin_dummy() -> void:
	_lesson("Robots can be stopped with your wrench.\nBonk this practice bot three times.")
	_action("V / (R3): bonk the Dummy-Bot with your wrench")
	var approach := DUMMY_POSITION + Vector3(0.0, 0.0, 2.0)
	_trail.set_goal(approach)
	_dummy = TutorialDummy.new()
	_dummy.name = "TutorialDummy"
	_dummy.drop_al = STARTER_AL
	_main.add_child(_dummy)
	var toward_silo := Vector3.ZERO - DUMMY_POSITION
	_dummy.global_position = DUMMY_POSITION
	_dummy.rotation.y = atan2(toward_silo.x, toward_silo.z)
	_dummy.destroyed.connect(_on_dummy_destroyed)
	_dummy.bonked.connect(func(_who: Farmer) -> void: _bonked = true)
	_al_before_pop = GameState.parts[&"al"]
	_show(TutorialMarker.create(approach, RED, 1.4))


func _begin_porch() -> void:
	_lesson("That bot hurt you. Stand on the farmhouse porch to heal.")
	_action("Follow the trail to the porch; watch your normal HP bar refill")
	var where := Vector3(_heal_zone.global_position.x, 0.35, _heal_zone.global_position.z)
	_trail.set_goal(where)
	var marker := TutorialMarker.create(where, GREEN, 2.0)
	marker.add_child(_steam())
	_show(marker)
	_porch_time = 0.0


func _begin_catwalk() -> void:
	_lesson("Climb to the very top of the silo to see where robots come from.")
	_action("Follow the trail to the silo ladder and climb to the top")
	var ladder := _silo.get_node_or_null(^"Ladder") as Node3D
	var foot := (ladder.global_position if ladder != null else _silo.global_position + Vector3(0, 0, 6.2)) + Vector3(0.0, 0.0, 0.8)
	foot.y = 0.0
	_trail.set_goal(foot)
	_show(TutorialMarker.create(foot, SKY, 1.3))


func _begin_practice() -> void:
	_lesson("A Nibbler is coming for the silo.\nFollow it, get close, and swing your wrench.")
	_action("V / (R3): stop the Nibbler before it reaches the silo")
	var nibbler: RobotArchetype = null
	for archetype in _director.archetypes:
		if archetype != null and archetype.id == &"nibbler":
			nibbler = archetype
			break
	if nibbler == null or _director.robots_parent == null:
		_go(Step.CATWALK)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.run_seed ^ 0x5A17
	_practice_robot = nibbler.scene.instantiate() as Robot
	_practice_robot.name = "PracticeNibbler"
	_practice_robot.setup(nibbler, 1, _director.curve, rng)
	_practice_robot.target_kind = Robot.TargetKind.SILO
	_practice_robot.is_thief = false
	_practice_robot.speed_multiplier = 0.35
	var where := PRACTICE_POSITION
	var map := _director.robots_parent.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		where = NavigationServer3D.map_get_closest_point(map, where)
	_practice_robot.position = _director.robots_parent.to_local(where) + Vector3.UP * 0.1
	_director.robots_parent.add_child(_practice_robot)
	_practice_robot.reset_physics_interpolation()
	_practice_robot.destroyed.connect(_on_practice_destroyed)
	_trail.set_goal(where)
	_show(TutorialMarker.create(where, RED, 1.4))


func _begin_repair() -> void:
	if _practice_crack == null or not is_instance_valid(_practice_crack):
		_go(Step.CATWALK)
		return
	_lesson("The robot cracked the silo. Leaks drain grain.\nHold Interact to patch this one.")
	_action("Follow the trail to the new silo crack")
	var stand := _practice_crack.global_position + _practice_crack.global_basis.z * 1.5
	stand.y = 0.0
	_show(TutorialMarker.create(stand, GOLD, 1.4))
	_trail.set_goal(stand)


func _begin_zipline() -> void:
	if _zipline == null:
		_go(Step.BELL)
		return
	_zip_ridden = false
	_lesson("Ziplines are the fast way down.\nRide the cable from the silo top to the barn.")
	_action("Stand under the cable and Interact to ride the zipline")
	_show(TutorialMarker.create(_zipline.interaction_point(), SKY, 1.3))


func _begin_bell() -> void:
	_lesson("Protect the silo and its grain with your wrench.\nRing the bell for wave 1; build new gear afterward.")
	_action("Follow the trail to the dinner bell")
	_director.tutorial_bonus_al = EARLY_BIRD_AL
	var where := _bell.global_position
	where.y = 0.0
	_trail.set_goal(where)
	_show(TutorialMarker.create(where, GOLD, 1.6))


# --- Per-frame ------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _finished:
		return
	for marker in _retired.duplicate():
		if marker.is_gone():
			_retired.erase(marker)
			marker.queue_free()
	if _farmer == null or not is_instance_valid(_farmer):
		return
	match step:
		Step.DUMMY:
			_update_dummy()
		Step.PORCH:
			_update_porch(delta)
		Step.PRACTICE:
			if _practice_robot != null and is_instance_valid(_practice_robot):
				# This first threat stays focused on the silo while Pip learns to intercept it.
				_practice_robot.target_kind = Robot.TargetKind.SILO
				_practice_robot.target_player = null
				if _marker != null:
					_marker.global_position = Vector3(_practice_robot.global_position.x, 0.0, _practice_robot.global_position.z)
				_practice_trail_left -= delta
				if _practice_trail_left <= 0.0:
					_practice_trail_left = 0.35
					_trail.set_goal(_practice_robot.global_position)
		Step.CATWALK:
			_update_catwalk(delta)
		Step.ZIPLINE:
			_update_zipline()


func _update_dummy() -> void:
	if _dummy == null:
		return
	if _dummy_dead_time < 0.0:
		return
	_dummy_dead_time += get_process_delta_time()
	var collected := GameState.parts[&"al"] >= _al_before_pop + _dummy.drop_al
	if (collected and (_bonked or _dummy_dead_time > 1.2)) or _dummy_dead_time > 9.0:
		_go(Step.PORCH)


func _update_porch(delta: float) -> void:
	if _heal_zone.contains(_farmer):
		_porch_time += delta
		if _farmer.health.current >= _farmer.health.max_health - 0.01 and _porch_time > 0.35:
			Fx.puff(self, _farmer.global_position + Vector3.UP * 1.2, GREEN, 0.7, 0.4)
			_go(Step.PRACTICE)


func _update_catwalk(delta: float) -> void:
	if _vista_time >= 0.0:
		_run_vista(delta)
		return
	if _farmer.state == Farmer.State.GROUNDED and _farmer.global_position.y >= SILO_TOP_HEIGHT:
		_start_vista()


func _update_zipline() -> void:
	if _farmer.state == Farmer.State.ZIPLINING:
		_zip_ridden = true
	elif _zip_ridden and _farmer.state == Farmer.State.GROUNDED:
		_go(Step.BELL)


# --- Events ---------------------------------------------------------------------------------------

func _on_crack_closed(crack: Node3D) -> void:
	if step == Step.REPAIR and crack == _practice_crack:
		_go(Step.CATWALK)
		return
	if step != Step.SILO or crack != _crack:
		return
	# The Harvest Bonus: the leaked grain pours back in.
	var refunded := _silo.add_grain(_silo.max_grain)
	if refunded > 0.0:
		Fx.puff(self, crack.global_position + Vector3(0, 1.0, 1.0), GOLD, 0.8, 0.5)
	AudioDirector.play_cue(&"robot_pop")
	_retire_marker()
	_trail.clear_goal()
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if step == Step.SILO:
			_go(Step.DUMMY))


func _on_dummy_destroyed(_dummy_bot: TutorialDummy) -> void:
	if step != Step.DUMMY:
		return
	_dummy_dead_time = 0.0
	_trail.clear_goal()
	_retire_marker()


func _on_silo_damaged(_amount: float, at_position: Vector3) -> void:
	if step != Step.PRACTICE or _practice_robot == null or not is_instance_valid(_practice_robot) or _practice_crack != null:
		return
	if at_position.distance_to(_silo.wall_point_toward(_practice_robot.global_position, 0.6)) > 2.0:
		return
	# One real hit demonstrates the threat; pause this rehearsal so an untimed lesson cannot destroy the silo.
	_practice_robot.set_physics_process(false)
	_practice_robot.agent.velocity = Vector3.ZERO
	_practice_crack = _silo.open_tutorial_crack(CRACK_SOCKET, 40.0)
	_lesson("It hit the silo and opened a leak.\nBonk the Nibbler, then patch the crack.")


func _on_practice_destroyed(_robot: Robot, _killer: Node) -> void:
	if step != Step.PRACTICE:
		return
	if _practice_crack != null and is_instance_valid(_practice_crack):
		_go(Step.REPAIR)
	else:
		_go(Step.CATWALK)


func _on_phase_changed(phase: int, _wave: int) -> void:
	if phase != WaveDirector.Phase.TUTORIAL:
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	step = Step.DONE
	if _hud != null:
		_hud.set_tutorial_lesson("")
		_hud.set_tutorial_action("")
	if _farmer != null and is_instance_valid(_farmer):
		_farmer.input.enabled = true
	_trail.clear_goal()
	_retire_marker()
	if _dummy != null and is_instance_valid(_dummy):
		_dummy.queue_free()
	if _practice_robot != null and is_instance_valid(_practice_robot):
		_practice_robot.kill(false)
	for tutorial_crack in [_crack, _practice_crack]:
		if tutorial_crack != null and is_instance_valid(tutorial_crack):
			_silo.repair_crack(tutorial_crack, INF)
	# Let the ground marker fade, then go.
	get_tree().create_timer(1.5).timeout.connect(queue_free)


# --- The vista from the catwalk -----------------------------------------------------------------------

## The camera sweeps over the farm's landmarks while the familiar HUD explains each view. Pip stands still.
func _start_vista() -> void:
	_vista_time = 0.0
	_retire_marker()
	_trail.clear_goal()
	_farmer.input.enabled = false
	_farmer.velocity = Vector3.ZERO
	# A camera of its own, held out over the rail: Pip's follow camera would sit inside the silo wall.
	_vista_yaw = _farmer.camera_rig.yaw
	_vista_cam = Camera3D.new()
	_vista_cam.fov = 62.0
	add_child(_vista_cam)
	_place_vista_cam(0.0)
	_vista_cam.make_current()
	_vista_targets.clear()
	_vista_lessons.clear()
	_vista_step = -1
	var chicken := _farm.get_node_or_null(^"NavRegion/ChickenHouse") as Node3D
	var tower := _farm.get_node_or_null(^"NavRegion/WaterTower") as Node3D
	if chicken != null:
		_add_vista(chicken.global_position, "The chicken house is a landmark on this side of the farm.")
	if tower != null:
		_add_vista(tower.global_position, "The water tower siren sounds before each attack.")
	for lane: Node3D in get_tree().get_nodes_in_group(LaneMarker.GROUP):
		_add_vista(lane.global_position, "Robots come through the corn. Watch these lanes when the siren sounds.")
		break


func _add_vista(target: Vector3, lesson: String) -> void:
	_vista_targets.append(target)
	_vista_lessons.append(lesson)


func _run_vista(delta: float) -> void:
	_vista_time += delta
	var index := int(_vista_time / VISTA_SECONDS)
	if index >= _vista_targets.size():
		_end_vista()
		return
	if index != _vista_step:
		_vista_step = index
		_lesson(_vista_lessons[index])
	var aim := _vista_targets[index] - _farmer.global_position
	_vista_yaw = lerp_angle(_vista_yaw, atan2(-aim.x, -aim.z), 1.0 - exp(-4.0 * delta))
	_place_vista_cam(deg_to_rad(-4.0))


func _place_vista_cam(pitch: float) -> void:
	_vista_cam.global_position = _farmer.global_position + Vector3.UP * 1.8 + Vector3(-sin(_vista_yaw), 0.0, -cos(_vista_yaw)) * 0.9
	_vista_cam.rotation = Vector3(pitch, _vista_yaw, 0.0)


func _end_vista() -> void:
	_vista_time = -1.0
	_drop_vista_cam()
	_farmer.input.enabled = true
	# Hand control back facing the dinner bell.
	var to_bell := _bell.global_position - _farmer.global_position
	_farmer.camera_rig.yaw = atan2(-to_bell.x, -to_bell.z)
	_farmer.camera_rig.pitch = deg_to_rad(-18.0)
	_go(Step.ZIPLINE)


func _drop_vista_cam() -> void:
	if _vista_cam == null:
		return
	if _farmer != null and is_instance_valid(_farmer):
		_farmer.camera_rig.camera.make_current()
	_vista_cam.queue_free()
	_vista_cam = null


# --- Helpers --------------------------------------------------------------------------------------

func _lesson(message: String) -> void:
	if _hud != null:
		_hud.set_tutorial_lesson(message)


func _action(message: String) -> void:
	if _hud != null:
		_hud.set_tutorial_action(message)


func _show(marker: TutorialMarker) -> void:
	add_child(marker)
	_marker = marker


func _retire_marker() -> void:
	if _marker == null:
		return
	_marker.set_wanted(false)
	_retired.append(_marker)
	_marker = null


## Warm green puffs rising from the porch, the "pie steam" that says this is where you heal.
func _steam() -> CPUParticles3D:
	var steam := CPUParticles3D.new()
	steam.amount = 22
	steam.lifetime = 2.6
	steam.direction = Vector3.UP
	steam.spread = 12.0
	steam.initial_velocity_min = 0.6
	steam.initial_velocity_max = 1.1
	steam.gravity = Vector3.ZERO
	steam.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	steam.emission_box_extents = Vector3(5.0, 0.1, 1.0)
	steam.position = Vector3(0.0, 0.8, 0.0)
	var puff := SphereMesh.new()
	puff.radius = 0.12
	puff.height = 0.24
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.6, 1.0, 0.6, 0.3)
	puff.material = material
	steam.mesh = puff
	steam.scale_amount_min = 0.6
	steam.scale_amount_max = 1.2
	return steam
