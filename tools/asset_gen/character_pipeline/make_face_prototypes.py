"""Temporary UV marks for controller validation; replace with authored face art."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
UV = {
    '001': {'eyes': [(.76,.786),(.043,.504)], 'brows':[(.644,.527),(.06,.551)], 'mouth':(.635,.747)},
    '002': {'eyes': [(.399,.658),(.049,.461)], 'brows':[(.035,.094),(.857,.425)], 'mouth':(.043,.35)},
}

for face_id, positions in UV.items():
    out = ROOT / f'assets/characters/_shared/face/face_{face_id}'
    out.mkdir(parents=True, exist_ok=True)
    guide = Image.open(ROOT / f'artifacts/golden_path/face_{face_id}_albedo.png').convert('RGBA')
    guides = ImageDraw.Draw(guide)
    for expression in ('normal','closed','surprised','squint'):
        image = Image.new('RGBA', (512,512), (0,0,0,0))
        draw = ImageDraw.Draw(image)
        for uv in positions['eyes']:
            x,y = round(uv[0]*512),round((1-uv[1])*512)
            if expression == 'closed':
                draw.line((x-7,y,x+7,y),fill=(38,23,23,240),width=3)
            elif expression == 'squint':
                draw.ellipse((x-7,y-2,x+7,y+2),fill=(37,24,25,235))
            else:
                radius = 8 if expression == 'surprised' else 5
                draw.ellipse((x-radius,y-radius,x+radius,y+radius),fill=(35,23,25,240))
        for uv in positions['brows']:
            x,y = round(uv[0]*512),round((1-uv[1])*512)
            draw.line((x-8,y+2,x+8,y-2 if expression == 'surprised' else y+2),fill=(48,30,27,220),width=3)
        x,y = round(positions['mouth'][0]*512),round((1-positions['mouth'][1])*512)
        if expression == 'surprised':
            draw.ellipse((x-4,y-6,x+4,y+6),fill=(82,38,43,220))
        else:
            draw.arc((x-8,y-3,x+8,y+5),5,175,fill=(93,42,43,220),width=3)
        image.save(out / f'{expression}.png')
    for label,color in [('eyes','red'),('brows','blue'),('mouth','green')]:
        for uv in positions[label] if label != 'mouth' else [positions[label]]:
            x,y=round(uv[0]*512),round((1-uv[1])*512)
            guides.ellipse((x-7,y-7,x+7,y+7),outline=color,width=3)
    guides.text((8,8),'red: eyes   blue: eyebrows   green: mouth',fill='black')
    guide.save(ROOT / f'artifacts/golden_path/face_{face_id}_uv_guide.png')
