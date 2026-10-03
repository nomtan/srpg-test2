"""Blender MCP: bake Face007 width into legacy Faces, preserve UV0 and profile placement."""
import hashlib
import json
from pathlib import Path
import bpy
from character_asset_metrics import inspect_glb
from build_modular_parts import prepare_static, export

ROOT = Path(__file__).resolve().parents[3]


def resize():
    # Explicit approved Face007 bounds from its recorded build, not the whole character.
    reference = json.loads((ROOT / 'assets/characters/generated/character007/build_report.json').read_text())
    face_bounds = next(value for name, value in reference['bounds'].items() if name.startswith('Face'))
    width = face_bounds[1][0] - face_bounds[0][0]
    rows = []
    for index in range(1, 7):
        number = f'{index:03d}'
        folder = ROOT / f'assets/characters/modular/face/{number}'
        metadata_path = folder / 'normalization.json'
        metadata = json.loads(metadata_path.read_text())
        old = inspect_glb(folder / 'model.glb')['geometry']['bounds']
        ratio = width / old['width']
        old_scale = metadata['scale']
        original = metadata.get('size_baseline', dict(scale=old_scale, position=metadata['position']))
        metadata['size_baseline'] = original
        metadata['scale'] = old_scale * ratio
        metadata['face_width_m'] = width
        metadata['size_reference'] = 'face007'
        profile = f'legacy_size007_{number}'
        metadata['expression_profile'] = profile
        # Transform original legacy projection into the resized, normalized space.
        factor = metadata['scale'] / original['scale']
        x, y, z = original['position']
        new_x, new_y, new_z = metadata['position']
        rect = (new_x + (-.23-x)*factor, new_z + (.848-z)*factor, .46*factor, .36*factor)
        depth = (-new_y + (.18+y)*factor, -new_y + (.33+y)*factor)
        path = ROOT / f'assets/characters/_shared/face/expression/profiles/{profile}.tres'
        path.write_text('[gd_resource type="Resource" script_class="ExpressionProfile" load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://scripts/character/expression_profile.gd" id="1"]\n\n[resource]\nscript = ExtResource("1")\nface_rect = Vector4(%s)\nsurface_depth = Vector2(%s)\n' % (', '.join(map(str,rect)), ', '.join(map(str,depth))), encoding='utf-8')
        scene = bpy.data.scenes.new(f'Face{number}_Size007')
        bpy.context.window.scene = scene
        parts = prepare_static('face', number, metadata)
        export(folder / 'model.glb', parts, False)
        metadata_path.write_text(json.dumps(metadata, indent=2)+'\n', encoding='utf-8')
        actual = inspect_glb(folder / 'model.glb')['geometry']['bounds']
        assert abs(actual['width'] - width) < 1e-5
        source = ROOT / f'assets/characters/tripo/face/{number}/model.glb'
        assert hashlib.sha256(source.read_bytes()).hexdigest() == metadata['source_sha256']
        rows.append(dict(id=number, ratio=ratio, old=old, new=actual))
    out = ROOT / 'artifacts/face_size007'
    out.mkdir(parents=True,exist_ok=True)
    (out/'measurements.json').write_text(json.dumps(dict(target_width=width,faces=rows),indent=2)+'\n',encoding='utf-8')
    print('FACE_SIZE007',width,[(r['id'],r['ratio']) for r in rows])


resize()
