"""Split the validated roster GLBs into reusable Body and Face scenes.

Run with Blender: blender -b --factory-startup --python export_modular_parts.py
The Tripo source GLBs and the existing combined GLBs are read only.
"""
from pathlib import Path
import json
import struct
import bpy


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "assets/characters/generated"
OUTPUT = ROOT / "assets/characters/modular"


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def select_only(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)


def export(path, objects, animations=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    select_only(objects)
    bpy.ops.export_scene.gltf(
        filepath=str(path), use_selection=True, export_animations=animations,
        export_animation_mode="ACTIONS", export_force_sampling=True,
        export_frame_range=False, export_extras=True,
    )


def write_body_without_head(source, target):
    """Keep validated skin and four clips byte-for-byte, removing Head node.

    Blender's glTF importer re-exports imported actions as duplicate .001 clips.
    Editing the glTF scene graph avoids that change to the playable Body.
    """
    blob = source.read_bytes()
    magic, version, length = struct.unpack_from("<III", blob)
    assert magic == 0x46546C67 and version == 2 and length == len(blob)
    json_length, json_type = struct.unpack_from("<II", blob, 12)
    assert json_type == 0x4E4F534A
    document = json.loads(blob[20:20 + json_length])
    assert [a["name"] for a in document["animations"]] == ["attack", "hit", "idle", "walk"]
    nodes = document["nodes"]
    head = next(i for i, node in enumerate(nodes) if node.get("name") == "Head")
    assert nodes[head].get("mesh") is not None
    nodes.pop(head)

    def remap(index):
        assert index != head
        return index - 1 if index > head else index

    for node in nodes:
        if "children" in node:
            node["children"] = [remap(i) for i in node["children"] if i != head]
    for scene in document["scenes"]:
        scene["nodes"] = [remap(i) for i in scene["nodes"]]
    for skin in document.get("skins", []):
        skin["joints"] = [remap(i) for i in skin["joints"]]
        if "skeleton" in skin:
            skin["skeleton"] = remap(skin["skeleton"])
    for animation in document["animations"]:
        for channel in animation["channels"]:
            channel["target"]["node"] = remap(channel["target"]["node"])
    # Retain only the body's geometry, texture, and referenced animation data.
    assert len(document["meshes"]) == len(document["materials"]) == 2
    assert len(document["textures"]) >= 2 and len(document["images"]) >= 2
    body_mesh = document["meshes"][0]
    assert all(p.get("material") == 0 and "extensions" not in p for p in body_mesh["primitives"])
    assert document["materials"][0]["pbrMetallicRoughness"]["baseColorTexture"]["index"] == 0
    assert document["textures"][0]["source"] == 0
    document["meshes"] = [body_mesh]
    document["materials"] = document["materials"][:1]
    document["textures"] = document["textures"][:1]
    document["images"] = document["images"][:1]

    used_accessors = set()
    for primitive in body_mesh["primitives"]:
        used_accessors.update(primitive["attributes"].values())
        if "indices" in primitive:
            used_accessors.add(primitive["indices"])
        for target in primitive.get("targets", []):
            used_accessors.update(target.values())
    for skin in document.get("skins", []):
        if "inverseBindMatrices" in skin:
            used_accessors.add(skin["inverseBindMatrices"])
    for animation in document["animations"]:
        for sampler in animation["samplers"]:
            used_accessors.update((sampler["input"], sampler["output"]))
    accessor_map = {old: new for new, old in enumerate(sorted(used_accessors))}
    for primitive in body_mesh["primitives"]:
        primitive["attributes"] = {k: accessor_map[v] for k, v in primitive["attributes"].items()}
        if "indices" in primitive:
            primitive["indices"] = accessor_map[primitive["indices"]]
        for target in primitive.get("targets", []):
            for key, value in target.items():
                target[key] = accessor_map[value]
    for skin in document.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = accessor_map[skin["inverseBindMatrices"]]
    for animation in document["animations"]:
        for sampler in animation["samplers"]:
            sampler["input"] = accessor_map[sampler["input"]]
            sampler["output"] = accessor_map[sampler["output"]]
    document["accessors"] = [document["accessors"][i] for i in sorted(used_accessors)]

    used_views = {accessor["bufferView"] for accessor in document["accessors"]}
    assert all("sparse" not in accessor for accessor in document["accessors"])
    used_views.add(document["images"][0]["bufferView"])
    view_map = {old: new for new, old in enumerate(sorted(used_views))}
    binary_length, binary_type = struct.unpack_from("<II", blob, 20 + json_length)
    assert binary_type == 0x004E4942
    binary = blob[28 + json_length:28 + json_length + binary_length]
    compact_binary = bytearray()
    compact_views = []
    for old in sorted(used_views):
        view = document["bufferViews"][old].copy()
        assert view.get("buffer", 0) == 0
        compact_binary.extend(b"\0" * ((-len(compact_binary)) % 4))
        offset = view.get("byteOffset", 0)
        data = binary[offset:offset + view["byteLength"]]
        assert len(data) == view["byteLength"]
        view["byteOffset"] = len(compact_binary)
        compact_binary.extend(data)
        compact_views.append(view)
    for accessor in document["accessors"]:
        accessor["bufferView"] = view_map[accessor["bufferView"]]
    document["images"][0]["bufferView"] = view_map[document["images"][0]["bufferView"]]
    document["bufferViews"] = compact_views
    document["buffers"] = [{"byteLength": len(compact_binary)}]
    compact_binary.extend(b"\0" * ((-len(compact_binary)) % 4))

    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((-len(encoded)) % 4)
    header = struct.pack("<III", magic, version, 28 + len(encoded) + len(compact_binary))
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(header + struct.pack("<II", len(encoded), json_type) + encoded +
                       struct.pack("<II", len(compact_binary), binary_type) + compact_binary)


def split(index):
    clear_scene()
    combined = SOURCE / f"charcter{index}" / "character.glb"
    bpy.ops.import_scene.gltf(filepath=str(combined))
    rig = next(obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE")
    body = next(obj for obj in bpy.context.scene.objects if obj.name == "Body")
    face = next(obj for obj in bpy.context.scene.objects if obj.name == "Head")
    root = rig.parent
    assert root and rig.data.bones.get("head")
    assert len(face.data.vertices) and face.data.materials

    # Body retains the validated skin, rest pose, and exactly four clips.
    write_body_without_head(combined, OUTPUT / "body" / index / "model.glb")

    # Keep the validated Head vertices in skeleton rest coordinates. Godot's
    # imported bone basis can differ from Blender's; the assembler applies
    # the inverse of Godot's own head rest transform at the common socket.
    head_rest = rig.data.bones["head"].matrix_local.copy()
    assert face.matrix_world.is_identity
    for modifier in list(face.modifiers):
        face.modifiers.remove(modifier)
    face.vertex_groups.clear()
    face.parent = None
    face.matrix_world.identity()
    face.name = "Face"
    export(OUTPUT / "face" / index / "model.glb", [face])
    print("MODULAR", index, "head_rest", tuple(head_rest.translation))


for i in range(1, 5):
    split(f"{i:03d}")
