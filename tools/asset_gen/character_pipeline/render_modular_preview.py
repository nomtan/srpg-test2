"""Render matched and swapped Body/Face rest poses for visual inspection."""
from pathlib import Path
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "artifacts/modular_preview"
OUT.mkdir(parents=True, exist_ok=True)
(OUT / ".gdignore").touch()
PAIRS = [(1, 1), (2, 2), (3, 3), (4, 4), (1, 2), (1, 3), (2, 1), (3, 4), (4, 1)]


for body_id, face_id in PAIRS:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/characters/modular/body/{body_id:03d}/model.glb"))
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / f"assets/characters/modular/face/{face_id:03d}/model.glb"))
    face = next(obj for obj in set(bpy.data.objects) - before if obj.type == "MESH")
    face.matrix_world.identity()

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 1.65
    camera.location = (1.4, -2.8, 1.05)
    target = Vector((0, 0, 0.75))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.resolution_x = 400
    scene.render.resolution_y = 400
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(OUT / f"body{body_id:03d}_face{face_id:03d}.png")
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", body_id, face_id)
