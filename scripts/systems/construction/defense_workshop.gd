class_name DefenseWorkshop
extends Interactable
## The stables' workbench and pickup rack. All physical defenses are assembled here between waves.
## A persistent first-use lesson guides the farmer through recipe → assembly → pickup → placement.

const GROUP_WORKSHOP: StringName = &"defense_workshop"
const GOLD := Color(1.0, 0.8, 0.28)

var _manager: ConstructionManager
var _status: Label3D
var _trail: TutorialTrail
var _trail_farmer: Farmer
var _marker: TutorialMarker
var _refresh: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(GROUP_WORKSHOP)
	interact_range = 2.8
	prompt = "Stables defense workshop · build / pick up"
	_build_look()


func interaction_point() -> Vector3:
	return to_global(Vector3(0.0, 0.0, 1.6))


func manager() -> ConstructionManager:
	if not is_instance_valid(_manager):
		_manager = get_tree().get_first_node_in_group(ConstructionManager.GROUP) as ConstructionManager
	return _manager


func prompt_text(_farmer: Farmer) -> String:
	var construction := manager()
	return prompt if construction != null and construction.is_open() else "Stables workshop · opens between waves"


func interact(farmer: Farmer) -> void:
	var construction := manager()
	if construction != null:
		construction.open_recipe_menu(farmer)


## A spaced pickup area along the front of the stables. Every job reserves its own rack slot.
func stock_position(slot: int) -> Vector3:
	return to_global(Vector3(-6.0 + (slot % 4) * 4.0, 0.0, 4.8 + floori(slot / 4.0) * 3.0))


func lesson_active() -> bool:
	var construction := manager()
	return construction != null and construction.is_open() and construction.director.wave >= 2 \
			and ConstructionManager.WORKSHOP_LESSON not in SaveManager.seen_intros


func lesson_text() -> String:
	var construction := manager()
	if not lesson_active():
		return ""
	if construction.in_hand != null:
		return "Carry your defense to a green spot. E / click places it; Tab returns it to the pickup rack.\nTry a Spring Trap by the silo ladder to throw small robots away."
	if not construction.ready_stock().is_empty():
		return "Your defense is ready at the STABLES pickup area. Walk over and press E to collect it.\nThen carry it to a green spot and press E / click to place it."
	if not construction.jobs.is_empty():
		return "Your defense is assembling at the STABLES. Standing beside it builds twice as fast.\nWhen it says READY, pick it up and carry it out."
	if not StatService.has_flag(&"defense.spring_trap"):
		return "Visit the STABLES DEFENSE WORKSHOP: follow the gold trail and press E.\nLearn the Spring Trap recipe (15 Al), then build a copy (12 Al). Earn more parts in battle if needed."
	return "Build a Spring Trap at the STABLES (12 Al), then pick up the finished trap.\nCarry it to the silo ladder or a robot lane and place it where the preview turns green."


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	var construction := manager()
	if construction == null:
		return
	var ready := construction.ready_stock().size()
	_status.text = "DEFENSE WORKSHOP\n" + ("E: learn recipes / build" if construction.is_open() else "Opens between waves")
	if ready > 0:
		_status.text += "\n%d READY FOR PICKUP" % ready
	var show_guide := lesson_active() and construction.in_hand == null
	if show_guide:
		var farmer := GameState.get_nearest_player(global_position) as Farmer
		if farmer == null:
			return
		if _trail == null or farmer != _trail_farmer:
			if _trail != null:
				_trail.queue_free()
			_trail = TutorialTrail.new()
			_trail.name = "WorkshopTrail"
			_trail.top_level = true
			add_child(_trail)
		if farmer != _trail_farmer:
			_trail_farmer = farmer
			_trail.setup(farmer)
		var goal := interaction_point()
		if ready > 0:
			goal = construction.ready_stock()[0].global_position + Vector3(0.0, 0.0, 1.2)
		_trail.set_goal(goal)
		if _marker == null:
			_marker = TutorialMarker.create(Vector3.ZERO, GOLD, 1.5)
			add_child(_marker)
		_marker.visible = true
		_marker.global_position = goal
	elif _trail != null:
		_trail.clear_goal()
		if _marker != null:
			_marker.visible = false


func _build_look() -> void:
	# A broad painted sign and a clay workbench make this station read from the silo.
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.8, 1.0, 1.4)
	collider.shape = shape
	collider.position.y = 0.5
	body.add_child(collider)
	add_child(body)
	var wood := Color(0.53, 0.35, 0.21)
	_box(Vector3(4.0, 0.2, 1.5), Vector3(0.0, 1.0, 0.0), wood)
	for x: float in [-1.6, 1.6]:
		_box(Vector3(0.18, 1.0, 0.18), Vector3(x, 0.5, 0.0), wood)
	_box(Vector3(4.5, 1.3, 0.18), Vector3(0.0, 2.4, -0.7), Color(0.22, 0.4, 0.3))
	_status = Label3D.new()
	_status.position = Vector3(0.0, 2.5, -0.55)
	_status.font_size = 38
	_status.pixel_size = 0.008
	_status.modulate = Color(1.0, 0.95, 0.77)
	_status.outline_size = 7
	_status.text = "DEFENSE WORKSHOP"
	add_child(_status)
	var pickup_sign := Label3D.new()
	pickup_sign.position = Vector3(0.0, 0.08, 6.0)
	pickup_sign.rotation_degrees.x = -90.0
	pickup_sign.font_size = 48
	pickup_sign.pixel_size = 0.012
	pickup_sign.modulate = GOLD
	pickup_sign.text = "PICK UP HERE"
	add_child(pickup_sign)
	for slot in 8:
		var pad := CylinderMesh.new()
		pad.top_radius = 0.85
		pad.bottom_radius = 0.85
		pad.height = 0.04
		Clay.part(self, pad, Color(0.82, 0.66, 0.32), Transform3D(Basis(),
				Vector3(-6.0 + (slot % 4) * 4.0, 0.025, 4.8 + floori(slot / 4.0) * 3.0)))


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	Clay.part(self, mesh, color, Transform3D(Basis(), at))
