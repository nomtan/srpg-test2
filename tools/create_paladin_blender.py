"""Build the reference-inspired block paladin. Run in Blender, or in stages via MCP.

Standalone: blender --background --python tools/create_paladin_blender.py
All coordinates are in design units. The asset root scales to 2.20 metres tall.
Front is -Y in Blender, +Z in the exported glTF coordinate system.
"""

import bpy
import bmesh
import contextlib
import io
import json
import math
import os
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'characters' / 'paladin'
OUT.mkdir(parents=True, exist_ok=True)
SCALE = 2.2 / 5.19
SCENE = None
COLLECTION = None
CHARACTER = None
GROUPS = {}
M = {}


def material(name, rgb, metal=0.0, rough=.5):
    mat = bpy.data.materials.new('PAL_' + name)
    mat.diffuse_color = (*rgb, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*rgb, 1)
    shader.inputs['Metallic'].default_value = metal
    shader.inputs['Roughness'].default_value = rough
    return mat


def empty(name, parent=None, loc=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    COLLECTION.objects.link(obj)
    obj.parent = parent
    obj.location = loc
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = .12
    return obj


def mesh(name, vertices, faces, mat, parent, bevel=0):
    data = bpy.data.meshes.new(name + '_Mesh')
    data.from_pydata(vertices, [], faces)
    data.update()
    obj = bpy.data.objects.new(name, data)
    COLLECTION.objects.link(obj)
    obj.parent = parent
    data.materials.append(M[mat] if isinstance(mat, str) else mat)
    if bevel:
        mod = obj.modifiers.new('Tiny machined edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
    for polygon in data.polygons:
        polygon.use_smooth = False
    return obj


def box(name, loc, size, mat, parent=None, bevel=.007, rot=None):
    x, y, z = (v / 2 for v in size)
    vertices = [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),
                (-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
    faces = [(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)]
    obj = mesh(name, vertices, faces, mat, parent or CHARACTER, bevel)
    obj.location = loc
    if rot:
        obj.rotation_euler = rot
    return obj


def outline(width, depth, cut, yc=0):
    x, y = width/2, depth/2
    return [(-x+cut,-y+yc),(x-cut,-y+yc),(x,-y+cut+yc),(x,y-cut+yc),
            (x-cut,y+yc),(-x+cut,y+yc),(-x,y-cut+yc),(-x,-y+cut+yc)]


def loft(name, levels, mat, parent=None, bevel=.007):
    # Levels: (z, width, depth, corner cut, y-centre, x-centre).
    vertices = []
    for z, width, depth, cut, yc, xc in levels:
        vertices.extend((x+xc, y, z) for x,y in outline(width,depth,cut,yc))
    n = 8
    faces = [tuple(range(n-1,-1,-1))]
    for row in range(len(levels)-1):
        for i in range(n):
            a, b = row*n+i, row*n+(i+1)%n
            faces.append((a,b,b+n,a+n))
    faces.append(tuple((len(levels)-1)*n+i for i in range(n)))
    return mesh(name,vertices,faces,mat,parent or CHARACTER,bevel)


def prism(name, points, front_y, back_y, mat, parent=None, bevel=.006):
    # points in the X/Z plane, counterclockwise from the front.
    n=len(points)
    verts=[(x,front_y,z) for x,z in points]+[(x,back_y,z) for x,z in points]
    faces=[tuple(range(n)),tuple(range(2*n-1,n-1,-1))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return mesh(name,verts,faces,mat,parent or CHARACTER,bevel)


def init_scene():
    global SCENE, COLLECTION, CHARACTER
    SCENE = bpy.data.scenes.new('PALADIN | Studio')
    bpy.context.window.scene = SCENE
    COLLECTION = bpy.data.collections.new('PALADIN | Character')
    SCENE.collection.children.link(COLLECTION)
    CHARACTER = empty('PALADIN_Root')
    CHARACTER['description'] = 'Block-style paladin inspired by the supplied front/back concept.'
    CHARACTER['front_axis'] = '-Y (Blender); +Z (glTF)'
    CHARACTER['height_metres'] = 2.20
    CHARACTER['rig_status'] = 'Static articulated object hierarchy; no skeletal rig or animations.'
    palette = {
        'Ivory': ((.79,.775,.77), .26,.40),
        'IvoryLight': ((.91,.875,.82), .22,.39),
        'IvoryShade': ((.64,.636,.67), .27,.43),
        'Gold': ((.90,.385,.028), .55,.31),
        'GoldLight': ((1.0,.53,.070), .5,.30),
        'GoldShade': ((.61,.235,.018), .55,.37),
        'Blue': ((.010,.041,.235), .06,.67),
        'BlueLight': ((.017,.061,.315), .04,.65),
        'BlueShade': ((.007,.026,.14), .03,.73),
        'Leather': ((.075,.048,.033), .0,.76),
        'LeatherLight': ((.13,.080,.045), .0,.71),
        'Black': ((.010,.012,.016), .03,.83),
        'Steel': ((.80,.835,.865), .62,.32),
        'SteelLight': ((.95,.95,.92), .50,.28),
        'SteelShade': ((.52,.57,.65), .60,.38),
    }
    for name,(rgb,metal,rough) in palette.items():
        M[name] = material(name,rgb,metal,rough)
    for name in ['Body','Helmet','Leg.L','Leg.R','Tabard','Cape']:
        GROUPS[name] = empty(name,CHARACTER)
    print('Created paladin scene and editable component hierarchy.')


def build_body():
    body = GROUPS['Body']
    loft('Padded torso',[(2.29,1.25,.72,.12,0,0),(3.24,1.38,.81,.15,0,0)],'BlueShade',body)
    # Stepped cuirass, with separately readable horizontal armor courses.
    courses=[(2.40,2.69,1.37,.85),(2.695,2.99,1.49,.97),(2.995,3.23,1.40,.91)]
    for i,(low,high,w,d) in enumerate(courses):
        loft('Cuirass course %02d'%i,[(low,w,d,.12,-.045,0),(high,w,d,.12,-.045,0)],'Ivory',body)
        box('Cuirass cross stem %02d'%i,(0,-d/2-.064,(low+high)/2),(.265,.06,high-low-.003),'Gold',body)
    box('Chest raised rib',(0,-.556,2.815),(1.42,.10,.14),'IvoryLight',body)
    box('Chest cross arms',(0,-.62,2.817),(.57,.044,.145),'GoldLight',body)
    box('Gorget dark opening',(0,-.015,3.30),(.78,.62,.21),'Black',body)
    loft('Blue padded collar',[(3.20,1.06,.83,.13,0,0),(3.42,1.06,.83,.13,0,0)],'Blue',body)
    box('Collar clasp',(0,-.438,3.30),(.23,.072,.15),'GoldShade',body)
    loft('Leather belt',[(2.12,1.39,.91,.13,-.015,0),(2.40,1.42,.94,.13,-.015,0)],'Leather',body)
    box('Belt centre buckle',(0,-.538,2.26),(.38,.115,.32),'Gold',body,bevel=.016)
    box('Belt buckle highlight',(0,-.601,2.278),(.29,.018,.24),'GoldLight',body,bevel=.003)
    for side in [-1,1]:
        g=GROUPS['Leg.L' if side>0 else 'Leg.R']
        g.location.x=side*.105
        x=side*.53
        box('Boot sole '+str(side),(x,-.13,.155),(.83,.96,.31),'Leather',g,bevel=.014)
        for j in range(2):
            box('Square toe plate %s %s'%(side,j),(x+(-.195 if j==0 else .195),-.426,.212),(.385,.355,.23),
                'LeatherLight' if j==0 else 'Leather',g,bevel=.006)
        loft('Ankle white sabaton '+str(side),[(.30,.73,.75,.07,-.035,x),(.62,.64,.62,.055,.015,x)],'Ivory',g)
        box('Ankle gold vertical '+str(side),(x,-.374,.453),(.25,.048,.293),'GoldLight',g)
        box('Dark knee joint '+str(side),(x,.005,.78),(.56,.57,.38),'Leather',g)
        loft('Gold knee cap '+str(side),[(.62,.57,.59,.05,-.025,x),(.86,.61,.63,.05,-.025,x)],'Gold',g)
        loft('Greave lower course '+str(side),[(.83,.77,.71,.075,0,x), (1.08,.70,.66,.065,0,x)],'Ivory',g)
        loft('Greave upper course '+str(side),[(1.083,.70,.66,.065,0,x),(1.37,.64,.60,.06,0,x)],'IvoryShade',g)
        box('Thigh leather '+str(side),(x,.015,1.47),(.61,.62,.44),'Leather',g)
        loft('Flared tasset ivory '+str(side),[(1.48,.77,.77,.06,-.005,x),(1.81,.63,.67,.055,-.005,x*.91)],'Ivory',g)
        loft('Tasset upper course '+str(side),[(1.815,.63,.67,.055,-.005,x*.91),(2.11,.58,.64,.055,-.005,x*.86)],'IvoryShade',g)
        loft('Tasset gold hem '+str(side),[(1.48,.78,.78,.055,-.005,x),(1.65,.70,.73,.055,-.005,x*.95)],'GoldLight',g)
        box('Tasset ivory inset '+str(side),(x,-.393,1.571),(.32,.022,.17),'IvoryLight',g,bevel=.002)
    tabard=GROUPS['Tabard']
    for j,(low,high) in enumerate([(.73,1.17),(1.172,1.62),(1.622,2.10)]):
        box('Tabard blue panel %02d'%j,(0,-.485,(low+high)/2),(.49,.115,high-low),'Blue' if j%2 else 'BlueLight',tabard)
        box('Tabard gold side stripe %02d'%j,(.284,-.491,(low+high)/2),(.10,.123,high-low),'GoldLight',tabard)
    box('Tabard golden hem',(0.049,-.488,.685),(.595,.13,.20),'GoldLight',tabard)
    print('Built torso, collar, belt, legs and front tabard.')


def build_helmet():
    h=GROUPS['Helmet']
    # The black face chamber remains visible through real gaps between grille bars.
    loft('Helmet inner darkness',[(3.49,1.30,1.02,.14,-.005,0),(4.23,1.49,1.15,.14,-.005,0)],'Black',h)
    for row in range(3):
        z=3.53+row*.21
        box('Helmet rear course %02d'%row,(0,.528,z+.103),(1.29,.20,.203),'IvoryShade',h)
        for side in [-1,1]:
            box('Temple plate %s %s'%(side,row),(side*.723,-.03,z+.103),(.20,1.06,.203),'Ivory',h)
            box('Front cheek %s %s'%(side,row),(side*.618,-.632,z+.103),(.245,.20,.203),'IvoryLight',h)
    # Five pale uprights frame four deep, vertical visor slits.
    for i,x in enumerate([-.45,-.225,0,.225,.45]):
        box('Visor upright %02d'%i,(x,-.709,3.815),(.112,.18,.57),'IvoryLight' if i%2 else 'Ivory',h,bevel=.004)
    loft('Helmet chin rim',[(3.43,1.51,1.37,.155,-.065,0),(3.60,1.55,1.40,.155,-.065,0)],'IvoryLight',h)
    for i,(z,w,d,cut) in enumerate([(4.035,1.68,1.49,.16),(4.245,1.61,1.42,.145),(4.455,1.50,1.31,.13)]):
        loft('Helmet dome course %02d'%i,[(z,w,d,cut,-.045,0),(z+.205,w,d,cut,-.045,0)],'Ivory',h)
    loft('Helmet crown step',[(4.665,1.25,1.12,.12,-.015,0),(4.815,1.25,1.12,.12,-.015,0)],'IvoryLight',h)
    loft('Helmet crown cap',[(4.82,.91,.87,.10,0,0),(4.91,.91,.87,.10,0,0)],'Ivory',h)
    # Continuous gold brow wraps around the stepped shell.
    loft('Gold brow band',[(4.035,1.74,1.53,.175,-.045,0),(4.235,1.74,1.53,.175,-.045,0)],'Gold',h)
    box('Brow front highlight',(0,-.832,4.137),(1.365,.055,.195),'GoldLight',h)
    for i,(z,y,height) in enumerate([(4.35,-.78,.22),(4.565,-.716,.205),(4.755,-.611,.17)]):
        box('Helmet golden central ridge %02d'%i,(0,y,z),(.30,.125,height),'Gold',h)
    box('Raised gold crest',(0,-.04,4.99),(.34,.94,.40),'Gold',h,bevel=.009)
    box('Crest front polished face',(0,-.516,4.984),(.335,.026,.385),'GoldLight',h,bevel=.003)
    helmet_surface_details()
    for side in [-1,1]:
        box('Temple blue strap '+str(side),(side*.836,.035,3.64),(.04,.87,.14),'Blue',h)
        box('Temple gold front stud '+str(side),(side*.845,-.411,3.65),(.084,.20,.20),'GoldLight',h)
        box('Temple gold back stud '+str(side),(side*.845,.437,3.65),(.084,.17,.20),'GoldShade',h)
    print('Built stepped helmet, open visor and gold crest.')


def helmet_surface_details():
    h=GROUPS['Helmet']
    for i,(z,y,height) in enumerate([(4.35,.689,.22),(4.565,.626,.205),(4.755,.555,.17)]):
        box('Helmet rear gold ridge %02d'%i,(0,y,z),(.30,.125,height),'Gold',h)
    # Subtle vertical panel joints preserve the voxel construction of the concept.
    for row,(z,w,d,c) in enumerate([(4.245,1.61,1.42,.145),(4.455,1.50,1.31,.13)]):
        face_w=w-2*c
        for j in range(4):
            x=-face_w/2+(j+.5)*face_w/4
            for side in [-1,1]:
                box('Crown face tile %s %s %s'%(row,j,side),(x,side*(d/2+.003)-.045,z+.1025),
                    (face_w/4-.004,.014,.198),'Ivory',h,bevel=.002)
        for j in range(3):
            y=-(d-2*c)/2+(j+.5)*(d-2*c)/3-.045
            for side in [-1,1]:
                box('Crown temple tile %s %s %s'%(row,j,side),(side*(w/2+.003),y,z+.1025),
                    (.014,(d-2*c)/3-.004,.198),'Ivory',h,bevel=.002)


def build_arms():
    for side in [-1,1]:
        arm=empty('Arm.L (shield)' if side>0 else 'Arm.R (sword)',CHARACTER,(side*.985,0,3.17))
        arm.rotation_euler[1]=-side*math.radians(23)
        GROUPS['ShieldArm' if side>0 else 'SwordArm']=arm
        box('Upper arm padded '+str(side),(0,0,-.35),(.46,.55,.79),'Leather',arm)
        box('Pauldron body '+str(side),(0,-.01,.01),(.78,.82,.43),'Ivory',arm,bevel=.012)
        box('Pauldron crown '+str(side),(0,.0,.245),(.59,.66,.085),'IvoryLight',arm)
        for j in [-1,1]:
            box('Pauldron front panel %s %s'%(side,j),(j*.192,-.428,.035),(.378,.035,.346),
                'Ivory' if j<0 else 'IvoryLight',arm,bevel=.004)
        box('Pauldron gold hem '+str(side),(0,-.006,-.224),(.805,.845,.143),'Gold',arm)
        box('Pauldron gold front '+str(side),(0,-.439,-.222),(.794,.032,.14),'GoldLight',arm,bevel=.003)
        box('Elbow leather joint '+str(side),(0,.0,-.63),(.46,.51,.22),'LeatherLight',arm)
        box('Forearm vambrace '+str(side),(0,-.006,-.858),(.565,.65,.35),'Ivory',arm)
        box('Vambrace raised front '+str(side),(0,-.341,-.85),(.37,.052,.30),'IvoryLight',arm)
        box('Glove wrist '+str(side),(0,-.01,-1.135),(.43,.50,.22),'Leather',arm)
        glove=empty('Hand.L' if side>0 else 'Hand.R',arm,(0,-.075,-1.40))
        GROUPS['ShieldHand' if side>0 else 'SwordHand']=glove
        box('Glove palm '+str(side),(0,0,0),(.44,.48,.40),'Leather',glove)
        for finger in range(3):
            box('Glove fingers %s %s'%(side,finger),(-.14+finger*.145,-.262,-.04),(.135,.18,.30),
                'LeatherLight',glove,bevel=.009)
        box('Glove thumb '+str(side),(-side*.27,-.117,.075),(.16,.24,.24),'LeatherLight',glove,rot=(0,-side*.28,0))
    print('Built articulated block arms and individually modelled glove fingers.')


def cape_surface(x,z):
    levels=[(.75,1.11,1.02),(.96,1.10,.99),(1.46,1.01,.91),
            (1.94,.92,.82),(2.42,.83,.71),(2.90,.75,.61),(3.27,.65,.45)]
    for i in range(len(levels)-1):
        lo,hi=levels[i],levels[i+1]
        if lo[0] <= z <= hi[0]:
            t=(z-lo[0])/(hi[0]-lo[0])
            w=lo[1]*(1-t)+hi[1]*t
            y=lo[2]*(1-t)+hi[2]*t
            break
    else:
        _,w,y=levels[0 if z<.75 else -1]
    u=max(-1,min(1,x/w))
    # Broad angular folds, not a smooth or inflated cape.
    fold=.065*abs(math.sin(u*math.pi*2))
    return y+fold


def cloth_patch(name, corners, mat, parent, offset=0, thickness=.055):
    front=[(x,cape_surface(x,z)+offset,z) for x,z in corners]
    back=[(x,y+thickness,z) for x,y,z in front]
    return mesh(name,front+back,[(3,2,1,0),(4,5,6,7),(0,1,5,4),
                (1,2,6,5),(2,3,7,6),(3,0,4,7)],mat,parent,bevel=.002)


def build_cape():
    cape=GROUPS['Cape']
    levels=[(3.27,.65),(2.90,.75),(2.42,.83),(1.94,.92),(1.46,1.01),(.96,1.10),(.75,1.11)]
    strips=8
    shades=['Blue','BlueShade','Blue','BlueLight','BlueLight','Blue','BlueShade','Blue']
    for row in range(len(levels)-1):
        ztop,wtop=levels[row]
        zbot,wbot=levels[row+1]
        for col in range(strips):
            u0=-1+2*col/strips
            u1=-1+2*(col+1)/strips
            corners=[(wbot*u0,zbot),(wbot*u1,zbot),(wtop*u1,ztop),(wtop*u0,ztop)]
            mat=('GoldLight' if col%3 else 'Gold') if row==len(levels)-2 else shades[col]
            cloth_patch('Cape facet %02d %02d'%(row,col),corners,mat,cape)
    # Low relief applique follows the same folds as the fabric beneath it.
    for i,(lo,hi) in enumerate([(1.20,1.46),(1.46,1.94),(1.94,2.18),(2.18,2.43),(2.43,2.76)]):
        cloth_patch('Cape cross vertical %02d'%i,[(-.135,lo),(.135,lo),(.135,hi),(-.135,hi)],
                    'GoldLight',cape,offset=.060,thickness=.017)
    for side in [-1,1]:
        xa,xb=sorted([side*.135,side*.47])
        cloth_patch('Cape cross arm '+str(side),[(xa,2.18),(xb,2.18),(xb,2.43),(xa,2.43)],
                    'GoldLight',cape,offset=.060,thickness=.017)
        box('Cape shoulder fastener '+str(side),(side*.595,-.26,3.235),(.18,.10,.18),'Gold',GROUPS['Body'])
    print('Built solid faceted cape, golden hem and raised rear cross.')


def build_weapons():
    bpy.context.view_layer.update()
    # The sword and shield are parented to their respective hands.
    hand=GROUPS['SwordHand']
    sword=empty('Sword',CHARACTER,hand.matrix_world.translation)
    sword.rotation_euler[1]=math.radians(-29)
    sword.location.y=-.29
    bpy.context.view_layer.update()
    world=sword.matrix_world.copy()
    sword.parent=hand
    sword.matrix_world=world
    GROUPS['Sword']=sword
    box('Sword leather grip',(0,0,-.04),(.205,.21,.75),'Leather',sword)
    for i in range(5):
        box('Sword grip wrap %02d'%i,(0,-.005,-.32+i*.128),(.218,.222,.040),'LeatherLight',sword,bevel=.003)
    box('Sword gold pommel',(0,0,-.485),(.35,.31,.18),'Gold',sword)
    box('Sword pommel end',(0,0,-.595),(.235,.24,.06),'GoldShade',sword)
    box('Sword broad crossguard',(0,0,.385),(.96,.34,.205),'Gold',sword,bevel=.012)
    box('Sword guard face',(0,-.183,.392),(.90,.029,.164),'GoldLight',sword)
    box('Sword gold blade collar',(0,0,.538),(.35,.195,.16),'GoldLight',sword)
    # Diamond section: genuine planar bevel faces with a sharp silhouette.
    verts=[(-.29,0,.52),(0,-.103,.52),(.29,0,.52),(0,.103,.52),
           (-.29,0,2.22),(0,-.103,2.22),(.29,0,2.22),(0,.103,2.22),(0,0,2.67)]
    faces=[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),
           (4,5,8),(5,6,8),(6,7,8),(7,4,8)]
    blade=mesh('Sword diamond-section blade',verts,faces,'Steel',sword)
    blade.data.materials.append(M['SteelLight'])
    blade.data.materials.append(M['SteelShade'])
    for i,poly in enumerate(blade.data.polygons):
        poly.material_index=[0,1,0,2,0,1,0,2,0][i]
    shield=empty('Shield',CHARACTER,(1.15,-.81,2.27))
    shield.rotation_euler=(math.radians(-4),math.radians(-10),math.radians(-8))
    bpy.context.view_layer.update()
    world=shield.matrix_world.copy()
    shield.parent=GROUPS['ShieldHand']
    shield.matrix_world=world
    GROUPS['Shield']=shield
    # Stepped heater outline, exactly shared by the brass rim and inset blue field.
    points=[(-.76,1.10),(-.59,1.10),(-.59,1.24),(.59,1.24),(.59,1.10),(.76,1.10),
            (.76,-.60),(.65,-.60),(.65,-.79),(.52,-.79),(.52,-.94),(.37,-.94),
            (.37,-1.09),(.19,-1.09),(.19,-1.22),(0,-1.37),(-.19,-1.22),
            (-.19,-1.09),(-.37,-1.09),(-.37,-.94),(-.52,-.94),(-.52,-.79),
            (-.65,-.79),(-.65,-.60),(-.76,-.60)]
    points=list(reversed(points))
    prism('Shield solid gold stepped rim',points,-.115,.115,'Gold',shield,bevel=.009)
    inset=[(x*.802,z*.864+.018) for x,z in points]
    prism('Shield recessed cobalt face',inset,-.133,-.113,'Blue',shield,bevel=.003)
    # An understated central blue highlight, split along the shield midline.
    prism('Shield blue light facet',[(0,-1.158),(.153,-1.048),(.153,-.918),(.298,-.918),
          (.298,-.788),(.417,-.788),(.417,-.65),(.524,-.65),(.524,-.50),(.61,-.50),
          (.61,.965),(.476,.965),(.476,1.087),(0,1.087)],-.136,-.134,'BlueLight',shield,bevel=0)
    cross=[(-.13,-.82),(.13,-.82),(.13,.22),(.41,.22),(.41,.48),(.13,.48),
           (.13,.83),(-.13,.83),(-.13,.48),(-.41,.48),(-.41,.22),(-.13,.22)]
    prism('Shield raised sacred cross',cross,-.204,-.139,'GoldLight',shield,bevel=.008)
    # The back is also finished, with real raised straps around a grip.
    rear=[(x*.85,z*.9) for x,z in points]
    prism('Shield leather backing',rear,.116,.134,'Leather',shield,bevel=.003)
    for z in [-.34,.35]:
        box('Shield rear leather strap '+str(z),(0,.245,z),(1.05,.17,.105),'LeatherLight',shield)
        for side in [-1,1]:
            box('Shield rear gold anchor %s %s'%(z,side),(side*.51,.183,z),(.10,.11,.14),'GoldShade',shield)
    box('Shield hand grip',(0,.30,.01),(.15,.18,.63),'Leather',shield)
    print('Built hand-parented faceted sword and fully finished stepped heraldic shield.')


def aim(obj, target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def setup_studio():
    global COLLECTION
    CHARACTER.scale=(SCALE,)*3
    COLLECTION=bpy.data.collections.new('STUDIO | Cameras and lighting (not exported)')
    SCENE.collection.children.link(COLLECTION)
    groundmat=material('Sand backdrop',(.60,.495,.39),0,.87)
    box('Studio ground',(0,0,-.022),(200,200,.04),groundmat,parent=None,bevel=0)
    # Remove the default character parent from the ground helper.
    ground=bpy.data.objects['Studio ground']
    ground.parent=None
    def camera(name,loc,target,ortho):
        data=bpy.data.cameras.new(name)
        obj=bpy.data.objects.new(name,data)
        COLLECTION.objects.link(obj)
        obj.location=loc
        aim(obj,target)
        data.type='ORTHO'
        data.ortho_scale=ortho
        data.lens=50
        return obj
    GROUPS['CameraFront']=camera('Camera | Front three-quarter',(-4.1,-7.5,4.05),(-.10,0,1.12),3.20)
    GROUPS['CameraRear']=camera('Camera | Rear three-quarter',(4.5,7.5,3.70),(0,.04,1.12),3.12)
    GROUPS['CameraFrontOrtho']=camera('Camera | Front orthographic',(0,-8,1.1),(0,0,1.1),3.1)
    GROUPS['CameraRearOrtho']=camera('Camera | Rear orthographic',(0,8,1.1),(0,0,1.1),3.1)
    SCENE.camera=GROUPS['CameraFront']
    def area(name,loc,power,size,color,target):
        data=bpy.data.lights.new(name,'AREA')
        data.energy=power
        data.shape='DISK'
        data.size=size
        data.color=color
        obj=bpy.data.objects.new(name,data)
        COLLECTION.objects.link(obj)
        obj.location=loc
        aim(obj,target)
    area('Key | warm softbox',(-3.7,-4.5,6.2),650,4.0,(1,.87,.71),(0,0,1.0))
    area('Fill | cool softbox',(4.0,-2.5,3.8),450,3.5,(.74,.82,1),(0,0,1.1))
    area('Rim | upper gold',(1.8,3.5,5.0),800,3.0,(1,.88,.69),(0,0,1.3))
    world=bpy.data.worlds.new('PALADIN | Warm studio world')
    world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.60,.64,.75,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.4
    SCENE.world=world
    SCENE.render.engine='CYCLES'
    SCENE.cycles.samples=64
    SCENE.cycles.use_denoising=True
    SCENE.render.resolution_x=1400
    SCENE.render.resolution_y=1400
    SCENE.render.resolution_percentage=100
    SCENE.render.image_settings.file_format='PNG'
    SCENE.render.image_settings.color_mode='RGBA'
    SCENE.render.film_transparent=False
    SCENE.view_settings.view_transform='AgX'
    SCENE.view_settings.look='AgX - Medium High Contrast'
    SCENE.render.filepath=str(OUT/'paladin_front.png')
    SCENE.unit_settings.system='METRIC'
    for area_ui in bpy.context.screen.areas:
        if area_ui.type=='VIEW_3D':
            area_ui.spaces.active.region_3d.view_perspective='CAMERA'
            area_ui.spaces.active.overlay.show_overlays=False
            area_ui.spaces.active.shading.type='MATERIAL'
    print('Studio ready: 2.2 metre character, four cameras and three softboxes.')


def save_asset():
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action='DESELECT')
    objects=[CHARACTER]+list(CHARACTER.children_recursive)
    triangle_count=0
    nonmanifold=[]
    for obj in objects:
        if obj.type!='MESH':
            continue
        bm=bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        if any(not edge.is_manifold for edge in bm.edges):
            nonmanifold.append(obj.name)
        bm.to_mesh(obj.data)
        bm.free()
        evaluated=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
        evaluated_mesh=evaluated.to_mesh()
        evaluated_mesh.calc_loop_triangles()
        triangle_count+=len(evaluated_mesh.loop_triangles)
        evaluated.to_mesh_clear()
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active=CHARACTER
    # Export only the character, preserving part names and object articulation.
    with contextlib.redirect_stdout(io.StringIO()):
        bpy.ops.export_scene.gltf(filepath=str(OUT/'paladin.glb'),export_format='GLB',
                                  use_selection=True,export_apply=True,export_yup=True,
                                  export_animations=False,export_cameras=False,export_lights=False)
    report={'mesh_objects':sum(o.type=='MESH' for o in objects),
            'triangles_after_bevel':triangle_count,'height_metres':2.2,
            'nonmanifold_meshes':nonmanifold,'material_count':len(M),
            'skeletal_rig':False,'animations':False,'front_axis_blender':'-Y',
            'front_axis_gltf':'+Z','studio_in_glb':False}
    (OUT/'asset_report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    bpy.ops.object.select_all(action='DESELECT')
    CHARACTER.select_set(True)
    bpy.context.view_layer.objects.active=CHARACTER
    SCENE.camera=GROUPS['CameraFront']
    SCENE.render.filepath=str(OUT/'paladin_front.png')
    old_save_version=bpy.context.preferences.filepaths.save_version
    bpy.context.preferences.filepaths.save_version=0
    try:
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'paladin.blend'))
    finally:
        bpy.context.preferences.filepaths.save_version=old_save_version
    print('Saved '+str(OUT/'paladin.blend'))
    print('Exported '+str(OUT/'paladin.glb'))


def build_all():
    init_scene()
    build_body()
    build_helmet()
    build_arms()
    build_cape()
    build_weapons()
    setup_studio()
    save_asset()


if __name__ == '__main__':
    build_all()
