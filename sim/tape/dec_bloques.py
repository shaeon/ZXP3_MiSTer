import struct,sys
L=[tuple(map(int,x.split())) for x in open(sys.argv[1])][1:]
d=[x[0] for x in L]; lv=[x[1] for x in L]
exp=[]; e=open('exp.bin','rb').read(); p=0
while p<len(e): n=struct.unpack('<H',e[p:p+2])[0]; exp.append(e[p+2:p+2+n]); p+=2+n
i=0; got=[]; tones=0
while i<len(d):
    pl=d[i]; j=i
    while j<len(d) and abs(d[j]-pl)<=max(30,pl*0.03): j+=1
    if j-i<15: i+=1; continue
    if j-i<100:  # tono corto del bucle
        tones+=1; i=j; continue
    first_level=lv[i]
    i=j+2; bits=[]
    while i+1<len(d) and abs(d[i]-d[i+1])<=max(30,d[i]*0.03) and d[i]<pl-50: bits.append(d[i]); i+=2
    if not bits: continue
    thr=(min(bits)+max(bits))/2; b=''.join('1' if x>thr else '0' for x in bits)
    got.append((bytes(int(b[k:k+8],2) for k in range(0,len(b)//8*8,8)), first_level))
for n,ex in enumerate(exp):
    if n>=len(got): print('bloque',n+1,'falta'); continue
    g,fl=got[n]; print('bloque %d: %d/%d bytes %s, nivel del primer pulso del piloto=%d'%(n+1,len(g),len(ex),'OK' if g==ex else 'MAL',fl))
pil=[x for x in d if x>0]; esc=sorted(pil)[len(pil)//2]/2168.0   # escala: mediana ~ pulso de piloto
tono=1000*esc
print('pulsos del tono del bucle (esperados 3 x 20 = 60):', sum(1 for x in d if abs(x-tono)<=max(30,tono*0.03)))
