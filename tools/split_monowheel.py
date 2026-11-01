# Splits assets/Monowheel Robot Texture.glb into the parts RobotFactory assembles robots from.
# The source is one fused, posed mesh (its head and body are turned opposite ways), so this squares the parts up,
# cuts the head and arms off the torso, and writes:
#   assets/models/robots/parts/monowheel.glb        one object per part; each node's translation is the part's socket in
#                                                   kit space (Scout size, y up, front = -Z, wheel on the ground)
#   assets/models/robots/parts/monowheel_skin.png   the texture at 1024, with the UV islands bled outward so the black
#                                                   background doesn't show in mipmaps
#   assets/models/robots/parts/monowheel_mask.png   which paint each texel is: R cream, G red, B rubber, none of them brass.
#                                                   Told apart once here so scuffs don't speckle a repaint
# Run from the project root:
#   /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/split_monowheel.py
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

SOURCE = "assets/Monowheel Robot Texture.glb"
OUT_GLB = "assets/models/robots/parts/monowheel.glb"
OUT_SKIN = "assets/models/robots/parts/monowheel_skin.png"
OUT_MASK = "assets/models/robots/parts/monowheel_mask.png"
SKIN_SIZE = 1024
BLEED = 12

# Source units to kit units: this size puts the head and eye where the robot scenes' hurtboxes already are.
SCALE = 1.2
GROUND = 0.476
NECK_Y = 0.145
ARM_CUT_X = 0.172
# Measured from the emblem wings and tank pair (body), and the brows (head).
BODY_YAW = math.radians(22.0)
HEAD_YAW = math.radians(-17.0)
SHARP_ANGLE = math.radians(50.0)
# How far out the wheel's brass hub reaches, as a share of its radius.
HUB_FRACTION = 0.62


def to_game(co):
	# glTF front is +Z, the game's is -Z. Blender imports (x, y, z)_gltf as (x, -z, y). A pure rotation, so winding holds.
	return Vector((-co.x, co.z, co.y))


def to_blender(g):
	# The exporter maps Blender (x, y, z) to glTF (x, z, -y).
	return Vector((g.x, -g.z, g.y))


def islands(bm):
	seen = set()
	found = []
	for start in bm.verts:
		if start in seen:
			continue
		stack = [start]
		seen.add(start)
		island = []
		while stack:
			v = stack.pop()
			island.append(v)
			for edge in v.link_edges:
				other = edge.other_vert(v)
				if other not in seen:
					seen.add(other)
					stack.append(other)
		found.append(island)
	return found


def classify(island):
	"""Which part a free-floating island belongs to, from its bounds in unsquared game axes."""
	points = np.array([tuple(v.co) for v in island])
	low, high = points.min(0), points.max(0)
	mid = (low + high) * 0.5
	if len(island) > 1000:
		return "main"
	if low[1] < -0.45:
		return "wheel"
	if high[1] < -0.08 and abs(mid[0]) < 0.14:
		return "fender"
	if low[1] > 0.4:
		return "antenna"
	if abs(mid[0]) > 0.29:
		return "claw_left" if mid[0] < 0.0 else "claw_right"
	if mid[1] > 0.3:
		return "head"
	if mid[2] > 0.05:
		return "pack"
	return "torso"


def extract(source, verts, cuts=()):
	"""A new bmesh of `verts`' faces, trimmed by each (normal, offset) cut to the side the normal points at."""
	bm = bmesh.new()
	uv_in = source.loops.layers.uv.active
	uv_out = bm.loops.layers.uv.new("UVMap")
	made = {v: bm.verts.new(v.co) for v in verts}
	done = set()
	for v in verts:
		for face in v.link_faces:
			if face not in done:
				done.add(face)
				new_face = bm.faces.new([made[loop.vert] for loop in face.loops])
				for a, b in zip(face.loops, new_face.loops):
					b[uv_out].uv = a[uv_in].uv
	for normal, offset in cuts:
		geom = list(bm.verts) + list(bm.edges) + list(bm.faces)
		bmesh.ops.bisect_plane(bm, geom=geom, plane_co=normal * offset, plane_no=normal, clear_inner=True)
	return bm


def transform(bm, matrix):
	for v in bm.verts:
		v.co = matrix @ v.co


def bounds(bm, predicate=lambda v: True):
	points = np.array([tuple(v.co) for v in bm.verts if predicate(v)])
	return Vector(points.min(0)), Vector(points.max(0))


def write_part(name, bm, pivot, axle_up=False):
	"""Links `bm` (in kit space) as an object at `pivot`. A wheel's axle is laid along local Y, like a cylinder's."""
	low, high = bounds(bm)
	for v in bm.verts:
		local = v.co - pivot
		if axle_up:
			local = Vector((local.y, -local.x, local.z))
		v.co = to_blender(local)
	bm.normal_update()
	for face in bm.faces:
		face.smooth = True
	for edge in bm.edges:
		if edge.is_manifold and edge.calc_face_angle(0.0) > SHARP_ANGLE:
			edge.smooth = False
	mesh = bpy.data.meshes.new(name)
	bm.to_mesh(mesh)
	bm.free()
	obj = bpy.data.objects.new(name, mesh)
	obj.location = to_blender(pivot)
	bpy.context.scene.collection.objects.link(obj)
	print("PART %-11s verts %5d pivot %s bounds %s .. %s" % (name, len(mesh.vertices), rounded(pivot), rounded(low), rounded(high)))


