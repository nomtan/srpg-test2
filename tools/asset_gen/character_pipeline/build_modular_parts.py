"""Export independent Tripo parts without an intermediate character.glb.

Run in a fresh Blender process, for example:
  blender -b --factory-startup --python build_modular_parts.py -- --kind body --id 005
  blender -b --factory-startup --python build_modular_parts.py -- --kind face --id 005

Each part's normalization.json is an asset contract, never a Body/Face pair fit.
The raw Tripo inputs are immutable. Export to a staging root with --output-root
before replacing a live model.glb.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_characters import align_arms, bounds, import_source, transfer_weights
from build_golden_path import create_animations


ROOT = Path(__file__).resolve().parents[3]
MODULAR = ROOT / "assets/characters/modular"
REFERENCE_RIG = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"
REQUIRED_CLIPS = ("idle", "walk", "attack", "hit")


def contract(kind, part_id):
    path = MODULAR / kind / part_id / "normalization.json"
    if not path.is_file():
        raise ValueError(f"Missing per-part normalization contract: {path}")
    settings = json.loads(path.read_text(encoding="utf8"))
    expected = {
        "standard": "ashen_character_v1",
        "version": 1,
        "asset_type": kind,
        "id": part_id,
        "rig_profile": "humanoid_v1",
        "coordinate_space": "humanoid_v1_rest",
    }
    mismatches = [key for key, value in expected.items() if settings.get(key) != value]
    if mismatches:
        raise ValueError(f"Invalid Standard v1 metadata fields {mismatches}: {path}")
    return settings


def assert_identity(obj, label):
    if any(abs(obj.scale[i] - 1.0) > 1e-5 for i in range(3)) or any(
        abs(obj.location[i]) > 1e-5 for i in range(3)
    ) or any(abs(obj.rotation_euler[i]) > 1e-5 for i in range(3)):
        raise ValueError(f"{label} transform must be identity: {obj.name}")


def inspect_static(obj, kind):
    if obj.type != "MESH" or not obj.data.vertices:
        raise ValueError(f"{kind} must contain a mesh")
    if obj.vertex_groups or any(mod.type == "ARMATURE" for mod in obj.modifiers):
        raise ValueError(f"{kind} cannot be skinned")
    assert_identity(obj, kind)


def clean_toon_materials(obj):
    """Keep the base-color path and remove PBR inputs ignored by the game shader."""
    for material in obj.data.materials:
        if material is None or not material.use_nodes:
            continue
        tree = material.node_tree
        principled = next((node for node in tree.nodes if node.type == "BSDF_PRINCIPLED"), None)
        if principled is None:
            continue
        keep = {"Base Color", "Alpha"}
        for socket in principled.inputs:
            if socket.name not in keep:
                for link in list(socket.links):
                    tree.links.remove(link)
        for name, value in (("Metallic", 0.0), ("Roughness", 1.0), ("Specular IOR Level", 0.0)):
            if name in principled.inputs:
                principled.inputs[name].default_value = value


def export(path, objects, animations):
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(path), use_selection=True, use_active_scene=True,
        export_animations=animations, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_range=False, export_extras=True,
    )


def prepare_body(part_id, settings):
    if settings.get("rig_profile") != "humanoid_v1":
        raise ValueError("Body requires rig_profile humanoid_v1")
    if not REFERENCE_RIG.is_file():
        raise ValueError(f"Missing humanoid_v1 reference rig: {REFERENCE_RIG}")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(REFERENCE_RIG))
    imported = set(bpy.data.objects) - before
    rig = next(obj for obj in imported if obj.type == "ARMATURE")
    donor = next(obj for obj in rig.children if obj.type == "MESH")
    if len(rig.data.bones) != 65 or "head" not in rig.data.bones:
        raise ValueError("Reference asset no longer matches humanoid_v1")
    for pose_bone in rig.pose.bones:
        pose_bone.custom_shape = None
    rig.name = "humanoid_v1"
    rig.data.name = "humanoid_v1"
    body = donor
    if part_id != "001":
        imported_body = import_source("body", part_id)
        if len(imported_body) != 1:
            raise ValueError("Body source must contain one static mesh")
        body = next(iter(imported_body))
        if body.type != "MESH":
            raise ValueError("Body source must be a mesh")
        lo, hi = bounds(body)
        donor_lo, donor_hi = bounds(donor)
        scale = (donor_hi.z - donor_lo.z) / (hi.z - lo.z)
        center = Vector(((lo.x + hi.x) / 2, 0, lo.z))
        body.data.transform(Matrix.Scale(scale, 4) @ Matrix.Translation(-center) @ body.matrix_world)
        body.matrix_world = Matrix.Identity(4)
        if settings.get("arm_alignment") == "match_rig_source":
            align_arms(donor, body, rig)
        transfer_weights(donor, body, rig)
        for collection in list(donor.users_collection):
            collection.objects.unlink(donor)
    body.name = "Body"
    clean_toon_materials(body)
    body.data.materials[0].name = "Body_" + part_id
    root = bpy.data.objects.new("Character", None)
    bpy.context.scene.collection.objects.link(root)
    rig.parent = root
    create_animations(rig)
    if len(rig.data.bones) != 65 or "head" not in rig.data.bones:
        raise ValueError("Body skeleton validation failed")
    if not all(name in bpy.data.actions for name in REQUIRED_CLIPS):
        raise ValueError("Body animation validation failed")
    assert_identity(root, "Body root")
    assert_identity(rig, "Body rig")
    assert_identity(body, "Body mesh")
    return [root, rig, body]


def normalize_head_hair_materials(part, part_id):
    """Require an explicit Head/Hair material boundary for post-v1 faces.

    Geometry guessing is intentionally avoided: a false hair classification can
    project eyes onto bangs. Reference faces 001-006 remain legacy-compatible.
    """
    if int(part_id) <= 6:
        return
    head = []
    hair = []
    for material in part.data.materials:
        lowered = material.name.lower()
        if lowered.startswith("head"):
            head.append(material)
        elif lowered.startswith("hair"):
            hair.append(material)
    if not head or not hair:
        raise ValueError(
            "Standard v1 Face requires materials named Head* and Hair*; "
            "prepare the source in Blender instead of guessing geometry"
        )
    for index, material in enumerate(head):
        material.name = "Head" if index == 0 else f"Head_{index + 1:02d}"
    for index, material in enumerate(hair):
        material.name = "Hair" if index == 0 else f"Hair_{index + 1:02d}"


def prepare_static(kind, part_id, settings):
    imported = import_source(kind, part_id)
    if len(imported) != 1:
        raise ValueError(f"{kind} source must contain one mesh and no rig")
    part = next(iter(imported))
    if part.type != "MESH" or part.animation_data:
        raise ValueError(f"{kind} source must be an unanimated mesh")
    scale = settings.get("scale")
    position = settings.get("position")
    if not isinstance(scale, (float, int)) or scale <= 0 or not isinstance(position, list) or len(position) != 3:
        raise ValueError(f"{kind} normalization requires positive scale and 3D position")
    part.data.transform(Matrix.Translation(Vector(position)) @ Matrix.Scale(scale, 4) @ part.matrix_world)
    part.matrix_world = Matrix.Identity(4)
    part.name = kind.capitalize()
    clean_toon_materials(part)
    if kind == "face":
        normalize_head_hair_materials(part, part_id)
    inspect_static(part, kind)
    return [part]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("body", "face"), required=True)
    parser.add_argument("--id", required=True)
    parser.add_argument("--output-root", type=Path, default=MODULAR)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not (len(args.id) == 3 and args.id.isdigit() and int(args.id) > 0):
        raise ValueError("Part ID must be a positive three-digit number")
    source = ROOT / "assets/characters/tripo" / args.kind / args.id / "model.glb"
    if (ROOT / "assets/characters/tripo").resolve() in args.output_root.resolve().parents or args.output_root.resolve() == (ROOT / "assets/characters/tripo").resolve():
        raise ValueError("Output cannot overwrite immutable Tripo sources")
    before_hash = hashlib.sha256(source.read_bytes()).hexdigest()
    settings = contract(args.kind, args.id)
    if settings.get("source_sha256") != before_hash:
        raise ValueError("Immutable Tripo source hash differs from normalization metadata")
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.system = "METRIC"
    scene.render.fps = 30
    objects = prepare_body(args.id, settings) if args.kind == "body" else prepare_static(args.kind, args.id, settings)
    target = args.output_root / args.kind / args.id / "model.glb"
    export(target, objects, args.kind == "body")
    if hashlib.sha256(source.read_bytes()).hexdigest() != before_hash:
        raise ValueError("Immutable Tripo source changed")
    print("DIRECT_MODULAR_EXPORT", args.kind, args.id, target)


if __name__ == "__main__":
    main()
