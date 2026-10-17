"""Export the seed-driven illustration trees (source/environment/vegetation/stylized_tree_seed.blend)
as game GLBs for JRPGWorldSample2, plus their leaf-cluster texture.

Run inside Blender with stylized_tree_seed.blend open:
    exec(open(r"<repo>/tools/vegetation/build_seed_trees.py", encoding="utf-8").read())

Each variant (VARIANT_COUNT, drawn by _variants) is its own Geometry Nodes seed and crown shape
of the "Canopy" object plus its own procedural branch structure, baked into three LOD meshes (<asset>_LOD0..2) with three material
slots read by scripts/world_jrpg/open_field_seed_tree.gdshader ("SeedCards", "SeedCore") and
open_field_toon_tree.gdshader ("Toon", trunk and branches). Every branch ends inside a crown
lump, so the limbs visibly carry the foliage.
  - SeedCards: camera-facing leaf cards. Every corner sits at the card center; UV2 is the
    corner's offset in the view plane (m), UV the leaf-cluster texture.
  - SeedCore: the crown's lump hull under the cards, filling the gaps with deep foliage.
  - vertex COLOR: rgb = painted sRGB color (each lump's own sunlit cap over the crown's
    top-to-bottom gradient), a = 1 card / 0 core / 0 bark.
  - NORMAL: cards and core carry the crown's proxy ("hull_n") normal, so lighting reads per
    lump, never per card.
"""
import bpy, math, os, random
import numpy as np
from mathutils import Vector

# <repo>/source/environment/vegetation/stylized_tree_seed.blend -> <repo>
REPO = os.path.abspath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..", ".."))
VEG = os.path.join(REPO, "assets", "environment", "vegetation")
OUT_DIR = os.path.join(VEG, "trees", "seed")
TEXTURE = os.path.join(VEG, "textures", "seed_leaf_cluster.png")
EXPORT_SCALE = 2.0
# Ten variants, each with its own crown seed, crown shape, branch structure and a slight leaf
# hue, all drawn from one fixed RNG so a rebuild reproduces them.
VARIANT_COUNT = 12
# Variants (by index) whose single trunk widens all the way down into a broad, conical foot:
# {index: (base radius multiplier, profile exponent)}. Larger exponents keep the trunk slim
# higher up and swell it mostly near the ground.
CONE_TRUNKS = {10: (2.6, 1.6), 11: (3.2, 2.4)}
VARIANT_SEED = 2024
# Height (Blender m) of the crown's lowest lumps: with EXPORT_SCALE the foliage starts ~7 m
# up a long bare trunk whatever the crown's own size; the crown center is placed from it.
CROWN_BASE_Z = 3.6
# LOD0 leaf cards: cards per m^2 of lump hull (before EXPORT_SCALE) and card size.
CARD_DENSITY = 22.0
CARD_SIZE = 0.5
# Per LOD: share of the generated cards kept, their size multiplier (~1/sqrt(share) keeps the
# leaf coverage), hull subdivisions, branch detail (0 = with twigs, 1 = limbs only). Every LOD
# reuses the same cards and lumps, so the silhouette and colors never jump between LODs.
# Every LOD is the light, far weight (fewer, larger cards on a coarse hull); the twigs stay so
# no lump ever floats free of the limbs up close.
LODS = [(0.15, 2.2, 1, 0), (0.15, 2.2, 1, 0), (0.15, 2.2, 1, 0)]
# Foliage ramp (sRGB): deep blue-green underside -> green -> yellow-green -> pale sunlit cap.
LEAF_RAMP = [(0.0, (0.19, 0.37, 0.40)), (0.3, (0.23, 0.46, 0.39)), (0.55, (0.42, 0.60, 0.28)),
             (0.8, (0.60, 0.72, 0.32)), (1.0, (0.80, 0.85, 0.45))]
