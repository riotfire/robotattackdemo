class_name RobotArchetype
extends Resource
## A robot archetype (GDD 9.3): a size (type) x attack style (class) cell of the attack grid, with wave-1
## stats, behavior variables, threat cost and drops. Generated in data/robots/archetypes from the
## data/source/robots/archetypes table by tools/build_robot_data.gd; one column per property below.

## Size: small, medium, large (GDD 9.1).
enum RobotType { SCOUT, GRUNT, HEAVY }
## Attack style, the grid's columns (GDD 9.2): close up, a long-distance projectile, or from the air.
enum RobotClass { MELEE, RANGED, FLIGHT }
## What a robot does when it can't reach its farmer (GDD 9.6). GIVE_UP: back to the silo after
## give_up_time. THROW (M2-B9): up to two telegraphed throws of its ranged_attack_id from
## DifficultyCurve.unreachable_throw_first_wave, then back to the silo. RELOCATE behaves like GIVE_UP until M2-B12.
enum OnUnreachable { GIVE_UP, THROW, RELOCATE }

## GDD 11.4 cost per robot by size, and multipliers by attack style. A trio costs three robots.
const TYPE_COSTS: PackedFloat32Array = [2.0, 4.0, 14.0]
const CLASS_COST_MULTIPLIERS: PackedFloat32Array = [1.0, 1.25, 1.6]
## The things that can pull a robot off the silo (see distract_triggers).
const DISTRACT_TRIGGERS: Array[StringName] = [&"hurt", &"near", &"repairing", &"airborne"]
const ATTACK_DIR := "res://data/robots/attacks"
## Hits from within this angle of straight ahead count as "from the front" for front_guard.
const FRONT_GUARD_HALF_ANGLE: float = 60.0

@export var id: StringName = &""
@export var display_name: String = ""
@export var robot_type: RobotType = RobotType.SCOUT
@export var robot_class: RobotClass = RobotClass.MELEE
@export var scene: PackedScene
## First wave this archetype can spawn in regular spawns (GDD 9.5). Heavies debut earlier as a Foreman.
@export var unlock_wave: int = 1
## Relative chance among archetypes of the same type during spawn-budget selection.
@export var spawn_weight: float = 1.0
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

@export_group("Behavior (GDD 9.2, 9.6)")
## Chance at spawn to go for the silo; otherwise it hunts the farmer. A trio rolls once, for all three.
@export_range(0.0, 1.0) var silo_focus: float = 0.7
## Chance a silo-bound robot grabs a grain sack instead. Ignored for Scout melee robots (Nibblers),
## which steal at DifficultyCurve.thief_share instead (GDD 11.7).
@export_range(0.0, 1.0) var steal_chance: float = 0.0
## Chance a spawn is a trio (GDD 9.6). Large robots, flyers and Foremen are always solo, whatever this says.
@export_range(0.0, 1.0) var trio_chance: float = 0.4
## The trio chance by DifficultyCurve.trio_full_wave, reached in steps from trio_chance (small ground
## robots: 40% in waves 1-2, 60% from wave 3, 70% by wave 15). Below 0 keeps trio_chance at every wave.
@export var trio_chance_late: float = 0.7
## Once a second while attacking the silo, the chance to switch to the farmer when a trigger is active.
@export_range(0.0, 1.0) var distractibility: float = 0.3
## Any of DISTRACT_TRIGGERS. hurt: the farmer damaged it. near: the farmer is within distract_range.
## repairing: the farmer is repairing within range. airborne: the farmer is jetpacking or up on a perch.
@export var distract_triggers: Array[StringName] = [&"hurt", &"near"]
## How close the farmer must be for a trigger to count.
@export var distract_range: float = 8.0
## Seconds on a target before it can be distracted again, so robots don't flip back and forth.
@export var commit_time: float = 2.0
## Goes back to the silo after chasing the farmer this long once within distract_range. 0 = no limit.
@export var chase_time: float = 6.0
## Goes back to the silo if the farmer leads it this far from the silo. 0 = no limit.
@export var leash_range: float = 25.0
## Goes back to the silo if the farmer stays out of reach (e.g. on a roof) this long. 0 = never.
@export var give_up_time: float = 3.0
@export var on_unreachable: OnUnreachable = OnUnreachable.GIVE_UP

@export_group("Ranged attack (M2-B7)")
## The AttackProfile this robot fires, by id in data/robots/attacks. Ranged robots take their charge,
## interval and damage from the profile instead of the wave-1 stats above; melee robots with
## on_unreachable = throw throw it at an out-of-reach farmer (M2-B9). Empty for other melee robots.
@export var ranged_attack_id: StringName = &""

@export_group("Defense and tells (M2-B9)")
## Share of damage blocked from hits within FRONT_GUARD_HALF_ANGLE of its facing (the Clanker's arm guard,
## from DifficultyCurve.arm_guard_first_wave). 0 = none.
@export_range(0.0, 1.0) var front_guard: float = 0.0
## Extra parts RobotFactory adds so the role reads at a glance: arm_guard, pea_shooter, bolt_pouch, clod_scoop.
@export var tells: Array[StringName] = []

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


## The AttackProfile named by ranged_attack_id, or null.
func ranged_attack() -> AttackProfile:
	if ranged_attack_id.is_empty():
		return null
	var path := ATTACK_DIR.path_join("%s.tres" % ranged_attack_id)
	return load(path) as AttackProfile if ResourceLoader.exists(path) else null


## Threat cost of one robot (GDD 11.4): size cost x attack-style multiplier.
func threat_cost() -> float:
	return TYPE_COSTS[robot_type] * CLASS_COST_MULTIPLIERS[robot_class]


## Large robots and flyers never form trios (GDD 9.6); neither do Foremen, which the director spawns alone.
func can_form_trio() -> bool:
	return robot_type != RobotType.HEAVY and robot_class != RobotClass.FLIGHT
