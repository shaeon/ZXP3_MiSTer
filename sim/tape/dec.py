import struct,sys
l=[int(x) for x in open(sys.argv[1])][1:]
t=open('test.tzx','rb').read()
exp=[t[15:15+21-2] if False else None]
p=10; exp=[]
while p<len(t):
    if t[p]==0x10: n=struct.unpack('<H',t[p+3:p+5])[0]; exp.append(t[p+5:p+5+n]); p+=5+n
    else: n=int.from_bytes(t[p+16:p+19],'little'); exp.append(t[p+19:p+19+n]); p+=19+n
i=0; got=[]
while i<len(l):
    pl=l[i]; j=i
    while j<len(l) and abs(l[j]-pl)<=6: j+=1
    if j-i<100: i+=1; continue
    i=j+2; bits=[]
    while i+1<len(l) and abs(l[i]-l[i+1])<=6 and l[i]<pl-50: bits.append(l[i]); i+=2
    thr=(min(bits)+max(bits))/2; b=''.join('1' if x>thr else '0' for x in bits)
    got.append((bytes(int(b[k:k+8],2) for k in range(0,len(b)//8*8,8)), len(b)%8))
for e,(g,rest) in zip(exp,got): print(len(e), len(g), 'bits sobrantes',rest, 'OK' if e==g else 'DIFERENTE', '' if e==g else 'ultimo esperado %02x'%e[-1])
