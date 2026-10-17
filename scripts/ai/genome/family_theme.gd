class_name FamilyTheme
extends Resource
## A family theme (GDD 10.1 Layer 2): drives every other gene's allowlist, the accessories and the name.

@export var id: StringName = &""
## The theme word in family names: "The Minty <Pirate> Teapots".
@export var theme_word: String = ""
@export var body_shapes: Array[StringName] = []
@export var heads: Array[StringName] = []
@export var eye_styles: Array[StringName] = []
@export var antennas: Array[StringName] = []
@export var patterns: Array[StringName] = []
## Melee weapon arms this theme favors (class lock: melee is always a claw, fist or hammer).
@export var melee_arms: Array[StringName] = []
@export var palettes: Array[RobotPalette] = []
## Accessory part ids the factory knows how to build (2-4 per theme).
@export var accessories: Array[StringName] = []


func pick(gene: StringName, rng: RandomNumberGenerator) -> StringName:
	var options: Array[StringName] = get(gene)
	return options[rng.randi_range(0, options.size() - 1)] if not options.is_empty() else &""
