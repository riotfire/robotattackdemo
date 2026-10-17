class_name RobotGenome
extends Resource
## One wave's robot family (GDD 10.1 Layer 2): every robot in the wave shares these genes.
##
## The whole family is a pure function of its 6-character family code (plus the wave, for the trait
## count), so a shared code rebuilds the same look in the Almanac (GDD 10.2). roll() derives codes from
## (run_seed, wave, attempt) and takes the first one that passes the novelty rules against earlier waves.

@export var family_code: String = ""
@export var wave: int = 1
@export var theme: FamilyTheme
@export var palette: RobotPalette
@export var body_shape: StringName = &""
@export var head: StringName = &""
@export var eye_style: StringName = &""
@export var antenna: StringName = &""
@export var melee_arm: StringName = &""
## Indexed by RobotArchetype.RobotType.
@export var locomotion_by_type: Array[StringName] = []
@export var pattern: StringName = &""
@export var wear: StringName = &""
@export var personality: StringName = &""
@export var voice_pitch: float = 1.0
@export var size: float = 1.0
@export var accessory: StringName = &""
@export var traits: Array[RobotTrait] = []
@export var family_name: String = ""


static func roll(run_seed: int, wave_number: int, lib: GeneLibrary, history: Array[RobotGenome],
		curve: DifficultyCurve) -> RobotGenome:
	var genome: RobotGenome = null
	for attempt in 32:
		var code := GeneLibrary.encode(hash([run_seed, wave_number, &"genome", attempt]))
		genome = from_code(code, wave_number, lib, curve)
		if lib.is_novel(genome, history):
			return genome
	return genome


static func from_code(code: String, wave_number: int, lib: GeneLibrary, curve: DifficultyCurve) -> RobotGenome:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(code)
	var g := RobotGenome.new()
	g.family_code = code
	g.wave = wave_number
	g.theme = lib.themes[rng.randi_range(0, lib.themes.size() - 1)]
	g.palette = lib.pick_palette(g.theme, rng)
	g.body_shape = g.theme.pick(&"body_shapes", rng)
	g.head = g.theme.pick(&"heads", rng)
	g.eye_style = g.theme.pick(&"eye_styles", rng)
	g.antenna = g.theme.pick(&"antennas", rng)
	g.melee_arm = g.theme.pick(&"melee_arms", rng)
	g.pattern = g.theme.pick(&"patterns", rng)
	for options in GeneLibrary.LOCOMOTION:
		g.locomotion_by_type.append(options[rng.randi_range(0, options.size() - 1)])
	g.wear = GeneLibrary.WEARS[rng.randi_range(0, GeneLibrary.WEARS.size() - 1)]
	g.personality = GeneLibrary.PERSONALITIES[rng.randi_range(0, GeneLibrary.PERSONALITIES.size() - 1)]
	g.voice_pitch = rng.randf_range(0.7, 1.4)
	g.size = rng.randf_range(0.9, 1.1)
	g.accessory = g.theme.pick(&"accessories", rng)
	g.traits = lib.pick_traits(rng, curve.trait_count(wave_number))
	g.family_name = "The %s %s %s" % [g.palette.adjective, g.theme.theme_word, GeneLibrary.BODY_PLURALS.get(g.body_shape, "Bots")]
	return g


## How many of the 5 shape genes match another family's.
func matching_shape_genes(other: RobotGenome) -> int:
	var count := 0
	for gene: StringName in [&"body_shape", &"head", &"eye_style", &"antenna"]:
		if get(gene) == other.get(gene):
			count += 1
	if not locomotion_by_type.is_empty() and not other.locomotion_by_type.is_empty() \
			and locomotion_by_type[0] == other.locomotion_by_type[0]:
		count += 1
	return count


func has_trait(id: StringName) -> bool:
	for robot_trait in traits:
		if robot_trait.id == id:
			return true
	return false


func trait_names() -> PackedStringArray:
	var names := PackedStringArray()
	for robot_trait in traits:
		names.append(robot_trait.display_name)
	return names


## Foreman title (Appendix B).
func foreman_title(rng: RandomNumberGenerator) -> String:
	var body := GeneLibrary.BODY_SINGULARS.get(body_shape, "Bot") as String
	match rng.randi_range(0, 2):
		0:
			return "Big Boss %s" % GeneLibrary.HEAD_NAMES.get(head, "Bot")
		1:
			return "Foreman %s %s" % [theme.theme_word, body]
	return "The Grand %s" % body
