"""Independent integer references for the main NPU regression.

The retained host, sigmoid and scalar edge cases came from the former v2 tests.
Vectors are regenerated under tests/sim; no duplicate RTL source is required.
"""
from pathlib import Path
from math import isqrt
from decimal import Decimal, localcontext, ROUND_HALF_EVEN
import argparse
import json
import random
from unittest.mock import patch

def verify_rom(rtl, verbose=True):
    with localcontext() as ctx:
        ctx.prec = 70
        values = [int((Decimal(32768)/(1+(-(Decimal(i)/16-8)).exp())).to_integral_value(rounding=ROUND_HALF_EVEN)) for i in range(257)]
    assert values[128] == 16384 and values[0] == 11 and values[-1] == 32757
    assert all(x <= y for x,y in zip(values,values[1:]))
    assert max(y-x for x,y in zip(values,values[1:])) <= 512
    assert all(values[i]+values[256-i] == 32768 for i in range(257))
    mem = ''.join(f'{v:04x}\n' for v in values)
    case = '`ifndef SIGMOID_SAMPLE_SVH\n`define SIGMOID_SAMPLE_SVH\n'
    case += 'module sigmoid_sample(input logic [8:0] index, output logic [15:0] value);\n    always_comb begin\n    case(index)\n'
    case += ''.join(f"        {i}: value = 16'h{v:04x};\n" for i,v in enumerate(values))
    case += "        default: value = 16'h0000;\n    endcase\n    end\nendmodule\n`endif\n"
    for name,text in [('sigmoid_257.mem',mem),('sigmoid_lut.svh',case)]:
        path=rtl/name
        if path.read_text(encoding='utf-8')!=text:
            raise ValueError(f'Incorrect ROM: {path}')
    if verbose:
        print('SIGMOID_ROM_PASS: 257 samples, endpoints, monotonicity, adjacent_delta<=512, symmetry and RNE')

def validate_rom_rejections(rtl):
    """Check asset validation without configurable ROM behavior in the RTL."""
    originals={name:(rtl/name).read_text(encoding='utf-8')
               for name in ('sigmoid_257.mem','sigmoid_lut.svh')}
    for name,text in originals.items():
        def missing_asset(path, **kwargs):
            if path.name==name:
                raise FileNotFoundError(path)
            return originals[path.name]
        with patch.object(Path,'read_text',missing_asset):
            try:
                verify_rom(rtl,verbose=False)
            except FileNotFoundError:
                pass
            else:
                raise AssertionError(f'Missing ROM was accepted: {name}')
        if name.endswith('.mem'):
            values=text.splitlines()
            values[128]='0000'
            corrupt='\n'.join(values)+'\n'
        else:
            corrupt=text.replace("128: value = 16'h4000;",
                                 "128: value = 16'h0000;")
            assert corrupt!=text
        def corrupt_asset(path, **kwargs):
            return corrupt if path.name==name else originals[path.name]
        with patch.object(Path,'read_text',corrupt_asset):
            try:
                verify_rom(rtl,verbose=False)
            except ValueError:
                pass
            else:
                raise AssertionError(f'Incorrect ROM was accepted: {name}')
    print('ROM_VALIDATION_PASS: missing_assets=2 corrupt_assets=2')

