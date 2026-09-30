"""Inspect disconnected geometry in normalized Face GLBs with Blender."""
from pathlib import Path
import bpy


ROOT = Path(__file__).resolve().parents[3]


def inspect(face_id):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    path = ROOT / f"assets/characters/modular/face/{face_id}/model.glb"
    bpy.ops.import_scene.gltf(filepath=str(path))
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        mesh = obj.data
        parent = list(range(len(mesh.vertices)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        for edge in mesh.edges:
            a, b = edge.vertices
            parent[find(a)] = find(b)
        islands = {}
        for vertex in mesh.vertices:
            islands.setdefault(find(vertex.index), []).append(vertex.co)
        print("FACE_ISLANDS", face_id, obj.name, "vertices", len(mesh.vertices), "islands", len(islands))
        for coordinates in sorted(islands.values(), key=len, reverse=True)[:12]:
            lo = [min(point[i] for point in coordinates) for i in range(3)]
            hi = [max(point[i] for point in coordinates) for i in range(3)]
            print("ISLAND", len(coordinates), [round(v, 3) for v in lo], [round(v, 3) for v in hi])


for face_id in ("001", "002", "003", "004"):
    inspect(face_id)
