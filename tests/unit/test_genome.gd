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
	assert_eq(RobotGenome.from_code("AAAAAA", 6, lib, curve).traits.size(), 0, "the opening rolls no traits")
	assert_eq(RobotGenome.from_code("AAAAAA", 7, lib, curve).traits.size(), 1)
	assert_eq(RobotGenome.from_code("AAAAAA", 20, lib, curve).traits.size(), 2)


func test_every_palette_contrasts_with_the_farm() -> void:
	for theme in lib.themes:
		assert_eq(theme.palettes.size(), 4, "%s has 4 palettes" % theme.theme_word)
		for palette in theme.palettes:
			assert_gte(RobotPalette.luminance_contrast(palette.primary, lib.farm_color), lib.min_contrast,
					"%s %s contrasts with the grass" % [palette.adjective, theme.theme_word])


func test_nibbler_is_always_the_monowheel_sculpt() -> void:
	var archetype := load("res://data/robots/archetypes/nibbler.tres") as RobotArchetype
	var rng := RandomNumberGenerator.new()
	for code: String in ["PIRATE", "ABCDEF", "ZZZZZZ", "M2M2M2"]:
		var genome := RobotGenome.from_code(code, 6, lib, curve)
		genome.locomotion_by_type[0] = &"pogo"
		var pose := Node3D.new()
		var look := RobotFactory.build(pose, genome, archetype, rng)
		assert_eq(look.wheels.size(), 1, "%s rolls on one wheel" % code)
		assert_eq((look.wheels[0] as MeshInstance3D).mesh, RobotSkin.mesh(&"wheel"), "%s uses the sculpted wheel" % code)
		pose.free()


func test_families_differ_on_the_skin_by_color_only() -> void:
	var archetype := load("res://data/robots/archetypes/clanker.tres") as RobotArchetype
	var rng := RandomNumberGenerator.new()
	var genome := RobotGenome.from_code("PIRATE", 6, lib, curve)
	genome.pattern = &"checker"
	genome.wear = &"rusty"
	var pose := Node3D.new()
	RobotFactory.build(pose, genome, archetype, rng)
	var skins := 0
	for node in pose.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		if part.material_override == Clay.robot_skin():
			skins += 1
			assert_null(part.get_instance_shader_parameter(&"pattern_id"), "%s has no pattern" % part.mesh)
			assert_null(part.get_instance_shader_parameter(&"wear"), "%s has no wear" % part.mesh)
	assert_gt(skins, 0, "the robot wears the skin")
	pose.free()


func test_every_rollable_shape_has_a_morph() -> void:
	for theme in lib.themes:
		for shape in theme.body_shapes:
			assert_true(RobotSkin.BODY_MORPHS.has(shape), "body %s has a morph" % shape)
		for shape in theme.heads:
			assert_true(RobotSkin.HEAD_MORPHS.has(shape), "head %s has a morph" % shape)


func test_morphs_keep_the_mesh_and_only_build_once() -> void:
	var stock := RobotSkin.mesh(&"torso")
	var settings := RobotSkin.BODY_MORPHS[&"toaster"]
	var bent := RobotSkin.morphed(&"torso", &"toaster", settings, RobotSkin.TORSO_SHELL)
	assert_ne(bent, stock, "a morph is its own mesh")
	assert_eq(bent.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(), stock.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size(),
			"bending moves vertices without adding any")
	assert_eq(RobotSkin.morphed(&"torso", &"toaster", settings, RobotSkin.TORSO_SHELL), bent, "robots share the built mesh")
	assert_eq(RobotSkin.morphed(&"head", &"dome", RobotSkin.HEAD_MORPHS[&"dome"], RobotSkin.HEAD_SHELL), RobotSkin.mesh(&"head"),
			"the stock dome is the sculpt itself")


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
