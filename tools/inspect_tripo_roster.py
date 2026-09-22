"""Render the nine source meshes for rig fitting, without modifying source files."""
import json
import sys
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from tripo_roster_common import preview_scene

SOURCES = {
    'adventure': 'tripo_adventure/adventure.glb',
    'black_mage': 'tripo_black_mage/black_mage.glb',
    'butler': 'tripo_butler/butler.glb',
    'chief_butler': 'tripo_chief_butler/chief_butler.glb',
    'hero': 'tripo_hiro/hero.glb',
    'knight': 'tripo_knight2/knigth.glb',
    'scholar': 'tripo_scholar/scholar.glb',
    'warrior': 'tripo_warrior/warrior.glb',
    'white_mage': 'tripo_white_mage/white_mage.glb',
}

def main():
    out = ROOT / 'artifacts/tripo_roster/source'
    out.mkdir(parents=True, exist_ok=True)
    report = {}
    for key, path in SOURCES.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/characters' / path))
        scene = bpy.context.scene
        mesh = next(o for o in scene.objects if o.type == 'MESH')
        report[key] = {'vertices': len(mesh.data.vertices), 'polygons': len(mesh.data.polygons),
                       'matrix': [list(r) for r in mesh.matrix_world],
                       'bounds': [list(v) for v in mesh.bound_box],
                       'bones': [{'name': b.name, 'head': list(b.head_local), 'tail': list(b.tail_local)}
                                 for o in scene.objects if o.type == 'ARMATURE' for b in o.data.bones]}
        for mat in mesh.data.materials:
            nodes, links = mat.node_tree.nodes, mat.node_tree.links
            bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
            tex = bsdf.inputs['Base Color'].links[0].from_node
            output = next(n for n in nodes if n.type == 'OUTPUT_MATERIAL')
            emit = nodes.new('ShaderNodeEmission')
            links.new(tex.outputs['Color'], emit.inputs['Color'])
            links.new(emit.outputs[0], output.inputs['Surface'])
        _, camera = preview_scene(scene)
        camera.location = (.12, -3, .9)
        camera.rotation_euler = (Vector((0, 0, .49)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
        scene.render.resolution_x = 400
        scene.render.resolution_y = 460
        scene.render.filepath = str(out / (key + '.png'))
        bpy.ops.render.render(write_still=True)
        print('INSPECTED', key, flush=True)
    (out / 'structure.json').write_text(json.dumps(report, indent=2), encoding='utf-8')

if __name__ == '__main__':
    main()
