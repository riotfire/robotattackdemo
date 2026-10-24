class_name RobotArchetype
extends Resource
## One of the nine robot archetypes (GDD 9.3): type x class, wave-1 stats, threat cost and drops.
## M1 ships the melee class: Nibbler, Clanker and Thumper (data/robots/archetypes, generated from the
## data/source/robots/archetypes table by tools/build_robot_data.gd; one column per property below).

enum RobotType { SCOUT, GRUNT, HEAVY }
enum RobotClass { MELEE, SHORT_RANGE, LONG_RANGE }

## GDD 11.4 base costs by type and multipliers by class.
const TYPE_COSTS: PackedFloat32Array = [2.0, 6.0, 14.0]
const CLASS_COST_MULTIPLIERS: PackedFloat32Array = [1.0, 1.25, 1.6]

@export var id: StringName = &""
@export var display_name: String = ""
@export var robot_type: RobotType = RobotType.SCOUT
@export var robot_class: RobotClass = RobotClass.MELEE
@export var scene: PackedScene
## First wave this archetype can spawn in regular spawns (GDD 9.5). Heavies debut earlier as a Foreman.
@export var unlock_wave: int = 1
## Relative chance among archetypes of the same type during spawn-budget selection.
@export var spawn_weight: float = 1.0
## Robots spawned per spawn event: Grunts come in squads of 3 (GDD 9.1).
@export var squad_size: int = 1
## Roughly the body radius at this type's scale; used to stand off the silo wall.
@export var body_radius: float = 0.35

@export_group("Wave 1 stats (GDD 9.1, 9.4)")
@export var base_hp: float = 30.0
@export var move_speed: float = 8.0
@export var attack_range: float = 1.8
@export var attack_interval: float = 1.0
## Telegraph before each hit lands.
@export var attack_windup: float = 0.3
@export var damage_vs_farmer: float = 4.0
@export var damage_vs_silo: float = 6.0

@export_group("Targeting (GDD 9.2)")
## Chance to pick the farmer instead of the silo at spawn (melee: silo 70% / farmer 30%).
@export_range(0.0, 1.0) var farmer_target_chance: float = 0.3
## Switches to the farmer when the farmer damages it from within this range.
@export var aggro_range: float = 10.0
## Gives up on a farmer who stays out of reach (e.g. on a roof) for this long and goes back to the silo.
@export var unreachable_give_up_time: float = 3.0
## Chance a silo-bound robot grabs a grain sack instead. Ignored for Scout melee robots (Nibblers),
## which steal at DifficultyCurve.thief_share instead (GDD 11.7).
@export_range(0.0, 1.0) var steal_chance: float = 0.0

@export_group("Heavy slam (GDD 9.3)")
## Shockwave ring from a slam; jump over it. 0 = no shockwave.
@export var shockwave_damage: float = 0.0
@export var shockwave_radius: float = 8.0
@export var shockwave_time: float = 0.8

@export_group("Drops (GDD 12.2)")
@export var drop_al_min: int = 1
@export var drop_al_max: int = 2
## Melee robots drop +1 Aluminium.
@export var drop_al_class_bonus: int = 1
@export_range(0.0, 1.0) var drop_cu_chance: float = 0.15
@export var drop_cu_min: int = 1
@export var drop_cu_max: int = 1
@export_range(0.0, 1.0) var drop_au_chance: float = 0.01
@export var drop_au_min: int = 1
@export var drop_au_max: int = 1
@export_range(0.0, 1.0) var drop_pc_chance: float = 0.005
@export var drop_pc_min: int = 1
@export var drop_pc_max: int = 1


func threat_cost() -> float:
	return TYPE_COSTS[robot_type] * CLASS_COST_MULTIPLIERS[robot_class]
