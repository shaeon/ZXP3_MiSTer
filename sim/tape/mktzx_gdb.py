import struct
def tap(flag,data):
    b=bytes([flag])+data; x=0
    for c in b: x^=c
    return b+bytes([x])
W=lambda v: struct.pack('<H',v); D=lambda v: struct.pack('<I',v)
hdr=tap(0,bytes([3])+b'GDBTEST   '+struct.pack('<HHH',64,32768,0x8000))
d1=tap(0xff,bytes((i*7+3)&255 for i in range(64)))
d2=tap(0xff,bytes((i*13+5)&255 for i in range(40)))
t=b'ZXTape!\x1a\x01\x14'
t+=bytes([0x10])+W(1000)+W(len(hdr))+hdr                       # B1 estándar
t+=bytes([0x21,4])+b'grp1'+bytes([0x22])                         # grupo
t+=bytes([0x2B])+D(1)+bytes([0])                                 # nivel bajo
t+=bytes([0x23])+W(1)                                            # salto (se ignora)
t+=bytes([0x26])+W(2)+W(1)+W(2)+bytes([0x27])                    # call + return
sel=bytes([1])+W(1)+bytes([3])+b'abc'
t+=bytes([0x28])+W(len(sel)+1)+bytes([1])+sel                    # select
t+=bytes([0x18])+D(13)+W(0)+bytes([0x44,0xAC,0])+bytes([1])+D(3)+bytes([5,6,7])  # CSW (se salta)
# B2: GDB que codifica un bloque estándar
asp=2; npp=2
ptab=bytes([0])+W(2168)+W(0) + bytes([0])+W(667)+W(735)          # símbolo 0: pulso piloto; símbolo 1: sync1+sync2
prle=bytes([0])+W(600) + bytes([1])+W(1)
asd=2; npd=2
dtab=bytes([0])+W(855)+W(855) + bytes([0])+W(1710)+W(1710)
bits=''.join(format(c,'08b') for c in d1)
data=bytes(int(bits[i:i+8],2) for i in range(0,len(bits),8))
body=W(1000)+D(2)+bytes([npp,asp])+D(len(bits))+bytes([npd,asd])+ptab+prle+dtab+data
t+=bytes([0x19])+D(len(body))+body
# B3: bucle de 3 tonos cortos y bloque estándar final
t+=bytes([0x24])+W(3)+bytes([0x12])+W(1000)+W(20)+bytes([0x25])
t+=bytes([0x10])+W(0)+W(len(d2))+d2
open('t.tzx','wb').write(t); open('t.hex','w').write('\n'.join('%02x'%c for c in t)+'\n'); print(len(t))
open('exp.bin','wb').write(b''.join([struct.pack('<H',len(x))+x for x in (hdr,d1,d2)]))
# el mismo contenido como TAP (longitud + bloque), para probar la carga de TAP
tap=b''.join(struct.pack('<H',len(x))+x for x in (hdr,d1,d2))
open('t.tap','wb').write(tap); open('tap.hex','w').write('\n'.join('%02x'%c for c in tap)+'\n')
