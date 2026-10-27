import struct, zlib, json
from pathlib import Path
root=Path('AfterBell/Assets.xcassets')
(root/'AppIcon.appiconset').mkdir(parents=True, exist_ok=True)
(root/'Contents.json').write_text(json.dumps({'info':{'author':'xcode','version':1}}))
def chunk(kind,data):
 return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
def png(n):
 rows=bytearray()
 for y in range(n):
  rows.append(0)
  for x in range(n):
   t=(x+y)/(2*n)
   color=tuple(int(a*(1-t)+b*t) for a,b in zip((182,155,235),(120,97,197)))
   u=abs(x/n-.5);v=abs(y/n-.5)
   if u+v<.215 and min(u,v)<.067 or (u<.045 and v<.25) or (v<.045 and u<.25):color=(249,245,255)
   rows.extend(color)
 return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',n,n,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(rows),9))+chunk(b'IEND',b'')
images=[]
for size in (20,29,40,60):
 for scale in (2,3):
  n=size*scale;fn=f'icon-{n}.png';(root/'AppIcon.appiconset'/fn).write_bytes(png(n));images.append({'idiom':'iphone','size':f'{size}x{size}','scale':f'{scale}x','filename':fn})
(root/'AppIcon.appiconset'/'icon-1024.png').write_bytes(png(1024))
images.append({'idiom':'ios-marketing','size':'1024x1024','scale':'1x','filename':'icon-1024.png'})
(root/'AppIcon.appiconset'/'Contents.json').write_text(json.dumps({'images':images,'info':{'author':'xcode','version':1}}))
