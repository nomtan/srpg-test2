"""Measure the hair-independent Face size metric (jaw width) of modular legacy Faces.

  blender -b --factory-startup --python measure_face_jaw.py -- --ids 001,002,003,005,006,007 [--write]

Renders each modular Face front-orthographic in flat albedo, finds the chin on the
center column (lowest pixel of an uninterrupted 6cm skin run, so strands hanging
below the chin are skipped), and measures the skin run at chin + 4cm. The value is converted to source
units (divided by the current scale) because it must not depend on a previous
normalization. --write stores it as `head_metrics` in normalization.json; the
resize script consumes only that recorded value. Overlays go to
artifacts/face_size_jaw/ for visual review.
"""
import argparse
import colorsys
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
FACES = ROOT / "assets/characters/modular/face"
OUT = ROOT / "artifacts/face_size_jaw"
METHOD = "jaw_width_chin_plus_4cm_v1"
PIXELS = 2400
SPAN = 0.6
CENTER_HEIGHT = 1.1
OFFSET = 0.04
MPP = SPAN / PIXELS


def skin_like(color):
    h, s, v = colorsys.rgb_to_hsv(*color[:3])
    return color[3] > 0.8 and 0.03 < h < 0.11 and 0.12 < s < 0.45 and v > 0.8


def close(a, b, tolerance):
    return a[3] > 0.8 and sum(abs(a[k] - b[k]) for k in range(3)) < tolerance


def render(face_id):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bpy.ops.import_scene.gltf(filepath=str(FACES / face_id / "model.glb"))
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "FLAT"
    scene.display.shading.color_type = "TEXTURE"
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = scene.render.resolution_y = PIXELS
    scene.render.film_transparent = True
    camera = bpy.data.cameras.new("JawCamera")
    camera.type = "ORTHO"
    camera.ortho_scale = SPAN
    obj = bpy.data.objects.new("JawCamera", camera)
    scene.collection.objects.link(obj)
    scene.camera = obj
    obj.rotation_euler = (math.pi / 2, 0, 0)
    obj.location = (0, -3, CENTER_HEIGHT)
    path = OUT / f"front_{face_id}.png"
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    image = bpy.data.images.load(str(path))
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(PIXELS, PIXELS, 4)[::-1]
    return path, pixels


def height(row):
    return CENTER_HEIGHT + (PIXELS / 2 - row) * MPP


def measure(pixels):
    cx = PIXELS // 2
    run = int(0.06 / MPP)
    chin = None
    for row in range(PIXELS - 1, run, -1):
        color = pixels[row, cx]
        if skin_like(color) and all(skin_like(pixels[row - k, cx]) for k in range(1, run)):
            chin = row
            break
    if chin is None:
        raise ValueError("no visible chin on the center column")
    row = chin - int(OFFSET / MPP)
    reference = pixels[row, cx]
    if not skin_like(reference):
        raise ValueError("measurement row center is not skin")

    def extent(step):
        x = cx
        while close(pixels[row, x + step], reference, 0.16):
            x += step
        return x

    left, right = extent(-1), extent(1)
    return dict(chin_height=height(chin), row_height=height(row), left=left, right=right,
                left_x=(left - cx) * MPP, right_x=(right - cx) * MPP, jaw_width=(right - left) * MPP)


def overlay(path, result):
    image = bpy.data.images.load(str(path))
    pixels = np.array(image.pixels[:], dtype=np.float32).reshape(PIXELS, PIXELS, 4)[::-1].copy()
    row = PIXELS // 2 - int((result["row_height"] - CENTER_HEIGHT) / MPP)
    chin = PIXELS // 2 - int((result["chin_height"] - CENTER_HEIGHT) / MPP)
    pixels[row - 2:row + 3, result["left"]:result["right"]] = (1, 0, 0, 1)
    pixels[chin - 2:chin + 3, PIXELS // 2 - 60:PIXELS // 2 + 60] = (0, 0.6, 1, 1)
    image.pixels[:] = pixels[::-1].ravel()
    image.filepath_raw = str(path.with_name(path.stem + "_jaw.png"))
    image.file_format = "PNG"
    image.save()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ids", required=True)
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    OUT.mkdir(parents=True, exist_ok=True)
    rows = {}
    for face_id in args.ids.split(","):
        metadata_path = FACES / face_id / "normalization.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf8"))
        path, pixels = render(face_id)
        result = measure(pixels)
        overlay(path, result)
        result.update(scale=metadata["scale"], jaw_width_source=result["jaw_width"] / metadata["scale"])
        rows[face_id] = result
        if args.write:
            metadata["head_metrics"] = dict(method=METHOD, jaw_width_source=result["jaw_width_source"],
                                            chin_height_source=(result["chin_height"] - metadata["position"][2]) / metadata["scale"])
            metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8", newline="\n")
        print("FACE_JAW", face_id, "%.4f" % result["jaw_width"], "x %.4f..%.4f" % (result["left_x"], result["right_x"]),
              "chin %.4f" % result["chin_height"], "source %.4f" % result["jaw_width_source"])
    (OUT / "measurements.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8", newline="\n")


main()
