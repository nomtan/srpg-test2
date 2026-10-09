"""Bake a skin-depth map for each legacy combined Face's ExpressionProfile.

Legacy Faces are one mesh with head and hair combined, so the shader cannot
tell skin from bangs by material. The toon shader draws eyes / eyebrows / mouth
only within a small tolerance of this map, so bangs in front of the skin hide
the features (as hair does on the Tripo reference head) instead of carrying
slices of them.

1. Bake the deepest front-facing layer (normal.z > 0.15, inside surface_depth)
   over the profile's face_rect. Seen from the front, bangs sit in front of it.
2. Tripo faces are outer shells with no skin behind the bangs, so fit a smooth
   surface to the face and treat texels in front of it as hair, except shallow
   nose / mouth bumps. Under hair the map holds the fitted skin.

Encoding: R = (z - surface_depth.x) / (surface_depth.y - surface_depth.x), 8-bit.
Row 0 of the image is face_uv.y = 0 (top of the face rect).

Run from the repository root (add `-- --debug` to print the region statistics):
  blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_skin_depth_maps.py
"""
import re
import sys
from pathlib import Path

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[3]
PROFILES = ROOT / "assets/characters/_shared/face/expression/profiles"
FACES = ROOT / "assets/characters/modular/face"
SIZE = 128
FRONT_NORMAL_Z = 0.15
FIT_DEGREE = 4
# Texels more than this in front of the fitted skin are treated as hair strands.
STRAND_GAP = 0.003
# An enclosed raised region whose outline steps less than this (median) is skin.
SMOOTH_STEP = 0.003
LOWER_FACE_V = 0.55
DEBUG = "--debug" in sys.argv


def read_profile(path):
    text = path.read_text(encoding="utf-8")
    rect = [float(v) for v in re.search(r"face_rect = Vector4\(([^)]*)\)", text).group(1).split(",")]
    depth = [float(v) for v in re.search(r"surface_depth = Vector2\(([^)]*)\)", text).group(1).split(",")]
    return rect, depth


def face_triangles(face_id):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(FACES / face_id / "model.glb"))
    triangles = []
    for obj in [o for o in bpy.data.objects if o.type == "MESH"]:
        mesh = obj.data
        mesh.calc_loop_triangles()
        # Blender is Z-up; Godot / glTF rest space is (x, z, -y).
        co = np.array([obj.matrix_world @ v.co for v in mesh.vertices])
        godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=1)
        indices = np.array([t.vertices[:] for t in mesh.loop_triangles])
        triangles.append(godot[indices])
    return np.concatenate(triangles)


def bake(triangles, rect, depth):
    x0, y0, width, height = rect
    edge1 = triangles[:, 1] - triangles[:, 0]
    edge2 = triangles[:, 2] - triangles[:, 0]
    normals = np.cross(edge1, edge2)
    lengths = np.linalg.norm(normals, axis=1)
    keep = lengths > 1e-12
    triangles, normals, lengths = triangles[keep], normals[keep], lengths[keep]
    front = normals[:, 2] / lengths > FRONT_NORMAL_Z
    triangles = triangles[front]
    # Face-uv of each vertex in texel units (u right, v down).
    u = (triangles[..., 0] - x0) / width * SIZE
    v = (1.0 - (triangles[..., 1] - y0) / height) * SIZE
    z = triangles[..., 2]
    skin = np.full((SIZE, SIZE), np.inf)
    for (ua, ub, uc), (va, vb, vc), (za, zb, zc) in zip(u, v, z):
        lo_u, hi_u = int(max(np.floor(min(ua, ub, uc)), 0)), int(min(np.ceil(max(ua, ub, uc)), SIZE - 1))
        lo_v, hi_v = int(max(np.floor(min(va, vb, vc)), 0)), int(min(np.ceil(max(va, vb, vc)), SIZE - 1))
        if lo_u > hi_u or lo_v > hi_v:
            continue
        gu, gv = np.meshgrid(np.arange(lo_u, hi_u + 1) + 0.5, np.arange(lo_v, hi_v + 1) + 0.5)
        det = (vb - vc) * (ua - uc) + (uc - ub) * (va - vc)
        if abs(det) < 1e-9:
            continue
        wa = ((vb - vc) * (gu - uc) + (uc - ub) * (gv - vc)) / det
        wb = ((vc - va) * (gu - uc) + (ua - uc) * (gv - vc)) / det
        wc = 1.0 - wa - wb
        # Half-texel slack so thin triangles still reach the texel they cross.
        slack = 0.5 / max(abs(det) ** 0.5, 1.0)
        inside = (wa >= -slack) & (wb >= -slack) & (wc >= -slack)
        tz = wa * za + wb * zb + wc * zc
        tz = np.where(inside & (tz >= depth[0]) & (tz <= depth[1]), tz, np.inf)
        block = skin[lo_v:hi_v + 1, lo_u:hi_u + 1]
        np.minimum(block, tz, out=block)
    return skin


