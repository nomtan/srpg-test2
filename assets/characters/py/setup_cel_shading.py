#!/usr/bin/env python3
"""
setup_cel_shading.py  -  Import the rigged/animated GLB and build a cel (toon) look
in Blender 4.x (EEVEE):
    * per-material 2-band toon shader  (Diffuse -> Shader-to-RGB -> constant ColorRamp)
    * inverted-hull outline via a Solidify modifier + black back-face material
    * Standard view transform + key/fill lighting so the bands read cleanly
    * every animation kept as an Action and stacked on NLA tracks so you can preview them

Run inside Blender:
    blender --python setup_cel_shading.py -- /path/to/base_body.glb
or paste into the Scripting tab after setting GLB_PATH below.

Tested target: Blender 4.2+ (EEVEE Next). Guards included for 4.0/4.1 EEVEE.
"""
import bpy, sys, os
from mathutils import Vector

# ---------------- tunables ----------------
GLB_PATH   = ""                      # set here, or pass after `--`
SHADOW_TONE = 0.42                    # 0..1 darkness of the shadow band
BAND_SPLIT  = 0.5                     # lambert value where shadow->light flips
OUTLINE     = 0.012                   # outline thickness (metres); model ~1.7m tall
BG_VALUE    = 0.16                    # world background grey
# ------------------------------------------

def get_glb_path():
    if "--" in sys.argv:
        after = sys.argv[sys.argv.index("--")+1:]
        if after: return after[0]
    return GLB_PATH

def set_eevee():
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng; break
        except TypeError:
            continue
    sc.view_settings.view_transform = "Standard"      # flat cel colours, no filmic roll-off
    # soft AA / no bloom washout
    try: sc.eevee.taa_render_samples = 32
    except Exception: pass

def base_color_of(mat):
    if mat.use_nodes:
        for n in mat.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                return tuple(n.inputs["Base Color"].default_value)
    return (0.8, 0.8, 0.8, 1.0)

def make_toon(mat):
    base = base_color_of(mat)
    mat.use_nodes = True
    nt = mat.node_tree; nt.nodes.clear()
    out  = nt.nodes.new("ShaderNodeOutputMaterial");  out.location=(600,0)
    emis = nt.nodes.new("ShaderNodeEmission");        emis.location=(400,0)
    mul  = nt.nodes.new("ShaderNodeMixRGB");          mul.location=(200,0); mul.blend_type="MULTIPLY"; mul.inputs[0].default_value=1.0
    ramp = nt.nodes.new("ShaderNodeValToRGB");        ramp.location=(-80,-40)
    s2r  = nt.nodes.new("ShaderNodeShaderToRGB");     s2r.location=(-300,-40)
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse");     diff.location=(-520,-40); diff.inputs["Color"].default_value=(1,1,1,1)
    # 2-band constant ramp
    e = ramp.color_ramp; e.interpolation = "CONSTANT"
    e.elements[0].position = 0.0; e.elements[0].color = (SHADOW_TONE,)*3+(1,)
    e.elements[1].position = BAND_SPLIT; e.elements[1].color = (1,1,1,1)
    mul.inputs["Color2"].default_value = base
    nt.links.new(diff.outputs[0], s2r.inputs[0])
    nt.links.new(s2r.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], mul.inputs["Color1"])
    nt.links.new(mul.outputs[0], emis.inputs["Color"])
    nt.links.new(emis.outputs[0], out.inputs["Surface"])
    mat.use_backface_culling = False

def outline_material():
    m = bpy.data.materials.get("CEL_Outline") or bpy.data.materials.new("CEL_Outline")
    m.use_nodes = True; nt=m.node_tree; nt.nodes.clear()
    out=nt.nodes.new("ShaderNodeOutputMaterial"); em=nt.nodes.new("ShaderNodeEmission")
    em.inputs[0].default_value=(0.02,0.02,0.025,1)
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    m.use_backface_culling = True            # cull front faces of the inflated shell
    return m

def add_outline(obj, omat):
    if omat.name not in [s.name for s in obj.data.materials]:
        obj.data.materials.append(omat)
    oidx = len(obj.data.materials)-1
    sol = obj.modifiers.new("CEL_Outline","SOLIDIFY")
    sol.thickness = -OUTLINE
    sol.offset = 1.0
    sol.use_flip_normals = True
    sol.material_offset = oidx               # clamps -> shell faces use the outline slot
    sol.use_rim = False
    sol.use_rim_only = False

def add_lights():
    # key sun
    sd = bpy.data.lights.new("CEL_Key","SUN"); sd.energy=3.0; sd.angle=0.15
    key = bpy.data.objects.new("CEL_Key", sd); bpy.context.scene.collection.objects.link(key)
    key.rotation_euler = (0.9, 0.0, 0.8)
    # gentle fill
    fd = bpy.data.lights.new("CEL_Fill","SUN"); fd.energy=1.0
    fill = bpy.data.objects.new("CEL_Fill", fd); bpy.context.scene.collection.objects.link(fill)
    fill.rotation_euler = (1.1, 0.0, -2.2)
    w = bpy.context.scene.world or bpy.data.worlds.new("World")
    bpy.context.scene.world = w; w.use_nodes=True
    bg = w.node_tree.nodes.get("Background")
    if bg: bg.inputs[0].default_value=(BG_VALUE,BG_VALUE,BG_VALUE*1.1,1); bg.inputs[1].default_value=1.0

def stack_actions_to_nla(arm):
    """Keep every imported animation reachable: one NLA track per Action (muted)."""
    if not arm.animation_data:
        arm.animation_data_create()
    ad = arm.animation_data
    acts = [a for a in bpy.data.actions]
    for a in acts:
        tr = ad.nla_tracks.new(); tr.name=a.name
        st = tr.strips.new(a.name, int(a.frame_range[0]), a)
        tr.mute = True
    if acts:
        ad.action = acts[0]                  # active one to scrub immediately

def main():
    path = get_glb_path()
    if not path or not os.path.exists(path):
        print("!! GLB not found. Set GLB_PATH or pass a path after --"); return
    set_eevee()
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]

    # collection
    col = bpy.data.collections.new("Character")
    bpy.context.scene.collection.children.link(col)
    for o in new:
        for c in o.users_collection: c.objects.unlink(o)
        col.objects.link(o)

    # toon-ify every imported material (skip our own outline)
    done=set()
    for o in new:
        if o.type!="MESH": continue
        for s in o.data.materials:
            if s and s.name not in done and s.name!="CEL_Outline":
                make_toon(s); done.add(s.name)

    omat = outline_material()
    for o in new:
        if o.type=="MESH": add_outline(o, omat)

    add_lights()

    arm = next((o for o in new if o.type=="ARMATURE"), None)
    if arm: stack_actions_to_nla(arm)

    print(f"[cel] imported {path}: {len([o for o in new if o.type=='MESH'])} mesh, "
          f"{len(done)} toon materials, {len(bpy.data.actions)} actions")
    print("[cel] NLA tracks are muted; un-mute one (or set armature Action) to preview.")

if __name__ == "__main__":
    main()