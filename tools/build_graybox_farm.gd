extends SceneTree
## Builds the M0 graybox farm (GDD 4.4) out of primitive meshes and saves:
##   res://scenes/farm/silo.tscn         silo, catwalks at 8 m and 16 m, caged ladder, 16 crack sockets, chute
##   res://scenes/farm/farm.tscn         ground, buildings, ladders, ziplines, porch heal zone, dinner bell,
##                                       shed door, prop slots, 8 spawn lanes, corn, fog
##   res://scenes/farm/farm_navmesh.res  navmesh baked from the static colliders (rebaked at run start
##                                       once the seeded props are placed)
##
## Run from the project folder:
##   <godot> --headless --path . --script res://tools/build_graybox_farm.gd
##
## Re-running overwrites those files, so hand edits to them are lost. Once the layout settles, edit the
## scenes in the editor instead and stop using this script. To rebake only farm_navmesh.res from the
## farm.tscn on disk (after hand edits, or a change to the bake settings), add `-- --navmesh-only`.
## GDD positions are (x = east, y = north) in meters from the silo. Godot is (x = east, z = south),
## so GDD (x, y) becomes Vector3(x, 0, -y).

const SILO_SCENE_PATH := "res://scenes/farm/silo.tscn"
const FARM_SCENE_PATH := "res://scenes/farm/farm.tscn"
const NAVMESH_PATH := "res://scenes/farm/farm_navmesh.res"

# Loaded at run time, not preloaded: they use autoload names, which don't exist yet when this
# script itself is compiled.
const SILO_SCRIPT_PATH := "res://scripts/systems/silo.gd"
const CLIMBABLE_SCRIPT_PATH := "res://scripts/components/climbable.gd"
const HEAL_ZONE_SCRIPT_PATH := "res://scripts/components/heal_zone.gd"
const LANE_MARKER_SCRIPT_PATH := "res://scripts/systems/lane_marker.gd"
const CORN_FIELD_SCRIPT_PATH := "res://scripts/systems/corn_field.gd"
const FARM_BOUNDARY_SCRIPT_PATH := "res://scripts/systems/farm_boundary.gd"
const ZIPLINE_SCRIPT_PATH := "res://scripts/components/zipline.gd"
const DINNER_BELL_SCRIPT_PATH := "res://scripts/components/dinner_bell.gd"
const TOOL_SHED_SCRIPT_PATH := "res://scripts/components/tool_shed.gd"
const PROP_SCATTER_SCRIPT_PATH := "res://scripts/systems/prop_scatter.gd"

const LAYER_WORLD := 1
const LAYER_PLAYER := 1 << 1
const LAYER_SILO := 1 << 5
const LAYER_INTERACTABLES := 1 << 7

const SILO_RADIUS := 4.0
const SILO_BODY_HEIGHT := 20.0
const CATWALK_LEVELS: PackedFloat32Array = [8.0, 16.0]
const CATWALK_SEGMENTS := 16
const CATWALK_OUTER := 5.6
## The silo ladder's climb line sits just outside the catwalks, on the south side (+Z).
const SILO_LADDER_RADIUS := 6.2

const LANE_RADIUS := 110.0
## Compass bearings (degrees clockwise from north) of lanes 1-8, matching the GDD 4.3 map.
const LANE_BEARINGS: PackedFloat32Array = [337.5, 22.5, 67.5, 112.5, 157.5, 202.5, 247.5, 292.5]

const C_GROUND := Color(0.3, 0.42, 0.22)
const C_FARMYARD := Color(0.42, 0.58, 0.3)
const C_CROPS := Color(0.74, 0.64, 0.36)
const C_SILO := Color(0.78, 0.2, 0.15)
const C_SILO_CAP := Color(0.62, 0.62, 0.64)
const C_METAL := Color(0.45, 0.46, 0.5)
const C_RAIL := Color(0.3, 0.3, 0.33)
const C_LADDER := Color(0.22, 0.22, 0.25)
const C_BARN := Color(0.62, 0.17, 0.13)
const C_ROOF := Color(0.32, 0.24, 0.22)
const C_HOME := Color(0.9, 0.85, 0.72)
const C_WOOD := Color(0.58, 0.43, 0.28)
const C_DARK := Color(0.16, 0.12, 0.1)
const C_HAY := Color(0.9, 0.78, 0.4)
const C_COOP := Color(0.86, 0.76, 0.56)
const C_STONE := Color(0.6, 0.6, 0.58)
const C_TANK := Color(0.42, 0.56, 0.62)
const C_SOIL := Color(0.4, 0.28, 0.18)
const C_GLASS := Color(0.75, 0.9, 0.85)
const C_VINE := Color(0.25, 0.5, 0.2)
const C_CABLE := Color(0.2, 0.2, 0.22)
const C_BELL := Color(0.9, 0.72, 0.25)

