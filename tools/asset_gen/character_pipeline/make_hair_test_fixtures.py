"""Generate two small static HairSocket test parts (not production hairstyles)."""
import math
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "assets/characters/modular/hair"


def make(part_id, radius, height, color):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    vertices = []
    rings = 5
    sides = 16
    for ring in range(rings):
        angle = (ring / (rings - 1)) * math.pi / 2
        for side in range(sides):
            direction = 2 * math.pi * side / sides
            vertices.append((radius * math.sin(angle) * math.cos(direction),
                             radius * .88 * math.sin(angle) * math.sin(direction),
                             height + .17 * math.cos(angle)))
    faces = []
    for ring in range(rings - 1):
        for side in range(sides):
            other = (side + 1) % sides
            faces.append((ring * sides + side, (ring + 1) * sides + side,
                          (ring + 1) * sides + other, ring * sides + other))
    mesh = bpy.data.meshes.new("HairFixtureMesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("Hair", mesh)
    bpy.context.scene.collection.objects.link(obj)
    material = bpy.data.materials.new("HairFixtureMaterial")
    material.diffuse_color = (*color, 1)
    mesh.materials.append(material)
    path = OUT / part_id / "model.glb"
    path.parent.mkdir(parents=True, exist_ok=True)
    obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(path), use_selection=True, export_animations=False)
    print("HAIR_TEST_FIXTURE", part_id, path)


make("901", .245, 1.22, (.18, .10, .06))
make("902", .255, 1.20, (.72, .47, .18))
