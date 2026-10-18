"""Clayify asset pipeline (GDD 19.4), run by Blender in the background:

    Blender -b --factory-startup --python-exit-code 1 -P tools/clayify/clayify.py -- tools/clayify/manifest.json <source root> <output root>

For each manifest entry it imports the source model (FBX / glTF / OBJ), bakes every face's material color
(or its texture color at the face's UVs) into a vertex color, recolors material names to the farm
palette, applies transforms, welds vertices, bevels hard edges, optionally subdivides, decimates and
displaces the surface, checks an explicit triangle budget, shades smooth, moves the origin to the
bottom center and exports a single-mesh glTF binary. In Godot the clay shader reads that vertex
color (Clay.vertex_colored()), so one material serves every model.
"""

import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_linear(value: str) -> tuple:
    value = value.lstrip("#")
    return tuple(srgb_to_linear(int(value[i:i + 2], 16) / 255.0) for i in (0, 2, 4)) + (1.0,)


def import_model(path: str) -> None:
    ext = os.path.splitext(path)[1].lower()
    if ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        raise ValueError("Unsupported model: " + path)


def material_color(material, palette: dict):
    """Returns (flat linear RGBA or None, image or None) for a material."""
    if material is None:
        return (1.0, 1.0, 1.0, 1.0), None
    if material.name in palette:
        return hex_to_linear(palette[material.name]), None
    for prefix, color in palette.items():
        if material.name.startswith(prefix):
            return hex_to_linear(color), None
    if material.use_nodes:
        bsdf = next((n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is not None:
            base = bsdf.inputs["Base Color"]
            if base.is_linked and base.links[0].from_node.type == "TEX_IMAGE":
                return None, base.links[0].from_node.image
            return tuple(base.default_value), None
    return tuple(material.diffuse_color), None


def sample_image(image, uv, cache: dict) -> tuple:
    if image.name not in cache:
        cache[image.name] = (image.size[0], image.size[1], list(image.pixels[:]))
    w, h, px = cache[image.name]
    x = min(w - 1, max(0, int((uv.x % 1.0) * w)))
    y = min(h - 1, max(0, int((uv.y % 1.0) * h)))
    i = (y * w + x) * 4
    # Image pixels are stored linear for sRGB images, which is what glTF COLOR_0 wants.
    return (px[i], px[i + 1], px[i + 2], 1.0)


def bake_vertex_colors(obj, palette: dict, cache: dict, tint: tuple) -> None:
    mesh = obj.data
    attr = mesh.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
    uv_layer = mesh.uv_layers.active
    looks = [material_color(slot.material, palette) for slot in obj.material_slots] or [((1.0, 1.0, 1.0, 1.0), None)]
    for poly in mesh.polygons:
        flat, image = looks[min(poly.material_index, len(looks) - 1)]
        if image is not None and uv_layer is not None:
            center = Vector((0.0, 0.0))
            for li in poly.loop_indices:
                center += uv_layer.data[li].uv
            color = sample_image(image, center / len(poly.loop_indices), cache)
        else:
            color = flat or (1.0, 1.0, 1.0, 1.0)
        color = tuple(color[i] * tint[i] for i in range(3)) + (1.0,)
        for li in poly.loop_indices:
            attr.data[li].color = color
    mesh.color_attributes.active_color = attr


def fit_to_gameplay(obj, fit: dict) -> None:
    """Stretches the model onto the building's gameplay dimensions so its visible walls, eaves, decks and
    roofs line up with the collision the farm builder authors. "size" is the footprint [x, z] in Godot
    meters; "height_keys" maps model heights to gameplay heights piecewise linearly, so e.g. a water
    tower's deck and tank top can both land exactly where the colliders are."""
    dims = obj.dimensions.copy()
    sx = fit["size"][0] / dims.x if fit["size"][0] > 0.0 else 1.0
    sy = fit["size"][1] / dims.y if fit["size"][1] > 0.0 else 1.0
    keys = sorted(fit.get("height_keys", [[0.0, 0.0], [dims.z, dims.z]]))
    for v in obj.data.vertices:
        z = v.co.z
        for (z0, d0), (z1, d1) in zip(keys, keys[1:]):
            if z <= z1 or (z1, d1) == keys[-1]:
                t = (z - z0) / (z1 - z0) if z1 != z0 else 0.0
                z = d0 + (d1 - d0) * t
                break
        v.co.x *= sx
        v.co.y *= sy
        v.co.z = z
    obj.data.update()


def triangle_count(obj) -> int:
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def _lattice(x: int, y: int, z: int, seed: int) -> float:
    value = (x * 73856093) ^ (y * 19349663) ^ (z * 83492791) ^ (seed * 2654435761)
    value &= 0xFFFFFFFF
    value ^= value >> 13
    value = (value * 1274126177) & 0xFFFFFFFF
    return value / 0xFFFFFFFF * 2.0 - 1.0


def _value_noise(x: float, y: float, z: float, seed: int) -> float:
    ix, iy, iz = math.floor(x), math.floor(y), math.floor(z)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = (f * f * (3.0 - 2.0 * f) for f in (fx, fy, fz))

    def lerp(a: float, b: float, t: float) -> float:
        return a + (b - a) * t

    planes = []
    for dz in (0, 1):
        rows = []
        for dy in (0, 1):
            rows.append(lerp(_lattice(ix, iy + dy, iz + dz, seed),
                             _lattice(ix + 1, iy + dy, iz + dz, seed), fx))
        planes.append(lerp(rows[0], rows[1], fy))
    return lerp(planes[0], planes[1], fz)


def displace_clay(obj, settings: dict) -> None:
    """Continuous, repeatable vector displacement avoids seams at split normals."""
    strength = float(settings.get("strength", 0.0))
    scale = float(settings.get("scale", 0.0))
    if strength <= 0.0 or scale <= 0.0:
        raise ValueError("displace strength and scale must be positive")
    seed = int(settings.get("seed", 17))
    for vertex in obj.data.vertices:
        x, y, z = (coord / scale for coord in vertex.co)
        vertex.co += Vector((
            _value_noise(x, y, z, seed),
            _value_noise(x, y, z, seed + 37),
            _value_noise(x, y, z, seed + 89),
        )) * strength
    obj.data.update()


def process(entry: dict, src_root: str, out_root: str) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    import_model(os.path.join(src_root, entry["src"]))
    palette = entry.get("palette", {})
    cache: dict = {}
    tint = hex_to_linear(entry["tint"]) if "tint" in entry else (1.0, 1.0, 1.0, 1.0)
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for obj in meshes:
        bake_vertex_colors(obj, palette, cache, tint)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    # Drop parents (FBX empties) but keep the world placement, then bake it into the vertices.
    world = obj.matrix_world.copy()
    obj.parent = None
    obj.matrix_world = world
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in list(bpy.context.scene.objects):
        if o != obj:
            bpy.data.objects.remove(o, do_unlink=True)

    obj.data.materials.clear()
    material = bpy.data.materials.new("clay")
    obj.data.materials.append(material)

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=entry.get("weld", 0.0005))
    bm.to_mesh(obj.data)
    bm.free()

    dims = obj.dimensions
    bevel = entry.get("bevel", 0.006)
    if bevel > 0.0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel * max(dims)
        mod.segments = entry.get("bevel_segments", 2)
        mod.limit_method = "ANGLE"
        mod.angle_limit = 0.6
        mod.use_clamp_overlap = True
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if entry.get("subdivide", 0) > 0:
        mod = obj.modifiers.new("Subsurf", "SUBSURF")
        mod.levels = entry["subdivide"]
        mod.render_levels = entry["subdivide"]
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if entry.get("decimate", 1.0) < 1.0:
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = entry["decimate"]
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if "displace" in entry:
        displace_clay(obj, entry["displace"])
    max_tris = entry.get("max_tris")
    tris = 0
    if max_tris is not None:
        tris = triangle_count(obj)
        if tris > max_tris:
            raise ValueError("%s has %d triangles (budget %d)" % (entry["out"], tris, max_tris))
    bpy.ops.object.shade_smooth()

    # Origin at the bottom center of the bounds, so placement in Godot is just "stand it here".
    corners = [Vector(c) for c in obj.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    offset = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    obj.data.transform(__import__("mathutils").Matrix.Translation(-offset))
    if "fit" in entry:
        fit_to_gameplay(obj, entry["fit"])
    obj.name = os.path.splitext(os.path.basename(entry["out"]))[0]

    out_path = os.path.join(out_root, entry["out"])
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", use_selection=False, export_apply=True,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False, export_normals=True,
        export_texcoords=True, export_materials="PLACEHOLDER", export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False)
    if max_tris is None:
        tris = triangle_count(obj)
    print("CLAYIFY %s  tris=%d  size=(%.2f, %.2f, %.2f)" % (
        entry["out"], tris, obj.dimensions.x, obj.dimensions.z, obj.dimensions.y))


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:]
    manifest_path, src_root, out_root = args[0], args[1], args[2]
    only = set(args[3:])
    with open(manifest_path) as f:
        manifest = json.load(f)
    palettes = manifest.get("palettes", {})
    for entry in manifest["models"]:
        if only and entry["out"] not in only:
            continue
        palette = dict(palettes.get(entry.get("palette_set", ""), {}))
        palette.update(entry.get("palette", {}))
        entry["palette"] = palette
        process(entry, src_root, out_root)


main()