# Multiplier over the ramp for every tree: the cooler, deeper green first tuned on the conifers.
FOLIAGE_TINT = (0.72, 0.86, 0.92)
# How much each lump's own height (vs the whole crown's) drives the ramp, and the floor of
# the ramp: the underside stays a mid blue-green, never black.
LUMP_WEIGHT = 0.85
RAMP_FLOOR = 0.12
CORE_DARKEN = 0.92
# The core sits this far (Blender m) inside the lump surface, cards this far (x card size) outside.
CORE_INSET = 0.2
CARD_LIFT = 0.15
# Bark: warm tan at the foot, cool purple up the fork where the crown shades it.
TRUNK_FOOT = (0.80, 0.66, 0.50)
TRUNK_FORK = (0.46, 0.40, 0.56)


def _variants():
    """{asset: (crown seed, crown inputs, branch style, leaf hue -1..1, reference crown)}.
    Crown: width (x) and depth ratio (y), height, how flat its underside is, lump count and
    size all vary widely, from narrow columns to broad flat umbrellas and lopsided ovals.
    The reference crown fixes the trunk (where the limbs leave it); the exported crown is
    the reference stretched 1.5-2.1x upward from the same underside and warped into a broken
    triangle: strongly narrowing toward the top (taper, which also shrinks the upper lumps),
    leaning (skew) and lumps pushed well off the smooth outline (jitter), drawn from a second
    RNG so the trunks stay as they were.
    Branch style (Blender m, before EXPORT_SCALE): stems = trunks from the ground (2-3 fork
    at `split`), fork_drop = how far below the crown's lowest lump the limbs leave the trunk,
    lean = fork offset (x, y), bend = limb arc, limbs = primary limbs (each into its own lump,
    spread around the crown), radius = trunk base radius (slender to stout), flare = how much
    the trunk swells into its roots at the ground, crook = random kinks."""
    rnd = random.Random(VARIANT_SEED)
    out = {}
    for i in range(VARIANT_COUNT):
        rmin = rnd.uniform(0.25, 0.5)
        rmax = rmin + rnd.uniform(0.15, 0.5)
        height = rnd.uniform(0.4, 1.6)
        flatten = rnd.uniform(0.2, 0.85)
        crown = {"Clusters": rnd.randint(12, 40), "Width": rnd.uniform(0.75, 2.2), "Depth Ratio": rnd.uniform(0.6, 1.4),
                 "Height": height, "Bottom Flatten": flatten,
                 # Lowest lumps reach down to about CROWN_BASE_Z: center = base + underside depth.
                 "Center Z": CROWN_BASE_Z + height * flatten + rmax,
                 "Cluster Radius Min": rmin, "Cluster Radius Max": rmax,
                 # The shape is chosen here; the seed only places the lumps.
                 "Shape Variation": 0.0}
        style = dict(stems=rnd.choices([1, 2, 3], weights=[7, 2, 1])[0], split=rnd.uniform(0.4, 2.2),
                     fork_drop=rnd.uniform(0.3, 1.4), lean=(rnd.gauss(0, 0.3), rnd.gauss(0, 0.3)),
                     bend=rnd.uniform(0.1, 0.45), limbs=rnd.randint(2, 6), radius=rnd.uniform(0.11, 0.32),
                     flare=rnd.uniform(0.0, 0.9), crook=rnd.uniform(0.01, 0.1))
        if i in CONE_TRUNKS:
            style.update(stems=1, cone=CONE_TRUNKS[i], radius=max(style["radius"], 0.2), flare=0.0)
            # A full, dense crown to sit on the heavy trunk.
            rmin, rmax = max(rmin, 0.4), max(rmax, max(rmin, 0.4) + 0.3)
            crown.update({"Clusters": max(crown["Clusters"], 28), "Cluster Radius Min": rmin, "Cluster Radius Max": rmax,
                          "Center Z": CROWN_BASE_Z + height * flatten + rmax})
        crown.update({"Skew X": 0.0, "Skew Y": 0.0, "Taper": 0.0, "Jitter": 0.0})
        seed, hue = rnd.randint(0, 999), rnd.uniform(-1, 1)
        warp = random.Random(VARIANT_SEED * 7 + i)
        tall = warp.uniform(1.5, 2.1)
        stretched = dict(crown)
        stretched.update({
            "Height": height * tall,
            # More lumps for the taller crown so it stays dense.
            "Clusters": min(60, int(crown["Clusters"] * (0.75 + 0.4 * tall))),
            # Same underside height: the extra height all goes up.
            "Center Z": CROWN_BASE_Z + height * tall * flatten + rmax,
            "Skew X": warp.gauss(0.0, 0.22), "Skew Y": warp.gauss(0.0, 0.22),
            # Strongly narrowing toward the top: a triangle, never a ball.
            "Taper": warp.uniform(-0.95, -0.55),
            # Lumps pushed well off the outline so the triangle reads broken, not geometric.
            "Jitter": warp.uniform(0.25, 0.5),
        })
        out["seed_tree_" + "abcdefghijklmnopqrstuvwxyz"[i]] = (seed, stretched, style, hue, crown)
    return out