## Ziplines (GDD 4.5): cable start and end. Riders hang 1.95 m below the cable.
## Z1 silo dome (22 m) -> barn roof (13 m); Z2 water tower top (19 m) -> silo upper catwalk (16 m);
## Z3 barn roof (13 m) -> stables roof (6 m).
const ZIPLINES: Array[Array] = [
	["Z1_SiloToBarn", Vector3(-0.9, 24.0, -0.8), Vector3(-31.0, 15.0, -23.0)],
	["Z2_TowerToSilo", Vector3(26.6, 21.0, 22.7), Vector3(3.65, 18.0, 3.12)],
	["Z3_BarnToStables", Vector3(-32.0, 15.0, -31.5), Vector3(8.0, 8.0, -34.0)],
]

## Prop slots (GDD 4.6): position (x, z) and which props may go there. Kept clear of ladders, doors,
## zipline landings and the player spawn.
const PROP_SLOTS: Array[Array] = [
	[Vector2(8, -14), ["hay", "crates"]], [Vector2(-8, -14), ["hay", "crates", "fence"]],
	[Vector2(-10, 10), ["hay", "crates"]], [Vector2(9, 17), ["crates", "hay", "tractor"]],
	[Vector2(19, 2), ["hay", "fence"]], [Vector2(-6, 21), ["hay", "crates", "tractor"]],
	[Vector2(-28, 8), ["crates", "hay"]], [Vector2(-14, -26), ["hay", "fence", "tractor"]],
	[Vector2(-3, -42), ["fence", "hay"]], [Vector2(44, 0), ["hay", "crates"]],
	[Vector2(40, 22), ["hay", "fence"]], [Vector2(-46, 12), ["fence", "scarecrow"]],
	[Vector2(-48, -12), ["hay", "crates"]], [Vector2(20, 42), ["fence", "scarecrow"]],
	[Vector2(-22, 44), ["hay", "scarecrow"]], [Vector2(0, 50), ["fence", "hay"]],
	[Vector2(24, -46), ["hay", "crates"]], [Vector2(60, -30), ["scarecrow", "hay"]],
	[Vector2(-62, 28), ["scarecrow", "fence"]], [Vector2(35, 60), ["hay", "scarecrow"]],
	[Vector2(-30, -62), ["scarecrow", "hay"]], [Vector2(70, 20), ["fence", "hay"]],
	[Vector2(-70, -10), ["scarecrow", "fence"]], [Vector2(55, 45), ["hay", "fence"]],
	[Vector2(-45, -50), ["hay", "scarecrow"]],
]

var _owner: Node
var _materials: Dictionary[String, StandardMaterial3D] = {}


func _initialize() -> void:
	# The root window only joins the tree once the main loop starts, and navmesh parsing needs it.
	_run.call_deferred()


