class_name ToolShed
extends Interactable
## The tool shed door (GDD 3.5, 13.1): opens the pegboard during intermissions. Shuttered during waves:
## a roll-down steel shutter drops over the door whenever the shed is closed, so the rule is visible
## without a sign. Level 0 opens it briefly for the first wrench purchase.

signal pegboard_requested(farmer: Farmer)

const GROUP_SHED: StringName = &"tool_shed"

const DOOR_WIDTH: float = 3.0
const DOOR_HEIGHT: float = 2.2
const DOOR_TOP: float = 2.5

## Level 0 controls when the first pegboard visit is available.
var tutorial_locked: bool = false
var tutorial_lock_prompt: String = "The shed opens after wave 1."

var _slam_left: float = 0.0
var _shutter: Node3D
var _shutter_closed: float = 1.0


func _ready() -> void:
	super._ready()
	add_to_group(GROUP_SHED)
	interact_range = 2.5
	prompt = "Open the pegboard"
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	_build_shutter()


func is_open() -> bool:
	if tutorial_locked or _slam_left > 0.0:
		return false
	var director := get_tree().get_first_node_in_group(WaveDirector.GROUP) as WaveDirector
	return director == null or director.phase in [WaveDirector.Phase.INTERMISSION, WaveDirector.Phase.SIREN,
			WaveDirector.Phase.CLEARED, WaveDirector.Phase.TUTORIAL]


## The shutter crashes down for `seconds` and then rolls back up.
func slam_shut(seconds: float) -> void:
	_slam_left = seconds
	_shutter_closed = 0.0
	AudioDirector.play_cue(&"wrench")


func can_interact(_farmer: Farmer) -> bool:
	return true


func prompt_text(_farmer: Farmer) -> String:
	if tutorial_locked:
		return tutorial_lock_prompt
	return prompt if is_open() else "The shed is shuttered during the attack!"


func interact(farmer: Farmer) -> void:
	if is_open():
		pegboard_requested.emit(farmer)


func _on_wave_phase_changed(phase: int, wave: int) -> void:
	if tutorial_locked and phase == WaveDirector.Phase.INTERMISSION and wave >= 2:
		tutorial_locked = false


func _process(delta: float) -> void:
	_slam_left = maxf(0.0, _slam_left - delta)
	if _shutter == null:
		return
	var target := 0.04 if is_open() else 1.0
	# Falls fast like a dropped shutter, rolls up slowly with a motor's pace.
	var speed := 9.0 if target > _shutter_closed else 1.1
	_shutter_closed = move_toward(_shutter_closed, target, speed * delta)
	_shutter.scale.y = maxf(0.04, _shutter_closed)
	_shutter.visible = _shutter_closed > 0.05


## A corrugated steel roll-down door in front of the shed's door, hinged at the top.
func _build_shutter() -> void:
	var shed := get_parent()
	if shed == null:
		return
	_shutter = Node3D.new()
	_shutter.name = "RollShutter"
	_shutter.position = Vector3(position.x, DOOR_TOP, position.z - 0.46)
	shed.add_child.call_deferred(_shutter)
	var steel := Color(0.48, 0.5, 0.54)
	var slat_count := 9
	for i in slat_count:
		var slat := BoxMesh.new()
		slat.size = Vector3(DOOR_WIDTH, DOOR_HEIGHT / slat_count - 0.03, 0.1)
		Clay.part(_shutter, slat, steel.lightened(0.06 * (i % 2)), Transform3D(Basis(),
				Vector3(0.0, -(i + 0.5) * DOOR_HEIGHT / slat_count, 0.0)))
	var stripe := BoxMesh.new()
	stripe.size = Vector3(DOOR_WIDTH, 0.18, 0.12)
	Clay.part(_shutter, stripe, Color(0.95, 0.75, 0.15), Transform3D(Basis(), Vector3(0.0, -DOOR_HEIGHT + 0.12, 0.0)))
	_shutter.visible = false