# Illustration conifers: tall, narrow crowns tapering to a point, packed with small lumps,
# a straight central leader through the crown with every lump on a short twig. They stand in
# for the low-poly toon conifers.
CONIFER_COUNT = 4
CONIFER_BASE_Z = 1.0


def _conifers():
    rnd = random.Random(VARIANT_SEED + 500)
    out = {}
    for i in range(CONIFER_COUNT):
        rmin = rnd.uniform(0.36, 0.44)
        rmax = rmin + rnd.uniform(0.14, 0.22)
        height = rnd.uniform(2.6, 3.4)
        flatten = rnd.uniform(0.15, 0.3)
        crown = {"Clusters": rnd.randint(64, 80), "Width": rnd.uniform(0.8, 1.0), "Depth Ratio": rnd.uniform(0.85, 1.15),
                 "Height": height, "Bottom Flatten": flatten,
                 "Center Z": CONIFER_BASE_Z + height * flatten + rmax,
                 "Cluster Radius Min": rmin, "Cluster Radius Max": rmax, "Shape Variation": 0.0,
                 # Spire: the spread narrows toward the top while the lumps stay big enough to
                 # overlap into one solid cone; a little lean and ragged lumps.
                 "Skew X": rnd.gauss(0.0, 0.06), "Skew Y": rnd.gauss(0.0, 0.06),
                 "Taper": rnd.uniform(-0.95, -0.82), "Jitter": rnd.uniform(0.06, 0.14)}
        style = dict(stems=1, split=0.0, fork_drop=rnd.uniform(0.15, 0.45), lean=(rnd.gauss(0, 0.05), rnd.gauss(0, 0.05)),
                     bend=0.1, limbs=0, radius=rnd.uniform(0.12, 0.19), flare=rnd.uniform(0.2, 0.7),
                     crook=rnd.uniform(0.005, 0.025), conifer=True,
                     # Smaller, denser cards keep the spire's outline crisp.
                     card_density=CARD_DENSITY * 1.5, card_size=CARD_SIZE * 0.7)
        out["seed_conifer_" + "abcdefghijklmnopqrstuvwxyz"[i]] = (rnd.randint(0, 999), crown, style, rnd.uniform(-0.5, 0.5), crown)
    return out


VARIANTS = {**_variants(), **_conifers()}


def _smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _ramp(t):
    t = min(max(t, 0.0), 1.0)
    for (p0, c0), (p1, c1) in zip(LEAF_RAMP, LEAF_RAMP[1:]):
        if t <= p1:
            f = (t - p0) / (p1 - p0)
            return tuple(a + (b - a) * f for a, b in zip(c0, c1))
    return LEAF_RAMP[-1][1]


