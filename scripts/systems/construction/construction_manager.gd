class_name ConstructionManager
extends Node
## Defenses are paid for and assembled at the stables workshop. Finished copies wait there, inactive,
## until a farmer picks one up and carries it out for free placement. Recipes remain lasting progression;
## copies, queue, pickup stock and deployed defenses are run-scoped. Existing relocation, repair, salvage,
## capacity and siren cutoff rules still apply. Cancelling a carried copy or hearing the siren returns it
## to its origin (the workshop rack for a new copy). Placement of an already assembled kit is instant.

signal changed

const GROUP: StringName = &"construction"
const DEFINITION_DIR := "res://data/defenses"
const BASE_CAPACITY: float = 8.0
## Jobs waiting behind the active one.
const MAX_WAITING: int = 2
const ASSIST_RATE: float = 2.0
const ASSIST_RANGE: float = 2.6
## Dismantling returns this share of a copy's price, times its condition.
const SALVAGE_SHARE: float = 0.5
## A full repair costs this share of a copy's price, scaled by the damage.
const REPAIR_SHARE: float = 0.5
## How far in front of the farmer the ghost stands, flat.
const PLACE_DISTANCE: float = 2.8
## The floor under the ghost must be within this height of the farmer's feet.
const FLOOR_REACH: float = 1.2
## Steepest floor a defense can stand on (the up component of its normal).
const MIN_FLOOR_NORMAL_Y: float = 0.6
## What a placement may not overlap: the world (buildings, props, fences), robots, the silo, barricades.
const BLOCK_MASK: int = 1 | 4 | 32 | Defense.LAYER
## What counts as floor.
const FLOOR_MASK: int = 1 | 32
## A spot this far above the ground (and not the silo's first catwalk) is a roof.
const ROOF_HEIGHT: float = 1.5
## How close to the first catwalk's height a spot on the silo must be to count as the catwalk.
const CATWALK_TOLERANCE: float = 1.0
## A move that ends this close to where the copy stood just puts it back.
const PUT_BACK_RANGE: float = 0.75
## How far ahead along the walkway a ghost stands on the narrow catwalk.
const CATWALK_PLACE_DISTANCE: float = 1.6

@export var director: WaveDirector

const RECIPE_IDS: Dictionary[StringName, StringName] = {&"spring_trap": &"build.spring_trap",
	&"scarecrow_decoy": &"build.decoy", &"scrap_barricade": &"build.barricade"}
const WORKSHOP_LESSON := "defense_workshop_placed"

var workshop: DefenseWorkshop = null
var definitions: Array[DefenseDefinition] = []
## One per copy standing on the farm (finished or unfinished), plus the origin of a copy being moved.
var sites: Array[DefenseSite] = []
var jobs: Array[Job] = []
## A finished copy picked up for a move, waiting to be set down; it snaps back at the siren.
var in_hand: Defense = null

var _in_hand_from: DefenseSite = null
var _menu: ChoiceMenu = null
var _menu_site: DefenseSite = null
var _at_workshop: bool = false
var _workshop_upgrades: bool = false
var _settled: bool = false
var _sites_root: Node3D
var _menu_refresh_left: float = 0.0
var _next_site: int = 0
## The farmer carrying a finished copy. `last_spot` is the current preview spot, for the HUD.
var _placer: Farmer = null
var _preview: PlacementPreview = null
var last_spot: Spot = null
## Holds the farmer's weapons and interaction off until the button that confirmed a placement is let go.
var _release_wait: Farmer = null
## Pickup uses Interact too: require its release before accepting a placement press.
var _placement_needs_release: bool = false


## Unfinished work on a site. `ghost` is the inactive copy standing there.
class Job:
	extends RefCounted
	var definition: DefenseDefinition
	var site: DefenseSite
	var ghost: Defense
	var reserved: Dictionary[StringName, int] = {}
	## A relocation of a finished copy: no parts, and the copy keeps its damage. `origin` is where it stood.
	var moving: bool = false
	var origin: DefenseSite = null
	var work: float = 1.0
	var done: float = 0.0

	func fraction() -> float:
		return clampf(done / maxf(0.01, work), 0.0, 1.0)

	## What cancelling it now returns: the unbuilt share of what it reserved.
	func unbuilt_refund() -> Dictionary[StringName, int]:
		var refund: Dictionary[StringName, int] = {}
		for part: StringName in reserved:
			var amount := floori(reserved[part] * (1.0 - fraction()))
			if amount > 0:
				refund[part] = amount
		return refund


## A candidate place for a defense: where, what kind of floor, the way it faces, and what's wrong with it
## ("" when it fits).
class Spot:
	extends RefCounted
	var position: Vector3 = Vector3.ZERO
	## &"ground", &"catwalk" or &"roof".
	var kind: StringName = &"ground"
	var launch: Vector3 = Vector3.FORWARD
	var problem: String = ""


func _ready() -> void:
	add_to_group(GROUP)
	_load_definitions()
	_sites_root = Node3D.new()
	_sites_root.name = "Defenses"
	add_child(_sites_root)
	EventBus.wave_phase_changed.connect(_on_wave_phase_changed)
	_find_workshop.call_deferred()


