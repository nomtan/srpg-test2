"""Validate portable GLB payloads and make labeled visual review sheets."""
import hashlib
import json
import struct
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT/'artifacts/character_phase1'
PATHS = {'adventure':'tripo_adventure/adventure.glb',
         'knight':'tripo_knight2/knigth.glb', 'black_mage':'tripo_black_mage/black_mage.glb'}


def glb(path):
    blob = path.read_bytes()
    magic, version, length = struct.unpack_from('<III',blob)
    assert magic==0x46546C67 and version==2 and length==len(blob)
    size = struct.unpack_from('<I',blob,12)[0]
    return json.loads(blob[20:20+size]), blob[28+size:]


def sheet(filename, rows):
    width,height = 280,350
    result = Image.new('RGB',(width*len(rows[0]),height*len(rows)),(32,34,39))
    draw = ImageDraw.Draw(result)
    for r,row in enumerate(rows):
        for c,(name,label) in enumerate(row):
            img = Image.open(ART/(name+'.png')).convert('RGB')
            img.thumbnail((width,height-28))
            result.paste(img,(c*width+(width-img.width)//2,r*height+28))
            draw.text((c*width+8,r*height+8),label,fill='white')
    result.save(ART/filename)


def main():
    inspection = json.loads((ART/'inspection.json').read_text(encoding='utf-8'))
    build = json.loads((ART/'build.json').read_text(encoding='utf-8'))
    portable = {}
    for key,relative in PATHS.items():
        raw = ROOT/'assets/characters'/relative
        assert hashlib.sha256(raw.read_bytes()).hexdigest()==inspection[key]['sha256']
        out = raw.parent/'prepared/phase1'
        body,binary = glb(out/'body.glb')
        head,_ = glb(out/'head_default.glb')
        assert len(body['meshes'])==1 and len(body['skins'])==1
        assert len(body['skins'][0]['joints'])==26
        assert not body.get('animations') and not head.get('animations') and not head.get('skins')
        for image in body['images']:
            view = body['bufferViews'][image['bufferView']]
            start = view.get('byteOffset',0)
            assert hashlib.sha256(binary[start:start+view['byteLength']]).hexdigest()==build[key]['source_image_sha256']
        for node in body['nodes']:
            if 'Socket' in node.get('name',''):
                assert max(abs(v) for v in node.get('translation',[0,0,0]))<1e-5
                assert max(abs(a-b) for a,b in zip(node.get('rotation',[0,0,0,1]),[0,0,0,1]))<1e-5
        portable[key] = {'raw_sha256_preserved':True, 'embedded_original_texture_preserved':True,
                         'body_meshes':1,'skeletons':1,'bones':26,'head_extra_skeletons':0,
                         'per_character_animations':0,'socket_local_identity':True}
    common,_ = glb(ROOT/'assets/characters/_shared/animations/common_combat.glb')
    assert {a['name'] for a in common['animations']}=={'idle','walk','attack_melee','cast_magic','hit'}
    (ART/'portable_validation.json').write_text(json.dumps(portable,indent=2),encoding='utf-8')
    sheet('animations_contact_sheet.jpg',[
        [(key+'_'+clip,key+' / '+clip) for clip in ['idle','walk','attack_melee','cast_magic','hit']]
        for key in PATHS])
    sheet('head_swaps_contact_sheet.jpg',[
        [(key+'_with_'+other,key+' body + '+other+' head') for other in PATHS if other!=key]
        for key in PATHS])
    sheet('rest_contact_sheet.jpg',[[(key+'_tpose',key+' / T-pose') for key in PATHS]])
    print('PORTABLE_PAYLOAD_CHECKS_PASSED; visual acceptance is separately documented.')


if __name__=='__main__': main()
