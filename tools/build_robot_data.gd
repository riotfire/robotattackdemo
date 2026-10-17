extends SceneTree
## Writes the M1 robot family data (GDD 10): 9 palettes, 3 themes (Junkyard, Disco, Pirate), 4 traits
## (Speedy, Armored, Gilded, Thieving) and the gene library that ties them together.
## Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_robot_data.gd
## Re-running overwrites the files under data/robots/{palettes,themes,traits} and gene_library.tres.

const ROOT := "res://data/robots"


func _initialize() -> void:
	var palettes: Dictionary[String, RobotPalette] = {
		"rusty": RobotPalette.make("Rusty", Color(0.6, 0.28, 0.15), Color(0.35, 0.3, 0.28), Color(0.75, 0.65, 0.4)),
		"slate": RobotPalette.make("Slate", Color(0.28, 0.32, 0.4), Color(0.25, 0.55, 0.55), Color(0.8, 0.65, 0.3)),
		"mustard": RobotPalette.make("Mustard", Color(0.95, 0.8, 0.2), Color(0.35, 0.38, 0.2), Color(0.45, 0.3, 0.2)),
		"bubblegum": RobotPalette.make("Bubblegum", Color(1.0, 0.68, 0.9), Color(0.55, 0.3, 0.75), Color(0.85, 0.85, 0.9)),
		"grape": RobotPalette.make("Grape", Color(0.45, 0.25, 0.7), Color(0.25, 0.7, 0.7), Color(0.95, 0.78, 0.3)),
		"chrome": RobotPalette.make("Chrome", Color(0.85, 0.87, 0.92), Color(0.85, 0.25, 0.65), Color(0.95, 0.78, 0.3)),
		"minty": RobotPalette.make("Minty", Color(0.6, 0.95, 0.85), Color(0.15, 0.2, 0.4), Color(0.95, 0.78, 0.3)),
		"teal": RobotPalette.make("Teal", Color(0.08, 0.38, 0.45), Color(0.8, 0.2, 0.2), Color(0.95, 0.8, 0.35)),
		"cherry": RobotPalette.make("Cherry", Color(0.75, 0.12, 0.2), Color(0.12, 0.12, 0.14), Color(0.95, 0.78, 0.3)),
	}
	for key in palettes:
		var path := ROOT.path_join("palettes/%s.tres" % key)
		_save(palettes[key], path)
		# Reload so themes reference the palette files instead of embedding copies.
		palettes[key] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as RobotPalette

	var themes: Array[FamilyTheme] = [
		_theme(&"junkyard", "Junkyard", [&"tin_can", &"barrel", &"lunchbox", &"toaster"], [&"bucket", &"old_tv", &"mailbox"],
				[&"cyclops", &"monocle", &"led_grid"], [&"spring", &"lightning_rod", &"whisk"], [&"rust_patches", &"none", &"hazard_tape"],
				[&"claw", &"hammer"], [palettes["rusty"], palettes["slate"], palettes["mustard"]], [&"tin_hat", &"exhaust_pipe"]),
		_theme(&"disco", "Disco", [&"gumdrop", &"egg", &"toaster"], [&"dome", &"light_bulb", &"old_tv"],
				[&"visor", &"twin_goggles", &"led_grid"], [&"bulb", &"propeller", &"spring"], [&"stars", &"polka_dots", &"checker"],
				[&"fist", &"claw"], [palettes["bubblegum"], palettes["grape"], palettes["chrome"]], [&"mirror_ball", &"star_glasses", &"afro"]),
		_theme(&"pirate", "Pirate", [&"barrel", &"egg", &"tin_can", &"lunchbox"], [&"bucket", &"teapot", &"dome", &"mailbox"],
				[&"monocle", &"cyclops", &"visor"], [&"lightning_rod", &"propeller", &"dish"], [&"stripes", &"none", &"checker"],
				[&"hammer", &"fist"], [palettes["minty"], palettes["teal"], palettes["cherry"]], [&"bandana", &"tricorn", &"hook"]),
	]
	for i in themes.size():
		var path := ROOT.path_join("themes/%s.tres" % themes[i].id)
		_save(themes[i], path)
		themes[i] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as FamilyTheme

	var traits: Array[RobotTrait] = [
		RobotTrait.make(&"speedy", "Speedy", "+25% move speed.", 1.0, 1.25, 1.0, false, &"speed_fins"),
		RobotTrait.make(&"armored", "Armored", "+40% HP, -10% speed.", 1.4, 0.9, 1.0, false, &"armor_plates"),
		RobotTrait.make(&"gilded", "Gilded", "x3 Gold drop chance.", 1.0, 1.0, 3.0, false, &"gold_band"),
		RobotTrait.make(&"thieving", "Thieving", "Any melee robot may steal grain.", 1.0, 1.0, 1.0, true, &"sack"),
	]
	for i in traits.size():
		var path := ROOT.path_join("traits/%s.tres" % traits[i].id)
		_save(traits[i], path)
		traits[i] = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as RobotTrait

	var library := GeneLibrary.new()
	library.themes = themes
	library.traits = traits
	_save(library, ROOT.path_join("gene_library.tres"))
	quit(0)


func _theme(id: StringName, word: String, bodies: Array[StringName], heads: Array[StringName], eyes: Array[StringName],
		antennas: Array[StringName], patterns: Array[StringName], arms: Array[StringName], palettes: Array[RobotPalette],
		accessories: Array[StringName]) -> FamilyTheme:
	var theme := FamilyTheme.new()
	theme.id = id
	theme.theme_word = word
	theme.body_shapes = bodies
	theme.heads = heads
	theme.eye_styles = eyes
	theme.antennas = antennas
	theme.patterns = patterns
	theme.melee_arms = arms
	theme.palettes = palettes
	theme.accessories = accessories
	return theme


func _save(resource: Resource, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := ResourceSaver.save(resource, path)
	print("%s: %s" % [path, error_string(err)])