func _exit_tree() -> void:
	settle_run_end()


func _load_definitions() -> void:
	definitions.clear()
	if not DirAccess.dir_exists_absolute(DEFINITION_DIR):
		return
	for file in ResourceLoader.list_directory(DEFINITION_DIR):
		if file.ends_with(".tres"):
			var definition := load(DEFINITION_DIR.path_join(file)) as DefenseDefinition
			if definition != null:
				definitions.append(definition)
	definitions.sort_custom(func(a: DefenseDefinition, b: DefenseDefinition) -> bool: return a.kind < b.kind)


func definition(id: StringName) -> DefenseDefinition:
	for each in definitions:
		if each.id == id:
			return each
	return null


## Every defense is directly buildable; saved recipe flags are only upgrade compatibility data.
func owned_definitions() -> Array[DefenseDefinition]:
	return definitions.duplicate()


## Construction runs only in the intermission, never during the siren or battle.
func is_open() -> bool:
	return director != null and director.phase == WaveDirector.Phase.INTERMISSION


func capacity_total() -> int:
	return roundi(StatService.get_stat(&"defense.capacity", BASE_CAPACITY))


func capacity_used() -> int:
	var used := 0
	for job in jobs:
		used += job.definition.capacity
	for defense in deployed():
		if job_for(defense) == null:
			used += defense.definition.capacity
	if in_hand != null and is_instance_valid(in_hand):
		used += in_hand.definition.capacity
	return used


## Every copy standing on the farm, finished or not.
func deployed() -> Array[Defense]:
	var result: Array[Defense] = []
	for site in sites:
		if not site.is_empty():
			result.append(site.occupant)
	return result


func job_at(site: DefenseSite) -> Job:
	for job in jobs:
		if job.site == site:
			return job
	return null


func job_for(defense: Defense) -> Job:
	for job in jobs:
		if job.ghost == defense:
			return job
	return null


func active_job() -> Job:
	return jobs[0] if not jobs.is_empty() else null


func is_placing() -> bool:
	return _placer != null and is_instance_valid(_placer)


# --- Spots ---------------------------------------------------------------------------------------

## The spot PLACE_DISTANCE in front of `farmer`, along the camera's flat facing. On the silo's first catwalk it
## is the point of the walkway ahead instead, so the ghost never hangs off the edge.
func spot_ahead(farmer: Farmer, defense_definition: DefenseDefinition, ignore: Defense = null) -> Spot:
	var facing := farmer.aim_forward_flat()
	facing.y = 0.0
	facing = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var at := farmer.global_position + facing * PLACE_DISTANCE
	var silo := GameState.silo
	if silo != null and _on_catwalk_level(farmer.global_position) \
			and _flat_distance(farmer.global_position, silo.global_position) < LadderRobot.CATWALK_RADIUS + 1.5:
		at = _ring_point(farmer.global_position + facing * CATWALK_PLACE_DISTANCE, farmer.global_position.y)
	var exclude: Array[RID] = [farmer.get_rid()]
	return spot_at(at, facing, defense_definition, farmer.global_position.y, exclude, ignore)


## The spot under `at` for `defense_definition`, facing `facing`. The floor is looked for within FLOOR_REACH of
## `reference_height` (the farmer's feet; `at.y` when NAN). `exclude` are bodies the overlap test ignores (the
## farmer); `ignore` is a copy being moved, which doesn't count as in the way of itself.
func spot_at(at: Vector3, facing: Vector3, defense_definition: DefenseDefinition, reference_height: float = NAN,
		exclude: Array[RID] = [], ignore: Defense = null) -> Spot:
	var spot := Spot.new()
	spot.position = at
	facing.y = 0.0
	spot.launch = facing.normalized() if facing.length_squared() > 0.0001 else Vector3.FORWARD
	var space := _space()
	if space == null:
		spot.problem = "Nowhere to build"
		return spot
	var height := at.y if is_nan(reference_height) else reference_height
	var ray := PhysicsRayQueryParameters3D.create(Vector3(at.x, height + FLOOR_REACH + 0.5, at.z),
			Vector3(at.x, height - FLOOR_REACH, at.z), FLOOR_MASK, exclude)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		spot.problem = "No solid floor there"
		return spot
	spot.position = hit["position"]
	if (hit["normal"] as Vector3).y < MIN_FLOOR_NORMAL_Y:
		spot.problem = "Too steep to build on"
		return spot
	_classify(spot, hit.get("collider") as Node)
	if spot.kind == &"catwalk":
		# Springs and walls on the catwalk sit on the ring the climbers walk (LadderRobot.CATWALK_RADIUS).
		spot.position = _ring_point(spot.position, spot.position.y)
	if defense_definition != null and not defense_definition.allowed_on(spot.kind):
		spot.problem = "A %s can't go on a %s" % [defense_definition.display_name, "roof" if spot.kind == &"roof" else String(spot.kind)]
		return spot
	if defense_definition != null:
		var blockers := exclude.duplicate()
		if hit.get("rid") is RID:
			blockers.append(hit["rid"])
		spot.problem = _overlap_problem(defense_definition, spot, blockers, ignore)
	return spot


