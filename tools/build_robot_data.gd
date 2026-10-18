extends SceneTree
## Writes the robot data in res://data/robots from the tables in res://data/source/robots (format:
## data/source/README.md): the archetypes (GDD 9.3), palettes, themes and traits (GDD 10), and the
## gene library's theme and trait lists. Files whose row is gone are deleted. Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_robot_data.gd
## Edit the tables, not the .tres files: test_content_tables.gd fails when the two disagree. The gene
## library's other settings (farm color, novelty rules) aren't in a table; edit those in the inspector.
##
## Palettes, themes, traits and the library keep the ext_resource ids of the files they replace, so
## unchanged rows rewrite identical files. Archetypes are written line by line instead: every filled
## cell becomes a line, so their .tres files spell out each stat rather than relying on the script's
## defaults (which are the Nibbler's).

const ContentTables := preload("res://tools/content_tables.gd")


func _initialize() -> void:
	var tables := ContentTables.new()
	var archetypes: Array[RobotArchetype] = []
	var archetype_properties: Array[PackedStringArray] = []
	for row in tables.archetype_rows():
		var archetype := RobotArchetype.new()
		archetype_properties.append(tables.fill(archetype, row))
		archetypes.append(archetype)
	var palettes := tables.palettes()
	tables.themes(palettes) # Only to check the rows; the saved themes are built below.
	var traits := tables.traits()
	if not tables.errors.is_empty():
		for message in tables.errors:
			printerr(message)
		printerr("Nothing written: fix the tables in %s first." % ContentTables.SOURCE_DIR.path_join("robots"))
		quit(1)
		return

	for kind in ["palettes", "themes", "traits", "archetypes"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ContentTables.ROBOT_DIR.path_join(kind)))
	# Loading the old files tells every resource they reference its ext_resource id for that file.
	for kind in ["palettes", "themes", "traits"]:
		var dir := ContentTables.ROBOT_DIR.path_join(kind)
		for file_name in DirAccess.get_files_at(dir):
			if file_name.get_extension() == "tres":
				ResourceLoader.load(dir.path_join(file_name))
	var library := GeneLibrary.new()
	if ResourceLoader.exists(ContentTables.GENE_LIBRARY_PATH):
		library = ResourceLoader.load(ContentTables.GENE_LIBRARY_PATH) as GeneLibrary

	# Reload what we save, so the themes and the library reference the files instead of embedding copies.
	var saved_palettes: Dictionary[StringName, RobotPalette] = {}
	for id in palettes:
		saved_palettes[id] = _save(palettes[id], ContentTables.robot_path("palettes", id)) as RobotPalette
	var saved_themes: Array[FamilyTheme] = []
	for theme in tables.themes(saved_palettes):
		saved_themes.append(_save(theme, ContentTables.robot_path("themes", theme.id)) as FamilyTheme)
	var saved_traits: Array[RobotTrait] = []
	for robot_trait in traits:
		saved_traits.append(_save(robot_trait, ContentTables.robot_path("traits", robot_trait.id)) as RobotTrait)
	library.themes = saved_themes
	library.traits = saved_traits
	_save(library, ContentTables.GENE_LIBRARY_PATH)

	var archetype_files := PackedStringArray()
	for i in archetypes.size():
		var path := ContentTables.robot_path("archetypes", archetypes[i].id)
		_write_line_by_line(archetypes[i], archetype_properties[i], path)
		archetype_files.append(path.get_file())

	_remove_stale("palettes", saved_palettes.keys())
	_remove_stale("themes", saved_themes.map(func(theme: FamilyTheme) -> StringName: return theme.id))
	_remove_stale("traits", saved_traits.map(func(robot_trait: RobotTrait) -> StringName: return robot_trait.id))
	var removed := ContentTables.remove_stale(ContentTables.ROBOT_DIR.path_join("archetypes"), archetype_files)
	if not removed.is_empty():
		print("Removed archetypes/%s" % ", archetypes/".join(removed))
	print("Wrote %d archetypes, %d palettes, %d themes, %d traits and the gene library to %s" % [archetype_files.size(),
			saved_palettes.size(), saved_themes.size(), saved_traits.size(), ContentTables.ROBOT_DIR])
	quit(0)


func _save(resource: Resource, path: String) -> Resource:
	var err := ResourceSaver.save(resource, path)
	if err != OK:
		printerr("Could not save %s: %s" % [path, error_string(err)])
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)


func _remove_stale(kind: String, ids: Array) -> void:
	var keep := PackedStringArray()
	for id: StringName in ids:
		keep.append("%s.tres" % id)
	var removed := ContentTables.remove_stale(ContentTables.ROBOT_DIR.path_join(kind), keep)
	if not removed.is_empty():
		print("Removed %s/%s" % [kind, (", %s/" % kind).join(removed)])


## Writes `resource` as a text resource with one line per property in `properties`, even when the value
## equals the script default (ResourceSaver would leave those out).
func _write_line_by_line(resource: Resource, properties: PackedStringArray, path: String) -> void:
	var script := resource.get_script() as Script
	var ext_resources := PackedStringArray(['[ext_resource type="Script" path="%s" id="1_arch"]' % script.resource_path])
	var lines := PackedStringArray(['script = ExtResource("1_arch")'])
	for property in properties:
		var value: Variant = resource.get(property)
		if value is Resource:
			var id := "%d_%s" % [ext_resources.size() + 1, property]
			ext_resources.append('[ext_resource type="%s" path="%s" id="%s"]' % [(value as Resource).get_class(),
					(value as Resource).resource_path, id])
			lines.append('%s = ExtResource("%s")' % [property, id])
		else:
			lines.append("%s = %s" % [property, var_to_str(value)])
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string('[gd_resource type="Resource" script_class="%s" format=3]\n\n%s\n\n[resource]\n%s\n' % [
			script.get_global_name(), "\n".join(ext_resources), "\n".join(lines)])