def make_leaf_texture(path, size=512, leaves=230, seed=11):
    """A round cluster of small pointed, serrated leaves radiating from the center.
    RGB = per-leaf value (grey, tinted by vertex color in the shader), A = cut-out."""
    rng = np.random.default_rng(seed)
    rgb = np.full((size, size), 0.85, np.float32)
    alpha = np.zeros((size, size), np.float32)
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float32) / size
    order = []
    for _ in range(leaves):
        r = 0.42 * rng.random() ** 0.7
        a = rng.random() * math.tau
        order.append((r, a))
    # Inner leaves first, so the outer ring overlaps them like a real clump seen from outside.
    for r, a in sorted(order):
        cx, cy = 0.5 + r * math.cos(a), 0.5 + r * math.sin(a)
        heading = a + rng.uniform(-0.6, 0.6) if r > 0.05 else rng.random() * math.tau
        length = rng.uniform(0.06, 0.09) * (1.0 + 0.3 * (r / 0.42))
        width = length * rng.uniform(0.32, 0.42)
        d = np.array([math.cos(heading), math.sin(heading)], np.float32)
        bx, by = cx - d[0] * length * 0.3, cy - d[1] * length * 0.3
        u = ((xs - bx) * d[0] + (ys - by) * d[1]) / length
        v = (-(xs - bx) * d[1] + (ys - by) * d[0]) / width
        inside = (u > 0) & (u < 1)
        prof = np.where(inside, np.sin(np.clip(u, 0, 1) * math.pi) ** 0.75, 0.0)
        prof *= 1.0 + 0.12 * np.sin(u * 28.0)
        mask = inside & (np.abs(v) < prof * 0.5)
        if not mask.any():
            continue
        value = rng.uniform(0.7, 1.0) * (0.82 + 0.26 * u)
        value = np.where(np.abs(v) < 0.05, value * 0.86, value)
        rgb[mask] = np.clip(value, 0, 1)[mask] if np.ndim(value) else value
        alpha[mask] = 1.0
    img = bpy.data.images.get("seed_leaf_cluster")
    if img:
        bpy.data.images.remove(img)
    img = bpy.data.images.new("seed_leaf_cluster", size, size, alpha=True)
    px = np.dstack([rgb, rgb, rgb, alpha])[::-1].reshape(-1)  # Blender rows are bottom-up
    img.pixels.foreach_set(px.astype(np.float32))
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def _leaf_card():
    """Unit quad with a UV map: the Geometry Nodes leaf instance for export."""
    me = bpy.data.meshes.get("LeafCardQuad") or bpy.data.meshes.new("LeafCardQuad")
    me.clear_geometry()
    me.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0)], [], [(0, 1, 2, 3)])
    uv = me.uv_layers.new(name="UVMap") if not me.uv_layers else me.uv_layers[0]
    for loop, co in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = co
    ob = bpy.data.objects.get("LeafCardQuad") or bpy.data.objects.new("LeafCardQuad", me)
    if not ob.users_collection:
        bpy.data.collections["TreeSource"].objects.link(ob)
    ob.hide_viewport = True
    return ob


def _inputs(mod):
    return {it.name: it.identifier for it in mod.node_group.interface.items_tree
            if getattr(it, "in_out", None) == "INPUT"}


class Part:
    """Mesh data under construction: per-vertex attributes, faces with a material slot."""
    def __init__(self):
        self.verts, self.normals, self.colors, self.uv, self.uv2, self.faces, self.slots = [], [], [], [], [], [], []

    def vertex(self, co, normal, color, uv=(0.0, 0.0), uv2=(0.0, 0.0)):
        self.verts.append(co)
        self.normals.append(normal)
        self.colors.append(color)
        self.uv.append(uv)
        self.uv2.append(uv2)
        return len(self.verts) - 1


