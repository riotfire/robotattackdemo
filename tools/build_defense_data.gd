extends SceneTree
## Writes the buildable defenses (DefenseDefinition, one .tres per row in res://data/defenses) from the table
## in res://data/source/defenses/items (format: data/source/README.md). Files whose row is gone are deleted.
## Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_defense_data.gd
## Edit the table, not the .tres files: test_content_tables.gd fails when the two disagree.

const ContentTables := preload("res://tools/content_tables.gd")


func _initialize() -> void:
	var tables := ContentTables.new()
	var definitions := tables.defenses()
	if not tables.errors.is_empty():
		for message in tables.errors:
			printerr(message)
		printerr("Nothing written: fix the table in %s first." % ContentTables.SOURCE_DIR.path_join(ContentTables.DEFENSES))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ContentTables.DEFENSE_DIR))
	var written := PackedStringArray()
	for definition in definitions:
		var path := ContentTables.defense_path(definition.id)
		var err := ResourceSaver.save(definition, path)
		if err != OK:
			printerr("Could not save %s: %s" % [path, error_string(err)])
			quit(1)
			return
		written.append(path.get_file())
	var removed := ContentTables.remove_stale(ContentTables.DEFENSE_DIR, written)
	print("Wrote %d defenses to %s%s" % [written.size(), ContentTables.DEFENSE_DIR,
			"; removed %s" % ", ".join(removed) if not removed.is_empty() else ""])
	quit(0)
