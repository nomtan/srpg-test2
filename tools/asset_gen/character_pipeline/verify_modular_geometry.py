"""Compare matched modular faces to the validated combined GLBs in Blender."""
from pathlib import Path
import json
import struct
import bpy
from mathutils.kdtree import KDTree


ROOT = Path(__file__).resolve().parents[3]


def glb_images(path):
    blob = path.read_bytes()
    json_length = struct.unpack_from("<I", blob, 12)[0]
    document = json.loads(blob[20:20 + json_length])
    binary_length = struct.unpack_from("<I", blob, 20 + json_length)[0]
    binary = blob[28 + json_length:28 + json_length + binary_length]
    images = []
    for image in document.get("images", []):
        view = document["bufferViews"][image["bufferView"]]
        start = view.get("byteOffset", 0)
        images.append(binary[start:start + view["byteLength"]])
    return images


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    return set(bpy.data.objects) - before


for index in range(1, 5):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    combined_path = ROOT / f"assets/characters/generated/charcter{index:03d}/character.glb"
    face_path = ROOT / f"assets/characters/modular/face/{index:03d}/model.glb"
    assert all(image in glb_images(combined_path) for image in glb_images(face_path))
    combined = load(combined_path)
    old_head = next(obj for obj in combined if obj.name == "Head")
    independent = load(face_path)
    new_face = next(obj for obj in independent if obj.type == "MESH")
    original_points = [old_head.matrix_world @ v.co for v in old_head.data.vertices]
    fitted_points = [new_face.matrix_world @ v.co for v in new_face.data.vertices]
    tree = KDTree(len(original_points))
    for vertex_index, point in enumerate(original_points):
        tree.insert(point, vertex_index)
    tree.balance()
    max_distance = max(tree.find(point)[2] for point in fitted_points)
    reverse_tree = KDTree(len(fitted_points))
    for vertex_index, point in enumerate(fitted_points):
        reverse_tree.insert(point, vertex_index)
    reverse_tree.balance()
    max_distance = max(max_distance, max(reverse_tree.find(point)[2] for point in original_points))
    assert max_distance < 0.00001, (index, max_distance)
    assert len(old_head.data.polygons) == len(new_face.data.polygons)
    old_image = old_head.data.materials[0].node_tree.nodes.get("Image Texture")
    new_image = new_face.data.materials[0].node_tree.nodes.get("Image Texture")
    if old_image and new_image:
        assert old_image.image.size[:] == new_image.image.size[:]
    print("GEOMETRY_PASS", index, "vertices", len(original_points), len(fitted_points),
          "max_distance_m", round(max_distance, 9), "textures_exact", True)