def _crown(canopy, seed, density, card_size, subdivisions, card_obj, hue=0.0, leaf_tint=None):
    """[cards, hull, lumps] of the evaluated canopy for one seed: cards as (center, normal,
    size, color, UV corners, spin, roll), hull as faces of (co, normal, color), lumps as
    (center, radius)."""
    mod = canopy.modifiers["StylizedCanopy"]
    ids = _inputs(mod)
    ico = next(n for n in mod.node_group.nodes if n.bl_idname == "GeometryNodeMeshIcoSphere")
    ico.inputs["Subdivisions"].default_value = subdivisions
    mod[ids["Seed"]] = seed
    mod[ids["Leaf Density"]] = density
    mod[ids["Leaf Size"]] = card_size
    mod[ids["Leaf Object"]] = card_obj
    canopy.update_tag()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(canopy.evaluated_get(dg), depsgraph=dg)
    hull_n = me.attributes["hull_n"].data
    lump_h = me.attributes["lump_h"].data
    tint = me.attributes["tint"].data
    uvs = me.uv_layers["UVMap"].data if "UVMap" in me.uv_layers else None
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    rnd = random.Random(seed)
    cards, hull = [], []
    lump_c = me.attributes["lump_c"].data
    lump_r = me.attributes["lump_r"].data
    lumps = {}

    def paint(i, core):
        t = LUMP_WEIGHT * _smoothstep(-0.15, 0.9, lump_h[i].value) + (1 - LUMP_WEIGHT) * (me.vertices[i].co.z - z0) / (z1 - z0)
        c = _ramp(RAMP_FLOOR + (1 - RAMP_FLOOR) * t * (0.85 if core else 1.0))
        k = tint[i].value
        c = tuple(ch * (a + (b - a) * k) for ch, a, b in zip(c, (0.94, 1.0, 1.06), (1.06, 1.02, 0.92)))
        # Per-variant hue: warmer (+) or cooler (-) foliage.
        c = (c[0] * (1 + 0.06 * hue), c[1], c[2] * (1 - 0.06 * hue))
        if leaf_tint:
            c = tuple(ch * m for ch, m in zip(c, leaf_tint))
        if core:
            c = tuple(ch * CORE_DARKEN for ch in c)
        return (*c, 0.0 if core else 1.0)

    for p in me.polygons:
        n = Vector(hull_n[p.vertices[0]].vector).normalized()
        if p.loop_total == 4:
            # Leaf card: its center, size, painted color, UV corners, a random spin and a
            # fixed thinning roll (a card kept at one LOD is kept at every finer one).
            center = sum((me.vertices[i].co for i in p.vertices), Vector()) / 4
            side = (me.vertices[p.vertices[0]].co - me.vertices[p.vertices[1]].co).length
            corners = [tuple(uvs[li].uv) if uvs else (0.0, 0.0) for li in p.loop_indices]
            cards.append((center, n, side, paint(p.vertices[0], False), corners, rnd.random() * math.tau, rnd.random()))
        else:
            c = Vector(lump_c[p.vertices[0]].vector)
            lumps[tuple(round(x, 4) for x in c)] = (c, lump_r[p.vertices[0]].value)
            verts = [(me.vertices[i].co.copy(), Vector(hull_n[i].vector).normalized(), paint(i, True)) for i in p.vertices]
            hull.append((verts if p.normal.dot(n) >= 0.0 else verts[::-1]))
    bpy.data.meshes.remove(me)
    return cards, hull, list(lumps.values())


def _add_crown(part, cards, hull, share, size_scale):
    """Cards collapse to their center (lifted off the core) with the corner offset in UV2;
    the core is the lump hull."""
    for center, n, side, color, corners, spin, roll in cards:
        if roll >= share:
            continue
        side *= size_scale
        pos = (center + n * side * CARD_LIFT) * EXPORT_SCALE
        cs, sn = math.cos(spin), math.sin(spin)
        idx = []
        for u, v in corners:
            ox, oy = (u - 0.5) * side, (v - 0.5) * side
            off = ((ox * cs - oy * sn) * EXPORT_SCALE, (ox * sn + oy * cs) * EXPORT_SCALE)
            idx.append(part.vertex(pos, n, color, (u, 1.0 - v), off))
        part.faces.append(tuple(idx))
        part.slots.append(0)
    for verts in hull:
        part.faces.append(tuple(part.vertex(co * EXPORT_SCALE, n, c) for co, n, c in verts))
        part.slots.append(1)


def _bezier(a, c, b, steps):
    return [a * (1 - t) ** 2 + c * 2 * (1 - t) * t + b * t * t for t in (i / steps for i in range(steps + 1))]


