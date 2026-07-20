import sys, json, struct, numpy as np

CT={5120:('b',1),5121:('B',1),5122:('h',2),5123:('H',2),5125:('I',4),5126:('f',4)}
NT={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}

def load_glb(path):
    d=open(path,'rb').read()
    magic,ver,length=struct.unpack('<III',d[:12]); off=12
    js=None; bin_=None
    while off<length:
        clen,ctype=struct.unpack('<II',d[off:off+8]); off+=8
        chunk=d[off:off+clen]; off+=clen
        if ctype==0x4E4F534A: js=json.loads(chunk)
        elif ctype==0x004E4942: bin_=chunk
    return js,bin_

def acc(g,bin_,i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    fmt,sz=CT[a['componentType']]; n=NT[a['type']]
    start=bv.get('byteOffset',0)+a.get('byteOffset',0)
    count=a['count']
    raw=bin_[start:start+count*n*sz]
    arr=np.frombuffer(raw,dtype=np.dtype(fmt)).reshape(count,n) if n>1 else np.frombuffer(raw,dtype=np.dtype(fmt))
    return arr.astype(np.float64) if fmt=='f' else arr.astype(np.int64)

def quat2mat(q):
    x,y,z,w=q; 
    return np.array([
        [1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
        [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
        [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])

def node_local(n):
    T=np.eye(4)
    if 'rotation' in n: T[:3,:3]=quat2mat(n['rotation'])
    if 'scale' in n: T[:3,:3]=T[:3,:3]@np.diag(n['scale'])
    if 'translation' in n: T[:3,3]=n['translation']
    return T

def world_mats(g, node_overrides=None):
    """compute world matrix per node index."""
    nodes=g['nodes']; parent={}
    for i,n in enumerate(nodes):
        for c in n.get('children',[]): parent[c]=i
    W={}
    def solve(i):
        if i in W: return W[i]
        n=nodes[i]
        loc = node_overrides[i] if (node_overrides and i in node_overrides) else node_local(n)
        p=parent.get(i)
        W[i]= (solve(p)@loc) if p is not None else loc
        return W[i]
    for i in range(len(nodes)): solve(i)
    return W

def skinned_positions(path, anim_name=None, t=0.0):
    g,bin_=load_glb(path)
    skin=g['skins'][0]; joints=skin['joints']
    ibm=acc(g,bin_,skin['inverseBindMatrices']).reshape(-1,4,4)
    ibm=np.transpose(ibm,(0,2,1))  # column-major -> row-major
    jslot={jn:k for k,jn in enumerate(joints)}
    overrides={}
    if anim_name:
        an=next(a for a in g['animations'] if a['name']==anim_name)
        # gather per-node channel samples at time t (LINEAR)
        per={}
        for ch in an['channels']:
            s=an['samplers'][ch['sampler']]; node=ch['target']['node']; path_=ch['target']['path']
            times=acc(g,bin_,s['input']); vals=acc(g,bin_,s['output'])
            if t<=times[0]: v=vals[0]
            elif t>=times[-1]: v=vals[-1]
            else:
                k=np.searchsorted(times,t)-1; a0=(t-times[k])/(times[k+1]-times[k])
                v=vals[k]*(1-a0)+vals[k+1]*a0
                if path_=='rotation': v=v/np.linalg.norm(v)
            per.setdefault(node,{})[path_]=v
        for node,d in per.items():
            n=g['nodes'][node]
            T=np.eye(4)
            rot=d.get('rotation', n.get('rotation',[0,0,0,1]))
            T[:3,:3]=quat2mat(rot)
            if 'scale' in d or 'scale' in n: T[:3,:3]=T[:3,:3]@np.diag(d.get('scale',n.get('scale',[1,1,1])))
            T[:3,3]=d.get('translation', n.get('translation',[0,0,0]))
            overrides[node]=T
    W=world_mats(g, overrides)
    # skinning matrices per joint
    JM=[W[jn]@ibm[k] for k,jn in enumerate(joints)]
    # gather mesh verts
    mesh_node=next(i for i,n in enumerate(g['nodes']) if 'mesh' in n and 'skin' in n)
    mesh=g['meshes'][g['nodes'][mesh_node]['mesh']]
    allpos=[]
    for prim in mesh['primitives']:
        pos=acc(g,bin_,prim['attributes']['POSITION'])
        jnt=acc(g,bin_,prim['attributes']['JOINTS_0'])
        for p,j in zip(pos,jnt):
            M=JM[int(j[0])]
            allpos.append((M@np.array([*p,1]))[:3])
    return np.array(allpos)

if __name__=="__main__":
    g,bin_=load_glb(sys.argv[1])
    print("nodes",len(g['nodes']),"meshes",len(g['meshes']),"materials",len(g.get('materials',[])),
          "skins",len(g.get('skins',[])),"animations",len(g.get('animations',[])))
    print("anim names:",[a['name'] for a in g.get('animations',[])][:5],"...")
    print("bind verts:",skinned_positions(sys.argv[1]).shape)