def generate_host(outdir, block):
    ROOT=outdir
    ROOT.mkdir(exist_ok=True)
    rng=random.Random(240602528)
    commands=[]
    cases=0
    case_starts=[]
    group='Norm'
    def emit(op,a=0,b=0,c=0): commands.append(f'{op:x} {a:08x} {b&0xffffffff:08x} {c&0xffffffff:08x}\n')
    def wr(a,v): emit(1,a,v)
    def check(a,v,mask=0xffffffff): emit(2,a,v,mask)
    def begin():
        nonlocal cases
        case_starts.append((len(commands),group))
        cases+=1;emit(7,cases);emit(0)
    def rne(n,d):
        sign=-1 if n<0 else 1
        q,r=divmod(abs(n),d)
        return sign*(q+int(2*r>d or (2*r==d and q%2)))
    def shift(n,r): return rne(n,1<<r) if r>=0 else n<<(-r)
    def sat(n,w): return max(-(1<<(w-1)),min((1<<(w-1))-1,n))
    def pack(values,w):
        per=256//w
        return [sum((v&((1<<w)-1))<<(w*j) for j,v in enumerate(values[i:i+per])) for i in range(0,len(values),per)]
    def memory(region,base,values,w,read=False):
        for i,word in enumerate(pack(values,w)):
            for lane in range(8):
                (check if read else wr)(region+(base+i)*32+lane*4,(word>>(lane*32))&0xffffffff)
    def ws(i,base,n,fmt,f=0): wr(0x20000+16*i,(base<<24)|(n<<14)|(fmt<<12)|(f<<7))
    def mat(i,k,n,m=1,r=0,wb=0,bb=900,s32=False,dynamic=False,no_bias=False):
        value=(wb<<86)|(bb<<76)|(k<<66)|(n<<56)|(m<<32)|(r<<26)|(int(s32)<<25)|int(dynamic)|(int(no_bias)<<1)
        for j in range(3): wr(0x20100+i*16+j*4,(value>>(j*32))&0xffffffff)
    def program(instructions):
        for i,v in enumerate(instructions+[0x1e00]): wr(0x30000+4*i,v)
    def ins(op,dst,s1,s0): return (op<<9)|(dst<<6)|(s1<<3)|s0
    def run(error=0,overflow=None):
        wr(0x40000,1)
        emit(3,200000,2|(error<<3)|((overflow or 0)<<2),0xf if overflow is not None else 0xb)
    def norm_ref(x,eps=0,delta=1):
        s=sum(v*v for v in x);n=len(x)
        v=(s*(1<<32))//n+eps
        assert v<(1<<64)
        root=isqrt(v)
        nr=max(0,root.bit_length()-1-9) if s else 0
        nm=rne(1<<(32+nr),root) if s else 0
        z=[sat(shift(v*nm,nr),24) for v in x]
        d=max(delta,max(abs(v) for v in z))
        qr=max(r for r in range(48) if (127<<r)<=d*((1<<24)-1))
        qm=rne(127<<qr,d)
        q=[sat(shift(v*qm,qr),8) for v in z]
        return q,z,d,nm,nr,qm,qr
    def compose(d,m,r):
        for out_r in range(47,-1,-1):
            out_m=rne(d*m*(1<<out_r),8323072*(1<<r))
            if 0<out_m<(1<<24): return out_m,out_r
        raise ValueError('coefficient cannot be represented')

    # Every practical K and both sides of all packing boundaries.
    for k in [1,2,3,7,8,15,16,17,28,31,32,33,63,64,65,96,127,128,129,160,255,256,257,511,512]:
        begin()
        x=[rng.randrange(-32768,32768) for _ in range(k)]
        if k==1:x=[-32768]
        eps=37
        q,z,d,nm,nr,qm,qr=norm_ref(x,eps)
        ws(0,0,k,1,12);ws(1,64,k,0);wr(0x40014,eps)
        memory(0x10000,0,x,16)
        program([ins(7,1,0,0)]);run(overflow=0)
        memory(0x10000,64,q,8,True);memory(0x10000,128,z,32,True)
        check(0x40020,(qr<<24)|qm);check(0x40024,(nr<<24)|nm);check(0x40028,d)

    for x,eps,delta in [([0]*33,0,1),([-32768]*512,0,1),([1]+[0]*511,0,1),([32767]*512,0,0xffffff)]:
        begin();k=len(x);q,z,d,nm,nr,qm,qr=norm_ref(x,eps,delta)
        ws(0,0,k,1);ws(1,64,k,0);wr(0x4001c,delta)
        memory(0x10000,0,x,16);program([ins(7,1,0,0)]);run(overflow=0)
        memory(0x10000,64,q,8,True);check(0x40028,d)

    group='Ternary'
    # Static ternary weights vary in every 32-weight chunk; tests the truncated 6'd64 bug.
    for k in [1,3,28,32,33,64,96,128,129,160,256,257,384,385,512]:
        for s32,n in [(False,17),(True,9)]:
            begin();a=[rng.randrange(-128,128) for _ in range(k)]
            if k==512:a=[-128]*k
            weights=[[rng.choice([-1,0,1]) for _ in range(k)] for _ in range(n)]
            if k==512:weights[0]=[-1]*k
            biases=[rng.randrange(-100,100) for _ in range(n)]
            if k==512:biases[0]=0
            ws(0,0,k,0);ws(1,64,n,3 if s32 else 1)
            mat(0,k,n,3,2,s32=s32)
            memory(0x10000,0,a,8);memory(0,900,biases,32)
            for row,w in enumerate(weights):memory(0,row*((k+127)//128),[{-1:3,0:0,1:1}[v] for v in w],2)
            raw=[shift(sum(x*w for x,w in zip(a,row))*3,2)+b for row,b in zip(weights,biases)]
            expected=[sat(v,32 if s32 else 16) for v in raw]
            program([ins(8,1,0,0)]);run(overflow=int(expected!=raw))
            memory(0x10000,64,expected,32 if s32 else 16,True)

    # Every weight-row stride can end exactly at the parameter SRAM boundary.
    for k in [128,256,384,512]:
        n=9;stride=(k+127)//128;base=1024-n*stride
        a=[rng.randrange(-128,128) for _ in range(k)]
        weights=[[rng.choice([-1,0,1]) for _ in range(k)] for _ in range(n)]
        expected=[sum(x*w for x,w in zip(a,row)) for row in weights]
        for invalid in [False,True]:
            begin();ws(0,0,k,0);ws(1,64,n,3)
            mat(0,k,n,wb=base+int(invalid),s32=True,no_bias=True)
            memory(0x10000,0,a,8);memory(0x10000,64,[12345]*n,32)
            if not invalid:
                for row,w in enumerate(weights):
                    memory(0,base+row*stride,[{-1:3,0:0,1:1}[v] for v in w],2)
            program([ins(8,1,0,0)]);run(error=int(invalid),overflow=0)
            memory(0x10000,64,[12345]*n if invalid else expected,32,True)

    # Dynamic q scale must travel from NORM to each following BitLinear.
    for k in [3,28,33,128,512]:
        begin();x=[rng.randrange(-16000,16001) for _ in range(k)]
        q,z,d,*_=norm_ref(x)
        m,r=compose(d,4096,0)
        w=[rng.choice([-1,0,1]) for _ in range(k)]
        y=sat(shift(sum(a*b for a,b in zip(q,w))*m,r)+17,32)
        ws(0,0,k,1,12);ws(1,64,k,0);ws(2,96,1,3,12)
        mat(0,k,1,4096,0,s32=True,dynamic=True)
        memory(0x10000,0,x,16);memory(0,0,[{-1:3,0:0,1:1}[v] for v in w],2);memory(0,900,[17],32)
        program([ins(7,1,0,0),ins(8,2,0,1)]);run(overflow=0)
        memory(0x10000,96,[y],32,True)

    # Stateful descriptor checks, stale scale, bounds, no-bias and unsupported opcodes.
    begin();ws(0,0,32,0);ws(1,64,1,1);mat(0,32,1,no_bias=True)
    memory(0x10000,0,[1]*32,8);memory(0,0,[1]*32,2)
    program([ins(8,1,0,0)]);run(overflow=0);memory(0x10000,64,[32],16,True)
    group='Norm'
    for kind in range(12):
        begin();ws(0,0,32,1);ws(1,64,32,0)
        memory(0x10000,0,[123]*32,16)
        if kind==0:ws(0,0,0,1)
        elif kind==1:ws(0,0,513,1)
        elif kind==2:ws(1,64,31,0)
        elif kind==3:ws(0,0,32,0)
        elif kind==4:wr(0x40010,0) # scratch overlaps input
        elif kind==5:wr(0x40010,64) # scratch overlaps output
        elif kind==6:wr(0x40010,254)
        elif kind==7:wr(0x4001c,0)
        elif kind==8:wr(0x40014,0xffffffff);wr(0x40018,0xffffffff)
        elif kind==9:ws(0,255,32,1)
        elif kind==10:ws(0,0,32,1,25)
        program([ins(7,1,0,0)] if kind!=11 else [ins(5,1,0,0)])
        run(error=1)

    # A rejected dispatch must not expose overflow retained by the previous core run.
    begin();ws(0,0,33,1);ws(1,64,33,0)
    memory(0x10000,0,[123]*33,16);memory(0x10000,64,[91]*33,8)
    wr(0x40014,0xffffffff);wr(0x40018,0xffffffff)
    program([ins(7,1,0,0)]);run(error=1,overflow=1)
    ws(0,0,33,0);run(error=1,overflow=0)
    memory(0x10000,64,[91]*33,8,True)
    ws(0,0,33,1);wr(0x40014,0);wr(0x40018,0)
    run(overflow=0);memory(0x10000,64,norm_ref([123]*33)[0],8,True)

    # Abort NORM while its divider is active, then restart after reset. SRAM and
    # program contents survive; descriptor/control state is deliberately reloaded.
    begin();x=[rng.randrange(-16000,16001) for _ in range(33)]
    ws(0,0,33,1);ws(1,64,33,0);memory(0x10000,0,x,16)
    memory(0x10000,64,[91]*33,8);program([ins(7,1,0,0)])
    wr(0x40000,1);emit(8,5000)
    check(0x40000,2,0xf);memory(0x10000,64,[91]*33,8,True)
    ws(0,0,33,1);ws(1,64,33,0);run(overflow=0)
    memory(0x10000,64,norm_ref(x)[0],8,True)

    group='Rowwise'
    # Row-wise scaling including left shifts, ties, saturation, unsigned gates and tails.
    for op,af,bf,df,au,bu,du in [(1,4,4,2,0,0,0),(2,4,4,8,0,0,0),(3,1,1,8,0,0,0),
                                (3,12,15,12,0,1,0),(3,24,24,0,0,0,0),(2,15,15,15,1,1,1)]:
        for n in [1,3,16,17,28,33]:
            begin()
            a=[rng.randrange(32769) if au else rng.randrange(-32768,32768) for _ in range(n)]
            b=[rng.randrange(32769) if bu else rng.randrange(-32768,32768) for _ in range(n)]
            if n>2 and bu:b[0]=32768;b[1]=0
            raw=[shift((x+y if op==1 else x-y if op==2 else x*y),af+(bf if op==3 else 0)-df) for x,y in zip(a,b)]
            expected=[max(0,min(32768,x)) if du else sat(x,16) for x in raw]
            ws(0,0,n,2 if au else 1,af);ws(1,40,n,2 if bu else 1,bf);ws(2,80,n,2 if du else 1,df)
            memory(0x10000,0,a,16);memory(0x10000,40,b,16)
            program([ins(op,2,1,0)]);run(overflow=int(raw!=expected));memory(0x10000,80,expected,16,True)

    with localcontext() as ctx:
        ctx.prec=70
        lut=[int((Decimal(32768)/(1+(-(Decimal(i)/16-8)).exp())).to_integral_value(rounding=ROUND_HALF_EVEN)) for i in range(257)]
    for f in [0,1,4,8,12,15,20,24]:
        begin();x=[-32768,-32767,-1,0,1,32766,32767]+[rng.randrange(-32768,32768) for _ in range(26)]
        def sigmoid(v):
            grid=max(0,min(256<<24,(v<<(28-f))+(128<<24)))
            index,frac=divmod(grid,1<<24)
            return rne(lut[index]*(1<<24)+(lut[min(index+1,256)]-lut[index])*frac,1<<24)
        ws(0,0,len(x),1,f);ws(1,64,len(x),2,15);memory(0x10000,0,x,16)
        program([ins(6,1,0,0)]);run(overflow=0);memory(0x10000,64,[sigmoid(v) for v in x],16,True)

    # Fused recurrence has one rounding after both products (a pair of MULs is not equivalent).
    for n in [1,3,17,512]:
        begin();h=[rng.randrange(-32768,32768) for _ in range(n)];candidate=[rng.randrange(-32768,32768) for _ in range(n)]
        gate=[rng.randrange(32769) for _ in range(n)]
        h[0]=1;candidate[0]=1;gate[0]=16384 # separate RNE(0.5)+RNE(0.5) would incorrectly give zero
        if n>2:gate[1]=0;gate[2]=32768
        expected=[rne(f*a+(32768-f)*b,32768) for a,b,f in zip(h,candidate,gate)]
        ws(0,0,n,1,12);ws(1,40,n,2,15);ws(2,80,n,1,12)
        memory(0x10000,0,candidate,16);memory(0x10000,40,gate,16);memory(0x10000,80,h,16)
        program([ins(11,2,1,0)]);run(overflow=0);memory(0x10000,80,expected,16,True)
    begin();x=[-32768,-1,0,1,16384,32767];ws(0,0,len(x),1,4);ws(1,64,len(x),1,6)
    memory(0x10000,0,x,16);program([ins(12,1,0,0)]);run(overflow=1)
    memory(0x10000,64,[sat(max(v,0)*4,16) for v in x],16,True)

    group='Ternary'
    for kind in range(14):
        begin();ws(0,0,32,0);ws(1,64,1,1);mat(0,32,1,no_bias=True)
        memory(0x10000,0,[1]*32,8);memory(0,0,[1]*32,2);memory(0x10000,64,[12345],16)
        if kind==0:mat(0,0,1)
        elif kind==1:mat(0,513,1)
        elif kind==2:mat(0,32,0)
        elif kind==3:mat(0,32,1,r=48)
        elif kind==4:mat(0,32,1,s32=True)
        elif kind==5:ws(0,0,31,0)
        elif kind==6:ws(0,0,32,1)
        elif kind==7:ws(1,64,2,1)
        elif kind==8:mat(0,32,2,wb=1023);ws(1,64,2,1)
        elif kind==9:mat(0,32,9,bb=1023);ws(1,64,9,1)
        elif kind==10:ws(1,0,1,1)
        elif kind==11:mat(0,32,1,dynamic=True)
        elif kind==12:memory(0,0,[2]+[1]*31,2)
        elif kind==13:ws(0,255,64,0);mat(0,64,1)
        program([ins(8,1,0,0)]);run(error=1);check(0x10000+64*32,12345)

    # Missing/invalidated runtime scale is rejected; static scale after NORM is rejected.
    for kind in range(3):
        begin();ws(0,0,3,1);ws(1,64,3,0);ws(2,96,1,3);mat(0,3,1,s32=True,dynamic=kind!=0,no_bias=True)
        memory(0x10000,0,[2,4,6],16);memory(0,0,[1]*3,2)
        program([ins(7,1,0,0)]);run(overflow=0)
        if kind==1:wr(0x10000+64*32,0) # overwrite q data
        if kind==2:ws(1,64,3,0) # change descriptor
        program([ins(8,2,0,1)]);run(error=1)

    # Static scale must also reject a preconfigured descriptor alias of NORM q.
    # The last case begins exactly after q's extent and must remain legal.
    for alias_base,alias_len,invalid in [(64,33,True),(65,32,True),(63,64,True),(66,32,False)]:
        begin();ws(0,0,33,1);ws(1,64,33,0);ws(2,alias_base,alias_len,0);ws(3,96,1,3)
        mat(0,alias_len,1,s32=True,no_bias=True)
        memory(0x10000,0,[123]*33,16);memory(0x10000,96,[12345],32)
        if not invalid:memory(0x10000,alias_base,[1]*alias_len,8)
        memory(0,0,[1]*alias_len,2)
        program([ins(7,1,0,0),ins(8,3,0,2)]);run(error=int(invalid),overflow=0)
        memory(0x10000,96,[12345 if invalid else alias_len],32,True)

    group='Rowwise'
    for kind in range(8):
        begin();ws(0,0,17,1,4);ws(1,40,17,1,4);ws(2,80,17,1,4)
        memory(0x10000,0,[1]*17,16);memory(0x10000,40,[1]*17,16);memory(0x10000,80,[12345],16)
        op=1
        if kind==0:ws(1,40,17,0,4)
        elif kind==1:ws(1,40,17,1,5)
        elif kind==2:ws(2,1,17,1,4) # partial overlap
        elif kind==3:ws(2,255,17,1,4)
        elif kind==4:ws(0,0,513,1,4)
        elif kind==5:op=6;ws(2,80,17,2,14)
        elif kind==6:op=3;ws(1,40,17,2,15);memory(0x10000,40,[65535]*17,16)
        elif kind==7:op=11;ws(1,40,17,2,15);ws(2,80,17,1,5)
        program([ins(op,2,1,0)]);run(error=1);check(0x10000+80*32,12345)

    group='HostDecode'
    # Host decode must not alias out-of-range or unaligned writes onto valid memory.
    begin();wr(0,0x12345678);emit(6,0x8000,0);emit(6,1,0);check(0,0x12345678)
    wr(0x10000,0x87654321);emit(6,0x12000,0);check(0x10000,0x87654321)
    program([]);run(overflow=0)

    # Fetch all 512 PCs, then restart without resetting or reloading the program.
    begin();program([0]*511);run(overflow=0);check(0x40004,511)
    run(overflow=0);check(0x40004,511)
    # A final NOP must stop with an error instead of wrapping PC back to zero.
    begin()
    for i in range(512):wr(0x30000+4*i,0)
    run(error=1,overflow=0);check(0x40004,511)

    selected=[]
    groups={}
    for i,(start,case_group) in enumerate(case_starts):
        if block not in ('All','Host') and block!=case_group:
            continue
        end=case_starts[i+1][0] if i+1<len(case_starts) else len(commands)
        selected.extend(commands[start:end])
        groups[case_group]=groups.get(case_group,0)+1
    (ROOT/'host_vectors.txt').write_text(''.join(selected),encoding='ascii')
    return {'host_cases':sum(groups.values()),'host_commands':len(selected),'host_groups':groups}

def generate_sigmoid(outdir):
    root=outdir
    with localcontext() as ctx:
        ctx.prec=70
        lut=[int((Decimal(32768)/(1+(-(Decimal(i)/16-8)).exp())).to_integral_value(rounding=ROUND_HALF_EVEN)) for i in range(257)]
    with (root/'sigmoid_expected.mem').open('w',encoding='ascii') as out:
        for f in range(25):
            den=1<<f
            for raw in range(-32768,32768):
                numerator=max(0,min(256*den,raw*16+128*den))
                index,rem=divmod(numerator,den)
                y_num=lut[index]*den+(lut[min(256,index+1)]-lut[index])*rem
                y,r=divmod(y_num,den)
                y+=int(2*r>den or (2*r==den and y%2))
                out.write(f'{y:04x}\n')
    return {'sigmoid_cases':25*65536,'sigmoid_formats':list(range(25))}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rtl',type=Path,default=Path(__file__).resolve().parent.parent/'Verilog Source code')
    parser.add_argument('--block',default='All',choices=['All','Host','Norm','Ternary','Rowwise','Scalar','DivProfiles','Postscale','Sigmoid','Sram','Imem','Arithmetic','AccMul','AddSub','Mul'])
    parser.add_argument('--check',action='store_true',help='Verify the main sigmoid ROM without generating test vectors')
    parser.add_argument('--output',type=Path,help='Isolated server vector output directory')
    args=parser.parse_args()
    verify_rom(args.rtl)
    validate_rom_rejections(args.rtl)
    if not args.check:
        output=args.output or Path(__file__).resolve().parent/'sim'
        output.mkdir(parents=True,exist_ok=True)
        metadata={}
        if args.block in ('All','Host','Norm','Ternary','Rowwise'):
            metadata.update(generate_host(output,args.block))
        if args.block in ('All','Sigmoid'):
            metadata.update(generate_sigmoid(output))
        (output/'vectors.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
        print('REFERENCE_PASS '+json.dumps(metadata))
