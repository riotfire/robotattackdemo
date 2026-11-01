extends Node3D
## Pose QA for Mabel (assets/Mabel Annimation.glb). Puts the real farmer scene in a small sandbox (floor, ledge,
## ladder block, zipline) and drives it through every state that picks a clip, with real input, so the clip choice,
## cross-fades and the weapon-in-hand are exactly what the game plays. Writes:
##   <out>/<scenario>.png      contact sheet of that scenario (QA camera, tiles captioned with state / clip / time)
##   <out>/game_*.png          full-frame shots through the farmer's own over-the-shoulder camera
##   <out>/ticks.csv           one row per 24 fps tick: state, clip, speed, biggest bone jump, foot clearance
##   <out>/report.txt          clip stride and climb-rate measurements, plus the largest pose jumps
## godot --path . --fixed-fps 60 --resolution 1600x900 res://tests/tools/pose_gallery.tscn -- --out=/tmp/pose-gallery
## Add --only=jump,ladder to run some scenarios. Escape exits.

const FARMER_SCENE: PackedScene = preload("res://scenes/player/farmer.tscn")
const MABEL_SCRIPT: Script = preload("res://scripts/player/mabel_model.gd")
const MABEL_GLB: String = "res://assets/Mabel Annimation.glb"
const SCENARIOS: Array[String] = ["clips", "idle", "walk_run", "aim_strafe", "fire", "reload", "melee", "carry", "jump", "ledge", "jetpack",
		"ladder", "zipline", "rope", "hurt", "game_cam", "death"]
const TILE_SIZE := Vector2i(300, 450)
const COLUMNS: int = 8
## Camera offsets in the farmer's own frame (x right, y up, z backward), so a front view has negative z.
const VIEW_FRONT := Vector3(3.0, 1.2, -3.4)
const VIEW_SIDE := Vector3(4.6, 1.1, 0.0)
const VIEW_BACK := Vector3(2.4, 1.5, 3.8)
const ACTIONS: Array[StringName] = [&"move_forward", &"move_back", &"move_left", &"move_right", &"jump", &"aim",
		&"fire", &"melee", &"interact", &"reload"]
const LEDGE := Vector3(-12.0, 0.0, 0.0)
const LADDER_FOOT := Vector3(8.0, 0.0, -3.6)
const ZIP_START := Vector3(-24.0, 6.0, 10.0)
const ZIP_END := Vector3(-24.0, 3.6, -20.0)

var _out: String = "/tmp/pose-gallery"
var _only: PackedStringArray = []
var _farmer: Farmer
var _mabel: MabelModel
## What the QA camera follows: the farmer, or a free-standing Mabel while sampling raw clips.
var _follow: Node3D
var _camera: Camera3D
var _label: Label
var _view: Vector3 = VIEW_FRONT
var _view_yaw: float = 0.0
var _scenario: String = ""
var _clock: float = 0.0
var _tiles: Array[Image] = []
var _rows: PackedStringArray = ["scenario,tick,t,state,clip,speed,y_vel,max_bone_deg,max_bone,foot_clearance_cm"]
var _prev_rotations: Array[Quaternion] = []
var _jumps: Array = []
var _prev_clip: StringName = &""
var _bone_names: PackedStringArray = []
var _climb_report: String = ""
var _extra_report: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=").split(",")
	DirAccess.make_dir_recursive_absolute(_out)
	_climb_report = _measure_raw_climb()
	_build_world()
	_farmer = FARMER_SCENE.instantiate()
	add_child(_farmer)
	_farmer.global_position = Vector3(0.0, 0.1, 0.0)
	_mabel = _farmer.get_node("Model/Pose/Mabel")
	for i in _mabel._skeleton.get_bone_count():
		_bone_names.append(_mabel._skeleton.get_bone_name(i))
	GameState.god_mode = true
	for node in [&"attack.wrench", &"attack.pistol", &"attack.shotgun", &"attack.rifle", &"attack.maul",
			&"attack.scythe"]:
		StatService.grant(node)
	StopMotionClock.tick_24.connect(_on_tick)
	_camera = Camera3D.new()
	_camera.fov = 38.0
	add_child(_camera)
	_camera.make_current()
	_run.call_deferred()


