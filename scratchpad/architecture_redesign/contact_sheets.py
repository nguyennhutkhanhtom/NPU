from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json
root=Path(__file__).resolve().parents[2]
work=Path(__file__).parent
ds=json.loads((root/'docs/diagrams/architecture_index.json').read_text(encoding='utf-8'))
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',14)
for start in range(0,len(ds),16):
    sheet=Image.new('RGB',(1800,2200),'#eeeeee');draw=ImageDraw.Draw(sheet)
    for i,d in enumerate(ds[start:start+16]):
        image=Image.open(work/'png'/f'{d["key"]}.png').convert('RGB');image.thumbnail((430,510))
        x=(i%4)*450;y=(i//4)*550
        draw.text((x+10,y+5),d['key'][:48],fill='black',font=font)
        sheet.paste(image,(x+10+(430-image.width)//2,y+30))
    sheet.save(work/f'contact_{start//16+1:02}.png')
print('Contact sheets:',(len(ds)+15)//16)
