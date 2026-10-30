# Genera test.tzx / test.hex: cabecera estándar (0x10), bloque turbo (0x11) y bloque de datos (0x10)
import struct
def tap(flag,data):
    b=bytes([flag])+data; x=0
    for c in b: x^=c
    return b+bytes([x])
hdr=tap(0,bytes([3])+b'TESTBLOCK '+struct.pack('<HHH',300,32768,0x8000))
dat=tap(0xff,bytes((i*37+11)&255 for i in range(300)))
t=b'ZXTape!\x1a\x01\x14'
t+=bytes([0x10])+struct.pack('<HH',200,len(hdr))+hdr
t+=bytes([0x11])+struct.pack('<HHHHHHBH',1200,400,450,500,1000,600,8,100)+struct.pack('<I',len(dat))[:3]+dat
t+=bytes([0x10])+struct.pack('<HH',100,len(dat))+dat
open('test.tzx','wb').write(t)
open('test.hex','w').write('\n'.join('%02x'%c for c in t)+'\n')