func _run() -> void:
	if "--navmesh-only" in OS.get_cmdline_user_args():
		quit(0 if _rebake_saved_farm() else 1)
		return
	if not _save_scene(_build_silo(), SILO_SCENE_PATH):
		quit(1)
		return
	# Parsing needs global transforms, so bake on a copy that is in the tree. Then save a fresh copy
	# that never entered the tree, so nothing from _ready() gets packed into the scene.
	var bake_copy := _build_farm()
	root.add_child(bake_copy)
	var navmesh := _bake_navmesh(bake_copy.get_node(^"NavRegion") as NavigationRegion3D)
	root.remove_child(bake_copy)
	bake_copy.free()
	if navmesh == null or ResourceSaver.save(navmesh, NAVMESH_PATH) != OK:
		push_error("Navmesh bake or save failed")
		quit(1)
		return
	var farm := _build_farm()
	var saved_navmesh := ResourceLoader.load(NAVMESH_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as NavigationMesh
	(farm.get_node(^"NavRegion") as NavigationRegion3D).navigation_mesh = saved_navmesh
	quit(0 if _save_scene(farm, FARM_SCENE_PATH) else 1)


## Bakes farm_navmesh.res from the saved farm.tscn and leaves the scenes alone.
func _rebake_saved_farm() -> bool:
	var farm := (load(FARM_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(farm)
	var navmesh := _bake_navmesh(farm.get_node(^"NavRegion") as NavigationRegion3D)
	root.remove_child(farm)
	farm.free()
	if navmesh == null or ResourceSaver.save(navmesh, NAVMESH_PATH) != OK:
		push_error("Navmesh bake or save failed")
		return false
	return true


# --- Silo -----------------------------------------------------------------------------------------

func _build_silo() -> Node3D:
	var silo := StaticBody3D.new()
	silo.name = "Silo"
	silo.set_script(load(SILO_SCRIPT_PATH))
	silo.collision_layer = LAYER_WORLD | LAYER_SILO
	silo.collision_mask = 0
	_owner = silo

	var visual := _node3d(silo, "Visual")
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = SILO_RADIUS
	body_mesh.bottom_radius = SILO_RADIUS
	body_mesh.height = SILO_BODY_HEIGHT
	body_mesh.radial_segments = 32
	var body_xform := Transform3D(Basis(), Vector3(0.0, SILO_BODY_HEIGHT * 0.5, 0.0))
	_mesh(visual, "Body", body_mesh, body_xform, C_SILO)
	var body_shape := CylinderShape3D.new()
	body_shape.radius = SILO_RADIUS
	body_shape.height = SILO_BODY_HEIGHT
	_shape(silo, "BodyShape", body_shape, body_xform)
	# Dome cap: a truncated cone up to the flat 22 m perch.
	_cylinder(silo, "Cap", SILO_RADIUS, 1.8, 2.0, Vector3(0.0, SILO_BODY_HEIGHT + 1.0, 0.0), C_SILO_CAP, true, 32, visual)

	for level in CATWALK_LEVELS:
		_build_catwalk(silo, visual, level)

	var sockets := _node3d(silo, "CrackSockets")
	var specs: Array[Vector3] = []  # (bearing degrees, height, band)
	for k in 8:
		specs.append(Vector3(22.5 + 45.0 * k, 1.3 if k % 2 == 0 else 2.6, 0))
	for k in 4:
		specs.append(Vector3(45.0 + 90.0 * k, 9.3, 1))
	for k in 4:
		specs.append(Vector3(67.5 + 90.0 * k, 17.3, 2))
	for i in specs.size():
		var theta := deg_to_rad(specs[i].x)
		var dir := Vector3(sin(theta), 0.0, cos(theta))
		var socket := Marker3D.new()
		socket.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), dir * (SILO_RADIUS + 0.03) + Vector3.UP * specs[i].y)
		socket.set_meta(&"band", int(specs[i].z))
		_add(sockets, socket, "Socket_%02d" % i)
	_node3d(silo, "Cracks")

	# Grain chute on the east side: where Nibbler thieves grab sacks (GDD 3.3).
	var chute := Marker3D.new()
	chute.transform = Transform3D(Basis.looking_at(Vector3.LEFT, Vector3.UP), Vector3(SILO_RADIUS + 0.02, 0.6, 0.0))
	_add(silo, chute, "Chute")
	_box(silo, "ChuteHatch", Vector3(0.12, 0.9, 1.2), Vector3(SILO_RADIUS + 0.02, 0.75, 0.0), C_METAL, false)

	_climbable(silo, "Ladder", Vector3(0.0, 0.0, SILO_LADDER_RADIUS), Vector3.BACK, SILO_BODY_HEIGHT + 0.2,
			PackedFloat32Array(CATWALK_LEVELS), 1.4, SILO_LADDER_RADIUS - 1.0, 1.85)
	return silo


func _build_catwalk(silo: StaticBody3D, visual: Node3D, level: float) -> void:
	var seg_len := 2.0 * CATWALK_OUTER * tan(PI / CATWALK_SEGMENTS) + 0.05
	var depth := CATWALK_OUTER - SILO_RADIUS + 0.1
	var center_r := SILO_RADIUS - 0.1 + depth * 0.5
	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(seg_len, 0.2, depth)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_mesh.size
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(seg_len, 1.0, 0.08)
	var rail_shape := BoxShape3D.new()
	rail_shape.size = rail_mesh.size
	var ring := _node3d(visual, "Catwalk%d" % int(level))
	for k in CATWALK_SEGMENTS:
		var theta := TAU * k / CATWALK_SEGMENTS
		var b := Basis(Vector3.UP, theta)
		var dir := Vector3(sin(theta), 0.0, cos(theta))
		var floor_xform := Transform3D(b, dir * center_r + Vector3.UP * (level - 0.1))
		_mesh(ring, "Floor%02d" % k, floor_mesh, floor_xform, C_METAL)
		_shape(silo, "Catwalk%dFloor%02d" % [int(level), k], floor_shape, floor_xform)
		if k == 0:
			continue  # Gap in the railing where the ladder meets the catwalk.
		var rail_xform := Transform3D(b, dir * (CATWALK_OUTER - 0.04) + Vector3.UP * (level + 0.5))
		_mesh(ring, "Rail%02d" % k, rail_mesh, rail_xform, C_RAIL)
		_shape(silo, "Catwalk%dRail%02d" % [int(level), k], rail_shape, rail_xform)


# --- Farm -----------------------------------------------------------------------------------------

func _build_farm() -> Node3D:
	var farm := Node3D.new()
	farm.name = "Farm"
	_owner = farm
	_build_environment(farm)

	var nav := NavigationRegion3D.new()
	_add(farm, nav, "NavRegion")

	var ground := _body(nav, "Ground", Vector3.ZERO)
	_box(ground, "Ground", Vector3(280.0, 1.0, 280.0), Vector3(0.0, -0.5, 0.0), C_GROUND)
	_cylinder(ground, "CropRing", 100.0, 100.0, 0.02, Vector3(0.0, 0.011, 0.0), C_CROPS, false, 64)
	_cylinder(ground, "Farmyard", 55.0, 55.0, 0.02, Vector3(0.0, 0.021, 0.0), C_FARMYARD, false, 64)
	# Felt, not clay (GDD 15.2): the ground stays a flat matte material without lumps.
	var felt: Dictionary[String, Color] = {"Ground": C_GROUND, "CropRing": C_CROPS, "Farmyard": C_FARMYARD}
	for felt_name in felt:
		(ground.get_node(felt_name) as MeshInstance3D).material_override = _mat(felt[felt_name])

	var silo_scene := ResourceLoader.load(SILO_SCENE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var silo := silo_scene.instantiate()
	nav.add_child(silo)
	silo.owner = farm

	var climbables := _node3d(farm, "Climbables")
	_build_home(nav, climbables)
	_build_tool_shed(nav)
	_build_barn(nav, climbables)
	_build_stables(nav)
	_build_chicken_house(nav)
	_build_water_tower(nav, climbables)
	_build_garden(nav)
	_build_well(nav)

	_build_heal_zone(farm)
	_build_lanes(farm)
	_build_ziplines(farm)
	_build_dinner_bell(farm)
	_build_props(nav)

	var corn := MultiMeshInstance3D.new()
	corn.set_script(load(CORN_FIELD_SCRIPT_PATH))
	corn.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(farm, corn, "CornField")

	var boundary := Node.new()
	boundary.set_script(load(FARM_BOUNDARY_SCRIPT_PATH))
	_add(farm, boundary, "FarmBoundary")

	var spawn := Marker3D.new()
	spawn.position = Vector3(0.0, 0.2, 10.0)
	_add(farm, spawn, "PlayerSpawn")
	spawn.add_to_group(&"player_spawns", true)
	return farm


func _build_environment(farm: Node3D) -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.56, 0.84)
	sky_material.sky_horizon_color = Color(0.78, 0.82, 0.84)
	sky_material.ground_horizon_color = Color(0.78, 0.82, 0.84)
	sky_material.ground_bottom_color = Color(0.32, 0.34, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	# Fog boundary (GDD 4.7): the corn wall at 100 m fades out and the spawn ring at 110 m is hidden.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.8, 0.82, 0.8)
	env.fog_density = 1.0
	env.fog_depth_begin = 55.0
	env.fog_depth_end = 125.0
	env.fog_depth_curve = 1.2
	env.fog_sky_affect = 0.25
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_add(farm, world_env, "WorldEnvironment")

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.light_angular_distance = 0.8
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	_add(farm, sun, "Sun")


func _build_home(nav: Node3D, climbables: Node3D) -> void:
	# GDD (-30, -22). Main roof ridge 10 m, porch roof 4 m on the south side, porch heal zone.
	var home := _body(nav, "Home", Vector3(-30.0, 0.0, 22.0))
	_box(home, "Walls", Vector3(14.0, 7.0, 10.0), Vector3(0.0, 3.5, 0.0), C_HOME)
	_prism(home, "Roof", Vector3(10.0, 3.0, 14.0), Vector3(0.0, 8.5, 0.0), C_ROOF, 90.0)
	_box(home, "PorchFloor", Vector3(14.0, 0.2, 3.5), Vector3(0.0, 0.1, 6.75), C_WOOD)
	# Ramp down from the porch's front edge (z 8.5, 0.2 m up) to the yard over 2 m, so the porch is walked onto.
	_tilted_box(home, "PorchRamp", Vector3(3.0, 0.2, 2.02), Vector3(0.0, 0.0, 9.49), atan2(0.2, 2.0), C_WOOD)
	_box(home, "PorchRoof", Vector3(14.4, 0.3, 3.7), Vector3(0.0, 3.85, 6.75), C_ROOF)
	for x: float in [-6.9, 6.9]:
		_box(home, "PorchPost%d" % int(signf(x)), Vector3(0.3, 3.7, 0.3), Vector3(x, 1.85, 8.35), C_WOOD)
	_box(home, "Door", Vector3(1.4, 2.4, 0.1), Vector3(0.0, 1.4, 5.02), C_DARK, false)
	_label(home, "HOME  (porch heals)", Vector3(0.0, 11.5, 0.0))
	# Vine trellis up to the porch roof, at the porch's east end.
	_climbable(climbables, "PorchTrellis", Vector3(-22.2, 0.0, 28.75), Vector3.RIGHT, 4.0,
			PackedFloat32Array(), 1.2, 1.5, 0.0, C_VINE)


func _build_tool_shed(nav: Node3D) -> void:
	# GDD (-20, 2). Roof 4 m. Rain barrel + crate step-up on the east side.
	var shed := _body(nav, "ToolShed", Vector3(-20.0, 0.0, -2.0))
	_box(shed, "Shed", Vector3(8.0, 4.0, 6.0), Vector3(0.0, 2.0, 0.0), C_WOOD)
	_box(shed, "Shutter", Vector3(3.0, 2.2, 0.1), Vector3(0.0, 1.4, 3.02), C_DARK, false)
	_cylinder(shed, "RainBarrel", 0.45, 0.45, 1.1, Vector3(4.8, 0.55, 3.6), C_WOOD, true, 12)
	_box(shed, "CrateLow", Vector3(1.2, 2.2, 1.2), Vector3(4.6, 1.1, 2.4), C_WOOD)
	_box(shed, "CrateHigh", Vector3(1.2, 3.2, 1.2), Vector3(4.6, 1.6, 1.2), C_WOOD)
	_label(shed, "TOOL SHED  (pegboard)", Vector3(0.0, 5.5, 0.0))
	# The door on the south face opens the pegboard during intermissions (GDD 13.1).
	var door := Node3D.new()
	door.set_script(load(TOOL_SHED_SCRIPT_PATH))
	door.position = Vector3(0.0, 0.0, 3.6)
	_add(shed, door, "PegboardDoor")


func _build_barn(nav: Node3D, climbables: Node3D) -> void:
	# GDD (-32, 28). Hayloft 7 m facing the north lanes, roof ridge 13 m, side ladder to the hayloft.
	var barn := _body(nav, "Barn", Vector3(-32.0, 0.0, -28.0))
	_box(barn, "Walls", Vector3(18.0, 9.0, 14.0), Vector3(0.0, 4.5, 0.0), C_BARN)
	_prism(barn, "Roof", Vector3(18.0, 4.0, 14.0), Vector3(0.0, 11.0, 0.0), C_ROOF)
	_box(barn, "HayloftLedge", Vector3(5.0, 0.3, 2.5), Vector3(0.0, 6.85, -8.25), C_WOOD)
	_box(barn, "HayloftDoor", Vector3(3.0, 2.6, 0.1), Vector3(0.0, 8.4, -7.05), C_DARK, false)
	_box(barn, "BarnDoor", Vector3(5.0, 5.0, 0.1), Vector3(0.0, 2.5, 7.05), C_DARK, false)
	_label(barn, "BARN  (hayloft 7 m)", Vector3(0.0, 14.5, 0.0))
	_climbable(climbables, "BarnLadder", Vector3(-32.0, 0.0, -38.1), Vector3.FORWARD, 7.0,
			PackedFloat32Array(), 1.2, 1.4, 0.0)


func _build_stables(nav: Node3D) -> void:
	# GDD (20, 34). Long flat roof at 6 m. Hay-bale stairs on the south face.
	var stables := _body(nav, "Stables", Vector3(20.0, 0.0, -34.0))
	_box(stables, "Stables", Vector3(28.0, 6.0, 8.0), Vector3(0.0, 3.0, 0.0), C_WOOD)
	for i in 6:
		var h := float(i + 1)
		_box(stables, "HayStep%d" % i, Vector3(1.2, h, 1.2), Vector3(-13.4 + 1.2 * i, h * 0.5, 4.6), C_HAY)
	_label(stables, "STABLES", Vector3(0.0, 7.5, 0.0))


func _build_chicken_house(nav: Node3D) -> void:
	# GDD (34, 6). Roof 3.5 m. Hay-bale stairs on the west face.
	var coop := _body(nav, "ChickenHouse", Vector3(34.0, 0.0, -6.0))
	_box(coop, "Coop", Vector3(10.0, 3.5, 7.0), Vector3(0.0, 1.75, 0.0), C_COOP)
	for i in 3:
		var h := float(i + 1)
		_box(coop, "HayStep%d" % i, Vector3(1.2, h, 1.2), Vector3(-5.6, h * 0.5, 2.6 - 1.2 * i), C_HAY)
	_label(coop, "CHICKEN HOUSE", Vector3(0.0, 5.0, 0.0))


func _build_water_tower(nav: Node3D, climbables: Node3D) -> void:
	# GDD (28, -24). Deck 15 m, tank top 19 m with the wave siren. Long ladder plus a tank ladder.
	var tower := _body(nav, "WaterTower", Vector3(28.0, 0.0, 24.0))
	for x: float in [-2.6, 2.6]:
		for z: float in [-2.6, 2.6]:
			_box(tower, "Leg%d%d" % [int(signf(x)), int(signf(z))], Vector3(0.4, 15.0, 0.4), Vector3(x, 7.5, z), C_WOOD)
	_cylinder(tower, "Deck", 4.5, 4.5, 0.3, Vector3(0.0, 14.85, 0.0), C_WOOD, true, 24)
	_cylinder(tower, "Tank", 3.2, 3.2, 4.0, Vector3(0.0, 17.0, 0.0), C_TANK, true, 24)
	_box(tower, "Siren", Vector3(1.0, 0.8, 1.0), Vector3(0.0, 19.4, 0.0), C_RAIL)
	_label(tower, "WATER TOWER  (siren)", Vector3(0.0, 21.0, 0.0))
	_climbable(climbables, "WaterTowerLadder", Vector3(28.0, 0.0, 29.1), Vector3.BACK, 15.0,
			PackedFloat32Array(), 1.2, 1.2, 0.0)
	_climbable(climbables, "TankLadder", Vector3(31.9, 15.0, 24.0), Vector3.RIGHT, 4.0,
			PackedFloat32Array(), 1.2, 1.5, 0.0)


func _build_garden(nav: Node3D) -> void:
	# GDD (0, -34). Raised beds, 1.8 m trellises, greenhouse roof 3 m: a low cover maze.
	var garden := _body(nav, "Garden", Vector3(0.0, 0.0, 34.0))
	for i in 6:
		_box(garden, "Bed%d" % i, Vector3(1.6, 0.5, 6.0), Vector3(-12.0 + 4.0 * i, 0.25, 0.0), C_SOIL)
	for i in 4:
		_box(garden, "Trellis%d" % i, Vector3(0.15, 1.8, 3.0), Vector3(-10.0 + 4.0 * i, 0.9, -4.5), C_VINE)
	_box(garden, "Greenhouse", Vector3(6.0, 3.0, 4.0), Vector3(14.0, 1.5, 0.0), C_GLASS)
	_label(garden, "GARDEN", Vector3(0.0, 3.5, 0.0))


func _build_well(nav: Node3D) -> void:
	# GDD (14, -8). Roof 2.8 m: low cover right next to the silo.
	var well := _body(nav, "Well", Vector3(14.0, 0.0, 8.0))
	_cylinder(well, "Ring", 1.1, 1.1, 1.0, Vector3(0.0, 0.5, 0.0), C_STONE, true, 16)
	for x: float in [-0.95, 0.95]:
		_box(well, "Post%d" % int(signf(x)), Vector3(0.2, 2.6, 0.2), Vector3(x, 1.3, 0.0), C_WOOD)
	_box(well, "Roof", Vector3(2.6, 0.2, 2.0), Vector3(0.0, 2.7, 0.0), C_ROOF)
	_label(well, "WELL", Vector3(0.0, 4.0, 0.0))


func _build_heal_zone(farm: Node3D) -> void:
	var zone := Area3D.new()
	zone.set_script(load(HEAL_ZONE_SCRIPT_PATH))
	zone.position = Vector3(-30.0, 1.9, 28.75)
	zone.collision_layer = LAYER_INTERACTABLES
	zone.collision_mask = LAYER_PLAYER
	_add(farm, zone, "PorchHealZone")
	var shape := BoxShape3D.new()
	shape.size = Vector3(13.4, 3.4, 3.3)
	_shape(zone, "Shape", shape, Transform3D.IDENTITY)
	var glow := BoxMesh.new()
	glow.size = Vector3(13.4, 0.04, 3.3)
	var glow_instance := _mesh(zone, "Glow", glow, Transform3D(Basis(), Vector3(0.0, -1.57, 0.0)), Color(0.4, 1.0, 0.5))
	glow_instance.material_override = _mat(Color(0.4, 1.0, 0.5), true, 0.35)
	glow_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_lanes(farm: Node3D) -> void:
	var lanes := _node3d(farm, "Lanes")
	var pole := CylinderMesh.new()
	pole.top_radius = 0.3
	pole.bottom_radius = 0.3
	pole.height = 14.0
	var post := BoxMesh.new()
	post.size = Vector3(0.5, 5.0, 0.5)
	var bar := BoxMesh.new()
	bar.size = Vector3(8.1, 0.5, 0.3)
	for i in LANE_BEARINGS.size():
		var bearing := deg_to_rad(LANE_BEARINGS[i])
		var dir := Vector3(sin(bearing), 0.0, -cos(bearing))
		var marker := Marker3D.new()
		marker.set_script(load(LANE_MARKER_SCRIPT_PATH))
		marker.set(&"lane_index", i + 1)
		marker.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), dir * LANE_RADIUS)
		_add(lanes, marker, "Lane%d" % (i + 1))
		# The tall pole marks the spawn point in the corn; the gate marks where robots break out at 100 m.
		_mesh(marker, "Pole", pole, Transform3D(Basis(), Vector3(0.0, 7.0, 0.0)), C_STONE)
		_mesh(marker, "GateLeft", post, Transform3D(Basis(), Vector3(-3.8, 2.5, -10.0)), C_STONE)
		_mesh(marker, "GateRight", post, Transform3D(Basis(), Vector3(3.8, 2.5, -10.0)), C_STONE)
		_mesh(marker, "GateBar", bar, Transform3D(Basis(), Vector3(0.0, 5.2, -10.0)), C_STONE)
		var sign_label := _label(marker, "LANE %d" % (i + 1), Vector3(0.0, 6.8, -10.0), 160)
		sign_label.name = "Sign"