func _process(delta: float) -> void:
	_clock += delta
	if _farmer == null or not is_instance_valid(_farmer):
		return
	var target := _farmer.get_global_transform_interpolated().origin if _follow == null else _follow.global_position
	_camera.global_position = target + Basis(Vector3.UP, _view_yaw) * _view
	_camera.look_at(target + Vector3.UP * 0.9)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()


# --- World ----------------------------------------------------------------------------------------

func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.62, 0.76, 0.9)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 1.0)
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	add_child(sun)
	var checker := Image.create_empty(64, 64, false, Image.FORMAT_RGB8)
	for x in 64:
		for y in 64:
			var dark := (x / 32 + y / 32) % 2 == 0
			checker.set_pixel(x, y, Color(0.34, 0.45, 0.2) if dark else Color(0.42, 0.54, 0.26))
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_texture = ImageTexture.create_from_image(checker)
	floor_material.uv1_scale = Vector3(40.0, 40.0, 1.0)
	floor_material.roughness = 1.0
	_block(Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0), floor_material)
	var block_material := StandardMaterial3D.new()
	block_material.albedo_color = Color(0.72, 0.6, 0.45)
	block_material.roughness = 1.0
	_block(LEDGE + Vector3(0.0, 1.5, 0.0), Vector3(6.0, 3.0, 6.0), block_material)
	_block(Vector3(8.0, 2.0, -7.0), Vector3(8.0, 4.0, 6.0), block_material)
	_build_ladder()
	_build_zipline()


func _block(center: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	mesh.mesh = box_mesh
	mesh.material_override = material
	body.add_child(mesh)
	body.position = center
	add_child(body)


func _build_ladder() -> void:
	var ladder := Climbable.new()
	ladder.climb_height = 4.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 4.6, 1.6)
	shape.shape = box
	shape.position = Vector3(0.0, 2.3, 0.4)
	ladder.add_child(shape)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.3, 0.16)
	for side in [-0.35, 0.35]:
		_add_box(ladder, Vector3(side, 2.0, 0.0), Vector3(0.06, 4.0, 0.06), wood)
	for rung in 16:
		_add_box(ladder, Vector3(0.0, 0.25 + rung * 0.25, 0.0), Vector3(0.7, 0.04, 0.04), wood)
	ladder.position = LADDER_FOOT
	add_child(ladder)


func _build_zipline() -> void:
	var line := Zipline.new()
	var end := Marker3D.new()
	end.name = "End"
	line.add_child(end)
	line.position = ZIP_START
	add_child(line)
	end.global_position = ZIP_END
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.15, 0.15, 0.15)
	var length := ZIP_START.distance_to(ZIP_END)
	var mid := Node3D.new()
	add_child(mid)
	mid.position = (ZIP_START + ZIP_END) * 0.5
	mid.look_at_from_position(mid.position, ZIP_END)
	_add_box(mid, Vector3.ZERO, Vector3(0.05, 0.05, length), cable)
	for anchor in [ZIP_START, ZIP_END]:
		var pole_material := StandardMaterial3D.new()
		pole_material.albedo_color = Color(0.5, 0.4, 0.3)
		_block(Vector3(anchor.x, anchor.y * 0.5, anchor.z - 0.3), Vector3(0.3, anchor.y, 0.3), pole_material)


func _add_box(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)


# --- Run ------------------------------------------------------------------------------------------

