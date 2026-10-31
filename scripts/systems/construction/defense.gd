class_name Defense
extends Node3D
## A deployed defense on a DefenseSite: a spring trap, a decoy or a barricade (DefenseDefinition). Run-scoped:
## it stays put between waves and keeps its damage, and the run's end clears it. Only a finished copy acts;
## ConstructionManager keeps unfinished work as a ghost that does nothing until intermission completes it.
## Robots find active defenses through GROUP. Damage comes from robots that smash it (barricade breaches,
## lured robots, a Heavy stomping a spring); at 0 it breaks and the copy is spent.

signal broken(defense: Defense)

const GROUP: StringName = &"defenses"
## Physics layer of solid defenses (barricades). Robots collide with it; the farmer walks through, so a
## barricade never cuts the farmer off from a ladder, a crack or an exit.
const LAYER: int = 1 << 8

var definition: DefenseDefinition
var site: DefenseSite
## The farmer who placed it: trap kills are credited to them.
var placed_by: Node = null
## Full durability of this copy: the definition's, with upgrades that applied when it was built.
var max_hp: float = 1.0
var hp: float = 0.0
var active: bool = false
## Finished stock is shown solid on the workshop rack, but never acts until placed.
var ready_for_pickup: bool = false

var _hp_label: Label3D


## Call before adding to the tree.
## `full_hp` above 0 replaces the definition's durability (Sturdy Scrap).
func setup(defense_definition: DefenseDefinition, defense_site: DefenseSite, owner_farmer: Node, full_hp: float = -1.0) -> void:
	definition = defense_definition
	site = defense_site
	placed_by = owner_farmer
	max_hp = full_hp if full_hp > 0.0 else definition.max_hp
	hp = max_hp


func _ready() -> void:
	add_to_group(GROUP)
	_build_look()
	_hp_label = Label3D.new()
	_hp_label.font_size = 26
	_hp_label.outline_size = 7
	_hp_label.pixel_size = 0.0012
	_hp_label.fixed_size = true
	_hp_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_hp_label.position = Vector3.UP * (label_height())
	add_child(_hp_label)
	set_active(active)
	_refresh_label()


## Whether it acts. ConstructionManager turns a copy on when its assembly completes.
func set_active(on: bool) -> void:
	active = on
	_on_active_changed()
	_refresh_label()


func is_elevated() -> bool:
	return site != null and site.kind != &"ground"


func condition() -> float:
	return clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0


## Robot hits and stomps. Returns the damage taken.
func take_damage(packet: DamagePacket) -> float:
	if hp <= 0.0 or packet.amount <= 0.0:
		return 0.0
	var taken := minf(hp, packet.amount)
	hp -= taken
	Fx.puff(self, global_position + Vector3.UP * 0.6, Color(0.8, 0.7, 0.5), 0.25, 0.15)
	_refresh_label()
	if hp <= 0.0:
		_break()
	return taken


func repair_full() -> void:
	hp = max_hp
	_refresh_label()


## Where a robot attacking it aims, and how far that is from a robot at `from` (flat).
func strike_point(from: Vector3) -> Vector3:
	return global_position + Vector3.UP * 0.5


func distance_from(from: Vector3) -> float:
	var flat := from - global_position
	flat.y = 0.0
	return flat.length()


func label_height() -> float:
	return 1.6


func _break() -> void:
	active = false
	remove_from_group(GROUP)
	Fx.puff(self, global_position + Vector3.UP * 0.5, Color(0.65, 0.55, 0.4), 0.8, 0.4)
	EventBus.hud_message.emit("%s broke!" % definition.display_name, 2.0)
	broken.emit(self)
	queue_free()


func _refresh_label() -> void:
	if _hp_label == null or definition == null:
		return
	var damaged := hp < max_hp - 0.5
	_hp_label.visible = damaged or not active
	_hp_label.text = ("%d%%" % roundi(condition() * 100.0)) if active else ("%s READY\nE / X: pick up" % definition.display_name if ready_for_pickup else "assembling")
	_hp_label.modulate = Color(1.0, 0.75, 0.4) if not active and not ready_for_pickup else Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.35, 0.3), 1.0 - condition())


## Called after the copy moved to another site, so it can face the new site's way.
func relocated() -> void:
	var look := get_node_or_null(^"Look")
	if look != null:
		look.name = "RetiredLook_%d" % look.get_instance_id()
		(look as Node3D).visible = false
		look.queue_free()
	_build_look()
	_on_active_changed()


## Overridden by each defense: its clay look, built in code like the rest of the graybox.
func _build_look() -> void:
	pass


func _on_active_changed() -> void:
	var look := get_node_or_null(^"Look") as Node3D
	if look != null:
		# An unfinished copy is a pale, see-through ghost.
		for mesh in look.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).transparency = 0.0 if active or ready_for_pickup else 0.55