func _build_ziplines(farm: Node3D) -> void:
	var lines := _node3d(farm, "Ziplines")
	for spec in ZIPLINES:
		var start: Vector3 = spec[1]
		var end: Vector3 = spec[2]
		var line := Node3D.new()
		line.set_script(load(ZIPLINE_SCRIPT_PATH))
		line.position = start
		_add(lines, line, spec[0])
		var end_marker := Marker3D.new()
		end_marker.position = end - start
		_add(line, end_marker, "End")
		var cable := BoxMesh.new()
		cable.size = Vector3(0.05, 0.05, start.distance_to(end))
		var dir := (end - start).normalized()
		_mesh(line, "Cable", cable, Transform3D(Basis.looking_at(dir, Vector3.UP), (end - start) * 0.5), C_CABLE)
		var flat_back := -Vector3(dir.x, 0.0, dir.z).normalized()
		var pole := CylinderMesh.new()
		pole.top_radius = 0.07
		pole.bottom_radius = 0.07
		pole.height = 2.5
		_mesh(line, "StartPole", pole, Transform3D(Basis(), flat_back * 0.4 + Vector3.DOWN * 1.05), C_WOOD)
		_mesh(line, "EndPole", pole, Transform3D(Basis(), end - start - flat_back * 0.4 + Vector3.DOWN * 1.05), C_WOOD)
		_label(line, spec[0].left(2), Vector3(0.0, 0.6, 0.0), 40)


