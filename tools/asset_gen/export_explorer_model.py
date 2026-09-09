"""Export base_1.bbmodel's visible body and original walk/run clips to GLB.

Python standard library only; run from any directory. Hidden weapon groups are
omitted. Rigid meshes follow the original group pivots (no invented skeleton).
Blockbench free-model animations add Euler/position offsets to the rest pose:
https://github.com/JannisX11/blockbench/blob/master/js/animations/timeline_animators.js
"""
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/characters/base/base_1.bbmodel"
OUTPUT = ROOT / "assets/world_jrpg/explorer_base_1.glb"
SCALE = 1 / 12  # About 2.25 world units tall, matching the original sprite.


def quaternion(degrees):
    # Blockbench's free format uses Euler ZYX, right-handed Y-up.
    x, y, z = [math.radians(v) / 2 for v in degrees]
    sx, sy, sz = math.sin(x), math.sin(y), math.sin(z)
    cx, cy, cz = math.cos(x), math.cos(y), math.cos(z)
    return [sx * cy * cz - cx * sy * sz, cx * sy * cz + sx * cy * sz,
            cx * cy * sz - sx * sy * cz, cx * cy * cz + sx * sy * sz]


def sample(keys, time):
    def value(key):
        return [float(key["data_points"][0][axis]) for axis in "xyz"]
    if time <= keys[0]["time"]:
        return value(keys[0])
    for a, b in zip(keys, keys[1:]):
        if time <= b["time"]:
            t = (time - a["time"]) / (b["time"] - a["time"])
            return [x + (y - x) * t for x, y in zip(value(a), value(b))]
    return value(keys[-1])


