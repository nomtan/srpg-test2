import bpy
import os
import math

ROOT = r"C:\Users\nomur\Desktop\git\srpg-test2"
OUT_DIR = os.path.join(ROOT, "assets", "characters", "base_tpose")
BLEND_PATH = os.path.join(OUT_DIR, "CHR_Base_TPose.blend")
GLB_PATH = os.path.join(OUT_DIR, "CHR_Base_TPose.glb")
FBX_PATH = os.path.join(OUT_DIR, "CHR_Base_TPose.fbx")
os.makedirs(OUT_DIR, exist_ok=True)

# Start from a genuinely empty scene.
if bpy.context.object and bpy.context.object.mode != 'OBJECT':
    bpy.ops.object.mode_set(mode='OBJECT')
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for blocks in (bpy.data.meshes, bpy.data.curves, bpy.data.armatures, bpy.data.materials, bpy.data.actions):
    for block in list(blocks):
        blocks.remove(block)

def material(name, color, roughness=.78, metallic=0.0):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    bsdf=m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value=(*color,1)
    bsdf.inputs['Roughness'].default_value=roughness
    bsdf.inputs['Metallic'].default_value=metallic
    return m

MAT_BODY=material('MAT_Base_Body',(0.48,.53,.58))
MAT_JOINT=MAT_BODY
MAT_SKIN=MAT_BODY

def finish(o,name,mat,scale=None,bevel=0):
    o.name=name
    if scale:
        o.scale=scale
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if mat: o.data.materials.append(mat)
    if bevel:
        mod=o.modifiers.new('FacetedBevel','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.context.view_layer.objects.active=o
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in o.data.polygons: p.use_smooth=False
    return o

def ico(name,loc,scale,mat,sub=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub,radius=1,location=loc)
    return finish(bpy.context.object,name,mat,scale)

def cube(name,loc,scale,mat,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    return finish(bpy.context.object,name,mat,scale,bevel)

def cyl(name,loc,radius,depth,mat,rot=(0,0,0),vertices=10):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=radius,depth=depth,location=loc,rotation=rot)
    return finish(bpy.context.object,name,mat)

def cone(name,loc,r1,r2,depth,mat,rot=(0,0,0),vertices=10):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=depth,location=loc,rotation=rot)
    return finish(bpy.context.object,name,mat)

def mesh(name,verts,faces,mat):
    me=bpy.data.meshes.new(name+'_Mesh'); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(o); me.materials.append(mat)
    return o

def join(parts,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=parts[0]
    bpy.ops.object.join(); parts[0].name=name
    return parts[0]

# Dimensions: 1.50 m tall. Head (hairless base) is 0.47 m = 31.3% of total height.
# Feet touch Z=0; character forward is +Y. The pose is perfectly symmetrical around X=0.
head=join([
    ico('_head',(0,0,1.275),(.205,.19,.235),MAT_SKIN,2),
    ico('_earL',(.202,0,1.275),(.035,.032,.052),MAT_SKIN,1),
    ico('_earR',(-.202,0,1.275),(.035,.032,.052),MAT_SKIN,1)
],'BASE_Head')

# Torso is one Mixamo-friendly central part: pelvis, tapered ribcage, chest and neck.
body=join([
    cone('_torso',(0,0,.835),.245,.205,.42,MAT_BODY,vertices=10),
    ico('_chest',(0,0,.94),(.265,.17,.19),MAT_BODY,2),
    cube('_pelvis',(0,0,.64),(.205,.135,.10),MAT_JOINT,.025),
    cyl('_neck',(0,0,1.065),.085,.12,MAT_JOINT,vertices=10)
],'BASE_Body')

# T-pose arms: straight along X, palms facing down, modestly thick joints.
def make_arm(side):
    s=1 if side=='L' else -1
    parts=[
        ico('_shoulder'+side,(s*.285,0,.96),(.105,.105,.11),MAT_JOINT,2),
        cyl('_upper'+side,(s*.405,0,.96),.083,.25,MAT_BODY,(0,math.pi/2,0),10),
        ico('_elbow'+side,(s*.535,0,.96),(.078,.078,.078),MAT_JOINT,1),
        cone('_lower'+side,(s*.64,0,.96),.073,.062,.22,MAT_BODY,(0,math.pi/2,0),10),
        ico('_wrist'+side,(s*.755,0,.96),(.058,.058,.058),MAT_JOINT,1),
        cube('_hand'+side,(s*.805,.015,.96),(.05,.09,.045),MAT_SKIN,.025)
    ]
    return join(parts,'BASE_Arm_'+side)
arm_l=make_arm('L'); arm_r=make_arm('R')

# Legs remain separate, with clear knee and ankle volumes for later autorigging.
def make_leg(side):
    s=1 if side=='L' else -1
    parts=[
        ico('_hip'+side,(s*.125,0,.59),(.105,.105,.105),MAT_JOINT,1),
        cone('_thigh'+side,(s*.13,0,.46),.105,.09,.28,MAT_BODY,vertices=10),
        ico('_knee'+side,(s*.13,0,.315),(.085,.082,.082),MAT_JOINT,1),
        cone('_shin'+side,(s*.13,0,.20),.082,.07,.24,MAT_BODY,vertices=10),
        ico('_ankle'+side,(s*.13,.005,.085),(.067,.068,.07),MAT_JOINT,1),
        cube('_foot'+side,(s*.13,.085,.045),(.105,.16,.045),MAT_BODY,.028)
    ]
    return join(parts,'BASE_Leg_'+side)
leg_l=make_leg('L'); leg_r=make_leg('R')

# Stable transforms and descriptive metadata.
for o in bpy.context.scene.objects:
    if o.type=='MESH':
        bpy.context.view_layer.objects.active=o; o.select_set(True)
        bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
        o.select_set(False)
bpy.context.scene['asset_name']='CHR_Base_TPose'
bpy.context.scene['height_m']=1.50
bpy.context.scene['head_ratio']=0.313
bpy.context.scene['forward_axis']='+Y'
bpy.context.scene['up_axis']='+Z'
bpy.context.scene['pose']='T_POSE'
bpy.context.scene['mixamo_note']='Join the six body parts before Mixamo upload.'

bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.export_scene.gltf(filepath=GLB_PATH,export_format='GLB',use_selection=True,export_animations=False,export_yup=True)
bpy.ops.export_scene.fbx(
    filepath=FBX_PATH,
    use_selection=True,
    object_types={'MESH'},
    apply_unit_scale=True,
    bake_space_transform=False,
    axis_forward='-Z',
    axis_up='Y',
    add_leaf_bones=False,
    bake_anim=False,
)
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
print({'blend':BLEND_PATH,'glb':GLB_PATH,'fbx':FBX_PATH,'objects':[o.name for o in bpy.context.scene.objects]})
