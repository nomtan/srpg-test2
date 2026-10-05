"""Builds the Ashen Vow Phase 2 vegetation assets in Blender and exports them for Godot.

Run from the repository root (Blender 5.1+):

    blender -b --factory-startup --python tools/vegetation/build_vegetation_assets.py -- [asset ...]

With no asset names every known asset is rebuilt. The same bpy code can be pasted into a
Blender MCP session; running it headless keeps the result reproducible.

Outputs
    assets/environment/vegetation/<group>/<asset>.glb   (Godot runtime source)
    source/environment/vegetation/<asset>.blend         (editable Blender scene)

Conventions shared with Godot (scripts/world_jrpg/open_field_vegetation.gd)
    * Blender Z-up meters, exported Y-up; Godot scale 1.0.
    * Origin at the trunk / cluster bottom center.
    * Trees hold one object per LOD: <asset>_LOD0 .. _LOD2, plus a very low _LOD3;
      bushes hold _LOD0 .. _LOD2; grass and flower clusters are a single object.
    * Material slots: "Trunk" + "Leaves" for trees and bushes, "Grass" for grass,
      "Grass" + "Flower" for flower clusters.
    * Vertex color "Color" (float, linear) carries data, not albedo:
        R = tone   0 shadow / 0.5 base / 1 highlight
        G = wind weight   0 at the root, 1 at the freest tip
        B = phase   per foliage mass / per blade, desynchronizes the wind
        A = petal palette on flower heads (1 warm, 0 cool); 1 elsewhere
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSET_DIR = os.path.join(ROOT, "assets", "environment", "vegetation")
SOURCE_DIR = os.path.join(ROOT, "source", "environment", "vegetation")
UP = Vector((0.0, 0.0, 1.0))


# --- Mesh assembly ------------------------------------------------------------------

class MeshBuilder:
    """Accumulates vertices with per-vertex normal and data color, then emits one object."""

    def __init__(self):
        self.verts = []
        self.normals = []
        self.colors = []
        self.faces = []
        self.face_materials = []

    def vertex(self, co, normal, tone, wind, phase, alpha=1.0):
        self.verts.append(Vector(co))
        self.normals.append(Vector(normal).normalized())
        self.colors.append((clamp01(tone), clamp01(wind), clamp01(phase), alpha))
        return len(self.verts) - 1

    def face(self, indices, material):
        self.faces.append(tuple(indices))
        self.face_materials.append(material)

    def triangles(self):
        return sum(len(f) - 2 for f in self.faces)

    def build(self, name, materials):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        for material in materials:
            mesh.materials.append(material)
        for polygon, material in zip(mesh.polygons, self.face_materials):
            polygon.material_index = material
            polygon.use_smooth = True
        attribute = mesh.color_attributes.new("Color", "FLOAT_COLOR", "POINT")
        for i, color in enumerate(self.colors):
            attribute.data[i].color = color
        mesh.color_attributes.active_color = attribute
        mesh.validate(clean_customdata=False)
        mesh.normals_split_custom_set_from_vertices([tuple(n) for n in self.normals])
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def clamp01(x):
    return max(0.0, min(1.0, x))


def smoothstep(a, b, x):
    t = clamp01((x - a) / (b - a))
    return t * t * (3.0 - 2.0 * t)


def perpendicular(direction):
    helper = Vector((1.0, 0.0, 0.0)) if abs(direction.z) > 0.9 else UP
    return direction.cross(helper).normalized()


def tube(mb, points, sides, material, tone_range, wind_range, phase, flare=0.0, close_tip=True):
    """Tapered tube through [(position, radius)] with parallel-transported rings.

    flare widens the first ring into root buttresses (trunk base only)."""
    count = len(points)
    rings = []
    side = None
    for i, (p, r) in enumerate(points):
        p = Vector(p)
        ahead = Vector(points[min(i + 1, count - 1)][0]) - Vector(points[max(i - 1, 0)][0])
        direction = ahead.normalized()
        if side is None:
            side = perpendicular(direction)
        else:
            side = (side - direction * side.dot(direction)).normalized()
        other = direction.cross(side).normalized()
        t = i / (count - 1)
        ring = []
        for s in range(sides):
            angle = s / sides * math.tau
            radial = side * math.cos(angle) + other * math.sin(angle)
            radius = r
            if flare > 0.0 and i == 0:
                radius *= 1.0 + flare * max(0.0, math.cos(angle * 2.0 + 0.6)) ** 2
            tone = tone_range[0] + (tone_range[1] - tone_range[0]) * t + 0.08 * math.cos(angle)
            wind = wind_range[0] + (wind_range[1] - wind_range[0]) * t
            ring.append(mb.vertex(p + radial * radius, radial, tone, wind, phase))
        rings.append(ring)
    for i in range(count - 1):
        a, b = rings[i], rings[i + 1]
        for s in range(sides):
            n = (s + 1) % sides
            mb.face((a[s], a[n], b[n], b[s]), material)
    if close_tip:
        p_last, _ = points[-1]
        direction = (Vector(p_last) - Vector(points[-2][0])).normalized()
        tip = mb.vertex(Vector(p_last) + direction * points[-1][1] * 1.5, direction, tone_range[1], wind_range[1], phase)
        last = rings[-1]
        for s in range(sides):
            mb.face((last[s], last[(s + 1) % sides], tip), material)


def curve(start, direction, length, rise, steps):
    """Points on a gently up-curving limb (quadratic Bezier)."""
    start = Vector(start)
    direction = Vector(direction).normalized()
    middle = start + direction * length * 0.55
    end = start + direction * length + UP * length * rise
    result = []
    for i in range(steps + 1):
        t = i / steps
        result.append((1 - t) ** 2 * start + 2 * (1 - t) * t * middle + t * t * end)
    return result


# --- Foliage masses ------------------------------------------------------------------

_SPHERES = {}


def unit_sphere(subdivisions):
    """Icosphere vertices and triangles (cached). Blender counts the bare icosahedron as
    subdivision 1: 1 -> 20, 2 -> 80, 3 -> 320 triangles."""
    if subdivisions not in _SPHERES:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1.0)
        verts = [v.co.copy() for v in bm.verts]
        faces = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        _SPHERES[subdivisions] = (verts, faces)
    return _SPHERES[subdivisions]


class Mass:
    """One foliage clump: an irregular, flat-bottomed, lobed volume.

    The shape is decided once (seeded) so every LOD rebuilds the same silhouette."""

    def __init__(self, center, radius, height, seed, tone_bias=0.0, tilt=0.0):
        self.center = Vector(center)
        self.radius = radius
        self.height = height
        self.seed = seed
        self.tone_bias = tone_bias
        rng = random.Random(seed)
        self.offset = Vector((rng.uniform(-50, 50), rng.uniform(-50, 50), rng.uniform(-50, 50)))
        self.lobes = []
        for _ in range(rng.randint(4, 6)):
            d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1.0))).normalized()
            self.lobes.append((d, rng.uniform(0.22, 0.4)))
        self.stretch = rng.uniform(0.85, 1.1)
        self.rotation = Matrix.Rotation(rng.uniform(0, math.tau), 3, "Z") @ Matrix.Rotation(tilt, 3, "X")
        self.phase = rng.random()

    def surface(self, d):
        """Displaced local point for unit direction d (before rotation / translation)."""
        r = 1.0 + 0.2 * noise.noise(d * 1.4 + self.offset) + 0.07 * noise.noise(d * 3.5 - self.offset)
        for lobe, amount in self.lobes:
            r += amount * max(0.0, d.dot(lobe)) ** 4
        z = d.z
        # Stylized foliage: a lumpy dome on top and a flattened underside.
        if z < -0.35:
            z = -0.35 + (z + 0.35) * 0.45
        return Vector((d.x * r * self.radius, d.y * r * self.radius * self.stretch, z * r * self.height))

    def emit(self, mb, material, subdivisions, crown_center, crown_half, trunk_reach, scale=1.0, wind_scale=1.0):
        verts, faces = unit_sphere(subdivisions)
        indices = []
        for d in verts:
            local = self.rotation @ (self.surface(d) * scale)
            p = self.center + local
            # Normal blends the clump's own bulge with the whole crown's: soft, cohesive shading.
            own = (self.rotation @ Vector((d.x / self.radius, d.y / (self.radius * self.stretch), d.z / self.height))).normalized()
            whole = Vector(((p.x - crown_center.x) / crown_half.x, (p.y - crown_center.y) / crown_half.x, (p.z - crown_center.z) / crown_half.z)).normalized()
            normal = (own * 0.55 + whole * 0.45).normalized()
            height01 = clamp01((p.z - (crown_center.z - crown_half.z)) / (2.0 * crown_half.z))
            outer = clamp01(Vector((p.x - crown_center.x, p.y - crown_center.y, (p.z - crown_center.z) * 1.4)).length / max(crown_half.x, crown_half.z))
            tone = 0.12 + 0.42 * height01 + 0.22 * max(0.0, normal.z) + 0.22 * outer - 0.3 * max(0.0, -normal.z) + self.tone_bias
            reach = Vector((p.x, p.y, 0.0)).length
            wind = (0.35 + 0.45 * clamp01(reach / trunk_reach) + 0.2 * height01) * wind_scale
            indices.append(mb.vertex(p, normal, tone, wind, self.phase))
        for f in faces:
            mb.face(tuple(indices[i] for i in f), material)


# --- Trees -----------------------------------------------------------------------------

class TreeDesign:
    """Trunk, primary and secondary limbs and foliage masses, resolved once from a seed."""

    def __init__(self):
        self.trunk = []          # [(point, radius)]
        self.limbs = []          # [(points, r0, r1, wind0, wind1, level)]
        self.masses = []         # [(Mass, keep)]  keep = coarsest LOD that still has it
        self.crown_center = Vector()
        self.crown_half = Vector((1, 1, 1))
        self.reach = 1.0
        self.height = 0.0
        self.trunk_radius = 0.3
        self.wind_scale = 1.0    # bushes sway less than tree crowns
        self.trunk_flare = (0.55, 0.3)   # root buttresses: LOD0-1, LOD2+


def design_broadleaf_a():
    """Broadleaf A: ~7.5 m. A short, gently S-bent trunk forks at 2-3 m into five rising
    primary limbs, each with one secondary. The crown is one large top mass, five medium
    masses on the primary tips, five small accent masses on the secondary tips and two
    shadowed fill masses inside, leaving gaps where the limbs show through."""
    rng = random.Random(20261005)
    tree = TreeDesign()
    lean = Vector((1.0, 0.35, 0.0))
    trunk_path = [(0.0, -0.35), (0.0, 0.0), (0.05, 0.8), (0.14, 1.6), (0.18, 2.3), (0.12, 3.1), (0.02, 3.9), (-0.06, 4.7)]
    radii = [0.42, 0.4, 0.31, 0.27, 0.24, 0.19, 0.14, 0.09]
    for (bend, z), r in zip(trunk_path, radii):
        tree.trunk.append((Vector((lean.x * bend, lean.y * bend, z)), r))
    tree.trunk_radius = 0.34

    def trunk_at(z):
        for (a, ra), (b, rb) in zip(tree.trunk, tree.trunk[1:]):
            if a.z <= z <= b.z:
                t = (z - a.z) / (b.z - a.z)
                return a.lerp(b, t), ra + (rb - ra) * t
        return tree.trunk[-1]

    golden = math.radians(137.5)
    heading = rng.uniform(0, math.tau)
    tips = []
    for i in range(5):
        z = 2.05 + i * 0.36 + rng.uniform(-0.08, 0.08)
        heading += golden + rng.uniform(-0.25, 0.25)
        pitch = math.radians(rng.uniform(28, 38) + i * 4.0)
        direction = Vector((math.cos(heading) * math.cos(pitch), math.sin(heading) * math.cos(pitch), math.sin(pitch)))
        start, r_here = trunk_at(z)
        length = rng.uniform(2.1, 2.5) - i * 0.15
        points = curve(start, direction, length, 0.22, 5)
        tree.limbs.append((points, r_here * 0.6, 0.05, 0.04, 0.28, 1))
        tips.append((points[-1], direction))
        # One secondary limb per primary, leaving 60 % along it and turning outward.
        fork = points[3]
        side = Vector((-direction.y, direction.x, 0.0)) * (1 if i % 2 else -1)
        sub_dir = (direction * 0.6 + side * 0.7 + UP * 0.2).normalized()
        sub = curve(fork, sub_dir, rng.uniform(1.0, 1.3), 0.25, 3)
        tree.limbs.append((sub, 0.075, 0.03, 0.2, 0.42, 2))
        tips.append((sub[-1], sub_dir))

    top = tree.trunk[-1][0]
    tree.masses.append((Mass(top + Vector((0.1, 0.0, 1.0)), 2.0, 1.55, 11, tone_bias=0.06), 3))
    # Interior fill: keeps the crown from reading as separate puffs on sticks.
    for k, angle in enumerate((0.6, 3.6)):
        offset = Vector((math.cos(angle), math.sin(angle), 0.0)) * 0.9
        tree.masses.append((Mass(top + offset + Vector((0, 0, -0.25)), 1.45, 1.15, 31 + k, tone_bias=-0.1), 3))
    for i, (tip, direction) in enumerate(tips):
        flat = Vector((direction.x, direction.y, 0)).normalized()
        if i % 2 == 0:
            center = tip + flat * 0.15 + UP * 0.4
            mass = Mass(center, rng.uniform(1.2, 1.45), rng.uniform(1.0, 1.15), 100 + i, tilt=rng.uniform(-0.15, 0.15))
            tree.masses.append((mass, 3))
        else:
            center = tip + UP * 0.25
            mass = Mass(center, rng.uniform(0.7, 0.9), rng.uniform(0.6, 0.72), 200 + i, tone_bias=-0.03, tilt=rng.uniform(-0.25, 0.25))
            tree.masses.append((mass, 1))
    _measure_crown(tree)
    return tree


def _measure_crown(tree):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for mass, _ in tree.masses:
        for axis, extent in ((0, mass.radius * 1.3), (1, mass.radius * 1.3), (2, mass.height * 1.3)):
            lo[axis] = min(lo[axis], mass.center[axis] - extent)
            hi[axis] = max(hi[axis], mass.center[axis] + extent)
    tree.crown_center = (lo + hi) * 0.5
    tree.crown_half = Vector(((hi.x - lo.x + hi.y - lo.y) * 0.25, 0.0, (hi.z - lo.z) * 0.5))
    tree.reach = max((Vector((m.center.x, m.center.y, 0)).length + m.radius) for m, _ in tree.masses)
    tree.height = hi.z


def _trunk_at(tree, z):
    for (a, ra), (b, rb) in zip(tree.trunk, tree.trunk[1:]):
        if a.z <= z <= b.z:
            t = (z - a.z) / (b.z - a.z)
            return a.lerp(b, t), ra + (rb - ra) * t
    return tree.trunk[-1]


def design_spreading(p):
    """Broadleaf B / C and the oaks: Broadleaf A's structure (bent trunk, primary limbs on
    a golden-angle spiral, one or two secondaries each, masses on the limb tips plus top
    and fill masses) driven by a parameter set, so each species reads by silhouette:

        trunk         [(bend, z, radius)] along `lean`
        primaries     count, fork height / step, pitch (deg) + step, length + step, rise
        override      {index: {pitch, length, radius, tip_scale}} for co-dominant stems or
                      a landmark limb
        top, fill     explicit crown masses (offset from the trunk top)
        tip, accent   mass size ranges on primary / secondary tips (+ lift)"""
    rng = random.Random(p["seed"])
    tree = TreeDesign()
    lean = Vector(p["lean"])
    for bend, z, r in p["trunk"]:
        tree.trunk.append((Vector((lean.x * bend, lean.y * bend, z)), r))
    tree.trunk_radius = p["trunk_radius"]
    flare = p.get("flare", 0.55)
    tree.trunk_flare = (flare, flare * 0.55)
    golden = math.radians(137.5)
    heading = rng.uniform(0, math.tau)
    tips = []
    for i in range(p["primaries"]):
        o = p.get("override", {}).get(i, {})
        z = p["fork_z"] + i * p["fork_step"] + rng.uniform(-0.08, 0.08)
        heading += golden + rng.uniform(-0.25, 0.25)
        pitch = math.radians(o.get("pitch", rng.uniform(*p["pitch"]) + i * p["pitch_step"]))
        direction = Vector((math.cos(heading) * math.cos(pitch), math.sin(heading) * math.cos(pitch), math.sin(pitch)))
        start, r_here = _trunk_at(tree, z)
        length = o.get("length", rng.uniform(*p["length"]) - i * p["length_step"])
        points = curve(start, direction, length, p["rise"], 5)
        tree.limbs.append((points, r_here * o.get("radius", p["limb_radius"]), p["limb_tip"], 0.04, 0.28, 1))
        tips.append((points[-1], direction, True, o.get("tip_scale", 1.0)))
        for k in range(p["secondaries"]):
            fork = points[3 - k]
            side = Vector((-direction.y, direction.x, 0.0)) * (1 if (i + k) % 2 else -1)
            sub_dir = (direction * 0.6 + side * 0.7 + UP * p["sub_rise"]).normalized()
            sub = curve(fork, sub_dir, rng.uniform(*p["sub_length"]), 0.25, 3)
            tree.limbs.append((sub, p["sub_radius"], 0.03, 0.2, 0.42, 2))
            tips.append((sub[-1], sub_dir, False, 1.0))
    top = tree.trunk[-1][0]
    for k, (offset, radius, height, bias) in enumerate(p["top"]):
        tree.masses.append((Mass(top + Vector(offset), radius, height, p["seed"] % 997 + 11 + k, tone_bias=bias), 3))
    count, radius, height, dist, dz = p["fill"]
    for k in range(count):
        angle = 0.6 + k * math.tau / count
        offset = Vector((math.cos(angle), math.sin(angle), 0.0)) * dist + Vector((0, 0, dz))
        tree.masses.append((Mass(top + offset, radius, height, p["seed"] % 997 + 31 + k, tone_bias=-0.1), 3))
    r0, r1, h0, h1, lift = p["tip"]
    a0, a1, b0, b1, alift = p["accent"]
    for i, (tip, direction, primary, tip_scale) in enumerate(tips):
        flat = Vector((direction.x, direction.y, 0)).normalized()
        if primary:
            mass = Mass(tip + flat * 0.15 + UP * lift, rng.uniform(r0, r1) * tip_scale, rng.uniform(h0, h1) * tip_scale,
                        p["seed"] % 997 + 100 + i, tone_bias=p.get("tip_bias", 0.0), tilt=rng.uniform(-0.15, 0.15))
            tree.masses.append((mass, 3))
        else:
            mass = Mass(tip + UP * alift, rng.uniform(a0, a1), rng.uniform(b0, b1), p["seed"] % 997 + 200 + i,
                        tone_bias=-0.03, tilt=rng.uniform(-0.25, 0.25))
            tree.masses.append((mass, 1))
    _measure_crown(tree)
    return tree


BROADLEAF_B = {
    # Tall and slender: a straight trunk forking high into steep limbs; an upright oval
    # crown in two tiers (a second top mass above the main one).
    "seed": 20261011, "lean": (0.3, -1.0, 0.0), "trunk_radius": 0.3,
    "trunk": [(0.0, -0.35, 0.38), (0.0, 0.0, 0.36), (0.03, 1.0, 0.28), (0.06, 2.0, 0.24), (0.05, 3.0, 0.2),
              (0.02, 4.0, 0.15), (-0.02, 5.0, 0.1)],
    "primaries": 5, "fork_z": 2.6, "fork_step": 0.5, "pitch": (50, 58), "pitch_step": 2.5,
    "length": (1.7, 2.0), "length_step": 0.08, "rise": 0.3, "limb_radius": 0.6, "limb_tip": 0.045,
    "secondaries": 1, "sub_rise": 0.45, "sub_length": (0.8, 1.05), "sub_radius": 0.065,
    "top": [((0.05, 0.0, 0.7), 1.55, 1.45, 0.04), ((0.25, -0.1, 2.0), 1.05, 0.95, 0.1)],
    "fill": (2, 1.25, 1.15, 0.75, -0.6),
    "tip": (0.95, 1.15, 0.95, 1.15, 0.45), "accent": (0.6, 0.75, 0.55, 0.68, 0.25),
}

BROADLEAF_C = {
    # Short, leaning and wide: the trunk splits low into a co-dominant stem and five
    # outreaching limbs, leaving a broad, lopsided crown heavier on the lean side.
    "seed": 20261017, "lean": (-1.0, 0.45, 0.0), "trunk_radius": 0.34,
    "trunk": [(0.0, -0.35, 0.44), (0.0, 0.0, 0.42), (0.12, 0.7, 0.33), (0.32, 1.4, 0.29), (0.52, 2.1, 0.24),
              (0.66, 2.8, 0.18), (0.72, 3.4, 0.12)],
    "primaries": 6, "fork_z": 1.6, "fork_step": 0.32, "pitch": (22, 32), "pitch_step": 3.0,
    "length": (2.3, 2.7), "length_step": 0.1, "rise": 0.28, "limb_radius": 0.6, "limb_tip": 0.05,
    "override": {0: {"pitch": 60, "length": 2.6, "radius": 0.85, "tip_scale": 1.15}},
    "secondaries": 1, "sub_rise": 0.2, "sub_length": (1.0, 1.3), "sub_radius": 0.07,
    "top": [((-0.3, 0.1, 0.85), 2.15, 1.2, 0.06)],
    "fill": (2, 1.5, 0.95, 1.1, -0.3),
    "tip": (1.15, 1.35, 0.8, 0.95, 0.35), "accent": (0.65, 0.85, 0.5, 0.62, 0.2),
}

OAK_A = {
    # Oak: a thick, short trunk and heavy limbs that leave it almost level, rising only at
    # the tips; the crown starts low and spreads wide in flattened masses.
    "seed": 20261023, "lean": (1.0, 0.2, 0.0), "trunk_radius": 0.55, "flare": 0.75,
    "trunk": [(0.0, -0.35, 0.72), (0.0, 0.0, 0.68), (0.04, 0.9, 0.55), (0.1, 1.8, 0.48), (0.12, 2.6, 0.4),
              (0.08, 3.3, 0.3), (0.02, 3.9, 0.2)],
    "primaries": 6, "fork_z": 1.85, "fork_step": 0.3, "pitch": (8, 16), "pitch_step": 3.5,
    "length": (3.3, 3.8), "length_step": 0.12, "rise": 0.42, "limb_radius": 0.6, "limb_tip": 0.07,
    "secondaries": 1, "sub_rise": 0.25, "sub_length": (1.3, 1.7), "sub_radius": 0.11,
    "top": [((0.0, 0.0, 0.75), 2.5, 1.3, 0.05)],
    "fill": (2, 1.8, 1.0, 1.5, -0.35),
    "tip": (1.45, 1.75, 0.85, 1.0, 0.4), "accent": (0.9, 1.1, 0.6, 0.72, 0.3), "tip_bias": -0.02,
}

OAK_B = {
    # Landmark oak: one long limb sweeps out low to one side and the crown follows it, so
    # the silhouette is asymmetric and recognisable on a hill top or by a ruin.
    "seed": 20261029, "lean": (-0.5, -1.0, 0.0), "trunk_radius": 0.6, "flare": 0.8,
    "trunk": [(0.0, -0.35, 0.78), (0.0, 0.0, 0.74), (0.06, 0.9, 0.6), (0.16, 1.8, 0.52), (0.2, 2.6, 0.43),
              (0.15, 3.4, 0.32), (0.06, 4.1, 0.2)],
    "primaries": 5, "fork_z": 2.0, "fork_step": 0.36, "pitch": (12, 20), "pitch_step": 4.0,
    "length": (3.2, 3.6), "length_step": 0.1, "rise": 0.4, "limb_radius": 0.6, "limb_tip": 0.07,
    "override": {0: {"pitch": 3, "length": 4.8, "radius": 0.7, "tip_scale": 1.1}},
    "secondaries": 1, "sub_rise": 0.25, "sub_length": (1.4, 1.8), "sub_radius": 0.1,
    "top": [((0.2, 0.0, 0.9), 2.4, 1.4, 0.06)],
    "fill": (2, 1.75, 1.05, 1.45, -0.35),
    "tip": (1.5, 1.8, 0.85, 1.0, 0.4), "accent": (0.95, 1.15, 0.6, 0.72, 0.3), "tip_bias": -0.02,
}


# --- Conifers --------------------------------------------------------------------------------

class Tier:
    """One conifer branch whorl: a flat-topped skirt whose rim breaks into drooping branch
    tips (lobes), with a shadowed underside. Stacked tiers read as steps, not stacked cones.
    Duck-typed with Mass so build_tree and the LOD table treat both alike."""

    def __init__(self, center, radius, height, seed, lobes, tone_bias=0.0):
        self.center = Vector(center)
        self.radius = radius
        self.height = height
        self.tone_bias = tone_bias
        rng = random.Random(seed)
        self.lobes = lobes
        self.lobe_phase = rng.uniform(0, math.tau)
        self.lobe_amp = rng.uniform(0.3, 0.42)
        self.bias_dir = rng.uniform(0, math.tau)
        self.bias = rng.uniform(0.1, 0.22)
        self.offset = rng.uniform(-50, 50)
        self.phase = rng.random()

    def rim(self, a):
        """Rim radius and lobe (0 notch .. 1 branch tip) at angle a."""
        lobe = abs(math.cos((a + self.lobe_phase) * self.lobes * 0.5)) ** 0.6
        r = self.radius * (1.0 - self.lobe_amp * (1.0 - lobe))
        r *= 1.0 + self.bias * math.cos(a - self.bias_dir)
        r *= 1.0 + 0.1 * noise.noise(Vector((math.cos(a) * 1.3, math.sin(a) * 1.3, self.offset)))
        return r, lobe

    def emit(self, mb, material, subdivisions, crown_center, crown_half, trunk_reach, scale=1.0, wind_scale=1.0):
        segments, top_rows, under_rows = {3: (28, (0.3, 0.62, 0.86, 1.0), (0.78, 0.4)),
                                          2: (16, (0.45, 0.8, 1.0), (0.5,)),
                                          1: (8, (0.55, 1.0), ()),
                                          0: (6, (1.0,), ())}[subdivisions]
        top = self.center.z + self.height * 0.5
        h = self.height
        rims = [self.rim(s / segments * math.tau) for s in range(segments)]

        def height01(z):
            return clamp01((z - (crown_center.z - crown_half.z)) / (2.0 * crown_half.z))

        def ring(v, under):
            out = []
            for s in range(segments):
                a = s / segments * math.tau
                radial = Vector((math.cos(a), math.sin(a), 0.0))
                r, lobe = rims[s]
                p = self.center + radial * r * scale * v
                # Branch tips droop below the notches between them.
                droop = 0.28 * h * lobe * v * v
                if under:
                    p.z = top - h * (0.45 + 0.55 * v) - droop
                    normal = (radial * 0.45 - UP * 0.9).normalized()
                    tone = 0.04 + 0.1 * v + self.tone_bias * 0.5
                else:
                    p.z = top - h * (0.45 * v + 0.55 * v * v) - droop
                    normal = (radial * (0.35 + 0.5 * v) + UP * (1.0 - 0.35 * v)).normalized()
                    tone = 0.2 + 0.32 * v + 0.38 * height01(p.z) + 0.1 * lobe + self.tone_bias
                whole = Vector(((p.x - crown_center.x) / crown_half.x, (p.y - crown_center.y) / crown_half.x, (p.z - crown_center.z) / crown_half.z)).normalized()
                normal = (normal * 0.65 + whole * 0.35).normalized()
                wind = (0.3 + 0.6 * v + 0.1 * height01(p.z)) * wind_scale
                out.append(mb.vertex(p, normal, tone, wind, self.phase))
            return out

        apex = mb.vertex(Vector((self.center.x, self.center.y, top)), UP, 0.35 + 0.4 * height01(top) + self.tone_bias, 0.3 * wind_scale, self.phase)
        rows = [ring(v, False) for v in top_rows]
        rows += [ring(v, True) for v in under_rows]
        bottom = mb.vertex(Vector((self.center.x, self.center.y, top - h * 0.45)), -UP, 0.02, 0.3 * wind_scale, self.phase)
        for s in range(segments):
            n = (s + 1) % segments
            mb.face((apex, rows[0][s], rows[0][n]), material)
            for a, b in zip(rows, rows[1:]):
                mb.face((a[s], b[s], b[n], a[n]), material)
            mb.face((rows[-1][s], bottom, rows[-1][n]), material)


def design_conifer(p):
    """A straight trunk carrying `tiers` whorls whose radius shrinks toward a narrow spire.
    Tier centers drift along `lean` with height and each whorl has its own lobe phase and
    lopsided bias, so the outline steps irregularly instead of forming a clean cone."""
    rng = random.Random(p["seed"])
    tree = TreeDesign()
    lean = Vector(p["lean"]).normalized()
    top_z = p["height"]
    steps = 6
    for i in range(steps + 1):
        t = i / steps
        z = -0.35 + (top_z - 0.5 + 0.35) * t
        tree.trunk.append((lean * (p["bend"] * t * t) + Vector((0, 0, z)), p["trunk_radius"] * (1.0 - 0.85 * t) + 0.03))
    tree.trunk_radius = p["trunk_radius"]
    tree.trunk_flare = (0.4, 0.2)
    count = p["tiers"]
    for i in range(count):
        t = i / (count - 1)
        z = p["first_tier"] + (top_z - p["first_tier"] - 0.9) * (t ** p["spacing"])
        center, _ = _trunk_at(tree, min(z, tree.trunk[-1][0].z))
        center = Vector((center.x + rng.uniform(-0.12, 0.12), center.y + rng.uniform(-0.12, 0.12), z))
        radius = (p["base_radius"] * (1.0 - t) + p["top_radius"] * t) * rng.uniform(0.84, 1.12) * p.get("scale_tier", {}).get(i, 1.0)
        height = (p["base_drop"] * (1.0 - t) + p["top_drop"] * t) * rng.uniform(0.92, 1.08)
        tree.masses.append((Tier(center, radius, height, p["seed"] % 997 + i, rng.choice(p["lobes"]), tone_bias=-0.06 * (1.0 - t)), 3))
    # The spire: a slim tier rising to a point at the top of the tree.
    tip = tree.trunk[-1][0]
    spire = Tier(Vector((tip.x, tip.y, top_z - 0.55)), p["top_radius"] * 0.55, 1.1, p["seed"] % 997 + 50, 5, tone_bias=0.05)
    spire.lobe_amp = 0.1
    tree.masses.append((spire, 3))
    lo = Vector((min(m.center.x - m.radius for m, _ in tree.masses), min(m.center.y - m.radius for m, _ in tree.masses), 0.0))
    hi = Vector((max(m.center.x + m.radius for m, _ in tree.masses), max(m.center.y + m.radius for m, _ in tree.masses), top_z))
    first = tree.masses[0][0]
    lo.z = first.center.z - first.height
    tree.crown_center = (lo + hi) * 0.5
    tree.crown_half = Vector(((hi.x - lo.x + hi.y - lo.y) * 0.25, 0.0, (hi.z - lo.z) * 0.5))
    tree.reach = max(Vector((m.center.x, m.center.y, 0)).length + m.radius for m, _ in tree.masses)
    tree.height = top_z
    return tree


CONIFER_A = {
    # Tall, narrow fir: eight close whorls over a short bare trunk.
    "seed": 20261031, "lean": (0.6, 0.8, 0.0), "bend": 0.25, "height": 8.8, "trunk_radius": 0.3,
    "tiers": 8, "first_tier": 2.1, "spacing": 0.9, "base_radius": 2.5, "top_radius": 0.75,
    "base_drop": 1.45, "top_drop": 0.95, "lobes": (7, 8, 9),
}

CONIFER_B = {
    # Older, broader spruce: fewer, heavier skirts that droop more, a leaning crown and a
    # thinned whorl that leaves a gap in the outline.
    "seed": 20261037, "lean": (-0.9, 0.45, 0.0), "bend": 0.55, "height": 7.3, "trunk_radius": 0.34,
    "tiers": 6, "first_tier": 1.6, "spacing": 0.85, "base_radius": 2.95, "top_radius": 0.9,
    "base_drop": 1.75, "top_drop": 1.1, "lobes": (6, 7), "scale_tier": {3: 0.72},
}

# Conifer whorls are cheap per tier, so far LODs keep every tier and only lose segments.
CONIFER_LODS = {
    0: (8, 1, 0, 0, 0, 3, 1.0),
    1: (6, 2, 0, 0, 0, 2, 1.0),
    2: (5, 3, 0, 0, 0, 1, 1.04),
    3: (4, 6, 0, 0, 0, 0, 1.08),
}


# --- Bushes ----------------------------------------------------------------------------------

def design_bush(p):
    """A few short twigs under overlapping foliage masses: the tree crowns' Mass shapes at
    shrub scale. Mass entries are (center, radius, height, keep)."""
    tree = TreeDesign()
    tree.trunk = [(Vector((0, 0, -0.1)), 0.05), (Vector((0, 0, 0.15)), 0.04)]
    tree.trunk_radius = 0.0
    tree.trunk_flare = (0.0, 0.0)
    tree.wind_scale = 0.45
    rng = random.Random(p["seed"])
    for k in range(p["twigs"]):
        a = k / p["twigs"] * math.tau + rng.uniform(-0.3, 0.3)
        direction = Vector((math.cos(a), math.sin(a), 1.4)).normalized()
        tree.limbs.append((curve(Vector((0, 0, 0.1)), direction, p["twig_length"], 0.2, 3), 0.03, 0.012, 0.02, 0.3, 1))
    for k, (center, radius, height, keep) in enumerate(p["masses"]):
        tree.masses.append((Mass(Vector(center), radius, height, p["seed"] % 997 + k, tone_bias=0.04 if k == 0 else 0.0,
                                 tilt=rng.uniform(-0.2, 0.2)), keep))
    _measure_crown(tree)
    return tree


BUSH_A = {
    # Rounded mound (~0.9 m): one dome with four lower masses around it.
    "seed": 3201, "twigs": 3, "twig_length": 0.35,
    "masses": [((0.0, 0.0, 0.48), 0.5, 0.42, 2), ((0.42, 0.1, 0.3), 0.36, 0.3, 2), ((-0.3, 0.34, 0.28), 0.34, 0.28, 2),
               ((-0.22, -0.38, 0.3), 0.36, 0.3, 1), ((0.18, -0.4, 0.22), 0.28, 0.22, 1)],
}

BUSH_B = {
    # Low, wide hedge clump (~0.6 m) for road and field edges.
    "seed": 3202, "twigs": 3, "twig_length": 0.3,
    "masses": [((-0.7, 0.25, 0.25), 0.4, 0.27, 2), ((-0.25, -0.15, 0.33), 0.47, 0.33, 2), ((0.3, 0.22, 0.29), 0.44, 0.3, 2),
               ((0.72, -0.28, 0.23), 0.36, 0.24, 2), ((0.0, 0.5, 0.2), 0.32, 0.2, 1), ((-0.55, -0.45, 0.18), 0.3, 0.18, 1)],
}

BUSH_C = {
    # Upright shrub (~1.2 m): stacked masses, the forest-floor understory bush.
    "seed": 3203, "twigs": 4, "twig_length": 0.6,
    "masses": [((0.0, 0.0, 0.34), 0.46, 0.36, 2), ((0.1, 0.06, 0.64), 0.38, 0.3, 2), ((-0.04, -0.02, 0.86), 0.24, 0.19, 2),
               ((-0.32, 0.18, 0.5), 0.28, 0.26, 1), ((0.3, -0.22, 0.46), 0.28, 0.25, 1)],
}

# Bushes are small and numerous: LOD0 is already lighter than a tree's LOD1. Masses with
# keep 1 drop out at LOD2.
BUSH_LODS = {
    0: (5, 1, 4, 1, 1, 3, 1.0),
    1: (4, 1, 0, 0, 0, 2, 1.04),
    2: (3, 1, 0, 0, 0, 1, 1.12),
}


TREE_LODS = {
    # level: (trunk sides, trunk ring stride, limb sides, limb ring stride, max limb level,
    #         foliage icosphere subdivisions, mass scale)
    0: (8, 1, 6, 1, 2, 3, 1.0),
    1: (6, 2, 5, 2, 1, 2, 1.0),
    2: (5, 4, 0, 0, 0, 2, 1.12),
    # Very low LOD for the far distance (§17): the main masses as bare icosahedra.
    3: (4, 7, 0, 0, 0, 1, 1.18),
}


def build_tree(name, tree, trunk_mat, leaf_mat, lods=None):
    objects = []
    report = {}
    for level, (t_sides, t_stride, l_sides, l_stride, max_limb, subdiv, mass_scale) in (lods or TREE_LODS).items():
        mb = MeshBuilder()
        trunk = tree.trunk[::t_stride]
        if trunk[-1] is not tree.trunk[-1]:
            trunk.append(tree.trunk[-1])
        tube(mb, trunk, t_sides, 0, (0.3, 0.75), (0.0, 0.06), 0.0, flare=tree.trunk_flare[0 if level < 2 else 1])
        for points, r0, r1, w0, w1, limb_level in tree.limbs:
            if limb_level > max_limb:
                continue
            pts = points[::l_stride]
            if pts[-1] is not points[-1]:
                pts.append(points[-1])
            ring = [(p, r0 + (r1 - r0) * i / (len(pts) - 1)) for i, p in enumerate(pts)]
            tube(mb, ring, l_sides, 0, (0.4, 0.65), (w0, w1), 0.0)
        for mass, keep in tree.masses:
            if keep < level:
                continue
            mass.emit(mb, 1, subdiv, tree.crown_center, tree.crown_half, tree.reach, mass_scale, tree.wind_scale)
        obj = mb.build("%s_LOD%d" % (name, level), [trunk_mat, leaf_mat])
        obj["height"] = round(tree.height, 3)
        obj["trunk_radius"] = tree.trunk_radius
        obj["crown_radius"] = round(tree.reach, 3)
        objects.append(obj)
        report["LOD%d" % level] = mb.triangles()
    return objects, report


# --- Grass -------------------------------------------------------------------------------

BLADE_ROWS = [(0.0, 1.0), (0.5, 0.78), (0.82, 0.42)]
TALL_BLADE_ROWS = [(0.0, 1.0), (0.35, 0.86), (0.62, 0.66), (0.85, 0.36)]


def blade(mb, material, base, height, lean_dir, lean, side, width, phase, shade, rows=BLADE_ROWS, tip=True):
    """One curved blade from `base`: a strip of quads through `rows` [(t, width factor)]
    closed by a tip triangle. Returns the blade's top point."""
    face_normal = side.cross(UP).normalized()
    if face_normal.dot(lean_dir) < 0:
        face_normal = -face_normal
    # Normals lean mostly up so a clump is lit like the ground under it.
    normal = (UP * 0.8 + face_normal * 0.35).normalized()

    def point(t):
        bend = lean * height * t * t
        return base + lean_dir * bend + UP * height * (t - 0.12 * lean * t * t)

    indices = []
    for t, w in rows:
        p = point(t)
        wind = t ** 1.6
        tone = 0.1 + 0.8 * t + shade
        indices.append((mb.vertex(p - side * width * w * 0.5, normal, tone, wind, phase),
                        mb.vertex(p + side * width * w * 0.5, normal, tone, wind, phase)))
    for (a0, a1), (b0, b1) in zip(indices, indices[1:]):
        mb.face((a0, a1, b1, b0), material)
    if tip:
        apex = mb.vertex(point(1.0), normal, 0.95 + shade, 1.0, phase)
        c0, c1 = indices[-1]
        mb.face((c0, c1, apex), material)
    return point(1.0)