func _run() -> void:
	_build_overlay()
	await _frames(30)
	var report: PackedStringArray = []
	report.append_array(_measure_clips())
	for name in SCENARIOS:
		if not _only.is_empty() and name not in _only:
			continue
		_scenario = name
		_tiles.clear()
		_release_all()
		await call("_sc_" + name)
		_release_all()
		_save_sheet(name)
	report.append_array(_extra_report)
	report.append_array(_largest_jumps())
	FileAccess.open(_out.path_join("ticks.csv"), FileAccess.WRITE).store_string("\n".join(_rows) + "\n")
	FileAccess.open(_out.path_join("report.txt"), FileAccess.WRITE).store_string("\n".join(report) + "\n")
	print("\n".join(report))
	get_tree().quit()


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(508.0, 8.0)
	_label.size = Vector2(584.0, 80.0)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 8)
	layer.add_child(_label)


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _press(action: StringName, strength: float = 1.0) -> void:
	Input.action_press(action, strength)


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _frames(3)
	Input.action_release(action)


func _release_all() -> void:
	for action in ACTIONS:
		Input.action_release(action)


## Puts the farmer somewhere on the floor facing `yaw`, holding weapon `slot`, and lets her settle into idle.
func _prep(at: Vector3, yaw: float, slot: int, view: Vector3 = VIEW_FRONT) -> void:
	_release_all()
	_farmer.teleport_to(at)
	_farmer.camera_rig.yaw = yaw
	_farmer.facing_yaw = yaw
	_farmer.model.rotation.y = yaw
	_farmer.weapons.equip_slot(slot)
	_view = view
	_view_yaw = yaw
	await _frames(40)


func _caption() -> String:
	var state: String = Farmer.State.keys()[_farmer.state]
	return "%s  %s\n%s  %.2f" % [_scenario, state, _mabel._current, _mabel._player.current_animation_position]


## Captures the QA camera, cropped to the middle of the frame where the farmer is, as one tile of the sheet.
func _snap(extra: String = "") -> void:
	_label.text = _caption() + ("\n" + extra if extra != "" else "")
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var crop := Rect2i(int(shot.get_width() * 0.3125), 0, int(shot.get_width() * 0.375), shot.get_height())
	var tile := shot.get_region(crop)
	tile.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	tile.convert(Image.FORMAT_RGBA8)
	_tiles.append(tile)


## Like _snap, but keeps the caption the caller already set.
func _snap_raw() -> void:
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	var crop := Rect2i(int(shot.get_width() * 0.3125), 0, int(shot.get_width() * 0.375), shot.get_height())
	var tile := shot.get_region(crop)
	tile.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_BILINEAR)
	tile.convert(Image.FORMAT_RGBA8)
	_tiles.append(tile)


## Pads the current sheet row so the next tile starts a new one.
func _new_row() -> void:
	while _tiles.size() % COLUMNS != 0:
		_tiles.append(null)


## `count` tiles, `spacing` physics frames apart.
func _burst(count: int, spacing: int, extra: String = "") -> void:
	for i in count:
		await _snap(extra)
		await _frames(spacing)


func _save_sheet(sheet_name: String) -> void:
	_new_row()
	if _tiles.is_empty():
		return
	var rows := _tiles.size() / COLUMNS
	var sheet := Image.create_empty(COLUMNS * TILE_SIZE.x, rows * TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.12, 0.12, 0.14))
	for i in _tiles.size():
		if _tiles[i] != null:
			sheet.blit_rect(_tiles[i], Rect2i(Vector2i.ZERO, TILE_SIZE),
					Vector2i((i % COLUMNS) * TILE_SIZE.x, (i / COLUMNS) * TILE_SIZE.y))
	sheet.save_png(_out.path_join(sheet_name + ".png"))


## One full-frame shot through the farmer's own camera: what the player actually sees.
func _game_shot(shot_name: String) -> void:
	_farmer.camera_rig.camera.make_current()
	_label.text = ""
	await _frames(2)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("game_%s.png" % shot_name))
	_camera.make_current()


# --- Per-tick logging -----------------------------------------------------------------------------

