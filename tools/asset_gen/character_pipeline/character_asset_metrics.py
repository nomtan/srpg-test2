"""Small, dependency-free GLB inspection helpers for the character pipeline.

The module intentionally reads glTF/GLB data directly.  It can therefore run in
CI before Blender or Godot is available, and is shared by the inspector and the
validator so both tools measure assets in exactly the same way.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Any, Iterable


COMPONENT_FORMATS = {
    5120: ("b", 1),
    5121: ("B", 1),
    5122: ("h", 2),
    5123: ("H", 2),
    5125: ("I", 4),
    5126: ("f", 4),
}
TYPE_COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
IDENTITY = [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]


def read_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError(f"GLB is truncated: {path}")
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError(f"Invalid GLB header: {path}")
    document: dict[str, Any] | None = None
    binary = b""
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + chunk_length]
        offset += chunk_length
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.rstrip(b" \t\r\n\0"))
        elif chunk_type == 0x004E4942:
            binary = chunk
    if document is None:
        raise ValueError(f"GLB has no JSON chunk: {path}")
    return document, binary


def _mat_mul(left: list[float], right: list[float]) -> list[float]:
    return [sum(left[row * 4 + k] * right[k * 4 + col] for k in range(4)) for row in range(4) for col in range(4)]


def _node_matrix(node: dict[str, Any]) -> list[float]:
    if "matrix" in node:
        source = node["matrix"]
        return [float(source[col * 4 + row]) for row in range(4) for col in range(4)]
    x, y, z, w = (float(value) for value in node.get("rotation", [0, 0, 0, 1]))
    rotation = [
        1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w), 0,
        2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w), 0,
        2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y), 0,
        0, 0, 0, 1,
    ]
    scale_values = node.get("scale", [1, 1, 1])
    scale = [float(scale_values[0]), 0, 0, 0, 0, float(scale_values[1]), 0, 0, 0, 0, float(scale_values[2]), 0, 0, 0, 0, 1]
    translation_values = node.get("translation", [0, 0, 0])
    translation = IDENTITY.copy()
    translation[3], translation[7], translation[11] = (float(value) for value in translation_values)
    return _mat_mul(translation, _mat_mul(rotation, scale))


def _transform_point(matrix: list[float], point: Iterable[float]) -> list[float]:
    x, y, z = point
    return [
        matrix[0] * x + matrix[1] * y + matrix[2] * z + matrix[3],
        matrix[4] * x + matrix[5] * y + matrix[6] * z + matrix[7],
        matrix[8] * x + matrix[9] * y + matrix[10] * z + matrix[11],
    ]


def node_world_matrices(document: dict[str, Any]) -> dict[int, list[float]]:
    nodes = document.get("nodes", [])
    parents = {child: parent for parent, node in enumerate(nodes) for child in node.get("children", [])}
    result: dict[int, list[float]] = {}

    def world(index: int) -> list[float]:
        if index not in result:
            local = _node_matrix(nodes[index])
            result[index] = _mat_mul(world(parents[index]), local) if index in parents else local
        return result[index]

    for index in range(len(nodes)):
        world(index)
    return result


def close(values: Iterable[float], expected: Iterable[float], tolerance: float = 2.5e-5) -> bool:
    values_list, expected_list = list(values), list(expected)
    return len(values_list) == len(expected_list) and all(
        math.isclose(left, right, abs_tol=tolerance, rel_tol=0) for left, right in zip(values_list, expected_list)
    )


def accessor_values(document: dict[str, Any], binary: bytes, accessor_index: int) -> list[tuple[float | int, ...]]:
    accessor = document["accessors"][accessor_index]
    if "sparse" in accessor:
        raise ValueError("Sparse accessors are not supported by the character asset inspector")
    view = document["bufferViews"][accessor["bufferView"]]
    component_type = accessor["componentType"]
    component_format, component_size = COMPONENT_FORMATS[component_type]
    component_count = TYPE_COMPONENTS[accessor["type"]]
    item_size = component_size * component_count
    stride = view.get("byteStride", item_size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    unpack = struct.Struct("<" + component_format * component_count).unpack_from
    result: list[tuple[float | int, ...]] = []
    normalized = accessor.get("normalized", False)
    for index in range(accessor["count"]):
        values = unpack(binary, start + index * stride)
        if normalized and component_type != 5126:
            if component_type in (5120, 5122):
                maximum = 127.0 if component_type == 5120 else 32767.0
                values = tuple(max(-1.0, value / maximum) for value in values)
            else:
                maximum = {5121: 255.0, 5123: 65535.0, 5125: 4294967295.0}[component_type]
                values = tuple(value / maximum for value in values)
        result.append(values)
    return result


def _image_size(payload: bytes) -> tuple[int, int] | None:
    if payload.startswith(b"\x89PNG\r\n\x1a\n") and len(payload) >= 24:
        return struct.unpack_from(">II", payload, 16)
    if payload.startswith(b"RIFF") and payload[8:12] == b"WEBP" and len(payload) >= 30:
        kind = payload[12:16]
        if kind == b"VP8X":
            return (1 + int.from_bytes(payload[24:27], "little"), 1 + int.from_bytes(payload[27:30], "little"))
    if payload.startswith(b"\xff\xd8"):
        offset = 2
        while offset + 9 < len(payload):
            if payload[offset] != 0xFF:
                offset += 1
                continue
            marker = payload[offset + 1]
            offset += 2
            if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
                continue
            if offset + 2 > len(payload):
                break
            length = int.from_bytes(payload[offset:offset + 2], "big")
            if marker in {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}:
                return (int.from_bytes(payload[offset + 5:offset + 7], "big"), int.from_bytes(payload[offset + 3:offset + 5], "big"))
            offset += length
    return None


def _image_metrics(document: dict[str, Any], binary: bytes, path: Path) -> list[dict[str, Any]]:
    result = []
    for index, image in enumerate(document.get("images", [])):
        payload = b""
        if "bufferView" in image:
            view = document["bufferViews"][image["bufferView"]]
            start = view.get("byteOffset", 0)
            payload = binary[start:start + view["byteLength"]]
        elif image.get("uri") and not image["uri"].startswith("data:"):
            image_path = path.parent / image["uri"]
            if image_path.is_file():
                payload = image_path.read_bytes()
        size = _image_size(payload)
        result.append({
            "index": index,
            "name": image.get("name", f"image_{index}"),
            "mime_type": image.get("mimeType"),
            "width": size[0] if size else None,
            "height": size[1] if size else None,
            "embedded_bytes": len(payload),
        })
    return result


def _mesh_bounds(document: dict[str, Any]) -> dict[str, Any] | None:
    accessors = document.get("accessors", [])
    worlds = node_world_matrices(document)
    occurrences: list[tuple[int, list[float]]] = []
    for node_index, node in enumerate(document.get("nodes", [])):
        if "mesh" in node:
            occurrences.append((node["mesh"], worlds[node_index]))
    if not occurrences:
        occurrences = [(index, IDENTITY) for index in range(len(document.get("meshes", [])))]
    minimum = [math.inf, math.inf, math.inf]
    maximum = [-math.inf, -math.inf, -math.inf]
    found = False
    for mesh_index, matrix in occurrences:
        for primitive in document["meshes"][mesh_index].get("primitives", []):
            position_index = primitive.get("attributes", {}).get("POSITION")
            if position_index is None:
                continue
            accessor = accessors[position_index]
            if "min" not in accessor or "max" not in accessor:
                continue
            for x in (accessor["min"][0], accessor["max"][0]):
                for y in (accessor["min"][1], accessor["max"][1]):
                    for z in (accessor["min"][2], accessor["max"][2]):
                        point = _transform_point(matrix, (x, y, z))
                        minimum = [min(minimum[axis], point[axis]) for axis in range(3)]
                        maximum = [max(maximum[axis], point[axis]) for axis in range(3)]
                        found = True
    if not found:
        return None
    size = [maximum[axis] - minimum[axis] for axis in range(3)]
    center = [(minimum[axis] + maximum[axis]) / 2 for axis in range(3)]
    return {"min": minimum, "max": maximum, "center": center, "size": size, "width": size[0], "height": size[1], "depth": size[2]}


def bone_contract(document: dict[str, Any]) -> dict[str, dict[str, Any]]:
    skins = document.get("skins", [])
    if len(skins) != 1:
        raise ValueError(f"Expected exactly one skin, found {len(skins)}")
    nodes = document.get("nodes", [])
    joints = skins[0].get("joints", [])
    joint_set = set(joints)
    parents = {child: parent for parent, node in enumerate(nodes) for child in node.get("children", [])}
    result: dict[str, dict[str, Any]] = {}
    worlds = node_world_matrices(document)
    for joint in joints:
        node = nodes[joint]
        name = node.get("name", f"joint_{joint}")
        parent = parents.get(joint)
        result[name] = {
            "parent": nodes[parent].get("name", f"joint_{parent}") if parent in joint_set else None,
            "translation": node.get("translation", [0, 0, 0]),
            "rotation": node.get("rotation", [0, 0, 0, 1]),
            "scale": node.get("scale", [1, 1, 1]),
            "global_rest_position": _transform_point(worlds[joint], (0, 0, 0)),
        }
    return result


def _skin_metrics(document: dict[str, Any], binary: bytes) -> dict[str, Any]:
    weighted = unweighted = invalid = 0
    maximum_influences = 0
    joint_count = len(document.get("skins", [{}])[0].get("joints", [])) if document.get("skins") else 0
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            attributes = primitive.get("attributes", {})
            position = document["accessors"][attributes["POSITION"]]
            if "WEIGHTS_0" not in attributes:
                unweighted += position["count"]
                continue
            weights_sets = [accessor_values(document, binary, attributes[name]) for name in ("WEIGHTS_0", "WEIGHTS_1") if name in attributes]
            joint_sets = [accessor_values(document, binary, attributes[name]) for name in ("JOINTS_0", "JOINTS_1") if name in attributes]
            for vertex_index in range(position["count"]):
                weights = [float(value) for values in weights_sets for value in values[vertex_index]]
                joints = [int(value) for values in joint_sets for value in values[vertex_index]]
                active = [index for index, weight in enumerate(weights) if weight > 1e-6]
                if active:
                    weighted += 1
                    maximum_influences = max(maximum_influences, len(active))
                    if any(index >= len(joints) or joints[index] >= joint_count for index in active):
                        invalid += 1
                else:
                    unweighted += 1
    return {
        "weighted_vertices": weighted,
        "unweighted_vertices": unweighted,
        "invalid_joint_vertices": invalid,
        "maximum_influences": maximum_influences,
    }


def _animation_metrics(document: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    for index, animation in enumerate(document.get("animations", [])):
        duration = 0.0
        for sampler in animation.get("samplers", []):
            accessor = document["accessors"][sampler["input"]]
            if accessor.get("max"):
                duration = max(duration, float(accessor["max"][0]))
        result.append({"name": animation.get("name", f"animation_{index}"), "duration": duration, "tracks": len(animation.get("channels", []))})
    return result


def _material_metrics(document: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    for index, material in enumerate(document.get("materials", [])):
        pbr = material.get("pbrMetallicRoughness", {})
        roles = []
        if "baseColorTexture" in pbr:
            roles.append("base_color")
        if "metallicRoughnessTexture" in pbr:
            roles.append("metallic_roughness")
        if "normalTexture" in material:
            roles.append("normal")
        if "occlusionTexture" in material:
            roles.append("occlusion")
        if "emissiveTexture" in material:
            roles.append("emissive")
        result.append({"index": index, "name": material.get("name", f"material_{index}"), "texture_roles": roles})
    return result


def _used_texture_indices(document: dict[str, Any]) -> set[int]:
    used: set[int] = set()
    for material in document.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        for texture in (
            pbr.get("baseColorTexture"),
            pbr.get("metallicRoughnessTexture"),
            material.get("normalTexture"),
            material.get("occlusionTexture"),
            material.get("emissiveTexture"),
        ):
            if texture and "index" in texture:
                used.add(texture["index"])
    return used


def _head_hair_structure(document: dict[str, Any], materials: list[dict[str, Any]]) -> dict[str, Any]:
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    mesh_names = []
    for node in nodes:
        if "mesh" in node:
            mesh_names.append(node.get("name", meshes[node["mesh"]].get("name", "")))
    material_names = [material["name"] for material in materials]
    lowered_meshes = [name.lower() for name in mesh_names]
    lowered_materials = [name.lower() for name in material_names]
    if any("head" in name for name in lowered_meshes) and any("hair" in name for name in lowered_meshes):
        method = "mesh_separation"
    elif any("head" in name for name in lowered_materials) and any("hair" in name for name in lowered_materials):
        method = "material_separation"
    else:
        method = "legacy_combined"
    return {"method": method, "mesh_names": mesh_names, "material_names": material_names, "expression_hair_isolated": method in {"mesh_separation", "material_separation"}}


def inspect_glb(path: Path) -> dict[str, Any]:
    document, binary = read_glb(path)
    vertices = triangles = primitives = 0
    uv_sets: set[str] = set()
    for mesh in document.get("meshes", []):
        for primitive in mesh.get("primitives", []):
            primitives += 1
            attributes = primitive.get("attributes", {})
            if "POSITION" in attributes:
                count = document["accessors"][attributes["POSITION"]]["count"]
                vertices += count
                if primitive.get("mode", 4) == 4:
                    triangles += document["accessors"][primitive["indices"]]["count"] // 3 if "indices" in primitive else count // 3
            uv_sets.update(name for name in attributes if name.startswith("TEXCOORD_"))
    materials = _material_metrics(document)
    images = _image_metrics(document, binary, path)
    used_textures = _used_texture_indices(document)
    bones: dict[str, dict[str, Any]] = {}
    if len(document.get("skins", [])) == 1:
        bones = bone_contract(document)
    animations = _animation_metrics(document)
    mesh_nodes = []
    for index, node in enumerate(document.get("nodes", [])):
        if "mesh" in node:
            mesh_nodes.append({
                "index": index,
                "name": node.get("name", f"node_{index}"),
                "translation": node.get("translation", [0, 0, 0]),
                "rotation": node.get("rotation", [0, 0, 0, 1]),
                "scale": node.get("scale", [1, 1, 1]),
                "matrix": node.get("matrix"),
            })
    roots = []
    scenes = document.get("scenes", [])
    root_indices = scenes[document.get("scene", 0)].get("nodes", []) if scenes else []
    for index in root_indices:
        node = document["nodes"][index]
        roots.append({"index": index, "name": node.get("name", f"node_{index}"), "translation": node.get("translation", [0, 0, 0]), "rotation": node.get("rotation", [0, 0, 0, 1]), "scale": node.get("scale", [1, 1, 1]), "matrix": node.get("matrix")})
    return {
        "path": path.as_posix(),
        "size_bytes": path.stat().st_size,
        "geometry": {"vertex_count": vertices, "triangle_count": triangles, "mesh_count": len(document.get("meshes", [])), "mesh_node_count": len(mesh_nodes), "primitive_count": primitives, "bounds": _mesh_bounds(document)},
        "materials": {"count": len(materials), "items": materials},
        "textures": {
            "texture_count": len(document.get("textures", [])),
            "used_texture_count": len(used_textures),
            "unused_texture_indices": sorted(set(range(len(document.get("textures", [])))) - used_textures),
            "image_count": len(images),
            "images": images,
        },
        "transform": {"roots": roots, "mesh_nodes": mesh_nodes},
        "rig": {"skeleton_count": len(document.get("skins", [])), "skin_count": len(document.get("skins", [])), "bone_count": len(bones), "bones": bones, "head_position": bones.get("head", {}).get("global_rest_position"), **_skin_metrics(document, binary)},
        "animations": {"player_count": 1 if animations else 0, "count": len(animations), "items": animations},
        "uv": {"sets": sorted(uv_sets), "set_count": len(uv_sets)},
        "head_hair": _head_hair_structure(document, materials),
    }


def compare_bones(actual: dict[str, dict[str, Any]], reference: dict[str, dict[str, Any]], tolerance: float = 2.5e-5) -> list[str]:
    differences = []
    if actual.keys() != reference.keys():
        missing = sorted(reference.keys() - actual.keys())
        extra = sorted(actual.keys() - reference.keys())
        differences.append(f"bone names differ (missing={missing}, extra={extra})")
        return differences
    for name, values in actual.items():
        expected = reference[name]
        if values["parent"] != expected["parent"]:
            differences.append(f"{name}: parent {values['parent']} != {expected['parent']}")
        for key in ("translation", "rotation", "scale"):
            if not close(values[key], expected[key], tolerance):
                differences.append(f"{name}: {key} differs")
    return differences