def _branch_structure(style, lumps, rnd):
    """[trunks, limbs, twigs], each a list of (points, radii): trunk(s) up to the fork, a
    primary limb into each of `limbs` lumps spread around the crown, and a twig from the
    nearest limb into every other lump. Every limb / twig ends at its lump's center."""
    up = Vector((0, 0, 1))
    base = Vector((0, 0, -0.1))
    # The limbs leave the trunk `fork_drop` below the reference crown's lowest lump.
    fork_z = style["fork_z"]
    style["fork_z"] = fork_z
    fork = Vector((style["lean"][0], style["lean"][1], fork_z))
    r0 = style["radius"]
    trunks, forks = [], []
    if style["stems"] == 1:
        # The control point sits straight above the foot: the trunk leaves the ground upright
        # and only leans / bows higher up.
        mid = base + up * (fork.z - base.z) * 0.5 + Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), 0)) * style["bend"] * 0.3
        trunks.append((_bezier(base, mid, fork, 10), r0, r0 * 0.62))
        forks.append((fork, r0 * 0.62))
    else:
        stems = style["stems"]
        split = Vector((0, 0, min(style["split"], fork_z - 0.8)))
        trunks.append((_bezier(base, (base + split) / 2, split, 3), r0 * 1.25, r0 * 1.1))
        a = rnd.random() * math.tau
        for k in range(stems):
            d = Vector((math.cos(a + k * math.tau / stems), math.sin(a + k * math.tau / stems), 0))
            top = fork + d * (0.38 if stems == 2 else 0.3) + up * rnd.uniform(-0.3, 0.3)
            ctrl = split + d * 0.25 + up * (top.z - split.z) * 0.35
            trunks.append((_bezier(split, ctrl, top, 8), r0 * (0.85 if stems == 2 else 0.72), r0 * 0.55))
            forks.append((top, r0 * 0.55))
    # Primary limbs: one lump per azimuth sector, the lowest (most visible) in each.
    sectors = [[] for _ in range(style["limbs"])]
    offset = rnd.random() * math.tau
    for c, r in (lumps if sectors else []):
        az = (math.atan2(c.y - fork.y, c.x - fork.x) - offset) % math.tau
        sectors[min(int(az / math.tau * style["limbs"]), style["limbs"] - 1)].append((c, r))
    limbs, used = [], set()
    for sector in sectors:
        if not sector:
            continue
        # Low and outer lumps: the limb shows below the crown and reaches out to its edge.
        c, r = min(sector, key=lambda l: l[0].z - 0.6 * l[1] - 0.8 * (l[0] - fork).xy.length)
        used.add(tuple(c))
        f, fr = min(forks, key=lambda f: (f[0] - c).length)
        span = c - f
        side = span.cross(up).normalized() if span.cross(up).length > 1e-4 else Vector((1, 0, 0))
        # Splay out first, then rise: the arc leaves the fork sideways like a real limb.
        ctrl = f + Vector((span.x, span.y, 0)) * 0.8 + up * span.z * 0.2 + side * rnd.uniform(-1, 1) * style["bend"]
        limbs.append((_bezier(f, ctrl, c, 7), fr * 0.8, 0.03))
    if style.get("conifer"):
        # Conifer: the trunk runs on as a straight leader to the crown's tip; every lump
        # hangs off it on a short twig.
        tip = Vector((fork.x, fork.y, max(c.z + 0.5 * r for c, r in lumps)))
        limbs.append((_bezier(fork, (fork + tip) / 2, tip, 14), forks[0][1] * 0.9, 0.02))
    # Every stem carries at least one limb: a stem without one would end in a bare stub.
    for f, fr in forks:
        if any((pts[0] - f).length < 1e-6 for pts, _, _ in limbs):
            continue
        free = [l for l in lumps if tuple(l[0]) not in used] or lumps
        c, r = min(free, key=lambda l: (l[0] - f).length)
        used.add(tuple(c))
        span = c - f
        ctrl = f + Vector((span.x, span.y, 0)) * 0.8 + up * span.z * 0.2
        limbs.append((_bezier(f, ctrl, c, 7), fr * 0.8, 0.03))
    # Twigs: every other lump hangs off the closest point of a limb.
    twigs = []
    for c, r in lumps:
        if tuple(c) in used or not limbs:
            continue
        best = None
        for pts, ra, rb in limbs:
            for i in range(2, len(pts) - 1):
                d = (pts[i] - c).length
                if best is None or d < best[0]:
                    best = (d, pts[i], ra + (rb - ra) * i / (len(pts) - 1))
        _, p, pr = best
        ctrl = (p + c) / 2 + up * (c - p).length * 0.2
        twigs.append((_bezier(p, ctrl, c, 4), min(pr * 0.7, 0.045), 0.012))
    out = []
    for group in (trunks, limbs, twigs):
        branches = []
        for pts, ra, rb in group:
            n = len(pts) - 1
            # Kinks fade out toward the ground so the flared foot stands straight under the trunk.
            kinked = [p if i in (0, n) else p + Vector((rnd.gauss(0, 1), rnd.gauss(0, 1), rnd.gauss(0, 0.5))) * style["crook"]
                      * min(1.0, max(0.0, p.z) / 1.5) for i, p in enumerate(pts)]
            radii = [ra + (rb - ra) * i / n for i in range(n + 1)]
            if group is trunks and pts[0].z < 0 and "cone" in style:
                # Conical trunk: widens steadily from the fork down to a broad foot.
                mul, power = style["cone"]
                top, foot = rb, ra * mul
                radii = [top + (foot - top) * (1.0 - min(max(p.z / fork_z, 0.0), 1.0)) ** power for p in kinked]
            elif group is trunks and pts[0].z < 0:
                # Root flare: the foot swells out, easing back to the trunk over ~1 m.
                radii = [r * (1.0 + style["flare"] * max(0.0, 1.0 - p.z / 1.0) ** 2.5) for r, p in zip(radii, kinked)]
            branches.append((kinked, radii))
        out.append(branches)
    return out