func _on_tick(_frame: int) -> void:
	if _mabel == null or not _mabel.visible:
		return
	var skeleton: Skeleton3D = _mabel._skeleton
	var rotations: Array[Quaternion] = []
	var worst := 0.0
	var worst_bone := ""
	for i in skeleton.get_bone_count():
		rotations.append(skeleton.get_bone_pose_rotation(i))
		if _prev_rotations.size() > i:
			var degrees := rad_to_deg(rotations[i].angle_to(_prev_rotations[i]))
			if degrees > worst:
				worst = degrees
				worst_bone = _bone_names[i]
	var changed: bool = _mabel._current != _prev_clip
	_prev_rotations = rotations
	var toe_l := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(MabelModel.FOOT_L))).origin
	var toe_r := (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(MabelModel.FOOT_R))).origin
	var clearance := (minf(toe_l.y, toe_r.y) - _farmer.global_position.y) * 100.0
	var state: String = Farmer.State.keys()[_farmer.state]
	var speed := Vector2(_farmer.velocity.x, _farmer.velocity.z).length()
	_rows.append("%s,%d,%.3f,%s,%s,%.2f,%.2f,%.1f,%s,%.1f" % [_scenario, _frame, _clock, state, _mabel._current, speed,
			_farmer.velocity.y, worst, worst_bone, clearance])
	if _scenario != "" and (worst > 20.0 or changed):
		_jumps.append([worst, _scenario, _frame, state, _prev_clip, _mabel._current, worst_bone, changed])
	_prev_clip = _mabel._current


func _largest_jumps() -> PackedStringArray:
	var lines: PackedStringArray = ["", "Largest single-tick bone rotations (degrees), * marks a clip change"]
	_jumps.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	for entry in _jumps.slice(0, 40):
		lines.append("  %5.1f %s  %-10s tick %d  %-9s %s -> %s  (%s)" % [entry[0], "*" if entry[7] else " ", entry[1],
				entry[2], entry[3], entry[4], entry[5], entry[6]])
	return lines


# --- Clip measurements ----------------------------------------------------------------------------

## Samples the locomotion clips on a throwaway copy of the model. A planted foot slides back along the body at the
## speed the clip covers, so that speed is the one at which the feet do not skate; MabelModel.WALK_SPEED and RUN_SPEED
## come from here. The shooting walks barely lift their feet, so for them the foot's back-sweep per second is compared
## with the walk's instead. The ladder clip's climb is measured from its raw hip travel.
func _measure_clips() -> PackedStringArray:
	var lines: PackedStringArray = ["Clip measurements (model scale and fit applied)"]
	var scene: Node3D = (load(MABEL_GLB) as PackedScene).instantiate()
	scene.set_script(MABEL_SCRIPT)
	add_child(scene)
	scene.position = Vector3(30.0, 0.0, 30.0)
	var model := scene as MabelModel
	var skeleton: Skeleton3D = model._skeleton
	var player: AnimationPlayer = model._player
	var fit: float = scene.scale.x
	lines.append("  fit scale %.4f, standing height %.2f m" % [fit, MabelModel.HEIGHT])
	var walk_sweep := 0.0
	for clip in ["Walking", "Running", "Run_and_Shoot", "Walk_Forward_While_Shooting_inplace"]:
		var length := player.get_animation(clip).length
		player.play(clip)
		player.pause()
		var samples := int(round(length * 24.0))
		var planted: Array[float] = []
		var sweeps: Array[float] = []
		for foot_name in [MabelModel.FOOT_L, MabelModel.FOOT_R]:
			var foot := skeleton.find_bone(foot_name)
			var zs: Array[float] = []
			var ys: Array[float] = []
			for i in samples + 1:
				player.seek(length * float(i) / samples, true)
				skeleton.force_update_all_bone_transforms()
				var p := (scene.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(foot))).origin * fit
				zs.append(p.z)
				ys.append(p.y)
			var low: float = ys.min()
			var total := 0.0
			var count := 0
			var back := 0.0
			var forth := 0.0
			for i in samples:
				var dz := zs[i + 1] - zs[i]
				back += maxf(0.0, -dz)
				forth += maxf(0.0, dz)
				if ys[i] < low + 0.03 and ys[i + 1] < low + 0.03:
					total += dz / (length / samples)
					count += 1
			sweeps.append(maxf(back, forth) / length)
			if count > 0:
				planted.append(absf(total / count))
		var sweep := (sweeps[0] + sweeps[1]) * 0.5
		if clip == "Walking":
			walk_sweep = sweep
		lines.append("  %-30s %.3f s  planted-foot speed %.2f m/s, back-sweep %.2f m/s, implied speed %.2f m/s" % [clip,
				length, (planted[0] + planted[1]) * 0.5 if planted.size() == 2 else 0.0, sweep,
				MabelModel.WALK_SPEED * sweep / maxf(walk_sweep, 0.001)])
	lines.append(_climb_report)
	lines.append_array(_sample_rope(scene as MabelModel, "Swing_on_Rope_to_Ground", 0.0, 1.0))
	lines.append_array(_sample_rope(scene as MabelModel, "Hop_with_Arms_Raised", 0.5, 1.8))
	scene.queue_free()
	return lines


