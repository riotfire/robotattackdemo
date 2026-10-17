extends GutTest
## Robot families (GDD 10): determinism, novelty rules, readability locks and the factory.

const LIBRARY := "res://data/robots/gene_library.tres"

var lib: GeneLibrary
var curve: DifficultyCurve


func before_each() -> void:
	lib = load(LIBRARY) as GeneLibrary
	curve = DifficultyCurve.new()


func test_same_code_rebuilds_the_same_family() -> void:
	var a := RobotGenome.from_code("K7Q2ZP", 7, lib, curve)
	var b := RobotGenome.from_code("K7Q2ZP", 7, lib, curve)
	for gene: StringName in [&"family_name", &"body_shape", &"head", &"eye_style", &"antenna", &"pattern",
			&"wear", &"personality", &"accessory", &"melee_arm"]:
		assert_eq(a.get(gene), b.get(gene), "gene %s" % gene)
	assert_eq(a.theme, b.theme)
	assert_eq(a.palette, b.palette)
	assert_eq(a.locomotion_by_type, b.locomotion_by_type)
	assert_eq(a.trait_names(), b.trait_names())


func test_same_seed_and_wave_roll_the_same_family() -> void:
	var history: Array[RobotGenome] = []
	var a := RobotGenome.roll(1234, 3, lib, history, curve)
	var b := RobotGenome.roll(1234, 3, lib, history, curve)
	assert_eq(a.family_code, b.family_code)
	assert_ne(RobotGenome.roll(1235, 3, lib, history, curve).family_code, a.family_code, "another seed, another family")


func test_family_codes_use_the_safe_alphabet() -> void:
	for value: int in [0, 1, 99999, 2147483647, -5]:
		var code := GeneLibrary.encode(value)
		assert_eq(code.length(), 6)
		for c in code:
			assert_true(GeneLibrary.CODE_ALPHABET.contains(c), "%s in %s" % [c, code])
			assert_false(c in ["0", "O", "1", "I"], "no ambiguous characters")


func test_novelty_rules_hold_over_a_run() -> void:
	var history: Array[RobotGenome] = []
	for wave in range(1, 21):
		var genome := RobotGenome.roll(777, wave, lib, history, curve)
		if not history.is_empty():
			var last := history[history.size() - 1]
			assert_ne(genome.theme, last.theme, "wave %d: no theme twice in a row" % wave)
			assert_gt(RobotPalette.oklab_distance(genome.palette.primary, last.palette.primary), 0.15, "wave %d: palette distance" % wave)
			assert_lte(genome.matching_shape_genes(last), 2, "wave %d: at most 2 shape genes match" % wave)
		history.append(genome)


func test_trait_count_follows_the_curve() -> void:
	assert_eq(RobotGenome.from_code("AAAAAA", 3, lib, curve).traits.size(), 0)
	assert_eq(RobotGenome.from_code("AAAAAA", 6, lib, curve).traits.size(), 1)
	assert_eq(RobotGenome.from_code("AAAAAA", 20, lib, curve).traits.size(), 2)


func test_every_palette_contrasts_with_the_farm() -> void:
	for theme in lib.themes:
		assert_eq(theme.palettes.size(), 3, "%s has 3 palettes" % theme.theme_word)
		for palette in theme.palettes:
			assert_gte(RobotPalette.luminance_contrast(palette.primary, lib.farm_color), lib.min_contrast,
					"%s %s contrasts with the grass" % [palette.adjective, theme.theme_word])


func test_factory_keeps_the_readability_locks() -> void:
	var genome := RobotGenome.from_code("PIRATE", 6, lib, curve)
	var rng := RandomNumberGenerator.new()
	for path: String in ["res://data/robots/archetypes/nibbler.tres", "res://data/robots/archetypes/clanker.tres",
			"res://data/robots/archetypes/thumper.tres"]:
		var archetype := load(path) as RobotArchetype
		var pose := Node3D.new()
		var look := RobotFactory.build(pose, genome, archetype, rng)
		var kit := pose.get_node(^"Kit") as Node3D
		var expected_scale := RobotFactory.TYPE_SCALES[int(archetype.robot_type)] * genome.size
		assert_almost_eq(kit.scale.x, expected_scale, expected_scale * 0.06, "%s is sized by type" % archetype.id)
		assert_false(look.eyes.is_empty(), "%s has an eye" % archetype.id)
		assert_not_null(look.bulb, "%s has the antenna bulb (Factory DNA)" % archetype.id)
		for eye in look.eyes:
			assert_eq(eye.get_instance_shader_parameter(&"tint"), RobotFactory.CLASS_EYE_COLORS[0], "melee eyes glow red")
		pose.free()
