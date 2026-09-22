"""Rebuild only neck geometry after a full build; require identical semantic split."""
import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prepare_character_phase1_5 import *

verify_protected()
keys=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else list(SOURCES)
assert all(key in SOURCES for key in keys)
for key,source in SOURCES.items():
    if key not in keys:continue
    out=(ROOT/'assets/characters'/source).parent/'prepared/phase1_5'
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/characters'/source))
    mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
    mesh.parent=None;mesh.matrix_world=Matrix.Identity(4);mesh.modifiers.clear()
    pixels=image_array(next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE'))
    selected,_,_=semantic_head(mesh,key,pixels)
    previous=json.loads((out/'semantic_selection.json').read_text())
    assert np.flatnonzero(selected).tolist()==previous['head_source_face_indices'],'Semantic split changed: run full build'
    body,head=split_semantic(mesh,selected)
    rig=native_rig(key)
    head.data.transform(TURN)
    neck_overlap(head,key,rig)
    mesh_name=head.data.name
    temporary=ART/(key+'_neck_mesh.blend')
    for image in bpy.data.images:
        if image.has_data and not image.packed_file:image.pack()
    bpy.data.libraries.write(str(temporary),{head.data})
    vertex_count=len(head.data.vertices)
    triangles=sum(len(p.vertices)-2 for p in head.data.polygons)
    head.modifiers.clear();head.parent=None;head.matrix_world=Matrix.Identity(4)
    head.name='HeadSet'
    head.data.transform(rig.data.bones['Head'].matrix_local.inverted())
    head.vertex_groups.clear()
    export(out/'head_default.glb',[head],yup=False)
    bpy.ops.wm.open_mainfile(filepath=str(out/'character.blend'))
    bpy.context.preferences.filepaths.save_version=0
    with bpy.data.libraries.load(str(temporary),link=False) as (available,loaded):
        loaded.meshes=[mesh_name]
    bpy.data.objects['HeadBase'].data=loaded.meshes[0]
    bpy.ops.wm.save_as_mainfile(filepath=str(out/'character.blend'))
    validation=json.loads((out/'validation.json').read_text())
    validation.update(head_vertices=vertex_count,head_triangles=triangles,acceptance='pending visual and runtime verification')
    write_json(out/'validation.json',validation)
    build_results=json.loads((ART/'build.json').read_text())
    build_results[key]=validation
    write_json(ART/'build.json',build_results)
    print('HEAD_REPAIRED',key,flush=True)
print('PROTECTED_UNCHANGED',verify_protected(),flush=True)