def export():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    groups = {g["uuid"]: g for g in data["groups"]}
    elements = {e["uuid"]: e for e in data["elements"]}
    gltf = {"asset": {"version": "2.0", "generator": "SRPG base_1 exporter"},
            "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [],
            "materials": [], "bufferViews": [], "accessors": [], "animations": []}
    binary = bytearray()
    node_map = {}
    rests = {}
    material_map = {}
    palette = json.loads((ROOT / "assets/characters/py/character_palette.json").read_text())
    for name, spec in palette.items():
        rgb = [int(spec["hex"].lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        # glTF baseColorFactor is linear; preserve the palette's sRGB appearance.
        rgb = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
        index = len(gltf["materials"])
        gltf["materials"].append({"name": name, "pbrMetallicRoughness": {
            "baseColorFactor": rgb + [1], "metallicFactor": 0, "roughnessFactor": 1}})
        for color in spec["colors"]:
            material_map[color] = index

    def accessor(rows, kind):
        width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}[kind]
        flat = [v for row in rows for v in row]
        offset = len(binary)
        binary.extend(struct.pack("<" + "f" * len(flat), *flat))
        view = len(gltf["bufferViews"])
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(flat) * 4})
        result = len(gltf["accessors"])
        gltf["accessors"].append({"bufferView": view, "componentType": 5126,
                                  "count": len(rows), "type": kind,
                                  "min": [min(r[i] for r in rows) for i in range(width)],
                                  "max": [max(r[i] for r in rows) for i in range(width)]})
        return result

    def mesh(element):
        if element["type"] != "mesh":
            raise ValueError("Visible non-mesh element requires explicit conversion: " + element["name"])
        vertices = element["vertices"]
        positions, normals = [], []
        for face in element["faces"].values():
            if face.get("texture", False) is None:
                continue
            points = [[v * SCALE for v in vertices[k]] for k in face["vertices"]]
            for i in range(1, len(points) - 1):
                triangle = [points[0], points[i], points[i + 1]]
                a = [triangle[1][j] - triangle[0][j] for j in range(3)]
                b = [triangle[2][j] - triangle[0][j] for j in range(3)]
                n = [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
                length = math.sqrt(sum(v*v for v in n))
                if length < 1e-10:
                    continue
                positions.extend(triangle)
                normals.extend([[v/length for v in n]] * 3)
        index = len(gltf["meshes"])
        gltf["meshes"].append({"name": element["name"], "primitives": [{"attributes": {
            "POSITION": accessor(positions, "VEC3"), "NORMAL": accessor(normals, "VEC3")},
            "material": material_map.get(element.get("color"), 0)}]})
        return index

    def visit(entry, parent=None, parent_origin=(0, 0, 0)):
        uuid = entry["uuid"] if isinstance(entry, dict) else entry
        obj = groups.get(uuid, elements.get(uuid))
        if not obj.get("export", True) or not obj.get("visibility", True):
            return
        origin = obj.get("origin", [0, 0, 0])
        rest_pos = [(a-b)*SCALE for a, b in zip(origin, parent_origin)]
        rest_rot = obj.get("rotation", [0, 0, 0])
        node = {"name": obj["name"], "translation": rest_pos, "rotation": quaternion(rest_rot)}
        index = len(gltf["nodes"])
        gltf["nodes"].append(node)
        node_map[uuid] = index
        rests[index] = (rest_pos, rest_rot)
        if parent is None:
            gltf["scenes"][0]["nodes"].append(index)
        else:
            gltf["nodes"][parent].setdefault("children", []).append(index)
        if uuid in elements:
            node["mesh"] = mesh(obj)
        else:
            for child in entry.get("children", []):
                visit(child, index, origin)

    for entry in data["outliner"]:
        visit(entry)

    clips = {"idle": None, "walk": "animation.walk_mcp_test", "run": "animation.run"}
    for name, source_name in clips.items():
        source = next(a for a in data["animations"] if a["name"] == source_name) if source_name else {}
        length = source.get("length", 1.0)
        times = sorted({round(i / 60, 8) for i in range(math.ceil(length * 60))} | {length} |
                       {k["time"] for a in source.get("animators", {}).values() for k in a.get("keyframes", [])})
        time_accessor = accessor([[t] for t in times], "SCALAR")
        animation = {"name": name, "channels": [], "samplers": []}
        for uuid, node in node_map.items():
            if uuid not in groups:
                continue
            animator = source.get("animators", {}).get(uuid, {})
            if animator.get("rotation_global"):
                raise ValueError("Global rotation is not supported")
            channels = {}
            for key in animator.get("keyframes", []):
                if key["channel"] not in ("position", "rotation"):
                    raise ValueError("Unsupported animation channel: " + key["channel"])
                if key["interpolation"] != "linear" or len(key["data_points"]) != 1:
                    raise ValueError("Expected numeric, linear keyframes")
                channels.setdefault(key["channel"], []).append(key)
            for keys in channels.values():
                keys.sort(key=lambda k: k["time"])
            rest_pos, rest_rot = rests[node]
            # Include neutral tracks too: run-only head motion must reset on walk/idle.
            for channel, path, kind in [("position", "translation", "VEC3"), ("rotation", "rotation", "VEC4")]:
                values = []
                for time in times:
                    v = sample(channels[channel], time) if channel in channels else [0, 0, 0]
                    values.append(quaternion([r+a for r, a in zip(rest_rot, v)]) if channel == "rotation"
                                  else [r+a*SCALE for r, a in zip(rest_pos, v)])
                sampler = len(animation["samplers"])
                animation["samplers"].append({"input": time_accessor, "output": accessor(values, kind), "interpolation": "LINEAR"})
                animation["channels"].append({"sampler": sampler, "target": {"node": node, "path": path}})
        gltf["animations"].append(animation)
    gltf["buffers"] = [{"byteLength": len(binary)}]
    encoded = json.dumps(gltf, separators=(",", ":"), ensure_ascii=True).encode()
    encoded += b" " * (-len(encoded) % 4)
    binary += b"\0" * (-len(binary) % 4)
    output = struct.pack("<III", 0x46546C67, 2, 28 + len(encoded) + len(binary))
    output += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
    output += struct.pack("<II", len(binary), 0x004E4942) + binary
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(output)
    print(f"Exported {len(gltf['meshes'])} visible meshes, {list(clips)} to {OUTPUT}")


if __name__ == "__main__":
    export()
