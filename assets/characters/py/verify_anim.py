import sys, numpy as np, matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from bbcommon import BBModel, euler_mat, mat4, sample_channel, ANIM_ROT_SIGN, ANIM_POS_SIGN

bb = BBModel("base.bbmodel")
WEAPON_ROOTS = {'onehand_sword','spear','gread_sword','shield','dagger_left','dagger_right','allow','bow'}
guid_name = {g:bb.groups[g]['name'] for g in bb.groups}
def chain(g):
    out=[]
    while g is not None: out.append(bb.groups[g]['name']); g=bb.group_parent.get(g)
    return out
body=[u for u,e in bb.elements.items()
      if e.get('export',True) and e.get('visibility',True)
      and not any(n in WEAPON_ROOTS for n in chain(bb.elem_bone.get(u)))]

ZONE = {2:('skin','#d9a17e'),6:('tunic','#4e5a63'),5:('boots','#3a2e27'),9:('accent','#a98c4a')}

# precompute per-vertex (worldpos, bone) and per-face polygons
verts=[]; vbone=[]; faces=[]; fcol=[]
for u in body:
    e=bb.elements[u]; wv,fs=bb.element_world_vertices(u)
    base=len(verts)
    b=bb.elem_bone.get(u)
    for p in wv: verts.append(p); vbone.append(b)
    col=ZONE.get(e.get('color'),('?','#cccccc'))[1]
    for f in fs:
        faces.append(tuple(base+i for i in f)); fcol.append(col)
verts=np.array(verts,float)

def rest_local(g):
    p=bb.group_parent.get(g)
    if p is None: return bb.world_rest[g]
    return np.linalg.inv(bb.world_rest[p])@bb.world_rest[g]
def rest_R(g):  # rest rotation part
    return rest_local(g)[:3,:3]

def pose(anim, t):
    """world matrix per bone at time t."""
    animrs=anim.get('animators',{})
    W={}
    def solve(g):
        if g in W: return W[g]
        p=bb.group_parent.get(g)
        rl=rest_local(g)
        pos=np.zeros(3); rot=np.zeros(3); scl=np.ones(3)
        a=animrs.get(g)
        if a:
            chs={}
            for kf in a.get('keyframes',[]):
                chs.setdefault(kf['channel'],[]).append(kf)
            if 'position' in chs: pos=sample_channel(chs['position'],t,anim['length'])*np.array(ANIM_POS_SIGN)
            if 'rotation' in chs: rot=sample_channel(chs['rotation'],t,anim['length'])*np.array(ANIM_ROT_SIGN)
            if 'scale' in chs:
                s=sample_channel(chs['scale'],t,anim['length']); scl=np.where(s==0,1,s)
        Rrest=rl[:3,:3]; trest=rl[:3,3]
        R=Rrest@euler_mat(*rot)
        local=mat4(R, trest+pos)
        local[:3,:3]=local[:3,:3]@np.diag(scl)
        Wp=np.eye(4) if p is None else solve(p)
        W[g]=Wp@local
        return W[g]
    for g in bb.groups: solve(g)
    return W

def skinned(anim,t):
    W=pose(anim,t)
    out=np.empty_like(verts)
    inv_rest={g:np.linalg.inv(bb.world_rest[g]) for g in bb.groups}
    for i,(v,b) in enumerate(zip(verts,vbone)):
        M=W[b]@inv_rest[b]
        out[i]=(M@np.array([*v,1.0]))[:3]
    return out

def render(animname, frames=6, out="anim.png", elev=8, azim=-70):
    anim=next(a for a in bb.animations if a['name']==animname) if hasattr(bb,'animations') else None
    anim=next(a for a in bb.data['animations'] if a['name']==animname)
    L=anim['length'] or 1.0
    fig=plt.figure(figsize=(frames*2.2,3.2))
    for k in range(frames):
        t=L*k/max(frames-1,1) if (anim['loop']!='loop') else L*k/frames
        pts=skinned(anim,t)[:,[0,2,1]]   # -> (X_depth, Z_width, Y_up) so bb-Y is vertical
        ax=fig.add_subplot(1,frames,k+1,projection='3d')
        polys=[[pts[i] for i in f] for f in faces]
        pc=Poly3DCollection(polys, facecolors=fcol, edgecolors='k', linewidths=0.2, alpha=1.0)
        ax.add_collection3d(pc)
        ax.set_xlim(-14,14); ax.set_ylim(-14,14); ax.set_zlim(-2,28)
        ax.set_box_aspect((1,1,1.1)); ax.view_init(elev=elev,azim=azim)
        ax.set_axis_off(); ax.set_title(f"t={t:.2f}",fontsize=7)
    plt.tight_layout(); plt.savefig(out,dpi=90); plt.close()
    print("wrote",out)

if __name__=="__main__":
    render(sys.argv[1], out=sys.argv[2] if len(sys.argv)>2 else "anim.png",
           azim=float(sys.argv[3]) if len(sys.argv)>3 else -70,
           elev=float(sys.argv[4]) if len(sys.argv)>4 else 8)