def fan(rng, b, blades, spread, height_range, width_range, lean_range=(0.18, 0.5)):
    """Draws one blade's placement in a fanned clump: outer blades lean further out, with a
    random twist so the fan is not perfectly radial. The draw order is part of the asset
    (grass_normal's shape depends on it)."""
    golden = math.radians(137.5)
    angle = b * golden + rng.uniform(-0.3, 0.3)
    radial = Vector((math.cos(angle), math.sin(angle), 0.0))
    dist = spread * math.sqrt((b + 0.5) / blades) * rng.uniform(0.6, 1.0)
    base = radial * dist
    height = rng.uniform(*height_range)
    lean_dir = (radial * (0.55 + dist / spread * 0.6) + Vector((rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3), 0))).normalized()
    lean = rng.uniform(*lean_range)
    side = Vector((-lean_dir.y, lean_dir.x, 0.0))
    side = (side * math.cos(rng.uniform(-0.5, 0.5)) + lean_dir * math.sin(rng.uniform(-0.5, 0.5))).normalized()
    width = rng.uniform(*width_range)
    phase = rng.random()
    shade = rng.uniform(-0.08, 0.08)
    return base, height, lean_dir, lean, side, width, phase, shade


def build_grass_cluster(name, grass_mat, seed, blades, height_range, spread, width_range,
                        lean_range=(0.18, 0.5), rows=BLADE_ROWS, stalks=0):
    """A small clump of curved blades fanning out from one root, so the clump reads as
    blades rather than a card. `stalks` adds thin seed-head stems above the blades
    (grass_wild)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    for b in range(blades):
        base, height, lean_dir, lean, side, width, phase, shade = fan(rng, b, blades, spread, height_range, width_range, lean_range)
        blade(mb, 0, base, height, lean_dir, lean, side, width, phase, shade, rows)
    top = height_range[1]
    for k in range(stalks):
        base, height, lean_dir, lean, side, width, phase, shade = fan(rng, k, stalks, spread * 0.6, (top * 1.0, top * 1.15), (0.012, 0.016), (0.08, 0.2))
        head = blade(mb, 0, base, height, lean_dir, lean, side, width, phase, shade, TALL_BLADE_ROWS, tip=False)
        seed_head(mb, 0, head, lean_dir, rng.uniform(0.06, 0.09), 0.022, phase, (0.75, 1.0))
    obj = mb.build(name, [grass_mat])
    obj["height"] = top
    return [obj], {"LOD0": mb.triangles()}


def seed_head(mb, material, at, lean_dir, length, width, phase, tone, alpha=1.0):
    """An elongated head of two crossed diamond cards (grass seed head, flower spike)."""
    axis = (UP + lean_dir * 0.25).normalized()
    for k in range(2):
        across = Vector((math.cos(k * math.pi * 0.5), math.sin(k * math.pi * 0.5), 0.0)) * width
        normal = (UP * 0.7 + across.normalized().cross(axis) * 0.3).normalized()
        bottom = mb.vertex(at, normal, tone[0], 1.0, phase, alpha)
        left = mb.vertex(at + axis * length * 0.38 - across, normal, (tone[0] + tone[1]) * 0.5, 1.0, phase, alpha)
        right = mb.vertex(at + axis * length * 0.38 + across, normal, (tone[0] + tone[1]) * 0.5, 1.0, phase, alpha)
        apex = mb.vertex(at + axis * length, normal, tone[1], 1.0, phase, alpha)
        mb.face((bottom, right, apex, left), material)


def flower_head(mb, material, at, facing, radius, petals, phase, alpha):
    """A flat star of petals around a center: vertex tone 0 marks the center (the shader
    paints it yellow), 1 the petal tips."""
    side = perpendicular(facing)
    other = facing.cross(side).normalized()
    normal = (facing * 0.8 + UP * 0.2).normalized()
    center = mb.vertex(at + facing * radius * 0.12, normal, 0.0, 1.0, phase, alpha)
    ring = []
    for k in range(petals * 2):
        a = k / (petals * 2) * math.tau
        r = radius if k % 2 == 0 else radius * 0.42
        # Petal tips cup up slightly.
        lift = facing * radius * (0.18 if k % 2 == 0 else 0.0)
        ring.append(mb.vertex(at + (side * math.cos(a) + other * math.sin(a)) * r + lift, normal,
                              1.0 if k % 2 == 0 else 0.62, 1.0, phase, alpha))
    for k in range(len(ring)):
        mb.face((center, ring[k], ring[(k + 1) % len(ring)]), material)


def build_flower_cluster(name, grass_mat, flower_mat, seed, leaves, stems, stem_height, kind, alpha):
    """A clump of short leaves with a few flower stems. kind "star": open star flowers;
    kind "spike": upright flower spikes. alpha picks the shader's petal palette
    (1 warm whites / yellows, 0 cool violets / blues)."""
    rng = random.Random(seed)
    mb = MeshBuilder()
    for b in range(leaves):
        base, height, lean_dir, lean, side, width, phase, shade = fan(rng, b, leaves, 0.12, (0.08, 0.17), (0.04, 0.055), (0.3, 0.6))
        blade(mb, 0, base, height, lean_dir, lean, side, width, phase, shade)
    for k in range(stems):
        base, height, lean_dir, lean, side, width, phase, shade = fan(rng, k, stems, 0.09, stem_height, (0.018, 0.024), (0.06, 0.18))
        top = blade(mb, 0, base, height, lean_dir, lean, side, width, phase, shade, TALL_BLADE_ROWS, tip=False)
        if kind == "star":
            facing = (UP + lean_dir * rng.uniform(0.2, 0.6)).normalized()
            flower_head(mb, 1, top, facing, rng.uniform(0.05, 0.066), rng.choice((5, 6)), phase, alpha)
        else:
            # A spike of three florets shrinking toward the top, like lupine or bellflower.
            length = rng.uniform(0.13, 0.17)
            for f in range(3):
                at = top - UP * 0.03 + (UP + lean_dir * 0.25).normalized() * length * f * 0.3
                seed_head(mb, 1, at, lean_dir, length * (0.5 - f * 0.08), 0.042 - f * 0.008, phase, (0.35 + f * 0.2, 0.75 + f * 0.12), alpha)
    obj = mb.build(name, [grass_mat, flower_mat])
    obj["height"] = stem_height[1]
    return [obj], {"LOD0": mb.triangles()}


# --- Scene, materials, export ------------------------------------------------------------

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def preview_material(name, color):
    """Viewport/preview material. Godot replaces it with the shared runtime material
    matched by this name, so only the name matters for the game."""
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nodes = material.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.9
    material.diffuse_color = color
    return material


def export(objects, group, name):
    os.makedirs(os.path.join(ASSET_DIR, group), exist_ok=True)
    os.makedirs(SOURCE_DIR, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    glb = os.path.join(ASSET_DIR, group, name + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=glb, export_format="GLB", use_selection=True, export_apply=True,
        export_yup=True, export_normals=True, export_tangents=False,
        export_vertex_color="ACTIVE", export_all_vertex_colors=False,
        export_materials="EXPORT", export_image_format="NONE", export_extras=True,
        export_cameras=False, export_lights=False, export_animations=False)
    blend = os.path.join(SOURCE_DIR, name + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
    return glb, blend


def asset_broadleaf_a():
    reset_scene()
    trunk = preview_material("Trunk", (0.36, 0.25, 0.17, 1.0))
    leaves = preview_material("Leaves", (0.27, 0.48, 0.2, 1.0))
    tree = design_broadleaf_a()
    objects, report = build_tree("broadleaf_a", tree, trunk, leaves)
    report["height"] = round(tree.height, 2)
    report["crown_radius"] = round(tree.reach, 2)
    return objects, "trees/broadleaf", "broadleaf_a", report


def asset_grass_normal():
    reset_scene()
    grass = preview_material("Grass", (0.4, 0.6, 0.25, 1.0))
    objects, report = build_grass_cluster("grass_normal", grass, 3101, 12, (0.15, 0.3), 0.16, (0.045, 0.065))
    report["height"] = 0.3
    return objects, "grass", "grass_normal", report


def tree_asset(name, group, design, lods=None):
    def make():
        reset_scene()
        trunk = preview_material("Trunk", (0.36, 0.25, 0.17, 1.0))
        leaves = preview_material("Leaves", (0.27, 0.48, 0.2, 1.0))
        tree = design()
        objects, report = build_tree(name, tree, trunk, leaves, lods)
        report["height"] = round(tree.height, 2)
        report["crown_radius"] = round(tree.reach, 2)
        return objects, group, name, report
    return make


def grass_asset(name, *args, **kwargs):
    def make():
        reset_scene()
        grass = preview_material("Grass", (0.4, 0.6, 0.25, 1.0))
        objects, report = build_grass_cluster(name, grass, *args, **kwargs)
        return objects, "grass", name, report
    return make


def flower_asset(name, *args):
    def make():
        reset_scene()
        grass = preview_material("Grass", (0.4, 0.6, 0.25, 1.0))
        flower = preview_material("Flower", (0.92, 0.88, 0.75, 1.0))
        objects, report = build_flower_cluster(name, grass, flower, *args)
        return objects, "flowers", name, report
    return make


ASSETS = {
    # Phase 2A quality standard.
    "broadleaf_a": asset_broadleaf_a,
    "grass_normal": asset_grass_normal,
    # Phase 2B.
    "broadleaf_b": tree_asset("broadleaf_b", "trees/broadleaf", lambda: design_spreading(BROADLEAF_B)),
    "broadleaf_c": tree_asset("broadleaf_c", "trees/broadleaf", lambda: design_spreading(BROADLEAF_C)),
    "oak_a": tree_asset("oak_a", "trees/oak", lambda: design_spreading(OAK_A)),
    "oak_b": tree_asset("oak_b", "trees/oak", lambda: design_spreading(OAK_B)),
    "conifer_a": tree_asset("conifer_a", "trees/conifer", lambda: design_conifer(CONIFER_A), CONIFER_LODS),
    "conifer_b": tree_asset("conifer_b", "trees/conifer", lambda: design_conifer(CONIFER_B), CONIFER_LODS),
    "bush_a": tree_asset("bush_a", "bushes", lambda: design_bush(BUSH_A), BUSH_LODS),
    "bush_b": tree_asset("bush_b", "bushes", lambda: design_bush(BUSH_B), BUSH_LODS),
    "bush_c": tree_asset("bush_c", "bushes", lambda: design_bush(BUSH_C), BUSH_LODS),
    # name, seed, blades, height range, spread, blade width range (+ lean, rows, stalks)
    "grass_short": grass_asset("grass_short", 3102, 10, (0.08, 0.14), 0.12, (0.035, 0.05), (0.25, 0.55)),
    "grass_tall": grass_asset("grass_tall", 3103, 14, (0.3, 0.48), 0.2, (0.04, 0.06), (0.15, 0.42), TALL_BLADE_ROWS),
    "grass_wild": grass_asset("grass_wild", 3104, 14, (0.18, 0.4), 0.22, (0.03, 0.07), (0.2, 0.75), TALL_BLADE_ROWS, 3),
    # name, seed, leaves, stems, stem height range, head kind, palette (1 warm / 0 cool)
    "flower_grass_a": flower_asset("flower_grass_a", 3201, 8, 5, (0.16, 0.28), "star", 1.0),
    "flower_grass_b": flower_asset("flower_grass_b", 3202, 7, 3, (0.26, 0.4), "spike", 0.0),
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(ASSETS)
    for name in names:
        objects, group, asset, report = ASSETS[name]()
        glb, blend = export(objects, group, asset)
        print("[vegetation] %s -> %s | %s" % (asset, os.path.relpath(glb, ROOT), report))


if __name__ == "__main__":
    main()