def _tube(part, points, radii, sides, color_at):
    """A tapered tube along `points`; its start is pushed back into the parent so joints overlap."""
    d0 = (points[1] - points[0]).normalized()
    points = [points[0] - d0 * radii[0] * 0.8] + points[1:]
    normal = d0.orthogonal().normalized()
    rings = []
    for i, p in enumerate(points):
        d = (points[min(i + 1, len(points) - 1)] - points[max(i - 1, 0)]).normalized()
        normal = (normal - d * normal.dot(d)).normalized()  # parallel transport
        binormal = d.cross(normal)
        ring = []
        for k in range(sides):
            a = k / sides * math.tau
            n = normal * math.cos(a) + binormal * math.sin(a)
            co = p + n * radii[i]
            ring.append(part.vertex(co * EXPORT_SCALE, n, color_at(co)))
        rings.append(ring)
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(sides):
            part.faces.append((r0[k], r0[(k + 1) % sides], r1[(k + 1) % sides], r1[k]))
            part.slots.append(2)


def _branches(part, structure, style, detail):
    top = style["fork_z"] + 1.2

    def color_at(co):
        t = min(max(co.z / top, 0.0), 1.0) ** 1.3
        return (*(a + (b - a) * t for a, b in zip(TRUNK_FOOT, TRUNK_FORK)), 0.0)

    trunks, limbs, twigs = structure
    for pts, radii in trunks:
        _tube(part, pts, radii, 7 if detail == 0 else 5, color_at)
    for pts, radii in limbs:
        _tube(part, pts, radii, 5 if detail == 0 else 4, color_at)
    if detail == 0:
        for pts, radii in twigs:
            _tube(part, pts, radii, 4, color_at)


def _build_mesh(name, part, materials):
    me = bpy.data.meshes.get(name)
    if me:
        bpy.data.meshes.remove(me)
    me = bpy.data.meshes.new(name)
    me.from_pydata(part.verts, [], part.faces)
    me.update()
    for m in materials:
        me.materials.append(m)
    me.polygons.foreach_set("material_index", part.slots)
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    col.data.foreach_set("color", [c for rgba in part.colors for c in rgba])
    me.color_attributes.active_color = col
    for layer_name, values in (("UVMap", part.uv), ("UV2", part.uv2)):
        layer = me.uv_layers.new(name=layer_name)
        layer.data.foreach_set("uv", [c for loop in me.loops for c in values[loop.vertex_index]])
    me.normals_split_custom_set_from_vertices(part.normals)
    return me