func _build_dinner_bell(farm: Node3D) -> void:
	var bell := Node3D.new()
	bell.set_script(load(DINNER_BELL_SCRIPT_PATH))
	bell.position = Vector3(-21.0, 0.0, 31.8)
	_add(farm, bell, "DinnerBell")
	_box(bell, "Post", Vector3(0.15, 2.4, 0.15), Vector3(0.0, 1.2, 0.0), C_WOOD, false)
	var swing := _node3d(bell, "Bell", Vector3(0.0, 2.25, 0.0))
	_cylinder(swing, "BellMesh", 0.28, 0.12, 0.35, Vector3(0.0, -0.2, 0.0), C_BELL, false, 16)
	_label(bell, "DINNER BELL", Vector3(0.0, 3.0, 0.0), 40)


func _build_props(nav: Node3D) -> void:
	var props := Node3D.new()
	props.set_script(load(PROP_SCATTER_SCRIPT_PATH))
	_add(nav, props, "Props")
	props.set(&"nav_region", nav)
	for i in PROP_SLOTS.size():
		var at: Vector2 = PROP_SLOTS[i][0]
		var slot := Marker3D.new()
		slot.position = Vector3(at.x, 0.0, at.y)
		slot.set_meta(&"kinds", PackedStringArray(PROP_SLOTS[i][1]))
		_add(props, slot, "Slot%02d" % i)