## Head and hands through the rope clip's first second, in metres relative to the feet, to pick the grip frame whose
## hands are overhead and together.
func _sample_rope(model: MabelModel, clip: String, from: float, to: float) -> PackedStringArray:
	var lines: PackedStringArray = ["  %s, head top / left hand / right hand / toe (x right, y up, z forward):" % clip]
	var skeleton: Skeleton3D = model._skeleton
	var player: AnimationPlayer = model._player
	var fit: float = model.scale.x
	player.play(clip)
	player.pause()
	for step in int(round((to - from) / 0.1)) + 1:
		var t := from + step * 0.1
		player.seek(t, true)
		skeleton.force_update_all_bone_transforms()
		var parts: PackedStringArray = []
		for bone_name in [MabelModel.HEAD_TOP, "mixamorig_LeftHand", MabelModel.HAND, MabelModel.FOOT_L]:
			var p := (model.global_transform.affine_inverse() * (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)))).origin * fit
			parts.append("(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z])
		lines.append("    t=%.1f  %s" % [t, "  ".join(parts)])
	return lines


## The ladder clip's climb per loop, read from the hips track before MabelModel flattens it (the glb's animations are
## shared resources, so this has to run before the first model is built).
func _measure_raw_climb() -> String:
	var raw: Node3D = (load(MABEL_GLB) as PackedScene).instantiate()
	add_child(raw)
	var skeleton: Skeleton3D = raw.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = raw.find_children("*", "AnimationPlayer", true, false)[0]
	var skeleton_scale := skeleton.global_transform.basis.get_scale().y
	var lines: PackedStringArray = []
	for clip_name in ["Fast_Ladder_Climb", "Ladder_Climb"]:
		var climb := player.get_animation(clip_name)
		for t in climb.get_track_count():
			if climb.track_get_type(t) == Animation.TYPE_POSITION_3D and str(climb.track_get_path(t)).ends_with(MabelModel.HIPS):
				var rise: float = (climb.track_get_key_value(t, climb.track_get_key_count(t) - 1) as Vector3).y \
						- (climb.track_get_key_value(t, 0) as Vector3).y
				# Metres at the model's fit scale of 1.2916 (see the stride lines), per second at 1x.
				var metres_per_second := absf(rise) * skeleton_scale * 1.2916 / climb.length
				lines.append("  %-30s %.3f s  hips rise %.2f units per loop = %.2f m/s at 1x; a 4 m/s ladder needs rate %.2f"
						% [clip_name, climb.length, rise, metres_per_second, 4.0 / maxf(metres_per_second, 0.001)])
	raw.queue_free()
	return "\n".join(lines)


# --- Scenarios ------------------------------------------------------------------------------------

## Every raw clip at eight evenly spaced times (first and last included), on a Mabel the farmer does not drive.
func _sc_clips() -> void:
	var stage := Node3D.new()
	stage.position = Vector3(30.0, 0.0, 30.0)
	add_child(stage)
	var scene: Node3D = (load(MABEL_GLB) as PackedScene).instantiate()
	scene.set_script(MABEL_SCRIPT)
	scene.rotation.y = PI
	stage.add_child(scene)
	var player: AnimationPlayer = (scene as MabelModel)._player
	_follow = stage
	_view = VIEW_FRONT
	_view_yaw = 0.0
	var names := Array(player.get_animation_list())
	names.sort()
	var sheet := 1
	for clip: String in names:
		var length := player.get_animation(clip).length
		for i in COLUMNS:
			player.play(clip)
			player.pause()
			player.seek(length * float(i) / (COLUMNS - 1), true)
			await _frames(2)
			_label.text = "%s\n%.2f / %.2f s" % [clip, player.current_animation_position, length]
			await _snap_raw()
		if _tiles.size() >= COLUMNS * 5:
			_save_sheet("clips_%d" % sheet)
			_tiles.clear()
			sheet += 1
	_follow = null
	stage.queue_free()


func _sc_idle() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2)
	for view in [VIEW_FRONT, VIEW_SIDE, VIEW_BACK]:
		_view = view
		await _frames(4)
		await _snap("pistol")
	_farmer.weapons.equip_slot(1)
	for view in [VIEW_FRONT, VIEW_SIDE, VIEW_BACK]:
		_view = view
		await _frames(4)
		await _snap("wrench")
	_farmer.weapons.equip_slot(7)
	_view = VIEW_FRONT
	await _frames(4)
	await _snap("scythe")
	_farmer.weapons.equip_slot(4)
	await _frames(4)
	await _snap("rifle")
	_new_row()
	_farmer.weapons.equip_slot(1)
	_view = VIEW_FRONT
	await _burst(8, 72, "idle over 10 s")


