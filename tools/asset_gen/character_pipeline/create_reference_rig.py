"""Freeze the Phase 2 humanoid_v1 rig and donor surface as a shared GLB.

The donor mesh transfers weights to new bodies. Animation channels are removed
from the reference; build_modular_parts.py creates the four standard clips.
This command is a one-time migration, never part of routine body export.
"""
import json
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
SOURCE = ROOT / "assets/characters/modular/body/001/model.glb"
TARGET = ROOT / "assets/characters/_shared/rigs/humanoid_v1.glb"
JSON_CHUNK = 0x4E4F534A


def main():
    data = SOURCE.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError("Invalid Body 001 reference GLB")
    offset = 12
    chunks = []
    while offset < len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        payload = data[offset + 8:offset + 8 + size]
        chunks.append((kind, payload))
        offset += 8 + size
    if not chunks or chunks[0][0] != JSON_CHUNK:
        raise ValueError("Missing glTF JSON chunk")
    document = json.loads(chunks[0][1])
    if len(document.get("skins", [])) != 1 or len(document["skins"][0]["joints"]) != 65:
        raise ValueError("Reference must have one 65-bone skin")
    if "head" not in {document["nodes"][i].get("name") for i in document["skins"][0]["joints"]}:
        raise ValueError("Reference lacks head bone")
    if len(document.get("meshes", [])) != 1:
        raise ValueError("Reference needs one weight-transfer donor mesh")
    document.pop("animations", None)
    encoded = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    chunks[0] = (JSON_CHUNK, encoded)
    body = b"".join(struct.pack("<II", len(payload), kind) + payload for kind, payload in chunks)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_bytes(struct.pack("<III", magic, version, 12 + len(body)) + body)
    print("HUMANOID_V1_REFERENCE", TARGET)


if __name__ == "__main__":
    main()
