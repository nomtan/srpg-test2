"""Derive the empty scabbard worn while the katana is drawn.

blender -b --factory-startup --python tools/asset_gen/build_katana_scabbard.py

saya.model.glb is the sheathed katana (scabbard + guard + hilt). Cutting it just
below the guard leaves the scabbard alone, so the hip keeps a scabbard while the
bare katana (model.glb) is in hand. The source GLBs are read only.
"""
import hashlib
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "assets/weapons/katana/001"
SOURCE = FOLDER / "saya.model.glb"
OUTPUT = FOLDER / "scabbard.glb"
# Top of the scabbard mouth; the guard of the sheathed model starts above it (Blender Z, tip at 0).
CUT_Z = 0.735


def build():
    before = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    meshes = [obj for obj in bpy.data.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise ValueError("saya.model.glb must contain one mesh")
    scabbard = meshes[0]
    scabbard.name = "KatanaScabbard"
    mesh = bmesh.new()
    mesh.from_mesh(scabbard.data)
    geometry = mesh.verts[:] + mesh.edges[:] + mesh.faces[:]
    bmesh.ops.bisect_plane(mesh, geom=geometry, plane_co=(0, 0, CUT_Z), plane_no=(0, 0, 1), clear_outer=True)
    mesh.to_mesh(scabbard.data)
    mesh.free()
    bpy.ops.object.select_all(action="DESELECT")
    scabbard.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT), use_selection=True, export_animations=False)
    if hashlib.sha256(SOURCE.read_bytes()).hexdigest() != before:
        raise ValueError("saya.model.glb changed")
    print("KATANA_SCABBARD", OUTPUT, len(scabbard.data.vertices))


build()
