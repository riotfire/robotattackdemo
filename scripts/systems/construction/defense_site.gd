class_name DefenseSite
extends Interactable
## Where one defense stands. There are no marked build spots: ConstructionManager makes a site wherever the
## farmer places a copy (free placement, playtest feedback 2026-10-26) and removes it with the copy. It
## remembers the kind of floor and the way the copy faces, and it is what the farmer interacts with to move,
## repair, dismantle or cancel that copy during an intermission. It draws nothing itself.

const GROUP_SITES: StringName = &"defense_sites"
const KINDS: Array[StringName] = DefenseDefinition.SITE_KINDS

## Nonnegative for a copy assembling or waiting on the stables pickup rack.
var workshop_slot: int = -1
## &"ground", &"catwalk" or &"roof".
var kind: StringName = &"ground"
var site_id: StringName = &""
## Flat direction a spring here throws robots, and the way a barricade faces: the camera's facing when it was
## placed, or out from the silo on the catwalk.
var launch_direction: Vector3 = Vector3.FORWARD
## Angle around the silo (radians, atan2 of x and z from the silo's center) for catwalk sites; climbers walk
## the ring by it.
var catwalk_angle: float = 0.0
## What stands here: a finished Defense or an unfinished job's ghost (ConstructionManager owns both).
var occupant: Defense = null

var _manager: ConstructionManager


func setup(manager: ConstructionManager, id: StringName, site_kind: StringName, launch: Vector3) -> void:
	_manager = manager
	site_id = id
	kind = site_kind
	launch.y = 0.0
	launch_direction = launch.normalized() if launch.length_squared() > 0.0001 else Vector3.FORWARD


func _ready() -> void:
	super._ready()
	add_to_group(GROUP_SITES)
	interact_range = 1.9
	prompt = "Defense"


func allows(definition: DefenseDefinition) -> bool:
	return definition != null and definition.allowed_on(kind)


func is_empty() -> bool:
	return occupant == null or not is_instance_valid(occupant)


func can_interact(_farmer: Farmer) -> bool:
	return _manager != null and not is_empty()


func prompt_text(_farmer: Farmer) -> String:
	if _manager == null or is_empty():
		return prompt
	if not _manager.is_open():
		return "%s · options at the intermission" % _occupant_text()
	if workshop_slot >= 0 and _manager.job_at(self) == null:
		return "%s · pick up and carry" % occupant.definition.display_name
	return "%s · E: options" % _occupant_text()


func interact(farmer: Farmer) -> void:
	if _manager != null and not is_empty():
		if workshop_slot >= 0 and _manager.job_at(self) == null:
			_manager.collect_stock(self, farmer)
		else:
			_manager.open_menu(self, farmer)


func _occupant_text() -> String:
	if is_empty():
		return ""
	var job := _manager.job_at(self) if _manager != null else null
	if job != null:
		return "%s %d%%" % [occupant.definition.display_name, roundi(job.fraction() * 100.0)]
	return "%s %d%%" % [occupant.definition.display_name, roundi(occupant.condition() * 100.0)]
