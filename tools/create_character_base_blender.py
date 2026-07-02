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

def loft(name, levels, mat, segments=10):
    verts=[]
    for z,rx,ry in levels:
        for i in range(segments):
            a=2*math.pi*i/segments
            verts.append((rx*math.cos(a),ry*math.sin(a),z))
    faces=[]
    faces.append(tuple(range(segments-1,-1,-1)))
    for row in range(len(levels)-1):
        a=row*segments; b=(row+1)*segments
        for i in range(segments):
            j=(i+1)%segments
            faces.append((a+i,a+j,b+j,b+i))
    top=(len(levels)-1)*segments
    faces.append(tuple(top+i for i in range(segments)))
    return mesh(name,verts,faces,mat)

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

# Torso follows the front/side silhouettes in base_male.png: narrow waist,
# modest chest depth, slightly wider pelvis, and no box-shaped transitions.
body=join([
    loft('_torso',[(.58,.155,.105),(.66,.19,.12),(.75,.165,.11),(.90,.205,.125),
                     (1.00,.19,.12),(1.035,.115,.095)],MAT_BODY,12),
    cyl('_neck',(0,0,1.075),.072,.105,MAT_BODY,vertices=10)
],'BASE_Body')

# T-pose arms: straight along X, palms facing down, modestly thick joints.
def make_arm(side):
    s=1 if side=='L' else -1
    parts=[
        ico('_shoulder'+side,(s*.215,0,.95),(.085,.09,.095),MAT_BODY,2),
        cone('_upper'+side,(s*.315,0,.95),.072,.062,.205,MAT_BODY,(0,math.pi/2,0),10),
        ico('_elbow'+side,(s*.42,0,.95),(.062,.064,.064),MAT_BODY,1),
        cone('_lower'+side,(s*.505,0,.95),.061,.048,.18,MAT_BODY,(0,math.pi/2,0),10),
        ico('_wrist'+side,(s*.595,0,.95),(.045,.048,.047),MAT_BODY,1),
        cube('_hand'+side,(s*.632,.012,.95),(.038,.065,.035),MAT_BODY,.018)
    ]
    return join(parts,'BASE_Arm_'+side)
arm_l=make_arm('L'); arm_r=make_arm('R')

# Legs remain separate, with clear knee and ankle volumes for later autorigging.
def make_leg(side):
    s=1 if side=='L' else -1
    parts=[
        ico('_hip'+side,(s*.095,0,.59),(.098,.10,.10),MAT_BODY,1),
        cone('_thigh'+side,(s*.10,0,.455),.098,.077,.285,MAT_BODY,vertices=10),
        ico('_knee'+side,(s*.10,.005,.305),(.075,.075,.078),MAT_BODY,1),
        cone('_shin'+side,(s*.10,.008,.19),.073,.055,.24,MAT_BODY,vertices=10),
        ico('_ankle'+side,(s*.10,.015,.075),(.055,.058,.062),MAT_BODY,1),
        cube('_foot'+side,(s*.10,.075,.038),(.088,.145,.038),MAT_BODY,.022)
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
