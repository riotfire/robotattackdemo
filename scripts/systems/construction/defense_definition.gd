class_name DefenseDefinition
extends Resource
## One buildable defense (DEFENSE_BUILDING_AND_COMBAT_PROGRESSION_PROPOSAL.md): its recipe flag, the price of
## each physical copy, the share of the farm's defense capacity it takes, its assembly time and durability,
## and the numbers its behavior reads. Generated into data/defenses/ from data/source/defenses/items by
## tools/build_defense_data.gd. Owning the recipe is lasting progression (a pegboard node sets the flag);
## every copy costs parts again, and a destroyed copy stays spent.

enum Kind { SPRING_TRAP, DECOY, BARRICADE }

## The kinds of DefenseSite.
const SITE_KINDS: Array[StringName] = [&"ground", &"catwalk", &"roof"]

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.SPRING_TRAP
@export var description: String = ""
## Stat flag that says this profile owns the recipe (StatService.has_flag).
@export var recipe_flag: StringName = &""
## Aluminium per copy. Base copies cost only Aluminium so the first lesson never waits on a rare drop.
@export var cost_al: int = 10
## Defense capacity a copy (or a job waiting to become one) takes, out of ConstructionManager's budget.
@export var capacity: int = 1
## Seconds of intermission work to assemble one copy at the base work rate.
@export var assembly_time: float = 8.0
## A move to another site costs this share of the assembly time again, and no parts.
@export_range(0.0, 1.0) var relocate_share: float = 0.5
## Durability. Damage stays on the copy between waves until it is repaired at an intermission.
@export var max_hp: float = 100.0
## Site kinds the definition may be placed on: ground, catwalk, roof.
@export var site_kinds: Array[StringName] = [&"ground"]

@export_group("Spring trap")
## Launch speed straight up and out along the site's launch direction, for a small robot.
@export var launch_up_speed: float = 12.0
@export var launch_out_speed: float = 7.0
## Robots of medium size get this share of the launch; large robots and Foremen are never launched.
@export_range(0.0, 1.0) var medium_launch_share: float = 0.6
## Seconds before the spring can fire again.
@export var reset_time: float = 5.0
## A robot this close (flat distance, and within 1.5 m of its height) sets it off.
@export var trigger_radius: float = 1.0
## Damage a large robot does to a spring by stepping on it (it doesn't fly).
@export var stomp_damage: float = 30.0

@export_group("Decoy")
## Eligible robots within this distance are pulled toward the decoy: on the ground, and from elevated sites.
@export var lure_radius_ground: float = 12.0
@export var lure_radius_elevated: float = 24.0
## Robots it holds at once, and how long each stays on it before going back to its own target.
@export var max_lured: int = 3
@export var lure_time: float = 10.0

@export_group("Barricade")
## Width across the approach; robots that touch it smash it before going on.
@export var barricade_width: float = 3.6
@export var barricade_height: float = 1.2


## The parts one copy costs.
func cost() -> Dictionary[StringName, int]:
	return {&"al": cost_al}


func allowed_on(site_kind: StringName) -> bool:
	return site_kind in site_kinds
