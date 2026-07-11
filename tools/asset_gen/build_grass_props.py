"""build_grass_props.py - 十字クワッド草propのGLB生成
blender --background --python build_grass_props.py
規格: 原点=底面中心 / アルファクリップ / 両面描画
tools/asset_gen/build_terrain_glb.py へ kind:"cross" として統合する想定の実装。
"""
import bpy, os, math

TEX_DIR = "/home/claude/props"
OUT_DIR = "/home/claude/props"

# name: (texture, width, height)
PROPS = {
    "prop_grass_short_01": ("prop_grass_short_01.png", 0.9, 0.45),
    "prop_grass_tall_01":  ("prop_grass_tall_01.png", 0.9, 0.85),
}

def make_material(tex_file):
    mat = bpy.data.materials.new(name=f"MAT_{os.path.splitext(tex_file)[0]}")
    mat.use_nodes = True
    mat.blend_method = "CLIP"          # -> glTF alphaMode MASK (Godotでアルファシザー)
    mat.alpha_threshold = 0.5
    mat.use_backface_culling = False   # -> doubleSided
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 1.0
    bsdf.inputs["Specular IOR Level"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX_DIR, tex_file))
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
    return mat

def build_cross(name, tex_file, width, height):
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    mat = make_material(tex_file)
    import bmesh
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new()
    hw = width / 2.0
    # 2枚のクワッドを45度/135度で交差(X字)
    for ang in (math.radians(45), math.radians(135)):
        dx, dy = math.cos(ang) * hw, math.sin(ang) * hw
        v = [bm.verts.new(p) for p in
             [(-dx, -dy, 0), (dx, dy, 0), (dx, dy, height), (-dx, -dy, height)]]
        f = bm.faces.new(v)
        for loop, uv in zip(f.loops, [(0, 0), (1, 0), (1, 1), (0, 1)]):
            loop[uv_layer].uv = uv
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    obj.data.materials.append(mat)
    bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(OUT_DIR, f"{name}.glb")
    bpy.ops.export_scene.gltf(filepath=path, use_selection=True,
                              export_format="GLB", export_yup=True)
    print("[OK]", path)

for name, (tex, w, h) in PROPS.items():
    build_cross(name, tex, w, h)
print("done")