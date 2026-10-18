extends SceneTree
## Writes the pegboard (GDD 13) from the tables in res://data/source/upgrades (format:
## data/source/README.md): one UpgradeNode .tres per row in res://data/upgrades. Files whose row is gone
## are deleted. Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_upgrade_catalog.gd
## Edit the tables, not the .tres files: test_content_tables.gd fails when the two disagree.
##
## Each node keeps the sub-resource and ext_resource ids of the file it replaces, so an unchanged row
## rewrites an identical file and an edited row only changes its own lines.

const ContentTables := preload("res://tools/content_tables.gd")


func _initialize() -> void:
	var tables := ContentTables.new()
	var nodes := tables.upgrade_nodes()
	if not tables.errors.is_empty():
		for message in tables.errors:
			printerr(message)
		printerr("Nothing written: fix the tables in %s first." % ContentTables.SOURCE_DIR.path_join(ContentTables.UPGRADES))
		quit(1)
		return

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ContentTables.UPGRADE_DIR))
	var written := PackedStringArray()
	for node in nodes:
		var path := ContentTables.upgrade_path(node.id)
		if ResourceLoader.exists(path):
			# Loading the old file also tells the scripts their ext_resource ids for this path.
			var old := ResourceLoader.load(path) as UpgradeNode
			if old != null:
				_keep_ids(node, old)
		var err := ResourceSaver.save(node, path)
		if err != OK:
			printerr("Could not save %s: %s" % [path, error_string(err)])
			quit(1)
			return
		written.append(path.get_file())
	var removed := ContentTables.remove_stale(ContentTables.UPGRADE_DIR, written)
	print("Wrote %d upgrade nodes to %s%s" % [written.size(), ContentTables.UPGRADE_DIR,
			"; removed %s" % ", ".join(removed) if not removed.is_empty() else ""])
	quit(0)


## Gives the node's sub-resources the ids they had in `old`: the cost curve, and effects and
## prerequisites matched by stat and node id.
func _keep_ids(node: UpgradeNode, old: UpgradeNode) -> void:
	if node.cost_curve != null and old.cost_curve != null:
		node.cost_curve.resource_scene_unique_id = old.cost_curve.resource_scene_unique_id
	_match_ids(node.effects, old.effects, &"stat")
	_match_ids(node.prerequisites, old.prerequisites, &"node_id")


func _match_ids(fresh: Array, previous: Array, key: StringName) -> void:
	var unused := previous.duplicate()
	for resource: Resource in fresh:
		for candidate: Resource in unused:
			if candidate != null and candidate.get(key) == resource.get(key):
				resource.resource_scene_unique_id = candidate.resource_scene_unique_id
				unused.erase(candidate)
				break