# --- Navmesh --------------------------------------------------------------------------------------

func _bake_navmesh(region: NavigationRegion3D) -> NavigationMesh:
	var navmesh := NavigationMesh.new()
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = LAYER_WORLD
	navmesh.cell_size = 0.25
	# Join only steps robots can walk onto. A capsule of radius r with a 45° floor_max_angle steps up about
	# r * (1 - cos 45°): 0.10 m for a Nibbler. Recast rounds heights to cell_height, so it may join steps
	# just under (agent_max_climb / cell_height + 1) * cell_height, 0.1 m here. The old 0.25 / 0.25 joined
	# the 0.2 m porch floor, and robots walked into its edge for good (tests/unit/test_robot_movement.gd).
	# project.godot sets navigation/3d/default_cell_height to match.
	navmesh.cell_height = 0.05
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.25
	navmesh.agent_max_climb = 0.05
	navmesh.agent_max_slope = 40.0
	navmesh.filter_baking_aabb = AABB(Vector3(-124.0, -2.0, -124.0), Vector3(248.0, 34.0, 248.0))
	var source := NavigationMeshSourceGeometryData3D.new()
	var started := Time.get_ticks_msec()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, region)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	print("Navmesh baked in %d ms: %d polygons, %d vertices" % [
		Time.get_ticks_msec() - started, navmesh.get_polygon_count(), navmesh.get_vertices().size()])
	return navmesh if navmesh.get_polygon_count() > 0 else null