func _sc_walk_run() -> void:
	for strength in [0.3, 0.5, 0.65, 1.0]:
		await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
		_press(&"move_forward", strength)
		await _frames(30)
		await _burst(8, 5, "stick %.2f" % strength)
		_new_row()
		_release_all()
		await _burst(8, 3, "release")
		_new_row()


func _sc_aim_strafe() -> void:
	var dirs := {"forward": [&"move_forward"], "back": [&"move_back"], "left": [&"move_left"],
			"right": [&"move_right"], "fwd+right": [&"move_forward", &"move_right"],
			"back+left": [&"move_back", &"move_left"]}
	for label in dirs:
		await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_FRONT)
		_press(&"aim")
		for action in dirs[label]:
			_press(action)
		await _frames(40)
		await _burst(6, 5, "aim " + label)
		_new_row()


func _sc_fire() -> void:
	for slot in [2, 3, 4]:
		await _prep(Vector3(0.0, 0.1, 0.0), 0.0, slot, VIEW_FRONT)
		await _tap(&"fire")
		await _burst(8, 2, "slot %d tap, no aim" % slot)
		_new_row()
		_press(&"aim")
		await _frames(20)
		await _tap(&"fire")
		await _burst(8, 2, "slot %d tap, aiming" % slot)
		_new_row()
		_release_all()
		await _burst(8, 3, "release")
		_new_row()
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _frames(30)
	await _tap(&"fire")
	await _burst(8, 3, "run + fire")
	_new_row()


func _sc_reload() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_FRONT)
	await _tap(&"fire")
	await _frames(40)
	await _tap(&"reload")
	await _burst(16, 4, "reload, standing")
	_new_row()
	await _burst(8, 4, "after")
	_new_row()
	await _tap(&"fire")
	await _frames(30)
	_press(&"move_forward")
	await _frames(10)
	await _tap(&"reload")
	await _burst(8, 4, "reload, running")
	_new_row()


func _sc_melee() -> void:
	for slot in [1, 6, 7]:
		await _prep(Vector3(0.0, 0.1, 0.0), 0.0, slot, VIEW_SIDE)
		await _tap(&"fire")
		await _burst(8, 2, "slot %d swing" % slot)
		_new_row()
		await _frames(30)
		await _burst(4, 3, "after")
		_new_row()
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _frames(30)
	await _tap(&"melee")
	await _burst(16, 2, "quick bonk, running")
	_new_row()