def rounded(v):
	return [round(c, 3) for c in v]


def rasterize(polygons):
	"""A texel mask of the given UV polygons."""
	covered = np.zeros((SKIN_SIZE, SKIN_SIZE), dtype=bool)
	for corners in polygons:
		for k in range(1, len(corners) - 1):
			tri = np.array((corners[0], corners[k], corners[k + 1])) * SKIN_SIZE
			low = np.maximum(np.floor(tri.min(0)).astype(int), 0)
			high = np.minimum(np.ceil(tri.max(0)).astype(int) + 1, SKIN_SIZE)
			if high[0] <= low[0] or high[1] <= low[1]:
				continue
			xs, ys = np.meshgrid(np.arange(low[0], high[0]) + 0.5, np.arange(low[1], high[1]) + 0.5)
			a, b, c = tri
			d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
			if abs(d) < 1e-9:
				continue
			u = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
			v = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
			covered[low[1]:high[1], low[0]:high[0]] |= (u >= -0.01) & (v >= -0.01) & (u + v <= 1.01)
	return covered


def box_count(mask, radius):
	"""For each texel, how many texels of `mask` lie in the square of `radius` around it."""
	total = np.zeros(mask.shape, dtype=np.int32)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			total += np.roll(np.roll(mask, dy, 0), dx, 1)
	return total


def save_png(rgb, path):
	out = bpy.data.images.new(os.path.basename(path), SKIN_SIZE, SKIN_SIZE, alpha=False)
	out.colorspace_settings.name = "Non-Color"
	rgba = np.concatenate((rgb, np.ones((SKIN_SIZE, SKIN_SIZE, 1), dtype=np.float32)), 2)
	out.pixels = rgba.ravel().tolist()
	out.filepath_raw = os.path.abspath(path)
	out.file_format = "PNG"
	out.save()


def bake_mask(srgb, tread):
	top = srgb.max(2)
	chroma = top - srgb.min(2)
	sat = chroma / np.maximum(top, 0.001)
	hue = 60.0 * (srgb[..., 1] - srgb[..., 2]) / np.maximum(chroma, 0.001)
	rubber = (sat < 0.4) & (top < 0.42)
	# Highlights on the tread are still rubber: close the gaps in it.
	rubber = ~(box_count(~(box_count(rubber, 3) > 0), 3) > 0)
	rubber = rubber | tread
	cream = (sat < 0.42) & ~rubber
	red = (hue < 25.0) & ~cream & ~rubber
	brass = ~cream & ~red & ~rubber
	# Scorch shading along cream's edges has brass's color but none of its width: an opening keeps only real brass.
	opened = box_count(box_count(brass, 2) >= 25, 2) > 0
	# What's no longer brass joins whichever paint is nearest.
	lost = brass & ~opened
	brass = brass & opened
	for _i in range(6):
		cream_near = box_count(cream, 1)
		red_near = box_count(red, 1)
		cream = cream | (lost & (cream_near > 0) & (cream_near >= red_near))
		red = red | (lost & (red_near > 0) & (red_near > cream_near))
		lost = lost & ~cream & ~red
	cream = cream | lost
	# A majority filter takes out what specks remain.
	counts = np.stack([box_count(m, 1) for m in (cream, red, rubber, brass)], 2)
	winner = counts.argmax(2)
	save_png(np.stack((winner == 0, winner == 1, winner == 2), 2).astype(np.float32), OUT_MASK)


def bake_skin(mesh, image):
	width, height = image.size
	pixels = np.array(image.pixels[:], dtype=np.float32).reshape(height, width, 4)[:, :, :3]
	step = width // SKIN_SIZE
	small = pixels.reshape(SKIN_SIZE, step, SKIN_SIZE, step, 3).mean((1, 3))
	uv = mesh.uv_layers.active.data
	covered = rasterize([[uv[i].uv for i in poly.loop_indices] for poly in mesh.polygons])
	for _i in range(BLEED):
		total = np.zeros_like(small)
		count = np.zeros((SKIN_SIZE, SKIN_SIZE), dtype=np.float32)
		for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
			total += np.roll(np.roll(small * covered[..., None], dy, 0), dx, 1)
			count += np.roll(np.roll(covered.astype(np.float32), dy, 0), dx, 1)
		grow = (~covered) & (count > 0.0)
		small[grow] = total[grow] / count[grow, None]
		covered = covered | grow
	# A byte image's pixels come back as stored: already the sRGB values it was painted in.
	save_png(small, OUT_SKIN)
	return small