# --- Helpers --------------------------------------------------------------------------------------

func _save_scene(scene_root: Node, path: String) -> bool:
	var packed := PackedScene.new()
	var err := packed.pack(scene_root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	print("Saved %s: %s" % [path, error_string(err)])
	scene_root.free()
	return err == OK


func _add(parent: Node, child: Node, child_name: String) -> Node:
	child.name = child_name
	parent.add_child(child)
	child.owner = _owner
	return child


func _node3d(parent: Node, node_name: String, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	_add(parent, node, node_name)
	return node


func _body(parent: Node, node_name: String, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.collision_layer = LAYER_WORLD
	body.collision_mask = 0
	_add(parent, body, node_name)
	return body


func _mat(color: Color, emissive: bool = false, alpha: float = 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), emissive, alpha]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if emissive:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 0.6
	_materials[key] = m
	return m


func _mesh(parent: Node, node_name: String, mesh: Mesh, xform: Transform3D, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = xform
	instance.material_override = Clay.colored(color)
	_add(parent, instance, node_name)
	return instance


func _shape(body: Node, node_name: String, shape: Shape3D, xform: Transform3D) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	_add(body, collision, node_name)
	return collision


func _box(body: Node3D, node_name: String, size: Vector3, center: Vector3, color: Color, collide: bool = true) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var xform := Transform3D(Basis(), center)
	_mesh(body, node_name, mesh, xform, color)
	if collide:
		var shape := BoxShape3D.new()
		shape.size = size
		_shape(body, node_name + "Shape", shape, xform)


## A box tilted about X. Positive tilt drops its far (+Z) end, so a ramp runs down toward the yard.
func _tilted_box(body: Node3D, node_name: String, size: Vector3, center: Vector3, tilt_radians: float, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var xform := Transform3D(Basis(Vector3.RIGHT, tilt_radians), center)
	_mesh(body, node_name, mesh, xform, color)
	var shape := BoxShape3D.new()
	shape.size = size
	_shape(body, node_name + "Shape", shape, xform)


func _cylinder(body: Node3D, node_name: String, bottom_radius: float, top_radius: float, height: float,
		center: Vector3, color: Color, collide: bool = true, segments: int = 24, mesh_parent: Node = null) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = segments
	var xform := Transform3D(Basis(), center)
	_mesh(mesh_parent if mesh_parent != null else body, node_name, mesh, xform, color)
	if not collide:
		return
	if is_equal_approx(bottom_radius, top_radius):
		var cylinder := CylinderShape3D.new()
		cylinder.radius = bottom_radius
		cylinder.height = height
		_shape(body, node_name + "Shape", cylinder, xform)
	else:
		var hull := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for i in segments:
			var a := TAU * i / segments
			points.append(Vector3(cos(a) * bottom_radius, -height * 0.5, sin(a) * bottom_radius))
			points.append(Vector3(cos(a) * top_radius, height * 0.5, sin(a) * top_radius))
		hull.points = points
		_shape(body, node_name + "Shape", hull, xform)


## Triangular roof. The ridge runs along local Z; yaw 90 turns it to run east-west.
func _prism(body: Node3D, node_name: String, size: Vector3, center: Vector3, color: Color, yaw_degrees: float = 0.0) -> void:
	var mesh := PrismMesh.new()
	mesh.size = size
	var xform := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_degrees)), center)
	_mesh(body, node_name, mesh, xform, color)
	var h := size * 0.5
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(0.0, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(0.0, h.y, h.z),
	])
	_shape(body, node_name + "Shape", hull, xform)