def build():
    os.makedirs(OUT_DIR, exist_ok=True)
    make_leaf_texture(TEXTURE)
    canopy = bpy.data.objects["Canopy"]
    mod = canopy.modifiers["StylizedCanopy"]
    ids = _inputs(mod)
    crown_keys = list(next(iter(VARIANTS.values()))[1])
    keep = {k: mod[ids[k]] for k in ["Seed", "Leaf Density", "Leaf Size", "Leaf Object"] + crown_keys}
    ico = next(n for n in mod.node_group.nodes if n.bl_idname == "GeometryNodeMeshIcoSphere")
    keep_sub = ico.inputs["Subdivisions"].default_value
    # The hull's inward offset: the only Vector Math "Scale" with a negative constant.
    inset = next(i for n in mod.node_group.nodes if n.bl_idname == "ShaderNodeVectorMath" and n.operation == "SCALE"
                 for i in n.inputs if i.name == "Scale" and not i.is_linked and i.default_value < 0)
    keep_inset = inset.default_value
    inset.default_value = -CORE_INSET
    card = _leaf_card()
    materials = [bpy.data.materials.get(n) or bpy.data.materials.new(n) for n in ("SeedCards", "SeedCore", "Toon")]
    export_col = bpy.data.collections.get("SeedTreeExport") or bpy.data.collections.new("SeedTreeExport")
    if export_col.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(export_col)
    report = {}
    try:
        for asset, (seed, crown, style, hue, reference) in VARIANTS.items():
            objs = []
            style = dict(style)
            # The trunk height comes from the reference crown, so warping the crown never
            # moves the trunk.
            for k, v in reference.items():
                mod[ids[k]] = v
            ref_lumps = _crown(canopy, seed, 0.0, CARD_SIZE, 1, card)[2]
            style["fork_z"] = max(1.0, min(c.z - r for c, r in ref_lumps) - style["fork_drop"])
            for k, v in crown.items():
                mod[ids[k]] = v
            tint = FOLIAGE_TINT
            cards, _, lumps = _crown(canopy, seed, style.get("card_density", CARD_DENSITY), style.get("card_size", CARD_SIZE),
                                     LODS[0][2], card, hue, tint)
            structure = _branch_structure(style, lumps, random.Random(seed * 31 + 7))
            hulls = {}
            for lod, (share, size_scale, subdivisions, detail) in enumerate(LODS):
                if subdivisions not in hulls:
                    # Same seed, so the same lumps; only the hull's tessellation differs.
                    hulls[subdivisions] = _crown(canopy, seed, 0.0, CARD_SIZE, subdivisions, card, hue, tint)[1]
                part = Part()
                _branches(part, structure, style, detail)
                _add_crown(part, cards, hulls[subdivisions], share, size_scale)
                name = "%s_LOD%d" % (asset, lod)
                me = _build_mesh(name, part, materials)
                ob = bpy.data.objects.get(name)
                if ob:
                    bpy.data.objects.remove(ob)
                ob = bpy.data.objects.new(name, me)
                export_col.objects.link(ob)
                objs.append(ob)
                report[name] = sum(len(p.vertices) - 2 for p in me.polygons)
            bpy.ops.object.select_all(action="DESELECT")
            for ob in objs:
                ob.hide_set(False)
                ob.select_set(True)
            bpy.context.view_layer.objects.active = objs[0]
            bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, asset + ".glb"), export_format="GLB",
                                      use_selection=True, export_normals=True, export_texcoords=True,
                                      export_vertex_color="ACTIVE", export_materials="EXPORT", export_yup=True)
            for ob in objs:
                ob.hide_set(True)
    finally:
        for k, v in keep.items():
            mod[ids[k]] = v
        ico.inputs["Subdivisions"].default_value = keep_sub
        inset.default_value = keep_inset
        canopy.update_tag()
    print("triangles:", report)


build()
