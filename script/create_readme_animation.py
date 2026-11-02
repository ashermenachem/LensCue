from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import math
root=Path(__file__).resolve().parent.parent / 'docs/assets'
fontpath='/System/Library/Fonts/Supplemental/Arial.ttf'
boldpath='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
font=lambda n,b=False: ImageFont.truetype(boldpath if b else fontpath,n)
W,H=1000,540
mint=(106,239,210)
frames=[]
lines=['Welcome to my presentation.', 'Today, we will explore', 'a whole new world together.', 'Take a breath. Keep going.']
for f in range(108):
    im=Image.new('RGB',(W,H),(12,17,21)); d=ImageDraw.Draw(im)
    # An intentionally illustrated desktop, no personal information.
    d.rounded_rectangle((32,24,968,394),radius=18,fill=(23,34,39),outline=(52,66,69),width=1)
    for y in range(25,394):
        color=(23+int((y-25)*.015),34+int((y-25)*.025),39+int((y-25)*.03))
        d.line((33,y,967,y),fill=color)
    d.line((33,52,967,52),fill=(47,62,65))
    d.text((53,34),'LensCue',font=font(12,True),fill=(188,203,201))
    d.text((850,34),'On this Mac',font=font(11),fill=(132,153,151))
    # The notch-connected prompter.
    d.rounded_rectangle((317,24,683,205),radius=22,fill=(0,0,0))
    d.rectangle((317,24,683,55),fill=(0,0,0))
    d.ellipse((495,32,505,42),fill=(17,32,37));d.ellipse((498,35,502,39),fill=(46,74,85))
    paused=36<=f<60
    # read-progress holds during the pause
    phase=f if f<36 else 36 if f<60 else f-24
    progress=min(2.9,phase/28)
    current=int(progress)
    frac=progress-current
    dy=0 if frac<.7 else (frac-.7)/.3
    shift=(current+dy)*34
    # Render on a separate layer to clip text below the camera cutout.
    text=Image.new('RGB',(346,115),(0,0,0));td=ImageDraw.Draw(text)
    for i,line in enumerate(lines):
        y=8+i*34-shift
        color=(245,249,248) if i==current else (99,110,109)
        tw=td.textlength(line,font=font(20,True))
        td.text(((346-tw)/2,y),line,font=font(20,True),fill=color)
    im.paste(text,(327,61))
    d.ellipse((497,188,503,194),fill=(242,189,104) if paused else mint)
    # Deliberately soft app-window silhouettes behind the prompter.
    d.rounded_rectangle((88,244,395,353),radius=10,fill=(31,44,49),outline=(52,66,69))
    d.text((108,264),'YOUR PRESENTATION',font=font(11,True),fill=(105,129,128))
    d.rounded_rectangle((108,293,302,301),radius=4,fill=(69,89,91))
    d.rounded_rectangle((108,315,351,322),radius=3,fill=(48,68,72))
    d.rounded_rectangle((608,244,912,353),radius=10,fill=(31,44,49),outline=(52,66,69))
    d.text((628,264),'STAY CLOSE TO THE LENS',font=font(11,True),fill=(105,129,128))
    for i in range(24):
        amp=3 if paused else 3+int(14*abs(math.sin(i*.7+f*.45)))
        x=630+i*10
        d.rounded_rectangle((x,315-amp,x+4,315+amp),radius=2,fill=(81,101,101) if paused else mint)
    label='Pause. Your script waits.' if paused else 'Speak. Your script follows.'
    tw=d.textlength(label,font=font(28,True));d.text(((W-tw)/2,424),label,font=font(28,True),fill=(238,245,244))
    sub='On-device English recognition  /  No account  /  No subscription'
    tw=d.textlength(sub,font=font(15));d.text(((W-tw)/2,472),sub,font=font(15),fill=(139,160,156))
    frames.append(im.quantize(colors=96))
frames[0].save(root/'voice-follow.gif',save_all=True,append_images=frames[1:],duration=85,loop=0,optimize=True,disposal=2)
frames[20].convert('RGB').save(root/'social-preview.png')
print('Created',root/'voice-follow.gif')
