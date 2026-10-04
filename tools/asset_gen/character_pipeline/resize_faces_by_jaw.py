"""Bake the hair-independent jaw-width size into legacy Faces, preserve UV0 and profile placement.

  blender -b --factory-startup --python resize_faces_by_jaw.py

Each Face's `head_metrics.jaw_width_source` is recorded by measure_face_jaw.py.
scale = face_size.jaw_width_m / jaw_width_source, pivoting on the existing
position so the chin/neck seam stays put. Faces in face_size.exceptions keep
their scale.
"""
import hashlib
import json
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from character_asset_metrics import inspect_glb
from build_modular_parts import STANDARD, prepare_static, export

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_RECT = (-.23, .848, .46, .36)
DEFAULT_DEPTH = (.18, .33)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


def resize():
    size = json.loads(STANDARD.read_text(encoding="utf8"))["face_size"]
    target = size["jaw_width_m"]
    rows = []
    for folder in sorted((ROOT / "assets/characters/modular/face").iterdir()):
        number = folder.name
        if number in size["exceptions"]:
            continue
        metadata_path = folder / "normalization.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf8"))
        metrics = metadata["head_metrics"]
        if metrics["method"] != size["metric"]:
            raise ValueError(f"face{number} head_metrics.method differs from {size['metric']}")
        old_scale = metadata["scale"]
        # Pre-resize placement; profile_origin is where the default projection was authored.
        original = metadata.setdefault("size_baseline", dict(scale=old_scale, position=metadata["position"]))
        origin = original.get("profile_origin", original["position"])
        metadata["scale"] = target / metrics["jaw_width_source"]
        metadata.pop("face_width_m", None)
        metadata["size_reference"] = size["metric"]
        profile = metadata["expression_profile"]
        # Transform the authored legacy projection into the resized, normalized space.
        factor = metadata["scale"] / original["scale"]
        x, y, z = origin
        new_x, new_y, new_z = metadata["position"]
        rect = (new_x + (DEFAULT_RECT[0] - x) * factor, new_z + (DEFAULT_RECT[1] - z) * factor,
                DEFAULT_RECT[2] * factor, DEFAULT_RECT[3] * factor)
        depth = tuple(-new_y + (value + y) * factor for value in DEFAULT_DEPTH)
        path = ROOT / f"assets/characters/_shared/face/expression/profiles/{profile}.tres"
        path.write_text('[gd_resource type="Resource" script_class="ExpressionProfile" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/character/expression_profile.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\nface_rect = Vector4(%s)\nsurface_depth = Vector2(%s)\n' % (", ".join(map(str, rect)), ", ".join(map(str, depth))), encoding="utf-8", newline="\n")
        old = inspect_glb(folder / "model.glb")["geometry"]["bounds"]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        parts = prepare_static("face", number, metadata)
        export(folder / "model.glb", parts, False)
        write_json(metadata_path, metadata)
        actual = inspect_glb(folder / "model.glb")["geometry"]["bounds"]
        source = ROOT / f"assets/characters/tripo/face/{number}/model.glb"
        assert hashlib.sha256(source.read_bytes()).hexdigest() == metadata["source_sha256"]
        rows.append(dict(id=number, old_scale=old_scale, scale=metadata["scale"], ratio=metadata["scale"] / old_scale, old=old, new=actual))
    out = ROOT / "artifacts/face_size_jaw"
    out.mkdir(parents=True, exist_ok=True)
    write_json(out / "resize.json", dict(metric=size["metric"], target_jaw_width=target, faces=rows))
    print("FACE_SIZE_JAW", target, [(row["id"], round(row["ratio"], 4)) for row in rows])


resize()
