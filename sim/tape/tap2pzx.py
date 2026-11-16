# Convierte un TAP a PZX con la codificación estándar de la ROM (para probar pzx_player).
# Uso: python3 tap2pzx.py entrada.tap salida.pzx
import struct, sys

def blk(tag, body):
    return tag + struct.pack('<I', len(body)) + body

tap = open(sys.argv[1], 'rb').read()
out = blk(b'PZXT', bytes([1, 0]))
p = 0
while p + 2 <= len(tap):
    n = struct.unpack('<H', tap[p:p+2])[0]; d = tap[p+2:p+2+n]; p += 2 + n
    pilot = 8063 if d and d[0] < 128 else 3223
    out += blk(b'PULS', struct.pack('<HHHH', 0x8000 | pilot, 2168, 667, 735))
    # bits (bit 31 = nivel inicial alto), pulso final, 2 pulsos por bit, secuencias del 0 y del 1
    out += blk(b'DATA', struct.pack('<IHBB', 0x80000000 | (8 * len(d)), 945, 2, 2) +
               struct.pack('<HHHH', 855, 855, 1710, 1710) + d)
    out += blk(b'PAUS', struct.pack('<I', 3500000))
open(sys.argv[2], 'wb').write(out)
