"""Build the legacy Face expression atlases from Face002's painted features.

Face002 (`tripo/face/002/face+facial.glb`) paints its eyes, eyebrows and mouth
into the texture. The other legacy Faces draw an overlay instead, and that
overlay must match Face002 exactly in position and texture. This script:

1. Projects Face002's front skin layer over the shared legacy face_rect
   (profile `legacy_size007_002`) at SIZE texels, sampling its texture.
2. Keys the painted eyes / right eyebrow / mouth against the local skin tone
   and un-mixes them (straight alpha). Bangs hide Face002's left eyebrow, so it
   is the right one mirrored about the features' centre line.
3. Writes PNG atlases with the ExpressionController row order. Each `normal`
   row is Face002's pixels unchanged; the other rows warp those same pixels
   (lid compression, lash-only closed eyes, brow tilts) or, for the mouth,
   draw shapes in Face002's mouth colour.

All legacy profiles share Face002's face_rect, so a texel lands on the same
rest-space point as on Face002. Re-bake the skin-depth maps after changing it.

Run from the repository root:
  blender -b --factory-startup --python tools/asset_gen/character_pipeline/build_face002_feature_atlases.py
"""
import re
import struct
import sys
import zlib
from pathlib import Path

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[3]
FACE = ROOT / "assets/characters/modular/face/002/model.glb"
PROFILE = ROOT / "assets/characters/_shared/face/expression/profiles/legacy_size007_002.tres"
DESTINATION = ROOT / "assets/characters/_shared/face/expression"
SIZE = 512
# The front layer sits in front of the head centre; deeper hits are back hair.
MIN_DEPTH = 0.10
SKIN = np.array([253.0, 207.0, 168.0])
# Face002's features are centred right of the rest-space midline (x = 0).
CENTER_X = 274.5
EYE_L = (127, 222, 232, 366)
EYE_R = (317, 222, 422, 366)
BROW_R = ((331, 209), (395, 192), 5)
MOUTH = (262, 408, 284, 418)
MOUTH_CENTER = (272.5, 412.5)
EYES = ["normal", "blink", "closed_strong", "angry", "sad", "surprised", "narrow", "happy"]
EYEBROWS = ["normal", "angry", "sad", "worried", "surprised", "confident"]
MOUTHS = ["normal", "smile", "laugh", "open", "angry", "sad", "smirk"]


def face_rect():
    text = PROFILE.read_text(encoding="utf-8")
    return [float(v) for v in re.search(r"face_rect = Vector4\(([^)]*)\)", text).group(1).split(",")]


