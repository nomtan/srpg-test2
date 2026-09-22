"""Read-only seam topology diagnostics; output to stdout."""
import sys
from pathlib import Path
sys.dont_write_bytecode=True
sys.path.insert(0,str(Path(__file__).resolve().parent))
from prepare_character_phase1_5 import *

for key,source in SOURCES.items():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/'assets/characters'/source))
    mesh=max((o for o in bpy.context.scene.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
    pixels=image_array(next(n.image for n in mesh.data.materials[0].node_tree.nodes if n.type=='TEX_IMAGE'))
    chosen,_,_=semantic_head(mesh,key,pixels)
    for part in split_semantic(mesh,chosen):
        bm=bmesh.new();bm.from_mesh(part.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-6)
        remaining={e for e in bm.edges if e.is_boundary}
        loops=[]
        while remaining:
            seed=remaining.pop(); group={seed};todo=[seed]
            while todo:
                edge=todo.pop()
                for v in edge.verts:
                    for other in v.link_edges:
                        if other in remaining:
                            remaining.remove(other);group.add(other);todo.append(other)
            verts={v for e in group for v in e.verts}
            loops.append({'edges':len(group),'min':[round(min(v.co[i] for v in verts),4) for i in range(3)],'max':[round(max(v.co[i] for v in verts),4) for i in range(3)]})
        print('SEAMS',key,part.name,sorted(loops,key=lambda x:-x['edges']),flush=True)
        bm.free()
