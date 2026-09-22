"""Portable payload audit and contact sheets from actual Godot captures."""
import hashlib
import json
import struct
from pathlib import Path
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parents[1]
ART=ROOT/'artifacts/character_phase1_5'
SOURCES={'adventure':'tripo_adventure/adventure.glb','knight':'tripo_knight2/knigth.glb','black_mage':'tripo_black_mage/black_mage.glb'}

def read_glb(path):
    data=path.read_bytes()
    assert struct.unpack_from('<III',data)==(0x46546C67,2,len(data))
    n=struct.unpack_from('<I',data,12)[0]
    return json.loads(data[20:20+n])

def sheet(path,rows):
    width,height=300,360
    image=Image.new('RGB',(width*max(map(len,rows)),height*len(rows)),(31,33,37))
    draw=ImageDraw.Draw(image)
    for y,row in enumerate(rows):
        for x,(name,label) in enumerate(row):
            item=Image.open(ART/(name+'.png')).convert('RGB')
            item.thumbnail((width,height-32))
            image.paste(item,(x*width+(width-item.width)//2,y*height+32))
            draw.text((x*width+7,y*height+9),label,fill='white')
    image.save(ART/path,quality=94)

def main():
    protected=json.loads((ART/'protected_before.json').read_text())
    changed=[p for p,h in protected.items() if hashlib.sha256((ROOT/p).read_bytes()).hexdigest()!=h]
    assert not changed,changed
    result={}
    for key,relative in SOURCES.items():
        out=(ROOT/'assets/characters'/relative).parent/'prepared/phase1_5'
        body=read_glb(out/'body.glb')
        head=read_glb(out/'head_default.glb')
        anim=read_glb(out/'animations/common_combat.glb')
        assert len(body['meshes'])==1 and len(body['skins'])==1
        assert len(body['skins'][0]['joints'])==26
        assert not head.get('skins') and not body.get('animations')
        assert {a['name'] for a in anim['animations']}=={'idle','walk','attack_melee','cast_magic','hit'}
        assert all(c['target']['path']=='rotation' for a in anim['animations'] for c in a['channels'])
        for node in body['nodes']:
            if 'Socket' in node.get('name',''):
                assert max(abs(x) for x in node.get('translation',[0,0,0]))<1e-5
                assert max(abs(x-y) for x,y in zip(node.get('rotation',[0,0,0,1]),[0,0,0,1]))<1e-5
        result[key]={'one_body_skeleton':True,'rigid_head':True,'five_rotation_only_baked_clips':True,'socket_bind_identity':True}
    godot=json.loads((ART/'godot_validation.json').read_text())
    assert godot['passed'] and godot['rendered']
    (ART/'portable_validation.json').write_text(json.dumps(result,indent=2))
    (ART/'preservation.json').write_text(json.dumps({'unchanged_files':len(protected),'all_protected_files_unchanged':True},indent=2))
    sheet('animations_contact_sheet.jpg',[[(k+'_'+a,k+' / '+a) for a in ['idle','walk','attack_melee','cast_magic','hit']] for k in SOURCES])
    sheet('head_swaps_contact_sheet.jpg',[[(b+'_with_'+h,b+' body + '+h+' head') for h in SOURCES if b!=h] for b in SOURCES])
    sheet('palette_contact_sheet.jpg',[[(k+'_palette_'+str(i),k+' / '+v) for i,v in enumerate(['original','primary','secondary','both'])] for k in SOURCES])
    sheet('emblem_contact_sheet.jpg',[[('knight_emblem_'+str(i),v) for i,v in enumerate(['clean / disabled','transparent diamond','transparent ring'])]])
    sheet('native_pose_contact_sheet.jpg',[[(k+'_raw_front',k+' raw'),(k+'_palette_0',k+' prepared')] for k in SOURCES])
    print('PHASE1_5_PORTABLE_AND_PRESERVATION_PASS',len(protected))

if __name__=='__main__': main()
