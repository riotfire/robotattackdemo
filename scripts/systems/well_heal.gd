class_name WellHeal
extends Node
## A drink at the well (PLAYTEST_SIMULATION_REPORT.md finding 7): the farm's well, 12 m from the silo wall,
## heals a farmer standing at it, so a hurt farmer doesn't have to run the 36 m to the Home porch through the
## fight. Slower than the porch (8 HP/s against 15), so the porch stays the better heal. Builds a HealZone
## around the farm's Well at run start; the farm scene itself is untouched.

@export var heal_per_second: float = 8.0
@export var radius: float = 3.2

var zone: HealZone = null


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	var well := _find_well()
	if well == null:
		return
	zone = HealZone.new()
	zone.name = "WellHealZone"
	zone.heal_per_second = heal_per_second
	zone.heal_stat = &""
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position = Vector3.UP * 1.5
	zone.add_child(shape)
	add_child(zone)
	zone.global_position = well.global_position
	var sign := Label3D.new()
	sign.text = "WELL  (heals)"
	sign.font_size = 72
	sign.outline_size = 12
	sign.modulate = Color(0.75, 0.95, 1.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	zone.add_child(sign)
	sign.position = Vector3.UP * 4.2


func _find_well() -> Node3D:
	var context: Node = GameState.silo
	while context != null:
		for path: NodePath in [^"Farm/NavRegion/Well", ^"NavRegion/Well"]:
			var well := context.get_node_or_null(path) as Node3D
			if well != null:
				return well
		context = context.get_parent()
	return null
