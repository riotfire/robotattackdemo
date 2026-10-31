class_name DefenseWorkshop
extends Interactable
## The stables' workbench and pickup rack. All physical defenses are assembled here between waves.
## A persistent first-use lesson guides the farmer through build → pickup → placement.

const GROUP_WORKSHOP: StringName = &"defense_workshop"
const GOLD := Color(1.0, 0.8, 0.28)

var _manager: ConstructionManager
var _status: Label3D
var _trail: TutorialTrail
var _trail_farmer: Farmer
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
		return "E / click: place at a green spot. Tab: return it."
	if not construction.ready_stock().is_empty():
		return "Ready at the STABLES! E: pick up, then carry it out."
	if not construction.jobs.is_empty():
		return "Building at the STABLES. Stand by the workbench to help."
	return "Build defenses at the STABLES. E opens the workbench."


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.25
	var construction := manager()
	if construction == null:
		return
	var ready := construction.ready_stock().size()
	_status.text = "DEFENSE WORKSHOP\n" + ("E: build defenses" if construction.is_open() else "Opens between waves")
	if ready > 0:
		_status.text += "\n%d READY FOR PICKUP" % ready
	var show_guide := lesson_active() and construction.in_hand == null and ready == 0 and construction.jobs.is_empty()
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
		_trail.set_goal(interaction_point())
	elif _trail != null:
		_trail.clear_goal()


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


func _box(size: Vector3, at: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	Clay.part(self, mesh, color, Transform3D(Basis(), at))