def fit_skin(deepest):
    """Smooth skin surface under the bangs.

    Tripo faces are outer shells: where a strand crosses the face there is no
    skin behind it, so the deepest layer jumps forward onto the strand. Fit a
    low-order polynomial to the deepest layer over the face and iteratively drop
    texels that sit in front of the fit (strands), keeping the skin.
    """
    gv, gu = np.mgrid[0:SIZE, 0:SIZE]
    u = (gu + 0.5) / SIZE * 2.0 - 1.0
    v = (gv + 0.5) / SIZE * 2.0 - 1.0
    terms = [u ** i * v ** j for i in range(FIT_DEGREE + 1) for j in range(FIT_DEGREE + 1 - i)]
    basis = np.stack([t.ravel() for t in terms], axis=1)
    z = deepest.ravel()
    # Fit only the eye / mouth band of the face; the scalp is mostly hair.
    use = np.isfinite(z) & (np.abs(u.ravel()) < 0.8) & (v.ravel() > -0.6) & (v.ravel() < 0.9)
    for _ in range(12):
        coeffs, *_ = np.linalg.lstsq(basis[use], z[use], rcond=None)
        residual = z - basis @ coeffs
        use = use & (residual < STRAND_GAP)
    fitted = (basis @ coeffs).reshape(SIZE, SIZE)
    kept = residual[use]
    print(f"  fit kept={use.sum()} residual p05={np.percentile(kept, 5) * 1000:.1f}mm p95={np.percentile(kept, 95) * 1000:.1f}mm")
    finite = np.isfinite(deepest)
    strand = finite & (deepest - fitted >= STRAND_GAP)
    # Nose / mouth bumps also rise above the smooth fit, but they have a shallow
    # outline and are enclosed by skin or sit in the lower face, while hair
    # reaches the face outline from above and ends in a depth step.
    for region in components(strand):
        steps = []
        enclosed = True
        for y, x in region:
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if not (0 <= ny < SIZE and 0 <= nx < SIZE) or not finite[ny, nx]:
                    enclosed = False
                elif not strand[ny, nx]:
                    steps.append(deepest[y, x] - deepest[ny, nx])
        if DEBUG and len(region) > 15:
            print(f"  region n={len(region)} enclosed={enclosed} v={np.mean([y for y, _ in region]) / SIZE:.2f} median_step={np.median(steps) * 1000 if steps else -1:.2f}mm")
        # Hair hangs from the scalp; a raised region centred in the lower face
        # (nose / mouth / chin) may also reach the chin outline.
        lower_face = np.mean([y for y, _ in region]) / SIZE > LOWER_FACE_V
        if (enclosed or lower_face) and steps and np.median(steps) < SMOOTH_STEP:
            for y, x in region:
                strand[y, x] = False
    # Follow the real surface where it is skin; under strands use the fit.
    return np.where(finite & ~strand, deepest, fitted)


def components(mask):
    """4-connected regions of a boolean grid as lists of (y, x)."""
    seen = np.zeros_like(mask)
    regions = []
    for start in zip(*np.nonzero(mask)):
        if seen[start]:
            continue
        seen[start] = True
        stack, region = [start], []
        while stack:
            y, x = stack.pop()
            region.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < SIZE and 0 <= nx < SIZE and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        regions.append(region)
    return regions


def encode(skin, depth):
    return np.clip((skin - depth[0]) / (depth[1] - depth[0]), 0.0, 1.0)


def write_png(path, values):
    image = bpy.data.images.new(path.stem, SIZE, SIZE, alpha=False, float_buffer=False)
    image.colorspace_settings.name = "Non-Color"
    # Blender images start at the bottom row; flip so PNG row 0 is face_uv.y = 0.
    rgba = np.repeat(values[::-1, :, None], 4, axis=2)
    rgba[..., 3] = 1.0
    image.pixels.foreach_set(rgba.astype(np.float32).ravel())
    image.filepath_raw = str(path)
    image.file_format = "PNG"
    image.save()


def main():
    for profile in sorted(PROFILES.glob("legacy_size007_*.tres")):
        face_id = profile.stem.rsplit("_", 1)[1]
        if not (FACES / face_id / "model.glb").exists():
            continue
        rect, depth = read_profile(profile)
        print(f"SKIN_DEPTH {face_id}")
        values = encode(fit_skin(bake(face_triangles(face_id), rect, depth)), depth)
        output = PROFILES / f"{profile.stem}_skin_depth.png"
        write_png(output, values)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