## Ground, the silo's first catwalk, or a roof (anything else above ROOF_HEIGHT, the silo's higher rings too).
## On the catwalk the facing follows the ring: out from the silo.
func _classify(spot: Spot, floor_node: Node) -> void:
	var silo := GameState.silo
	spot.kind = &"ground"
	var ground_y := silo.global_position.y if silo != null else 0.0
	if silo != null and floor_node != null and (floor_node == silo or silo.is_ancestor_of(floor_node)):
		if _on_catwalk_level(spot.position):
			spot.kind = &"catwalk"
			var out := spot.position - silo.global_position
			out.y = 0.0
			if out.length_squared() > 0.0001:
				spot.launch = out.normalized()
			return
	if spot.position.y - ground_y > ROOF_HEIGHT:
		spot.kind = &"roof"


## True when `point` is at the height of the silo's first catwalk.
func _on_catwalk_level(point: Vector3) -> bool:
	var silo := GameState.silo
	var ladder := silo.get_node_or_null(^"Ladder") as Climbable if silo != null else null
	if ladder == null or ladder.landings.is_empty():
		return false
	return absf(point.y - (ladder.global_position.y + ladder.landings[0])) <= CATWALK_TOLERANCE


## The point of the climbers' ring (LadderRobot.CATWALK_RADIUS) at `point`'s angle around the silo.
func _ring_point(point: Vector3, height: float) -> Vector3:
	var center := GameState.silo.global_position
	var out := point - center
	out.y = 0.0
	out = out.normalized() if out.length_squared() > 0.0001 else Vector3.FORWARD
	return Vector3(center.x, height, center.z) + out * LadderRobot.CATWALK_RADIUS


