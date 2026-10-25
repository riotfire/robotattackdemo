class_name RobotTrait
extends Resource
## A family gameplay mutator (GDD 10.3). Every trait has a visual tell the factory adds.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var hp_multiplier: float = 1.0
@export var speed_multiplier: float = 1.0
@export var gold_chance_multiplier: float = 1.0
## Any melee robot in the family may steal grain (Thieving).
@export var thieving: bool = false
@export var power_cell_chance_multiplier: float = 1.0
## Overcharged: on death the robot detonates after a short fuse, hurting robots (and farmers) within this
## radius in metres, scaled by the robot's size. Robots it kills that are Overcharged too go off in turn,
## so the blast chains. 0 means no blast.
@export var death_blast_radius: float = 0.0
## Blast damage to robots at the centre (half at the edge), scaled by the wave's HP curve and robot size,
## so a blast keeps killing the same robots at every wave.
@export var death_blast_damage: float = 0.0
## Blast damage to farmers, scaled by the wave's damage curve and robot size.
@export var death_blast_farmer_damage: float = 0.0
## Accessory the factory adds as the visual tell.
@export var tell: StringName = &""


static func make(trait_id: StringName, label: String, text: String, hp: float, speed: float, gold: float,
		steals: bool, tell_part: StringName) -> RobotTrait:
	var robot_trait := RobotTrait.new()
	robot_trait.id = trait_id
	robot_trait.display_name = label
	robot_trait.description = text
	robot_trait.hp_multiplier = hp
	robot_trait.speed_multiplier = speed
	robot_trait.gold_chance_multiplier = gold
	robot_trait.thieving = steals
	robot_trait.tell = tell_part
	return robot_trait
