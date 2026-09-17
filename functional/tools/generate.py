"""Deterministic numeric LUTs, executable ISA program and independent vector oracle."""
from pathlib import Path
import math, json, hashlib
from decimal import Decimal, localcontext
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"functional/assets"
OUT.mkdir(parents=True,exist_ok=True)
def write(name, text):
    (OUT/name).write_text(text,encoding="ascii")
def instruction(op,d=0,a=0,b=0):
    return op<<9 | d<<6 | b<<3 | a
for w,depth in ((8,64),(16,512)):
    f=w-4; scale=1<<f; lo=-(1<<(w-1)); hi=(1<<(w-1))-1; mask=(1<<w)-1
    sat=lambda x:max(lo,min(hi,x))
    def trunc_div(a,b): return (abs(a)//abs(b))*(-1 if (a<0) != (b<0) else 1)
    def div(a,b): return sat(trunc_div(a*scale,b)) if b else (0 if a==0 else (lo if a<0 else hi))
    def rms(v):
        denominator=math.isqrt((sum(x*x for x in v)//512+1)<<(2*f))
        return [sat(trunc_div(x<<(2*f),denominator)) for x in v]
    def packed(v):
        return [sum((v[i+j]&mask)<<(j*w) for j in range(32)) for i in range(0,512,32)]
    def hexwords(words): return "".join(f"{x:0{w*8}x}\n" for x in words)
    ex=[sat(math.floor(math.exp(raw/scale)*scale+0.5)) for raw in range(lo,hi+1)]
    sig=[sat(math.floor(scale/(1+math.exp(-raw/scale))+0.5)) for raw in range(lo,hi+1)]
    assert ex[-lo]==scale and sig[-lo]==scale//2
    assert next(raw for raw in range(lo,hi+1) if math.floor(math.exp(raw/scale)*scale+0.5)>hi)==(34 if w==8 else 8518)
    assert ex==sorted(ex) and sig==sorted(sig)
    # Independent high precision audit of all 8-bit inputs and 16-bit samples.
    with localcontext() as ctx:
        ctx.prec=60
        points=range(lo,hi+1) if w==8 else sorted(set([lo,hi,0,1,-1]+list(range(lo,hi+1,113))))
        for raw in points:
            e=(Decimal(raw)/scale).exp()
            nearest=lambda x:sat(int((x+Decimal("0.5")).to_integral_value(rounding="ROUND_FLOOR")))
            assert ex[raw-lo]==nearest(e*scale)
            assert sig[raw-lo]==nearest(Decimal(scale)/(1+1/e))
    write(f"exp_{w}.hex","".join(f"{x:0{w//4}x}\n" for x in ex))
    write(f"sig_{w}.bin","".join(f"{x:0{w}b}\n" for x in sig))
    def weight(m,r,c):
        if m==0: return int(r==c)
        if m==1: return (1 if c==(r+17)%512 else 0)-(1 if c==r else 0)
        if m==2: return 1
        if m==7: return -1
        return 0
    vectors=[[0]*512 for _ in range(64)]
    vectors[0]=[sat(((i*29)%97-48)*max(1,scale//32)) for i in range(512)]
    vectors[0][0]=lo; vectors[0][511]=hi
    vectors[1]=[scale if i%3 else -scale//2 for i in range(512)]
    initial_vectors=[v.copy() for v in vectors]
    matrices=[]
    for m in range(8):
        words=[]; per=w*16
        for k in range(0,512*512,per):
            word=0
            for j in range(per):
                r,c=divmod(k+j,512)
                word|=(weight(m,r,c)&3)<<(2*j)
            words.append(word)
        matrices+=words
    initial_memory=sum((packed(v) for v in vectors),[])+matrices
    regs=[[0]*512 for _ in range(8)]
    ops=[
        (9,0,0,0),(9,1,1,0),(1,2,0,1),(2,3,2,1),
        (3,4,3,1),(4,5,4,1),(5,6,0,0),(6,7,0,0),
        (7,2,0,0),(10,2,2,0),(8,3,0,2),(8,4,1,3),
        (9,3,4,0),(1,3,3,1),(10,7,3,7),(9,4,7,7),
        (7,5,4,0),(10,6,5,0),(8,5,2,6),(9,6,5,0),
        (10,7,6,0),(8,6,7,0),(9,7,6,0)]
    trace=[]
    for op,d,a,b in ops:
        x=regs[a].copy(); y=regs[b].copy()
        if op==9: regs[d]=vectors[b*8+a].copy()
        elif op==10: vectors[b*8+d]=x
        elif op==8:
            v=vectors[b].copy()
            vectors[d]=[sat(sum(weight(a,r,c)*v[c] for c in range(512))) for r in range(512)]
        elif op==1: regs[d]=[sat(u+v) for u,v in zip(x,y)]
        elif op==2: regs[d]=[sat(u-v) for u,v in zip(x,y)]
        elif op==3: regs[d]=[sat((u*v)//scale) for u,v in zip(x,y)]
        elif op==4: regs[d]=[div(u,v) for u,v in zip(x,y)]
        elif op==5: regs[d]=[ex[u-lo] for u in x]
        elif op==6: regs[d]=[sig[u-lo] for u in x]
        elif op==7: regs[d]=rms(x)
        result=vectors[d] if op==8 else vectors[b*8+d] if op==10 else regs[d]
        trace+=packed(result)
    program=[instruction(*op) for op in ops]+[instruction(15,0,5,6)]
    program+=[instruction(15)]*(depth-len(program))
    write(f"program_{w}.bin","".join(f"{i:013b}\n" for i in program))
    write(f"memory_{w}.hex",hexwords(initial_memory))
    write(f"golden_reg_{w}.hex",hexwords(sum((packed(v) for v in regs),[])))
    write(f"golden_mem_{w}.hex",hexwords(sum((packed(v) for v in vectors),[])+matrices))
    write(f"golden_trace_{w}.hex",hexwords(trace))
    rms_vectors=[[0]*512,[scale]*512,[lo if i%2 else hi for i in range(512)],
                 [hi]+[0]*511,[(i%17-8)*max(1,scale//16) for i in range(512)]]
    write(f"rms_input_{w}.hex",hexwords(sum((packed(v) for v in rms_vectors),[])))
    write(f"rms_golden_{w}.hex",hexwords(sum((packed(rms(v)) for v in rms_vectors),[])))
manifest={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(OUT.iterdir()) if p.is_file() and p.name!="manifest.json"}
(OUT/"manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
print("Numeric assets generated and independently audited (8/16 bit); 23-instruction oracle per profile.")
