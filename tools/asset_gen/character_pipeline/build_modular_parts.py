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
import math
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
    expression_v2 = any(obj.type == "MESH" and obj.data.color_attributes.get("ExpressionMask") is not None for obj in objects)
    bpy.ops.export_scene.gltf(
        filepath=str(path), use_selection=True, use_active_scene=True,
        export_animations=animations, export_animation_mode="ACTIONS",
        export_force_sampling=True, export_frame_range=False, export_extras=True,
        export_vertex_color="NAME" if expression_v2 else "MATERIAL",
        export_vertex_color_name="ExpressionMask",
        export_all_vertex_colors=not expression_v2,
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


def normalize_head_hair_materials(parts, part_id):
    """Require an explicit Head/Hair material boundary for post-v1 faces.

    Geometry guessing is intentionally avoided: a false hair classification can
    project eyes onto bangs. Reference faces 001-006 remain legacy-compatible.
    """
    if int(part_id) <= 6:
        return
    head = []
    hair = []
    materials = {material for part in parts for material in part.data.materials}
    for material in sorted(materials, key=lambda item: item.name if item else ""):
        if material is None:
            raise ValueError("Face has an unassigned material slot")
        lowered = material.name.lower()
        if lowered.startswith("head"):
            head.append(material)
        elif lowered.startswith("hair"):
            hair.append(material)
        else:
            raise ValueError(f"Unclassified Face material: {material.name}")
    if not head or not hair:
        raise ValueError(
            "Standard v1 Face requires materials named Head* and Hair*; "
            "prepare the source in Blender instead of guessing geometry"
        )
    for index, material in enumerate(head):
        material.name = "Head" if index == 0 else f"Head_{index + 1:02d}"
    for index, material in enumerate(hair):
        material.name = "Hair" if index == 0 else f"Hair_{index + 1:02d}"


def validate_expression_authoring(part):
    """Consume artist-authored data; never infer Head/Hair or facial landmarks."""
    mesh = part.data
    if not any(mesh.materials[p.material_index].name.startswith("Head") for p in mesh.polygons):
        return False, False
    if len(mesh.uv_layers) != 2 or mesh.uv_layers[1].name != "ExpressionUV":
        raise ValueError("Face v2 needs base UV first and ExpressionUV second")
    mask = mesh.color_attributes.get("ExpressionMask")
    if mask is None or mesh.color_attributes.active_color != mask:
        raise ValueError("Face v2 needs active color attribute ExpressionMask (red channel)")
    if mask.domain not in {"POINT", "CORNER"}:
        raise ValueError("ExpressionMask must use POINT or CORNER domain")
    enabled = disabled = False
    for polygon in mesh.polygons:
        material = mesh.materials[polygon.material_index]
        if not material.name.startswith("Head"):
            continue
        for loop_index in polygon.loop_indices:
            uv = mesh.uv_layers[1].data[loop_index].uv
            index = loop_index if mask.domain == "CORNER" else mesh.loops[loop_index].vertex_index
            red = mask.data[index].color[0]
            if not all(math.isfinite(value) and 0 <= value <= 1 for value in (*uv, red)):
                raise ValueError("ExpressionUV / ExpressionMask must be finite and within 0..1")
            enabled |= red > 0.5
            disabled |= red <= 0.5
    return enabled, disabled


def prepare_static(kind, part_id, settings, authored_face=None):
    if authored_face is None:
        imported = import_source(kind, part_id)
    else:
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(authored_face))
        imported = set(bpy.data.objects) - before
        if any(obj.type == "ARMATURE" or obj.animation_data for obj in imported):
            raise ValueError("Authored Face must have no rig or animations")
        imported = {obj for obj in imported if obj.type == "MESH"}
        # glTF preserves channel order, not Blender UV/color layer names.
        for obj in imported:
            if len(obj.data.uv_layers) == 2:
                obj.data.uv_layers[1].name = "ExpressionUV"
            if obj.data.color_attributes.active_color is not None:
                obj.data.color_attributes.active_color.name = "ExpressionMask"
    if not imported or any(part.type != "MESH" or part.animation_data for part in imported):
        raise ValueError(f"{kind} source must be an unanimated mesh")
    scale = settings.get("scale")
    position = settings.get("position")
    if not isinstance(scale, (float, int)) or scale <= 0 or not isinstance(position, list) or len(position) != 3:
        raise ValueError(f"{kind} normalization requires positive scale and 3D position")
    if kind == "face":
        normalize_head_hair_materials(imported, part_id)
    enabled = disabled = False
    for part in imported:
        world = part.matrix_world.copy()
        part.parent = None
        part.data = part.data.copy()
        part.data.transform(Matrix.Translation(Vector(position)) @ Matrix.Scale(scale, 4) @ world)
        part.matrix_world = Matrix.Identity(4)
        clean_toon_materials(part)
        if kind == "face" and int(part_id) > 6:
            if settings.get("expression_rendering") != "uv_v2":
                raise ValueError("New Face metadata must declare expression_rendering=uv_v2")
            part_enabled, part_disabled = validate_expression_authoring(part)
            enabled |= part_enabled
            disabled |= part_disabled
        inspect_static(part, kind)
    if kind == "face" and int(part_id) > 6 and (not enabled or not disabled):
        raise ValueError("Head mask must contain both allowed front and excluded regions")
    return list(imported)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--kind", choices=("body", "face"), required=True)
    parser.add_argument("--id", required=True)
    parser.add_argument("--output-root", type=Path, default=MODULAR)
    parser.add_argument("--authored-face", type=Path, help="Explicitly classified working GLB with authored UV/mask; raw source remains immutable")
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
    if args.authored_face:
        if args.kind != "face" or args.authored_face.resolve() == source.resolve():
            raise ValueError("--authored-face requires a separate Face working GLB")
        if hashlib.sha256(args.authored_face.read_bytes()).hexdigest() != settings.get("authored_sha256"):
            raise ValueError("Authored Face hash differs from normalization metadata")
    scene = bpy.context.scene
    scene.unit_settings.scale_length = 1.0
    scene.unit_settings.system = "METRIC"
    scene.render.fps = 30
    objects = prepare_body(args.id, settings) if args.kind == "body" else prepare_static(args.kind, args.id, settings, args.authored_face)
    target = args.output_root / args.kind / args.id / "model.glb"
    export(target, objects, args.kind == "body")
    (target.parent / "normalization.json").write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    if hashlib.sha256(source.read_bytes()).hexdigest() != before_hash:
        raise ValueError("Immutable Tripo source changed")
    print("DIRECT_MODULAR_EXPORT", args.kind, args.id, target)


if __name__ == "__main__":
    main()