## Every modelled weapon carried, run with and aimed, from the front, side and back.
func _sc_carry() -> void:
	for slot in [1, 2, 3, 7]:
		await _prep(Vector3(0.0, 0.1, 0.0), 0.0, slot, VIEW_FRONT)
		for view in [VIEW_FRONT, VIEW_SIDE, VIEW_BACK]:
			_view = view
			await _frames(4)
			await _snap("slot %d carried" % slot)
		_press(&"aim")
		await _frames(20)
		for view in [VIEW_FRONT, VIEW_SIDE]:
			_view = view
			await _frames(4)
			await _snap("slot %d aimed" % slot)
		_release_all()
		_view = VIEW_SIDE
		_press(&"move_forward")
		await _frames(30)
		await _burst(3, 6, "slot %d running" % slot)
		_new_row()


func _sc_jump() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	await _tap(&"jump")
	await _burst(16, 4, "standing jump")
	_new_row()
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _frames(30)
	await _tap(&"jump")
	await _burst(16, 4, "running jump")
	_new_row()
	_release_all()
	await _burst(8, 3, "after landing")
	_new_row()


func _sc_ledge() -> void:
	await _prep(LEDGE + Vector3(0.0, 3.1, 1.5), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _frames(40)
	await _burst(16, 4, "walks off ledge")
	_new_row()
	_release_all()
	await _burst(8, 3, "after landing")
	_new_row()


func _sc_jetpack() -> void:
	GameState.jetpack_unlocked = true
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	_press(&"jump")
	await _burst(6, 5, "jetpack hold")
	_view = VIEW_BACK
	await _burst(6, 5, "jetpack hold, back")
	_view = VIEW_SIDE
	_new_row()
	_release_all()
	await _burst(12, 5, "falls")
	_new_row()
	await _until(func() -> bool: return _farmer.state == Farmer.State.GROUNDED)
	await _burst(12, 3, "landed")
	_new_row()


func _until(condition: Callable, limit: int = 240) -> void:
	for i in limit:
		if condition.call():
			return
		await _frames(1)


func _sc_ladder() -> void:
	await _prep(LADDER_FOOT + Vector3(0.0, 0.1, 1.6), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _burst(3, 3, "walks to the ladder")
	await _until(func() -> bool: return _farmer.state == Farmer.State.CLIMBING)
	await _burst(8, 5, "climbs up")
	_new_row()
	_release_all()
	await _burst(4, 4, "hangs still")
	_press(&"move_back")
	await _burst(8, 5, "climbs down")
	_new_row()
	_release_all()
	await _tap(&"jump")
	await _burst(8, 4, "jumps off")
	await _until(func() -> bool: return _farmer.state == Farmer.State.GROUNDED)
	await _burst(8, 3, "lands")
	_new_row()
	# And again all the way up, over the top and onto the block.
	await _prep(LADDER_FOOT + Vector3(0.0, 0.1, 1.6), 0.0, 2, VIEW_SIDE)
	_press(&"move_forward")
	await _until(func() -> bool: return _farmer.state == Farmer.State.MANTLING, 600)
	await _burst(8, 3, "mantles over the top")
	_release_all()
	await _until(func() -> bool: return _farmer.state == Farmer.State.GROUNDED)
	await _burst(8, 3, "on top")
	_new_row()


## Where the head, hands, feet and weapon are relative to the farmer's feet (x right, y up, z back, in the model's
## frame), so the rope grip can be checked against the cable height.
func _log_bones(label: String) -> void:
	var skeleton: Skeleton3D = _mabel._skeleton
	var parts: PackedStringArray = []
	for bone_name in [MabelModel.HEAD_TOP, "mixamorig_LeftHand", MabelModel.HAND, MabelModel.HIPS, MabelModel.FOOT_L]:
		var bone := skeleton.find_bone(bone_name)
		var at := _farmer.model.to_local((skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin)
		parts.append("%s (%.2f, %.2f, %.2f)" % [bone_name.trim_prefix("mixamorig_"), at.x, at.y, at.z])
	var weapon_at := _farmer.model.to_local(_farmer.weapons.global_position)
	parts.append("weapon (%.2f, %.2f, %.2f)" % [weapon_at.x, weapon_at.y, weapon_at.z])
	_extra_report.append("  %s: %s" % [label, "; ".join(parts)])


func _sc_zipline() -> void:
	var line: Zipline = get_tree().get_nodes_in_group(&"interactables")[0]
	# Taking hold: yanked into the swing, then hanging.
	await _prep(Vector3(-24.0, 0.1, 14.0), 0.0, 2, VIEW_SIDE)
	_farmer.movement.start_zipline(line)
	await _burst(8, 3, "takes hold")
	await _frames(20)
	_log_bones("rope grip, cable %.2f m above her feet" % line.hang_height)
	await _burst(8, 9, "zipline ride")
	_new_row()
	# Letting go high on the line, in the middle, and low on it, then the line running out.
	for ride_frames: int in [20, 80, 120, 138]:
		await _prep(Vector3(-24.0, 0.1, 14.0), 0.0, 2, VIEW_SIDE)
		_farmer.movement.start_zipline(line)
		await _frames(ride_frames)
		var jump_off := ride_frames < 138
		if jump_off:
			await _tap(&"jump")
		await _burst(24, 4, "%s after %.1f s on the line" % ["jumps off" if jump_off else "line ends", ride_frames / 60.0])
		_new_row()
	await _prep(Vector3(-24.0, 0.1, 14.0), 0.0, 2, VIEW_SIDE)
	_farmer.movement.start_zipline(line)
	await _frames(40)
	_press(&"fire")
	await _burst(8, 3, "fires from the line")
	_new_row()


## The raw rope clip, 24 tiles from first frame to last, seen from the side and then from the front.
func _sc_rope() -> void:
	var stage := Node3D.new()
	stage.position = Vector3(30.0, 0.0, 30.0)
	add_child(stage)
	var scene: Node3D = (load(MABEL_GLB) as PackedScene).instantiate()
	scene.set_script(MABEL_SCRIPT)
	stage.add_child(scene)
	var player: AnimationPlayer = (scene as MabelModel)._player
	_follow = stage
	_view_yaw = 0.0
	var clip := "Swing_on_Rope_to_Ground"
	var length := player.get_animation(clip).length
	for view in [VIEW_SIDE, VIEW_FRONT]:
		_view = view
		for i in 24:
			player.play(clip)
			player.pause()
			player.seek(length * float(i) / 23.0, true)
			await _frames(2)
			_label.text = "%s\n%.2f / %.2f s" % [clip, player.current_animation_position, length]
			await _snap_raw()
	_follow = null
	stage.queue_free()


func _sc_hurt() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_FRONT)
	GameState.god_mode = false
	var packet := DamagePacket.new()
	packet.amount = 5.0
	_farmer.take_damage(packet)
	await _burst(16, 2, "hit")
	_new_row()
	await _frames(30)
	await _burst(2, 3, "recovered")
	GameState.god_mode = true


func _sc_game_cam() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2)
	await _game_shot("idle_pistol")
	_press(&"move_forward")
	await _frames(30)
	await _game_shot("run")
	_press(&"aim")
	await _frames(30)
	await _tap(&"fire")
	await _frames(4)
	await _game_shot("aim_fire")
	_release_all()
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 1)
	await _tap(&"fire")
	await _frames(6)
	await _game_shot("melee")
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2)
	await _tap(&"jump")
	await _frames(14)
	await _game_shot("jump")
	await _prep(LADDER_FOOT + Vector3(0.0, 0.1, 1.6), 0.0, 2)
	_press(&"move_forward")
	await _frames(100)
	await _game_shot("ladder")
	_release_all()
	await _prep(Vector3(-24.0, 0.1, 14.0), 0.0, 2)
	_farmer.movement.start_zipline(get_tree().get_nodes_in_group(&"interactables")[0])
	await _frames(60)
	await _game_shot("zipline")


func _sc_death() -> void:
	await _prep(Vector3(0.0, 0.1, 0.0), 0.0, 2, VIEW_SIDE)
	GameState.god_mode = false
	_farmer.health.apply_damage(9999.0)
	await _burst(16, 12, "dies")
	_new_row()
	await _game_shot("dead")
