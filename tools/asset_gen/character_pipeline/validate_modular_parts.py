"""Validate exported modular GLBs, including a common humanoid_v1 rest rig.

Run after Blender export and before copying staged parts into the live catalog.
"""
import argparse
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULAR = ROOT / "assets/characters/modular"
REFERENCE_RIG = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"
CLIPS = {"idle", "walk", "attack", "hit"}


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError(f"Invalid GLB: {path}")
    size, kind = struct.unpack_from("<II", data, 12)
    if kind != 0x4E4F534A:
        raise ValueError(f"Missing GLB JSON: {path}")
    return json.loads(data[20:20 + size])


def close(a, b, tolerance=2.5e-5):
    return len(a) == len(b) and all(math.isclose(x, y, abs_tol=tolerance, rel_tol=0) for x, y in zip(a, b))


def bone_contract(document):
    skins = document.get("skins", [])
    if len(skins) != 1:
        raise ValueError("Body requires exactly one skin")
    nodes = document["nodes"]
    joints = skins[0]["joints"]
    parents = {child: parent for parent, node in enumerate(nodes) for child in node.get("children", [])}
    result = {}
    for joint in joints:
        node = nodes[joint]
        name = node["name"]
        if name in result:
            raise ValueError(f"Duplicate bone: {name}")
        parent = parents.get(joint)
        result[name] = {
            "parent": nodes[parent]["name"] if parent in joints else None,
            "translation": node.get("translation", [0, 0, 0]),
            "rotation": node.get("rotation", [0, 0, 0, 1]),
            "scale": node.get("scale", [1, 1, 1]),
        }
    if "head" not in result or not any(name.lower().endswith("hips") for name in result):
        raise ValueError("Body requires root/hips and head bones")
    if len(result) != 65:
        raise ValueError(f"Expected 65 humanoid_v1 bones, found {len(result)}")
    return result


def validate_body(path, reference):
    document = read_glb(path)
    bones = bone_contract(document)
    if bones.keys() != reference.keys():
        raise ValueError(f"Skeleton bone names differ: {path}")
    for name, values in bones.items():
        standard = reference[name]
        if values["parent"] != standard["parent"] or any(
            not close(values[key], standard[key]) for key in ("translation", "rotation", "scale")
        ):
            raise ValueError(f"Skeleton rest differs at {name}: {path}")
    clips = {animation.get("name") for animation in document.get("animations", [])}
    if clips != CLIPS:
        raise ValueError(f"Body clips {clips} differ from {CLIPS}: {path}")
    joints = set(document["skins"][0]["joints"])
    for animation in document["animations"]:
        if not animation.get("channels") or not any(
            channel["target"].get("node") in joints for channel in animation["channels"]
        ):
            raise ValueError(f"Body clip has no bone animation: {animation.get('name')}: {path}")
    if not document.get("meshes"):
        raise ValueError(f"Body has no mesh: {path}")
    print("PASS body", path)


def validate_static(path, kind):
    document = read_glb(path)
    if document.get("skins") or document.get("animations"):
        raise ValueError(f"{kind} cannot contain a skin or animations: {path}")
    if not document.get("meshes"):
        raise ValueError(f"{kind} has no mesh: {path}")
    nodes = document.get("nodes", [])
    mesh_nodes = [node for node in nodes if "mesh" in node]
    if not mesh_nodes:
        raise ValueError(f"{kind} has no mesh node: {path}")
    for node in nodes:
        if "matrix" in node and not close(node["matrix"], [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]):
            raise ValueError(f"{kind} node matrix is not identity: {path}")
        if not close(node.get("translation", [0, 0, 0]), [0, 0, 0]) or not close(
            node.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1]
        ) or not close(node.get("scale", [1, 1, 1]), [1, 1, 1]):
            raise ValueError(f"{kind} mesh transform is not identity: {path}")
    for mesh in document["meshes"]:
        for primitive in mesh["primitives"]:
            accessor = document["accessors"][primitive["attributes"]["POSITION"]]
            if "min" not in accessor or "max" not in accessor:
                raise ValueError(f"{kind} has no mesh bounds: {path}")
            center = [(lo + hi) / 2 for lo, hi in zip(accessor["min"], accessor["max"])]
            if abs(center[0]) > .6 or not (.6 <= center[1] <= 1.6) or abs(center[2]) > .6:
                raise ValueError(f"{kind} is outside the common head rest-space region: {path}")
    print("PASS", kind, path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=MODULAR)
    args = parser.parse_args()
    bodies = sorted((args.root / "body").glob("*/model.glb"))
    static_paths = {"face": sorted((args.root / "face").glob("*/model.glb"))}
    if not bodies and not any(static_paths.values()):
        raise ValueError("No modular parts to validate")
    reference = bone_contract(read_glb(REFERENCE_RIG))
    for path in bodies:
        validate_body(path, reference)
    for kind in ("face",):
        for path in static_paths[kind]:
            validate_static(path, kind)


if __name__ == "__main__":
    main()
