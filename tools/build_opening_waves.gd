extends SceneTree
## Writes the authored opening (OpeningWave, one .tres per wave in res://data/opening) from the tables in
## res://data/source/opening (format: data/source/README.md). Files whose wave is gone are deleted. Run from
## the project folder:
##   <godot> --headless --path . --script res://tools/build_opening_waves.gd
## Edit the tables, not the .tres files: test_content_tables.gd fails when the two disagree. Each group
## keeps the sub-resource id "group_<n>", so regenerating unchanged tables rewrites identical files.

const ContentTables := preload("res://tools/content_tables.gd")


func _initialize() -> void:
	var tables := ContentTables.new()
	var waves := tables.opening_waves()
	if not tables.errors.is_empty():
		for message in tables.errors:
			printerr(message)
		printerr("Nothing written: fix the tables in %s first." % ContentTables.SOURCE_DIR.path_join("opening"))
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ContentTables.OPENING_DIR))
	var written := PackedStringArray()
	for opening in waves:
		var path := ContentTables.opening_path(opening.wave)
		var err := ResourceSaver.save(opening, path)
		if err != OK:
			printerr("Could not save %s: %s" % [path, error_string(err)])
			quit(1)
			return
		written.append(path.get_file())
	var removed := ContentTables.remove_stale(ContentTables.OPENING_DIR, written)
	print("Wrote %d opening waves to %s%s" % [written.size(), ContentTables.OPENING_DIR,
			"; removed %s" % ", ".join(removed) if not removed.is_empty() else ""])
	quit(0)