def tread_texels(bm, wheel_verts):
	"""The tyre's texels, found by shape: its faces out past the hub. Worn rubber's color is no guide."""
	points = np.array([tuple(v.co) for v in wheel_verts])
	mid = (points.min(0) + points.max(0)) * 0.5
	uv_layer = bm.loops.layers.uv.active
	radius = (points[:, 1].max() - points[:, 1].min()) * 0.5
	wanted = set(wheel_verts)
	faces = {face for v in wheel_verts for face in v.link_faces}
	polygons = []
	for face in faces:
		if all(loop.vert in wanted and math.hypot(loop.vert.co.y - mid[1], loop.vert.co.z - mid[2]) > radius * HUB_FRACTION for loop in face.loops):
			polygons.append([loop[uv_layer].uv.copy() for loop in face.loops])
	return rasterize(polygons)


def main():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SOURCE)
	source_obj = next(o for o in bpy.data.objects if o.type == "MESH")
	srgb = bake_skin(source_obj.data, next(i for i in bpy.data.images if i.size[0] > 0))

	bm = bmesh.new()
	bm.from_mesh(source_obj.data)
	bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
	for v in bm.verts:
		v.co = to_game(v.co)
	groups = {}
	for island in islands(bm):
		groups.setdefault(classify(island), []).extend(island)
	print("GROUPS", {k: len(v) for k, v in groups.items()})
	bake_mask(srgb, tread_texels(bm, groups["wheel"]))
	for obj in list(bpy.data.objects):
		bpy.data.objects.remove(obj)

	up = Vector((0.0, 1.0, 0.0))
	right = Vector((1.0, 0.0, 0.0))
	to_kit = Matrix.Translation((0.0, GROUND * SCALE, 0.0)) @ Matrix.Scale(SCALE, 4)

	# Matrix.Rotation about +Y turns +X toward -Z, which is what squaring up a positive source yaw needs.
	head = extract(bm, groups["main"] + groups["head"], [(up, NECK_Y)])
	low, high = bounds(head)
	head_mid = (low + high) * 0.5
	head_square = Matrix.Rotation(HEAD_YAW, 4, up)
	recenter = Matrix.Translation((-head_mid.x, 0.0, -head_mid.z))
	head_xform = to_kit @ head_square @ recenter
	transform(head, head_xform)
	low, high = bounds(head)
	head_center = (low + high) * 0.5

	antenna = extract(bm, groups["antenna"])
	transform(antenna, head_xform)
	low, high = bounds(antenna)
	antenna_pivot = Vector(((low.x + high.x) * 0.5, low.y, (low.z + high.z) * 0.5))

	body_square = Matrix.Rotation(BODY_YAW, 4, up)
	body = extract(bm, groups["main"] + groups["torso"], [(-up, -NECK_Y)])
	transform(body, body_square)
	low, high = bounds(body, lambda v: abs(v.co.x) < 0.2)
	body_center = (low + high) * 0.5
	body_xform = to_kit @ Matrix.Translation((-body_center.x, 0.0, -body_center.z))
	transform(body, body_xform)
	arm_x = ARM_CUT_X * SCALE
	left = extract(body, list(body.verts), [(-right, arm_x)])
	right_arm = extract(body, list(body.verts), [(right, arm_x)])
	torso = extract(body, list(body.verts), [(right, -arm_x), (-right, -arm_x)])
	body.free()
	low, high = bounds(torso)
	torso_center = (low + high) * 0.5

	full_body = body_xform @ body_square
	parts = []
	for name, arm, side in (("arm_left", left, -1.0), ("arm_right", right_arm, 1.0)):
		low, high = bounds(arm, lambda v: abs(abs(v.co.x) - arm_x) < 0.02)
		parts.append((name, arm, Vector((side * arm_x, (low.y + high.y) * 0.5, (low.z + high.z) * 0.5)), False))
	for name in ("claw_left", "claw_right", "pack", "fender"):
		part = extract(bm, groups[name])
		transform(part, full_body)
		low, high = bounds(part)
		parts.append((name, part, (low + high) * 0.5, False))
	wheel = extract(bm, groups["wheel"])
	transform(wheel, body_square)
	low, high = bounds(wheel)
	wheel_mid = (low + high) * 0.5
	transform(wheel, to_kit @ Matrix.Translation((-wheel_mid.x, 0.0, -body_center.z)))
	low, high = bounds(wheel)
	parts.append(("wheel", wheel, (low + high) * 0.5, True))
	parts.append(("head", head, head_center, False))
	parts.append(("antenna", antenna, antenna_pivot, False))
	parts.append(("torso", torso, torso_center, False))
	for name, part, pivot, axle_up in parts:
		write_part(name, part, pivot, axle_up)
	bm.free()

	bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", export_image_format="NONE", export_materials="NONE",
			export_yup=True, export_apply=False, export_animations=False, use_selection=False)


main()