def project(rect):
    """Front layer colour (0-255) over rect; row 0 is the top of the rect."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(FACE))
    obj = next(o for o in bpy.data.objects if o.type == "MESH")
    mesh = obj.data
    mesh.calc_loop_triangles()
    co = np.array([obj.matrix_world @ v.co for v in mesh.vertices])
    # Blender is Z-up; Godot / glTF rest space is (x, z, -y).
    godot = np.stack([co[:, 0], co[:, 2], -co[:, 1]], axis=1)
    uv_data = mesh.uv_layers.active.data
    uv = np.array([uv_data[i].uv[:] for i in range(len(uv_data))])
    points = godot[np.array([t.vertices[:] for t in mesh.loop_triangles])]
    uvs = uv[np.array([t.loops[:] for t in mesh.loop_triangles])]
    normals = np.cross(points[:, 1] - points[:, 0], points[:, 2] - points[:, 0])
    lengths = np.linalg.norm(normals, axis=1)
    keep = (lengths > 1e-12) & (normals[:, 2] > 0.0)
    points, uvs = points[keep], uvs[keep]
    x0, y0, width, height = rect
    u = (points[..., 0] - x0) / width * SIZE
    v = (1.0 - (points[..., 1] - y0) / height) * SIZE
    z = points[..., 2]
    # Deepest front-facing hit: the skin under the bangs where the shell has it.
    depth = np.full((SIZE, SIZE), np.inf)
    texcoord = np.zeros((SIZE, SIZE, 2))
    for k in range(len(points)):
        (ua, ub, uc), (va, vb, vc) = u[k], v[k]
        lo_u, hi_u = int(max(np.floor(min(ua, ub, uc)), 0)), int(min(np.ceil(max(ua, ub, uc)), SIZE - 1))
        lo_v, hi_v = int(max(np.floor(min(va, vb, vc)), 0)), int(min(np.ceil(max(va, vb, vc)), SIZE - 1))
        det = (vb - vc) * (ua - uc) + (uc - ub) * (va - vc)
        if lo_u > hi_u or lo_v > hi_v or abs(det) < 1e-9:
            continue
        gu, gv = np.meshgrid(np.arange(lo_u, hi_u + 1) + 0.5, np.arange(lo_v, hi_v + 1) + 0.5)
        wa = ((vb - vc) * (gu - uc) + (uc - ub) * (gv - vc)) / det
        wb = ((vc - va) * (gu - uc) + (ua - uc) * (gv - vc)) / det
        wc = 1.0 - wa - wb
        tz = wa * z[k, 0] + wb * z[k, 1] + wc * z[k, 2]
        block = depth[lo_v:hi_v + 1, lo_u:hi_u + 1]
        update = (wa >= -1e-4) & (wb >= -1e-4) & (wc >= -1e-4) & (tz >= MIN_DEPTH) & (tz < block)
        block[update] = tz[update]
        tuv = wa[..., None] * uvs[k, 0] + wb[..., None] * uvs[k, 1] + wc[..., None] * uvs[k, 2]
        texcoord[lo_v:hi_v + 1, lo_u:hi_u + 1][update] = tuv[update]
    image = next(i for i in bpy.data.images if i.size[0] > 0)
    w, h = image.size
    texture = np.array(image.pixels[:], dtype=np.float32).reshape(h, w, 4)[..., :3] * 255.0
    tx, ty = texcoord[..., 0] * w - 0.5, texcoord[..., 1] * h - 0.5
    ix, iy = np.floor(tx).astype(int), np.floor(ty).astype(int)
    fx, fy = (tx - ix)[..., None], (ty - iy)[..., None]
    x_a, x_b = np.clip(ix, 0, w - 1), np.clip(ix + 1, 0, w - 1)
    y_a, y_b = np.clip(iy, 0, h - 1), np.clip(iy + 1, 0, h - 1)
    color = (texture[y_a, x_a] * (1 - fx) * (1 - fy) + texture[y_a, x_b] * fx * (1 - fy)
             + texture[y_b, x_a] * (1 - fx) * fy + texture[y_b, x_b] * fx * fy)
    color[~np.isfinite(depth)] = 0.0
    return color


def blur(a, sigma):
    r = int(3 * sigma)
    kernel = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    kernel /= kernel.sum()
    for axis in (0, 1):
        pad = [(0, 0)] * a.ndim
        pad[axis] = (r, r)
        padded = np.pad(a, pad, mode="edge")
        n = a.shape[axis]
        a = sum(kernel[i] * np.take(padded, range(i, i + n), axis=axis) for i in range(2 * r + 1))
    return a


def dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy * dy + dx * dx <= r * r:
                out |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def components(mask):
    """8-connected labels."""
    labels = np.zeros(mask.shape, int)
    count = 0
    for start in zip(*np.nonzero(mask)):
        if labels[start]:
            continue
        count += 1
        labels[start] = count
        stack = [start]
        while stack:
            y, x = stack.pop()
            for ny in (y - 1, y, y + 1):
                for nx in (x - 1, x, x + 1):
                    if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = count
                        stack.append((ny, nx))
    return labels, count


def extract(color):
    """Face002 feature layers as (rgb, alpha) in the SIZE x SIZE face frame."""
    is_skin = (np.linalg.norm(color - SKIN, axis=2) < 22).astype(float)
    local = blur(color * is_skin[..., None], 14) / np.maximum(blur(is_skin, 14), 1e-3)[..., None]
    distance = np.linalg.norm(color - local, axis=2)
    red_green = color[..., 0] - color[..., 1]
    # Lit hair is orange (strongly red over green); darker hair shading only
    # matters around the eyes, where the lash is much darker still.
    alpha_brow = np.clip((distance - 14) / 41, 0, 1) * ~((red_green > 55) & (color[..., 1] > 148))
    alpha_eye = alpha_brow * ~((red_green > 55) & (color[..., 1] > 105))

    def finish(mask, alpha):
        soft = np.clip(blur(dilate(mask, 3).astype(float), 1.2) * 1.5, 0, 1)
        a = alpha * soft
        # Un-mix from the local skin so the layer composites back to the source.
        rgb = np.where(a[..., None] > 1e-3, local + (color - local) / np.maximum(a, 1e-3)[..., None], 0)
        return np.clip(rgb, 0, 255), a

    def eye(box):
        x0, y0, x1, y1 = box
        labels, count = components(alpha_eye[y0:y1, x0:x1] > 0.2)
        keep = np.zeros(labels.shape, bool)
        for i in range(1, count + 1):
            ys, xs = np.nonzero(labels == i)
            # Hair edges enter from the box sides / top; the eye itself is large.
            touches = xs.min() == 0 or xs.max() == x1 - x0 - 1 or ys.min() == 0
            if len(ys) >= 6 and (not touches or len(ys) > 2000):
                keep |= labels == i
        mask = np.zeros((SIZE, SIZE), bool)
        mask[y0:y1, x0:x1] = keep
        return finish(mask, alpha_eye)

    gy, gx = np.mgrid[0:SIZE, 0:SIZE]
    (bx0, by0), (bx1, by1), half = BROW_R
    d = np.array([bx1 - bx0, by1 - by0], float)
    t = np.clip(((gx - bx0) * d[0] + (gy - by0) * d[1]) / (d @ d), 0, 1)
    brow_mask = np.hypot(gx - (bx0 + t * d[0]), gy - (by0 + t * d[1])) < half
    mouth_mask = np.zeros((SIZE, SIZE), bool)
    mx0, my0, mx1, my1 = MOUTH
    mouth_mask[my0:my1, mx0:mx1] = True
    brow_r = finish(brow_mask, alpha_brow)
    return {
        "eye_l": eye(EYE_L),
        "eye_r": eye(EYE_R),
        "brow_r": brow_r,
        "brow_l": mirror(brow_r),
        "mouth": finish(mouth_mask, alpha_brow),
    }


def mirror(layer):
    source = np.clip(np.round(2 * CENTER_X - np.arange(SIZE)).astype(int), 0, SIZE - 1)
    return layer[0][:, source], layer[1][:, source]


def bounds(layer):
    ys, xs = np.nonzero(layer[1] > 0.05)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def sample(layer, sx, sy):
    """Bilinear sample of (rgb, alpha) at float source coords (premultiplied)."""
    rgb, a = layer
    pre = np.concatenate([rgb * a[..., None], a[..., None]], axis=2)
    ix, iy = np.floor(sx).astype(int), np.floor(sy).astype(int)
    fx, fy = (sx - ix)[..., None], (sy - iy)[..., None]
    inside = (ix >= 0) & (iy >= 0) & (ix < SIZE - 1) & (iy < SIZE - 1)
    ix, iy = np.clip(ix, 0, SIZE - 2), np.clip(iy, 0, SIZE - 2)
    out = (pre[iy, ix] * (1 - fx) * (1 - fy) + pre[iy, ix + 1] * fx * (1 - fy)
           + pre[iy + 1, ix] * (1 - fx) * fy + pre[iy + 1, ix + 1] * fx * fy)
    out[~inside] = 0
    a = out[..., 3]
    return np.where(a[..., None] > 1e-4, out[..., :3] / np.maximum(a, 1e-4)[..., None], 0), a


def inner_t(layer, gx):
    """0 at the outer corner, 1 at the corner nearest the face centre."""
    x0, _, x1, _ = bounds(layer)
    t = np.clip((gx - x0) / max(x1 - x0, 1), 0, 1)
    return t if (x0 + x1) / 2 < CENTER_X else 1 - t


def lid(layer, inner, outer):
    """Lower the upper lid by inner/outer texels, compressing the eye column-wise."""
    x0, y0, x1, y1 = bounds(layer)
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    t = inner_t(layer, gx)
    shift = outer + (inner - outer) * t
    span = y1 - y0
    sy = y0 + (gy - y0 - shift) * span / np.maximum(span - shift, 1)
    rgb, a = sample(layer, gx, sy)
    a = np.where(gy < y0 + shift, 0, a)
    return rgb, a


def scale(layer, sx_scale, sy_scale, anchor_y=None):
    x0, y0, x1, y1 = bounds(layer)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2 if anchor_y is None else anchor_y
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    return sample(layer, cx + (gx - cx) / sx_scale, cy + (gy - cy) / sy_scale)


def lash(layer):
    """Only the dark upper lash of an eye."""
    rgb, a = layer
    _, y0, _, y1 = bounds(layer)
    gy = np.mgrid[0:SIZE, 0:SIZE][0]
    luminance = rgb @ np.array([0.3, 0.59, 0.11])
    # The lash is reddish brown; the dark top of the iris is a neutral grey.
    keep = (gy < y0 + 0.36 * (y1 - y0)) & (luminance < 120) & (rgb[..., 0] - rgb[..., 2] > 25) & (a > 0.3)
    # The iris outline shares the lash colour; keep only the lash body.
    labels, count = components(keep)
    keep = labels == 1 + int(np.argmax([(labels == i).sum() for i in range(1, count + 1)]))
    soft = np.clip(blur(dilate(keep, 1).astype(float), 0.8) * 1.4, 0, 1)
    return rgb, a * soft


def closed(layer, drop, curve, flip, thickness=1.0):
    """Lash moved down to a closed-lid line.

    curve > 0 bends the line so its middle rises (happy ^^); flip turns the
    lash's own arch over so it sags like a relaxed closed lid.
    """
    strip = lash(layer)
    x0, y0, x1, y1 = bounds(strip)
    cy = (y0 + y1) / 2
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    s = (gx - (x0 + x1) / 2) / max((x1 - x0) / 2, 1)
    offset = drop - curve * (1 - np.clip(s, -1, 1) ** 2)
    local_y = (gy - offset - cy) / thickness
    return sample(strip, gx, cy + (-local_y if flip else local_y))


def brow_shift(layer, inner, outer, arch=0.0):
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(float)
    t = inner_t(layer, gx)
    shift = outer + (inner - outer) * t - arch * (1 - (2 * t - 1) ** 2)
    return sample(layer, gx, gy - shift)


def over(*layers):
    rgb = np.zeros((SIZE, SIZE, 3))
    a = np.zeros((SIZE, SIZE))
    for lrgb, la in layers:
        out_a = la + a * (1 - la)
        rgb = np.where(out_a[..., None] > 1e-5,
                       (lrgb * la[..., None] + rgb * (a * (1 - la))[..., None]) / np.maximum(out_a, 1e-5)[..., None], 0)
        a = out_a
    return rgb, a


def eye_rows(layers):
    rows = []
    for style in EYES:
        pair = []
        for side in ("eye_l", "eye_r"):
            eye = layers[side]
            height = bounds(eye)[3] - bounds(eye)[1]
            pair.append({
                "normal": lambda: eye,
                "blink": lambda: closed(eye, 0.52 * height, 0, True),
                "closed_strong": lambda: closed(eye, 0.50 * height, 0, True, 1.35),
                "angry": lambda: lid(eye, 0.26 * height, 0.02 * height),
                "sad": lambda: lid(eye, 0.02 * height, 0.36 * height),
                "surprised": lambda: scale(eye, 1.04, 1.08),
                "narrow": lambda: lid(eye, 0.40 * height, 0.40 * height),
                "happy": lambda: closed(eye, 0.50 * height, 0.10 * height, False),
            }[style]())
        rows.append(over(*pair))
    return rows


def eyebrow_rows(layers):
    shifts = {
        "normal": (0, 0, 0),
        "angry": (11, -3, 0),
        "sad": (-9, 5, 0),
        "worried": (-12, 0, 3),
        "surprised": (-13, -11, 3),
        "confident": (4, -4, 0),
    }
    return [over(*(brow_shift(layers[side], *shifts[style]) for side in ("brow_l", "brow_r"))) for style in EYEBROWS]


def mouth_rows(layers):
    rgb, a = layers["mouth"]
    # Face002's mouth is two tiny strokes; their colour drives the drawn shapes.
    line = (rgb * a[..., None]).sum((0, 1)) / max(a.sum(), 1e-3)
    inside = line * 0.55
    tongue = np.array([217.0, 129.0, 124.0])
    cx, cy = MOUTH_CENTER
    gy, gx = np.mgrid[0:SIZE, 0:SIZE].astype(float) + 0.5

    def stroke(points, width):
        d = np.full((SIZE, SIZE), np.inf)
        for p, q in zip(points[:-1], points[1:]):
            v = q - p
            t = np.clip(((gx - p[0]) * v[0] + (gy - p[1]) * v[1]) / max(v @ v, 1e-9), 0, 1)
            d = np.minimum(d, np.hypot(gx - p[0] - t * v[0], gy - p[1] - t * v[1]))
        return np.clip(width / 2 + 0.5 - d, 0, 1)

    def fill(points):
        inside_mask = np.zeros((SIZE, SIZE), bool)
        for p, q in zip(points, np.roll(points, -1, axis=0)):
            crosses = (p[1] > gy) != (q[1] > gy)
            x_at = p[0] + (gy - p[1]) * (q[0] - p[0]) / np.where(q[1] == p[1], 1e-9, q[1] - p[1])
            inside_mask ^= crosses & (gx < x_at)
        return blur(inside_mask.astype(float), 0.5)

    def curve(p0, p1, p2, n=24):
        t = np.linspace(0, 1, n)[:, None]
        return (1 - t) ** 2 * np.array(p0) + 2 * (1 - t) * t * np.array(p1) + t ** 2 * np.array(p2)

    def solid(color, alpha):
        return np.broadcast_to(color, (SIZE, SIZE, 3)), alpha

    width = 2.6
    rows = {"normal": layers["mouth"]}
    rows["smile"] = solid(line, stroke(curve((cx - 9, cy - 2), (cx, cy + 6), (cx + 9, cy - 2)), width))
    laugh = np.concatenate([curve((cx - 11, cy - 3), (cx, cy), (cx + 11, cy - 3)),
                            curve((cx + 11, cy - 3), (cx + 10, cy + 13), (cx, cy + 13))[1:],
                            curve((cx, cy + 13), (cx - 10, cy + 13), (cx - 11, cy - 3))[1:]])
    laugh_fill = fill(laugh)
    tongue_a = laugh_fill * np.clip(7.5 - np.hypot((gx - cx) / 1.3, gy - cy - 13), 0, 1)
    rows["laugh"] = over(solid(inside, laugh_fill), solid(tongue, tongue_a))
    open_shape = np.stack([cx + 5.5 * np.sin(np.linspace(0, 2 * np.pi, 40)),
                           cy + 2 + 7 * np.cos(np.linspace(0, 2 * np.pi, 40))], axis=1)
    open_fill = fill(open_shape)
    rows["open"] = over(solid(inside, open_fill),
                        solid(tongue, open_fill * np.clip(3.0 - np.hypot((gx - cx) / 1.4, gy - cy - 6.5), 0, 1)))
    rows["angry"] = solid(line, stroke(np.concatenate([curve((cx - 8, cy + 3), (cx - 4, cy - 2), (cx, cy + 1)),
                                                       curve((cx, cy + 1), (cx + 4, cy - 2), (cx + 8, cy + 3))[1:]]), width))
    rows["sad"] = solid(line, stroke(curve((cx - 8, cy + 3), (cx, cy - 5), (cx + 8, cy + 3)), width))
    rows["smirk"] = solid(line, stroke(curve((cx - 7, cy + 1), (cx + 2, cy + 3), (cx + 9, cy - 4)), width))
    return [rows[style] for style in MOUTHS]


def write_atlas(name, rows):
    rgb = np.concatenate([r for r, _ in rows])
    a = np.concatenate([a for _, a in rows])
    # Bleed colour into transparent texels so filtering does not darken edges.
    weight = blur(a, 3.0)
    bled = blur(rgb * a[..., None], 3.0) / np.maximum(weight, 1e-4)[..., None]
    rgb = np.where(a[..., None] > 1e-3, rgb, np.where(weight[..., None] > 1e-4, bled, SKIN))
    pixels = np.concatenate([rgb, a[..., None] * 255], axis=2).round().clip(0, 255).astype(np.uint8)
    write_png(DESTINATION / f"{name}_atlas.png", pixels)
    print(f"FACE002_ATLAS {name} rows={len(rows)} size={pixels.shape[1]}x{pixels.shape[0]}")


def write_png(path, pixels):
    h, w, _ = pixels.shape
    raw = b"".join(b"\x00" + pixels[y].tobytes() for y in range(h))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def main():
    layers = extract(project(face_rect()))
    write_atlas("legacy_eyes", eye_rows(layers))
    write_atlas("legacy_eyebrows", eyebrow_rows(layers))
    write_atlas("legacy_mouth", mouth_rows(layers))


if __name__ == "__main__":
    main()
    sys.stdout.flush()