## Why a copy of `defense_definition` can't stand at `spot`, or "": the world and robots by an overlap test of
## its footprint, other copies (springs and decoys aren't solid) by their footprints.
func _overlap_problem(defense_definition: DefenseDefinition, spot: Spot, exclude: Array[RID], ignore: Defense) -> String:
	var footprint := Footprint.of(defense_definition, spot.kind, spot.launch)
	var space := _space()
	if space == null:
		return ""
	var box := BoxShape3D.new()
	box.size = Vector3(footprint.half_length * 2.0 + footprint.radius * 2.0, footprint.height, footprint.radius * 2.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.collision_mask = BLOCK_MASK
	query.exclude = exclude
	query.transform = Transform3D(footprint.basis(), spot.position + Vector3.UP * (0.2 + footprint.height * 0.5))
	for result in space.intersect_shape(query, 8):
		var body := result.get("collider") as Node
		if ignore != null and body != null and ignore.is_ancestor_of(body):
			continue
		return "Something's in the way"
	for other in deployed():
		if other == ignore or not is_instance_valid(other):
			continue
		if absf(other.global_position.y - spot.position.y) > 1.5:
			continue
		var theirs := Footprint.of(other.definition, other.site.kind if other.site != null else &"ground",
				other.site.launch_direction if other.site != null else Vector3.FORWARD)
		if footprint.gap_to(spot.position, theirs, other.global_position) < 0.1:
			return "Too close to the %s" % other.definition.display_name
	return ""


## The flat outline a defense takes up: a capsule along `along` (a point for springs and decoys).
class Footprint:
	extends RefCounted
	var along: Vector3 = Vector3.RIGHT
	var half_length: float = 0.0
	var radius: float = 0.6
	var height: float = 1.0

	static func of(defense_definition: DefenseDefinition, kind: StringName, launch: Vector3) -> Footprint:
		var footprint := Footprint.new()
		match defense_definition.kind:
			DefenseDefinition.Kind.SPRING_TRAP:
				footprint.radius = 0.62
				footprint.height = 0.6
			DefenseDefinition.Kind.DECOY:
				footprint.radius = 0.45
				footprint.height = 1.6
			_:
				footprint.along = ScrapBarricade.wall_along(kind, launch)
				footprint.half_length = ScrapBarricade.wall_half_width(defense_definition, kind)
				footprint.radius = 0.25
				footprint.height = defense_definition.barricade_height
		return footprint

	func basis() -> Basis:
		var normal := Vector3.UP.cross(along).normalized()
		return Basis(along, Vector3.UP, -normal).orthonormalized()

	## Flat clearance between this footprint at `at` and `other` at `other_at` (negative when they overlap).
	func gap_to(at: Vector3, other: Footprint, other_at: Vector3) -> float:
		var best := INF
		for i in 9:
			var t := -1.0 + i * 0.25
			var point := at + along * half_length * t
			best = minf(best, other._segment_distance(other_at, point))
			var their_point := other_at + other.along * other.half_length * t
			best = minf(best, _segment_distance(at, their_point))
		return best - radius - other.radius

	func _segment_distance(at: Vector3, point: Vector3) -> float:
		var flat := point - at
		flat.y = 0.0
		var t := clampf(flat.dot(along), -half_length, half_length)
		return (flat - along * t).length()


# --- Placing, cancelling, moving -----------------------------------------------------------------

## Why `defense_definition` can't be placed at `spot` now, or "" when it can.
func placement_problem(defense_definition: DefenseDefinition, spot: Spot = null) -> String:
	if not is_open():
		return "Construction opens at the intermission"
	if jobs.size() > MAX_WAITING:
		return "The build queue is full (%d waiting)" % MAX_WAITING
	if capacity_used() + defense_definition.capacity > capacity_total():
		return "Not enough capacity (%d/%d used)" % [capacity_used(), capacity_total()]
	if not StatService.can_afford(defense_definition.cost()):
		return "Need %d Al" % defense_definition.cost_al
	if spot != null:
		return spot.problem
	return ""


func _find_workshop() -> void:
	if not is_instance_valid(workshop):
		workshop = get_tree().get_first_node_in_group(DefenseWorkshop.GROUP_WORKSHOP) as DefenseWorkshop


func at_workshop(farmer: Node3D) -> bool:
	_find_workshop()
	return is_instance_valid(workshop) and is_instance_valid(farmer) \
			and farmer.global_position.distance_to(workshop.interaction_point()) <= workshop.interact_range


## Physical copies can only enter the build queue at the stables, with the buyer present.
func craft(defense_definition: DefenseDefinition, farmer: Node3D) -> String:
	if not at_workshop(farmer):
		return "Build defenses at the stables workshop"
	var problem := placement_problem(defense_definition)
	if not problem.is_empty():
		return problem
	var slot := 0
	while sites.any(func(site: DefenseSite) -> bool: return site.workshop_slot == slot):
		slot += 1
	var spot := Spot.new()
	spot.position = workshop.stock_position(slot)
	var site := _add_site(spot, defense_definition)
	site.workshop_slot = slot
	var job := Job.new()
	job.definition = defense_definition
	job.site = site
	job.work = defense_definition.assembly_time
	job.reserved = defense_definition.cost()
	GameState.add_parts({&"al": -defense_definition.cost_al})
	# Retain saved upgrade prerequisites internally; there is no recipe purchase or learning step.
	StatService.grant(RECIPE_IDS[defense_definition.id])
	job.ghost = _make_defense(defense_definition, site, farmer)
	job.ghost.visible = false
	jobs.append(job)
	SaveManager.save_profile()
	_changed()
	return ""


## A placement consumes a physical copy already picked up; it cannot manufacture a remote copy.
func place(defense_definition: DefenseDefinition, spot: Spot, _farmer: Node) -> String:
	if in_hand == null or in_hand.definition != defense_definition:
		return "Build and pick up a defense at the stables first"
	return put_down(spot)


func ready_stock() -> Array[DefenseSite]:
	return sites.filter(func(site: DefenseSite) -> bool: return site.workshop_slot >= 0 \
			and not site.is_empty() and job_at(site) == null)


func collect_stock(site: DefenseSite, farmer: Farmer) -> bool:
	if site == null or site.workshop_slot < 0 or not is_instance_valid(farmer):
		return false
	if not at_workshop(farmer) and farmer.global_position.distance_to(site.interaction_point()) > site.interact_range:
		return false
	close_menu()
	return pick_up(site, farmer)


## Cancels the job on `site`, refunding its unbuilt share. A cancelled move puts the copy back where it stood.
## Returns what came back.
func cancel(site: DefenseSite) -> Dictionary[StringName, int]:
	var job := job_at(site)
	if job == null or not is_open():
		return {}
	var refund := job.unbuilt_refund()
	jobs.erase(job)
	if job.moving and job.origin != null and is_instance_valid(job.origin):
		var defense := job.ghost
		site.occupant = null
		_free_site(site)
		_settle_at(defense, job.origin)
	else:
		_remove_defense(job.ghost)
	if not refund.is_empty():
		GameState.add_parts(refund)
	SaveManager.save_profile()
	_changed()
	return refund


## Picks a finished copy up to move it this intermission. `farmer`, if given, starts placing it.
func pick_up(site: DefenseSite, farmer: Farmer = null) -> bool:
	if site != null and site.workshop_slot >= 0:
		if not is_instance_valid(farmer) or (not at_workshop(farmer)
				and farmer.global_position.distance_to(site.interaction_point()) > site.interact_range):
			return false
	if not is_open() or site.is_empty() or job_at(site) != null or in_hand != null:
		return false
	var defense := site.occupant
	site.occupant = null
	in_hand = defense
	_in_hand_from = site
	defense.ready_for_pickup = false
	defense.set_active(false)
	defense.visible = false
	if farmer != null:
		_start_placing(farmer)
	_changed()
	return true


## Sets the copy in hand down at `spot`: back where it came from at once, elsewhere as a setup job.
func put_down(spot: Spot) -> String:
	if in_hand == null or not is_instance_valid(in_hand):
		return "Nothing to place"
	if not is_open():
		return "Construction opens at the intermission"
	var defense := in_hand
	var origin := _in_hand_from
	if origin != null and _flat_distance(spot.position, origin.global_position) <= PUT_BACK_RANGE:
		_clear_hand()
		_settle_at(defense, origin)
		_changed()
		return ""
	if not spot.problem.is_empty():
		return spot.problem
	if origin != null and origin.workshop_slot >= 0:
		_clear_hand()
		var site := _add_site(spot, defense.definition)
		_settle_at(defense, site)
		_free_site(origin)
		if SaveManager.first_time(WORKSHOP_LESSON):
			EventBus.hud_message.emit("Defense deployed! Build more at the stables between waves.", 4.0)
			SaveManager.save_profile()
		_changed()
		return ""
	if jobs.size() > MAX_WAITING:
		return "The build queue is full (%d waiting)" % MAX_WAITING
	_clear_hand()
	var site := _add_site(spot, defense.definition)
	site.occupant = defense
	defense.site = site
	defense.global_position = site.global_position
	defense.visible = true
	defense.relocated()
	defense.set_active(false)
	var job := Job.new()
	job.definition = defense.definition
	job.site = site
	job.ghost = defense
	job.moving = true
	job.origin = origin
	job.work = defense.definition.assembly_time * defense.definition.relocate_share
	jobs.append(job)
	_changed()
	return ""


## Breaks a finished copy down for SALVAGE_SHARE of its price times its condition.
func dismantle(site: DefenseSite) -> int:
	if not is_open() or site.is_empty() or job_at(site) != null:
		return 0
	var defense := site.occupant
	var salvage := salvage_value(defense)
	_remove_defense(defense)
	if salvage > 0:
		GameState.add_parts({&"al": salvage})
	SaveManager.save_profile()
	_changed()
	return salvage


func salvage_value(defense: Defense) -> int:
	return floori(defense.definition.cost_al * SALVAGE_SHARE * defense.condition())


func repair_cost(defense: Defense) -> int:
	if defense.condition() >= 0.999:
		return 0
	return maxi(1, ceili(defense.definition.cost_al * REPAIR_SHARE * (1.0 - defense.condition())))


## Repairs a damaged finished copy for Aluminium. Returns false if it couldn't.
func repair(site: DefenseSite) -> bool:
	if not is_open() or site.is_empty() or job_at(site) != null:
		return false
	var defense := site.occupant
	var cost := repair_cost(defense)
	if cost <= 0 or GameState.parts.get(&"al", 0) < cost:
		return false
	GameState.add_parts({&"al": -cost})
	defense.repair_full()
	SaveManager.save_profile()
	_changed()
	return true


## The run is over (a loss, a restart, quitting): refund every unfinished job's unbuilt share, once.
## Finished, destroyed and moved copies stay spent.
func settle_run_end() -> void:
	if _settled:
		return
	_settled = true
	var refund: Dictionary[StringName, int] = {}
	for job in jobs:
		var share := job.unbuilt_refund()
		for part: StringName in share:
			refund[part] = refund.get(part, 0) + share[part]
	jobs.clear()
	if not refund.is_empty():
		GameState.add_parts(refund)
		SaveManager.save_profile()


func _physics_process(delta: float) -> void:
	_menu_refresh_left -= delta
	if _at_workshop and _menu != null and _menu.is_open() and _menu_refresh_left <= 0.0:
		_menu_refresh_left = 0.2
		_refresh_workshop()
	elif _menu_site != null and _menu != null and _menu.is_open() and _menu_refresh_left <= 0.0:
		_menu_refresh_left = 0.2
		_refresh_menu()
	_update_input()
	if not is_open() or jobs.is_empty():
		return
	var job := jobs[0]
	if not is_instance_valid(job.ghost):
		jobs.pop_front()
		_changed()
		return
	job.done += delta * work_rate(job)
	if job.done >= job.work:
		_complete(job)


## Work seconds per second on `job`: Quick Assembly, doubled while a farmer stands beside it.
func work_rate(job: Job) -> float:
	var rate := maxf(0.1, StatService.get_stat(&"defense.build_rate", 1.0))
	return rate * (ASSIST_RATE if assisted(job) else 1.0)


func assisted(job: Job) -> bool:
	if job == null:
		return false
	for player in GameState.players:
		var farmer := player as Farmer
		if farmer != null and farmer.is_alive() and farmer.state == Farmer.State.GROUNDED \
				and farmer.global_position.distance_to(workshop.interaction_point() if job.site.workshop_slot >= 0
					and is_instance_valid(workshop) else job.site.global_position) <= ASSIST_RANGE:
			return true
	return false


func _complete(job: Job) -> void:
	jobs.erase(job)
	job.ghost.ready_for_pickup = job.site.workshop_slot >= 0
	job.ghost.visible = true
	job.ghost.set_active(not job.ghost.ready_for_pickup)
	if job.moving and job.origin != null and is_instance_valid(job.origin):
		_free_site(job.origin)
	AudioDirector.play_cue(&"wrench", 1.3)
	EventBus.hud_message.emit("%s ready: pick it up at the stables" % job.definition.display_name
			if job.site.workshop_slot >= 0 else "%s ready" % job.definition.display_name, 3.0)
	_changed()


func _on_wave_phase_changed(phase: int, _wave: int) -> void:
	match phase:
		WaveDirector.Phase.SIREN:
			# The siren commits the bet: nothing more is built, moved or placed until the next intermission.
			close_menu()
			_stop_placing()
			if in_hand != null and is_instance_valid(in_hand) and _in_hand_from != null:
				var defense := in_hand
				var origin := _in_hand_from
				_clear_hand()
				_settle_at(defense, origin)
			if not jobs.is_empty():
				EventBus.hud_message.emit("Construction closed: %d unfinished" % jobs.size(), 2.0)
			_changed()
		WaveDirector.Phase.GAME_OVER:
			close_menu()
			_stop_placing()
			settle_run_end()


# --- Input: the recipe menu and placement mode ---------------------------------------------------

func _update_input() -> void:
	if _release_wait != null:
		if not is_instance_valid(_release_wait) or not (_release_wait.input.is_pressed(&"interact") or _release_wait.input.is_pressed(&"fire")):
			if is_instance_valid(_release_wait) and not is_placing():
				_release_wait.building = false
			_release_wait = null
	if is_placing():
		_update_placing()
		return
	if not is_open() or (_menu != null and _menu.is_open()) or get_tree().paused:
		return
	for player in GameState.players:
		var farmer := player as Farmer
		if farmer != null and is_instance_valid(farmer) and farmer.is_alive() and farmer.input.is_just_pressed(&"build"):
			if at_workshop(farmer):
				open_recipe_menu(farmer)
			else:
				EventBus.hud_message.emit("Build and pick up defenses at the STABLES. Follow the workshop sign.", 4.0)
			return


## Direct building and defense upgrades are available only at the stables.
func open_recipe_menu(farmer: Farmer) -> void:
	if not is_open() or not at_workshop(farmer):
		return
	if in_hand != null:
		_start_placing(farmer)
		return
	_ensure_menu()
	_menu_site = null
	_at_workshop = true
	_workshop_upgrades = false
	_menu.close_actions = [&"build"]
	_menu.open(farmer, "STABLES · DEFENSE WORKSHOP", _recipe_entries(farmer), workshop)
	_refresh_workshop()


func _refresh_workshop() -> void:
	if not _at_workshop or _menu == null or not _menu.is_open():
		return
	if not is_open() or not at_workshop(_menu.farmer):
		close_menu()
		return
	_menu.set_entries(_recipe_entries(_menu.farmer))
	_menu_subtitle(("Defense upgrades" if _workshop_upgrades else "Build → pick up when ready → carry out and place") + "\nCapacity %d/%d  ·  %d ready for pickup" % [
			capacity_used(), capacity_total(), ready_stock().size()])


func _recipe_entries(farmer: Farmer) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for site in ready_stock():
		entries.append({"id": "pickup_%s" % site.site_id, "text": "PICK UP · %s" % site.occupant.definition.display_name,
				"detail": "Already built and paid for. Carry it out and place it at a green spot.",
				"enabled": in_hand == null, "action": collect_stock.bind(site, farmer)})
	for job in jobs:
		if job.site.workshop_slot >= 0:
			entries.append({"id": "job_%s" % job.site.site_id, "text": "%s · %d%% · Cancel (+%d Al)" % [job.definition.display_name,
					roundi(job.fraction() * 100.0), job.unbuilt_refund().get(&"al", 0)],
					"enabled": true, "action": _cancel_workshop_job.bind(job.site)})
	if _workshop_upgrades:
		return _upgrade_entries(farmer)
	for each in definitions:
		var problem := placement_problem(each)
		entries.append({"id": "craft_%s" % each.id, "text": "BUILD · %s · %d Al · %.0f s" % [each.display_name, each.cost_al, each.assembly_time],
				"detail": each.description, "enabled": problem.is_empty(), "reason": problem,
				"action": _choose_recipe.bind(farmer, each)})
	entries.append({"id": "upgrades", "text": "Improve defenses", "enabled": true,
			"detail": "Stronger traps, sturdier walls, quicker building and more capacity.",
			"action": _show_workshop_upgrades.bind(true)})
	entries.append({"text": "Close", "enabled": true, "action": close_menu})
	return entries


func _show_workshop_upgrades(show_upgrades: bool) -> void:
	_workshop_upgrades = show_upgrades
	_refresh_workshop()


func _upgrade_entries(farmer: Farmer) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: StringName in StatService.catalog:
		var node: UpgradeNode = StatService.catalog[id]
		if node.branch != UpgradeNode.Branch.BUILD or id in RECIPE_IDS.values():
			continue
		var price := PackedStringArray()
		for part: StringName in StatService.next_cost(id):
			price.append("%d %s" % [StatService.next_cost(id)[part], String(part).capitalize()])
		var reason := "Fully upgraded" if StatService.is_maxed(id) else "Need " + " / ".join(price)
		if not StatService.prerequisites_met(id):
			var required := PackedStringArray()
			for prerequisite in node.prerequisites:
				if StatService.level_of(prerequisite.node_id) < prerequisite.level:
					required.append(StatService.catalog[prerequisite.node_id].display_name)
			reason = "First build or upgrade: " + ", ".join(required)
		entries.append({"id": String(id), "text": "%s %d/%d · %s" % [node.display_name, StatService.level_of(id),
				node.max_level, " / ".join(price) if not price.is_empty() else "MAX"], "detail": node.description,
				"enabled": StatService.can_purchase(id), "reason": reason,
				"action": _buy_workshop_upgrade.bind(farmer, id)})
	entries.append({"id": "back", "text": "Back to building", "enabled": true,
			"action": _show_workshop_upgrades.bind(false)})
	return entries


func _buy_workshop_upgrade(farmer: Farmer, id: StringName) -> void:
	if is_open() and at_workshop(farmer) and StatService.catalog.has(id) \
			and StatService.catalog[id].branch == UpgradeNode.Branch.BUILD and id not in RECIPE_IDS.values():
		StatService.purchase(id)
	_refresh_workshop()


func _cancel_workshop_job(site: DefenseSite) -> void:
	cancel(site)
	_refresh_workshop()


func _choose_recipe(farmer: Farmer, defense_definition: DefenseDefinition) -> void:
	var problem := craft(defense_definition, farmer)
	if not problem.is_empty():
		EventBus.hud_message.emit(problem, 3.0)
	_refresh_workshop()


func _start_placing(farmer: Farmer) -> void:
	if in_hand == null:
		return
	_stop_placing()
	_placer = farmer
	_placement_needs_release = true
	farmer.building = true
	_preview = PlacementPreview.new()
	_preview.name = "PlacementPreview"
	add_child(_preview)
	_update_placing()


func _stop_placing() -> void:
	if _preview != null and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if _placer != null and is_instance_valid(_placer) and _release_wait != _placer:
		_placer.building = false
	_placer = null
	last_spot = null


## The physical copy currently carried for placement.
func placing_definition() -> DefenseDefinition:
	return in_hand.definition if in_hand != null and is_instance_valid(in_hand) else null


func _update_placing() -> void:
	var farmer := _placer
	var placing := placing_definition()
	if not is_open() or not is_instance_valid(farmer) or not farmer.is_alive() or placing == null:
		_cancel_placing()
		return
	if _menu != null and _menu.is_open():
		return
	var spot := spot_ahead(farmer, placing, in_hand)
	if _in_hand_from != null \
			and _flat_distance(spot.position, _in_hand_from.global_position) <= PUT_BACK_RANGE:
		spot.problem = ""
	last_spot = spot
	_preview.show_spot(placing, spot)
	if _placement_needs_release:
		if not (farmer.input.is_pressed(&"interact") or farmer.input.is_pressed(&"fire") or farmer.input.is_pressed(&"build")):
			_placement_needs_release = false
		return
	if farmer.input.is_just_pressed(&"build"):
		_cancel_placing()
		return
	if not (farmer.input.is_just_pressed(&"interact") or farmer.input.is_just_pressed(&"fire")):
		return
	var result := put_down(spot)
	if not result.is_empty():
		EventBus.hud_message.emit(result, 1.5)
		return
	_release_wait = farmer
	_stop_placing()


## Build pressed again, or construction closed: drop the ghost. A copy in hand goes back where it stood.
func _cancel_placing() -> void:
	if in_hand != null and is_instance_valid(in_hand) and _in_hand_from != null:
		var defense := in_hand
		var origin := _in_hand_from
		_clear_hand()
		_settle_at(defense, origin)
		_changed()
	_stop_placing()


# --- The options menu of a placed copy -----------------------------------------------------------

func open_menu(site: DefenseSite, farmer: Farmer) -> void:
	_at_workshop = false
	if is_placing():
		return
	_ensure_menu()
	_menu_site = site
	_menu.close_actions = []
	_menu.open(farmer, site.occupant.definition.display_name if not site.is_empty() else "Defense", _menu_entries(site), site)


func close_menu() -> void:
	_at_workshop = false
	if _menu != null and _menu.is_open():
		_menu.close()
	_menu_site = null


func _ensure_menu() -> void:
	if _menu != null:
		return
	_menu = ChoiceMenu.new()
	_menu.name = "BuildMenu"
	add_child(_menu)
	_menu.closed.connect(func() -> void:
		_menu_site = null
		_at_workshop = false)


func _refresh_menu() -> void:
	if _menu_site == null or not is_instance_valid(_menu_site) or _menu_site.is_empty():
		close_menu()
		return
	_menu.set_entries(_menu_entries(_menu_site))


func _menu_entries(site: DefenseSite) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var header := "Capacity %d/%d" % [capacity_used(), capacity_total()]
	if not is_open():
		entries.append({"text": "Construction opens at the intermission", "enabled": false})
		_menu_subtitle(header)
		return entries
	var job := job_at(site)
	if job != null:
		var refund := job.unbuilt_refund()
		var status := ("Moving" if job.moving else "Assembling") if job == active_job() else "Waiting to build"
		entries.append({"text": "%s %s: %d%%" % [status, job.definition.display_name, roundi(job.fraction() * 100.0)],
				"enabled": false})
		var undo := "Cancel the move" if job.moving else "Cancel"
		entries.append({"text": undo + (" (+%d Al back)" % refund.get(&"al", 0) if not refund.is_empty() else ""),
				"enabled": true, "action": func() -> void: cancel(site)})
	elif not site.is_empty():
		var defense := site.occupant
		entries.append({"text": "Move it (setup %.0f s, no parts)" % (defense.definition.assembly_time * defense.definition.relocate_share),
				"enabled": in_hand == null, "reason": "You're already carrying one",
				"action": _move_from_menu.bind(site)})
		var cost := repair_cost(defense)
		if cost > 0:
			entries.append({"text": "Repair (%d Al)" % cost, "enabled": GameState.parts.get(&"al", 0) >= cost,
					"reason": "Need %d Al" % cost, "action": func() -> void: repair(site)})
		entries.append({"text": "Dismantle (+%d Al)" % salvage_value(defense), "enabled": true,
				"action": func() -> void: dismantle(site)})
	entries.append({"text": "Close", "enabled": true, "action": close_menu})
	_menu_subtitle(header + ("  ·  %d in the queue" % jobs.size() if not jobs.is_empty() else ""))
	return entries


func _move_from_menu(site: DefenseSite) -> void:
	var farmer := _menu.farmer
	close_menu()
	pick_up(site, farmer)


func _menu_subtitle(text: String) -> void:
	if _menu != null:
		_menu.set_subtitle(text)


# --- Copies and sites ----------------------------------------------------------------------------

func _make_defense(defense_definition: DefenseDefinition, site: DefenseSite, farmer: Node) -> Defense:
	var defense: Defense
	match defense_definition.kind:
		DefenseDefinition.Kind.SPRING_TRAP:
			defense = SpringTrap.new()
		DefenseDefinition.Kind.DECOY:
			defense = ScarecrowDecoy.new()
		_:
			defense = ScrapBarricade.new()
	var hp := defense_definition.max_hp
	if defense_definition.kind == DefenseDefinition.Kind.BARRICADE:
		hp *= StatService.get_stat(&"defense.barricade_hp", 1.0)
	defense.setup(defense_definition, site, farmer, hp)
	defense.name = "%s_%s" % [defense_definition.id, site.site_id]
	defense.active = false
	site.occupant = defense
	_sites_root.add_child(defense)
	defense.global_position = site.global_position
	defense.broken.connect(_on_defense_broken)
	return defense


## Puts `defense` back on `site`, finished and active (a move undone, or snapped back at the siren).
func _settle_at(defense: Defense, site: DefenseSite) -> void:
	site.occupant = defense
	defense.site = site
	defense.global_position = site.global_position
	defense.relocated()
	defense.visible = true
	defense.ready_for_pickup = site.workshop_slot >= 0
	defense.set_active(not defense.ready_for_pickup)


func _clear_hand() -> void:
	in_hand = null
	_in_hand_from = null


func _remove_defense(defense: Defense) -> void:
	if defense == null or not is_instance_valid(defense):
		return
	for site in sites.duplicate():
		if site.occupant == defense:
			site.occupant = null
			_free_site(site)
	defense.queue_free()


func _on_defense_broken(defense: Defense) -> void:
	for job in jobs.duplicate():
		if job.ghost == defense:
			jobs.erase(job)
	for site in sites.duplicate():
		if site.occupant == defense:
			site.occupant = null
			_free_site(site)
	_changed()


func _changed() -> void:
	changed.emit()
	EventBus.construction_changed.emit()


## The anchor for a copy of `defense_definition` placed at `spot`. A wide copy (a barricade) can be reached
## from anywhere along it.
func _add_site(spot: Spot, defense_definition: DefenseDefinition) -> DefenseSite:
	_next_site += 1
	var site := DefenseSite.new()
	site.name = "Site%d" % _next_site
	site.setup(self, StringName("site_%d" % _next_site), spot.kind, spot.launch)
	_sites_root.add_child(site)
	site.interact_range += Footprint.of(defense_definition, spot.kind, spot.launch).half_length
	site.global_position = spot.position
	if spot.kind == &"catwalk" and GameState.silo != null:
		var center := GameState.silo.global_position
		site.catwalk_angle = atan2(spot.position.x - center.x, spot.position.z - center.z)
	sites.append(site)
	return site


func _free_site(site: DefenseSite) -> void:
	if site == null or not is_instance_valid(site) or site == _in_hand_from:
		return
	for job in jobs:
		if job.origin == site:
			return
	sites.erase(site)
	site.queue_free()


func _space() -> PhysicsDirectSpaceState3D:
	var viewport := get_viewport()
	return viewport.get_world_3d().direct_space_state if viewport != null else null


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