func _label(parent: Node, text: String, pos: Vector3, font_size: int = 56) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = pos
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = font_size
	label.pixel_size = 0.01
	label.outline_size = 12
	_add(parent, label, "Label")
	return label


## A ladder (or trellis): trigger volume plus rails and rungs. Origin = foot of the climb line.
func _climbable(parent: Node, node_name: String, base: Vector3, outward: Vector3, height: float,
		landings: PackedFloat32Array, landing_depth: float, top_depth: float, top_rise: float,
		color: Color = C_LADDER) -> Area3D:
	var area := Area3D.new()
	area.set_script(load(CLIMBABLE_SCRIPT_PATH))
	area.transform = Transform3D(Basis.looking_at(-outward, Vector3.UP), base)
	area.collision_layer = LAYER_INTERACTABLES
	area.collision_mask = LAYER_PLAYER
	area.monitorable = false
	area.set(&"climb_height", height)
	area.set(&"landings", landings)
	area.set(&"landing_depth", landing_depth)
	area.set(&"top_exit_depth", top_depth)
	area.set(&"top_exit_rise", top_rise)
	_add(parent, area, node_name)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.9, height + 1.6, 1.2)
	_shape(area, "Shape", shape, Transform3D(Basis(), Vector3(0.0, (height + 1.6) * 0.5 - 0.3, 0.0)))

	var rail := BoxMesh.new()
	rail.size = Vector3(0.08, height + 1.0, 0.08)
	for x: float in [-0.35, 0.35]:
		_mesh(area, "Rail%d" % int(signf(x)), rail, Transform3D(Basis(), Vector3(x, (height + 1.0) * 0.5, -0.3)), color)
	var rung := BoxMesh.new()
	rung.size = Vector3(0.7, 0.05, 0.05)
	var count := int(height / 0.6)
	for i in count:
		_mesh(area, "Rung%02d" % i, rung, Transform3D(Basis(), Vector3(0.0, 0.3 + 0.6 * i, -0.3)), color)
	return area
