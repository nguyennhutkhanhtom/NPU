"""Rebuild editable architecture diagrams from reviewed, hash-bound RTL facts.

No RTL or simulation inputs are written. Native XML is authoritative; previews
are drawn from the same geometry. See architecture_manifest.json for scope.
"""
from pathlib import Path
from hashlib import sha256
from collections import Counter
import sys, re, json, zipfile, html, math, base64, zlib, urllib.parse, heapq, textwrap, os
from types import SimpleNamespace
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/diagrams'
WORK=ROOT/'scratchpad/architecture_redesign'
WORK.mkdir(parents=True,exist_ok=True)
sys.path.insert(0,str(Path(__file__).parent))
hierarchy=SimpleNamespace(RTL=ROOT/'Verilog Source code')

def save(p,data):
    p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(data.rstrip()+'\n',encoding='utf-8',newline='\n')
def digest(p): return sha256(p.read_bytes()).hexdigest()
def model(d):
    m=d.find('mxGraphModel')
    return m if m is not None else ET.fromstring(urllib.parse.unquote(zlib.decompress(base64.b64decode(d.text),-15).decode()))
def clean(g):
    g=re.sub(r'%%\{init:.*?\}%%','',g,flags=re.S)
    return re.sub(r'^\s*(?:classDef|class |style |linkStyle).*$', '',g,flags=re.M).strip()
def snapshot():
    p=WORK/'original_diagrams.zip'
    if p.exists():return
    files=[ROOT/'rtl_hierarchy.drawio',*OUT.glob('*.drawio'),*OUT.glob('*.svg'),OUT/'README.md',
           ROOT/'tools/docs/diagram_catalog.json',ROOT/'TASK_STATE.md']
    for f in (ROOT/'docs').rglob('*.md'):
        if '```mermaid' in f.read_text(encoding='utf-8'):files.append(f)
    with zipfile.ZipFile(p,'x',zipfile.ZIP_DEFLATED) as z:
        for f in sorted(set(files)):
            if f.exists():z.write(f,f.relative_to(ROOT).as_posix())
    save(WORK/'original_hashes.json',json.dumps({f.relative_to(ROOT).as_posix():digest(f) for f in files if f.exists()},indent=2))

def style_reference():
    ref=ROOT/'reference/Ethos_U85_mini.drawio'; pages=ET.parse(ref).getroot().findall('diagram')
    cells=[c for d in pages for c in model(d).findall('.//mxCell')]
    def get(cid):return next(c.get('style') for c in cells if c.get('id')==cid)
    roles={r:get(cid) for r,cid in {'control':'00-5','interface':'00-7','buffer':'00-9','compute':'00-11','output':'00-13','platform':'00-15','title':'00-2','subtitle':'00-3','group':'01-7','edge':'00-32'}.items()}
    save(WORK/'style_audit.json',json.dumps({'reference':ref.relative_to(ROOT).as_posix(),'sha256':digest(ref),
       'pages_inspected':[d.get('name') for d in pages], 'templates':roles,
       'adaptations':'Orthogonal routed connectors; 12 px blocks, 11 px signal labels, 20 px titles; open arrowheads; square semantic-color blocks. Hierarchy uses native parent containment for instantiation; complete replica paths remain in XML metadata.'},indent=2))
    return roles

def parse_ports(body):
    start=body.index('(')
    if '#' in body[:start]: _,end=hierarchy.balanced(body,start); start=body.index('(',end)
    head,_=hierarchy.balanced(body,start)
    ports={};direction=None;kind='logic';packed='';signed=False
    for part in re.split(r',\s*(?![^\[]*\])',head):
        part=part.strip();m=re.match(r'(input|output|inout)\s+(.*)',part,re.S)
        if m:
            direction=m[1];part=m[2].strip();packed='';signed=False
            t=re.match(r'(?:(wire|reg)\s+)?(logic|wire|\w+::\w+)\s*(.*)',part,re.S)
            if t:kind=t[2];part=t[3].strip()
            if part.startswith('signed'):signed=True;part=part[6:].strip()
            if part.startswith('['):i=part.index(']');packed=part[:i+1];part=part[i+1:].strip()
        n=re.match(r'(\w+)\s*(.*)',part,re.S)
        if n and direction:ports[n[1]]={'direction':direction,'type':kind,'signed':signed,'packed':packed or 'scalar','unpacked':n[2].strip()}
    return ports

def manifest():
    global hierarchy
    sources={p.name:digest(p) for p in hierarchy.RTL.iterdir() if p.suffix in {'.sv','.svh','.mem','.v'}}
    cache=OUT/'architecture_manifest.json'
    if cache.exists():
        data=json.loads(cache.read_text())
        if data['source_hashes']==sources:return data
    import build_hierarchy as parsed_hierarchy
    hierarchy=parsed_hierarchy
    modules={}
    for name,m in hierarchy.MODULES.items():
        b=m['body'];modules[name]={'source':m['file'],'line':m['line'],'ports':parse_ports(b),
         'instance_templates':m['templates'],'clock_events':sorted(set(re.findall(r'@\((.*?)\)',b))),
         'states':re.findall(r'typedef\s+enum.*?\{(.*?)\}',b,re.S),
         'generate_loops':re.findall(r'for\s*\((.*?)\)\s*begin\s*:\s*(\w+)',b,re.S),
         'localparams':dict(re.findall(r'localparam\s+(?:int|bit|logic(?:\s*\[[^]]+\])?)\s+(\w+)\s*=\s*([^;]+);',b)),
         'signals':re.findall(r'^\s*(?:logic|reg|wire)\s+([^;]+);',b,re.M)}
        for t in m['templates']:
            if t['module'] in hierarchy.MODULES:
                child_ports=parse_ports(hierarchy.MODULES[t['module']]['body'])
                assert set(t['ports'])<=set(child_ports),(name,t['name'],set(t['ports'])-set(child_ports))
                t['port_directions']={p:child_ports[p]['direction'] for p in t['ports']}
    configs={x:{'instances':hierarchy.hierarchy(v)} for x,v in [('quartus',1),('portable',0)]}
    data={'date':'2026-10-08','source_hashes':sources,'modules':modules,'configurations':configs,
     'clock_domains':{'llm_soc':'One clk. Raw rst_n reaches u_reset; all resettable child instances use core_rst_n. Combinational children have no clock/reset. Memories do not reset stored contents.',
       'matmul_wrap':'CLOCK_50 connects directly to matmulfree.clk; SW[0] connects to rst_n. Legacy modules use the same clock. No CDC or clock-gating instance is present.'},
     'limits':['Fixed llm_soc expansion: ATTN_DIV_LANES=4, SIGMOID_LANES=4, PERF_COUNTERS=0, ENABLE_DEBUG_INDEX=0; both memory backends.',
       'Legacy instance templates and port maps are indexed; legacy parameterized hierarchy is not fully elaborated.',
       'Widths with parameter expressions remain symbolic unless explicitly resolved in a configured diagram.',
       'altsyncram is an external vendor primitive; internal implementation is not available in repository RTL.',
       'Historical software/demo flows are contextual, not RTL module connectivity.']}
    save(OUT/'architecture_manifest.json',json.dumps(data,indent=2))
    return data

# Each replacement is reviewed against current RTL, rather than copied from a
# historical diagram. Labels describe functional logic unless explicitly named
# as module instances. Data, control and instantiation are separate edge kinds.
LINEAR='''flowchart TB
 S["Matrix launch<br/>weight_base_i[14:0], chunks_i[3:0], rows_i[9:0]"] --> C["IDLE / RUN / DRAIN<br/>Memory and dot counters"]
 C --> Q["Two parameter-word credits<br/>request_q - words_consumed < 2"]
 Q -->|"parameter_req_o / address_o[14:0]"| P["Parent parameter port"]
 P -->|"parameter_valid_i / data_i[255:0]"| F["fifo_q[0:1]<br/>2 × 256-bit words"]
 F --> W["64-bit slice per chunk<br/>32 × 2-bit ternary codes"]
 X["Parent input cache<br/>32 × S24 selected by input_chunk_o"] --> R["x_q[0:31] / w_q[0:31]<br/>Registered operands / launch_q"]
 W --> R
 R --> D["u_dot (ternary_dot32)<br/>Four registered stages"]
 D -->|"valid_o / sum_o S30"| A["Ordered S39 accumulator_q<br/>Reset at each row boundary"]
 A --> B["result_q[0:3] + fault bits<br/>Four reserved row slots"]
 B -->|"result_valid_o / S39 accumulator_o / fault"| O["Parent result consumer"]
 O -.->|"result_ready_i"| B
 B -.->|"started_rows_q - consumed_rows_q < 4"| R
 D -.->|"reserved code 10"| C
 C --> Z["Cancel / fault drain<br/>Wait for accepted memory and dot responses"]
 Z --> V["done_o pulse; busy_o includes queued results<br/>ready_o requires IDLE and empty result queue"]'''
HEAD='''flowchart TB
 S["start_i / cancel_i"] --> C["Ordered 4096-row vocabulary stream<br/>Request / response / sum / retire counters"]
 C --> A["Scale read per eight rows<br/>23040 + row[11:3]"]
 C --> W["Four int8 weight reads per row<br/>{row[11:0], chunk[1:0]}"]
 A --> P["Parent parameter request mux"]
 W --> P
 P -->|"parameter_valid_i / data_i[255:0]"| R["Scale / weight response routing"]
 R --> K["scale_word_q[255:0]<br/>Eight U24 coefficients in 32-bit slots"]
 R -->|"operand_capture_o / input_chunk_o"| O["Parent operand registers<br/>Cached S24 inputs and returned int8 weights"]
 O --> M["Parent u_math<br/>math_issue_o on next edge"]
 M -->|"sum_valid_i / sum_i S61"| U["Four ordered sums per row<br/>S39 sum_acc_q"]
 U --> F["Eight reserved result slots<br/>result_q S39 / coefficient_q U24"]
 K --> F
 F -->|"result_valid_o / row_o U12 / coefficient_o / accumulator_o"| E["Parent tagged scale / RNE / selection"]
 E -.->|"result_ready_i"| F
 F -.->|"issued_rows_q - retire_row_q < 8"| W
 C --> D["Cancellation retains ownership<br/>Drain parameter_pending_q and math_pending_q"]
 E --> Z["done_o after final result pop<br/>Parent separately drains selection pipeline"]'''
ROW='''flowchart TB
 E["u_linear_engine<br/>One launch per matrix; four result slots"] -->|"linear_feed = result_valid AND result_ready"| I["scalar_a_q S39 / scalar_b_q S25<br/>Capture row tag [0]"]
 I --> P["Three u_scalar_* logic_mul instances<br/>scalar_partial_q[0:2] S48 · tag [1]"]
 P --> A["scalar_pair_q S56 + linear_scalar_hi_q S48<br/>Registered low/mid pair and aligned high · tag [2]"]
 A --> S["scalar_product_q S64<br/>Pair + high shifted 16 · tag [3]"]
 S --> R["scalar_round_q S64<br/>RNE shift 24 · tag [4]"]
 R --> F["scalar_packet_*<br/>Low24 + full-width clamp flags + group · tag [5]"]
 F --> C["Two scalar_cluster_* register sets<br/>Group routing · tag [6]"]
 C --> G["Eight scalar_group_q S24 registers<br/>S24 clamp · tag [7]"]
 G --> W["write_vector_q[767:0]<br/>Select lane with tagged row[4:0] · tag [8]"]
 W -->|"linear_write: row[4:0]=31 or final row"| V["u_vectors<br/>Full 32-lane bank write acceptance"]
 T["linear_pipe_valid_q[8:0]<br/>linear_pipe_row_q[0:8] U10"] -.-> I & P & A & S & R & F & C & G & W
 V --> D["Operator completion drain<br/>Engine empty + tags empty + v_write_busy clear"]'''
SAMPLING='''flowchart TB
 H["Head result handshake<br/>S39 sum + U24 coefficient + U12 row"] --> A["Shared scalar operands / partials / pair+high / sum<br/>head_pipe_row_q follows six valid stages"]
 A --> R["RNE24 S64 result<br/>At head tag [3]"]
 N["random_q[31:24] → u_gumbel_lookup<br/>u_noise_mul × temperature_q U8"] --> P["Capture noise_product_q S33<br/>Advance xorshift32 once per ordered row"]
 R --> S["sampled_score_q S64 · tag [4]<br/>Temperature=0: add zero; otherwise add RNE8 noise"]
 P --> S
 S --> C["sat_s32 + eligibility · tag [5]<br/>Exclude IDs 0/2; EOS=1 only after min_new"]
 C --> B["Strict greater-than update<br/>best_score_q / best_token_q<br/>Lowest eligible ID wins ties"]
 B --> O["Final row 4095 finishes head selection<br/>Output ID and token feedback owned by parent"]'''
SOC='''flowchart TB
 H["Host request / ACK<br/>host_addr / wdata / rdata: 32 bits"] <--> F["Registered H_IDLE / EXEC / READ / WAIT / DONE<br/>Prompt / config / output-token registers"]
 F -.-> C["Graph + 112-bit one-hot operator control<br/>Ownership / cancellation / completion drain"]
 F <--> P["u_parameters (llm_parameter_ram)<br/>24576 × 256 bits; host 32-bit lane access"]
 C -.-> M["Parent resource muxes<br/>Memory requests, operands and returned results"]
 M <--> P
 M <--> V["u_vectors (llm_bank_ram)<br/>96 × 768 bits; 32 × S24 lanes"]
 M <--> K["u_cache (llm_bank_ram)<br/>4096 × 768 bits; causal K/V"]
 M <--> O["Parent caches / payload registers<br/>Input 12 × 768; metadata / RoPE reuse tags"]
 M <--> L["u_linear_engine<br/>Own ternary_dot32; four queued row results"]
 M <--> E["u_head_engine / u_attention_engine<br/>Parent capture and shared SIMD issue"]
 M <--> A["u_math STREAMING=1<br/>32 S24 × S32; products S56 / sum S61"]
 M <--> S["Parent scalar / vector epilogues<br/>Tagged scale / RNE / clamp / pack"]
 S --> T["Greedy / Gumbel selection<br/>Output token buffer and feedback"]
 T --> F'''
ARITH='''flowchart TB
 C["llm_soc operand / phase routing"] --> D["u_div (div)<br/>U64 numerator / U32 denominator"]
 C --> Q["u_root (isqrt_u64)<br/>U64 radicand / U32 root"]
 C --> S["g_sigmoid[0:3].u_sig<br/>S16/F12 inputs / U16/F15 outputs"]
 C --> N["u_attention_normalize<br/>32 S56 accumulators / U32 denominator"]
 N -->|"shared numerator / denominator / batch_start"| D
 D -->|"shared busy / done / U64 quotient / U32 remainder"| N
 N --> P["g_divider[1:3].g_private.u_div<br/>Three private U64/U32 dividers"]
 P --> N
 N -->|"vector_o 768 bits / done_o"| C
 Q --> C
 S --> C'''
INFERENCE='''flowchart TB
 H["Host loads parameters / prompt / config<br/>START validates prompt + max_new ≤ 128"] --> E["G_EMBED<br/>Prompt or feedback token committed by parent"]
 E --> L["Four transformer layers<br/>G_ANORM through G_MADD"]
 L --> P{"More prompt positions?"}
 P -->|"yes: G_NEXT"| E
 P -->|"no"| N["G_FNORM → G_HEAD<br/>4096 vocabulary rows; RTL token selection"]
 N --> O["G_ADVANCE<br/>output_memory[generated_q] stores selected ID"]
 O --> D{"max_new / EOS=1 / position=127?"}
 D -->|"yes"| F["G_DONE → G_IDLE<br/>Host reads IDs and decodes text"]
 D -->|"no: selected token feedback"| E'''

def reviewed_graphs():
    inv=json.loads((ROOT/'scratchpad/diagram_inventory.json').read_text(encoding='utf-8'))['diagrams']
    replacements={('docs/source_guide/blocks/llm_linear_engine.sv.md',1):LINEAR,
      ('docs/source_guide/blocks/llm_head_engine.sv.md',1):HEAD,
      ('docs/source_guide/blocks/llm_soc.sv.md',1):SOC,
      ('docs/source_guide/blocks/llm_soc.sv.md',2):ROW,
      ('docs/source_guide/blocks/llm_soc.sv.md',3):SAMPLING,
      ('docs/source_guide/full_graph.md',1):SOC,
      ('docs/source_guide/full_graph.md',2):'''flowchart TB
 C["llm_soc controller"] -.-> L["u_linear_engine<br/>Own ternary_dot32"]
 C -.-> H["u_head_engine<br/>Eight reserved results"]
 C -.-> A["u_attention_engine<br/>Causal QK scores"]
 L <--> R["Parent memory / input-cache routing"]
 H <--> R
 A <--> R
 H -.-> O["Parent Q/K / head operand registers"]
 A -.-> O
 R --> O
 O --> M["u_math STREAMING=1<br/>32 lane products / dot reduction"]
 M -->|"math_sum S61 / math_sum_valid"| H
 M -->|"math_sum S61 / math_sum_valid"| A
 L --> P["Parent tagged scalar epilogue"]
 H --> P''',
      ('docs/source_guide/full_graph.md',3):ARITH,
      ('docs/design/full_rtl_language.md',1):INFERENCE,
      ('docs/history/full_rtl_development.md',1):INFERENCE,
      ('docs/history/full_rtl_development.md',2):None,
      ('docs/history/full_rtl_development.md',3):ROW,
      ('docs/history/reviews/rtl_change_review_v2.md',1):ROW}
    layer=clean(next(d['graph'] for d in inv if d['file']=='docs/design/full_rtl_language.md' and d['index']==2))
    replacements[('docs/history/full_rtl_development.md',2)]=layer
    result=[]
    for i,d in enumerate(inv):
        key=(d['file'],d['index']);g=replacements.get(key,clean(d['graph']))
        if 'acc_mul.sv.md' in d['file'] and d['index']==1:
            g=g.replace('Sign extension to ACC_W<br/>Zero-pad unused leaves','Leaf TERM_W values / zero padding').replace('Generated balanced binary adders<br/>LEAVES minus one adders','Balanced binary adders<br/>Level width = min(TERM_W + level, ACC_W)')
        if 'acc_mul.sv.md' in d['file'] and d['index']==2:
            g=g.replace('S14 total_sum','S14 total_sum → total_sum_q register')
        if 'llm_bank_ram.sv.md' in d['file']:
            g=g.replace('768-bit row after five edges','32 × WIDTH row<br/>Five edges at ROWS ≤ 4096; six above 4096')
        if 'llm_parameter_ram.sv.md' in d['file']:
            g=g.replace('256-bit row after five edges','256-bit row<br/>Five edges at DEPTH=24576; four at DEPTH ≤ 4096')
        if 'llm_pkg.sv.md' in d['file']:
            g=g.replace('Fixed graph and SRAM offsets','llm_pkg compile-time definitions<br/>Fixed graph and SRAM offsets').replace('Exponential LUT','llm_exp_sample combinational module').replace('Xorshift32 and Gumbel LUT','llm_random_next function<br/>llm_gumbel_sample combinational module')
        if 'pipelined_word_ram.sv.md' in d['file']:
            g='''flowchart TB
 R["rd_en / wr_en + addresses / write data"] --> B{"Elaboration backend"}
 B -->|"Quartus, ROWS > 4096"| T["g_ip_tiled.g_tile<br/>Local request FFs → quartus_word_ram"]
 B -->|"Quartus, ROWS ≤ 4096"| W["g_ip<br/>Request FFs → one whole-bank quartus_word_ram"]
 B -->|"Portable"| P["g_model.g_tile<br/>Local request FFs → sram_word_tile"]
 T --> G["Registered four-tile group responses<br/>Balanced padded response tree"]
 P --> H["Registered four-tile group responses<br/>Masked group OR reduction"]
 G --> O["rd_data output register<br/>rd_valid at edge 4 for >4 tiles"]
 H --> Q{"GROUPS = 1?"}
 W --> Q
 Q -->|"yes"| S["rd_data from response stage<br/>rd_valid at edge 3"]
 Q -->|"no"| O
 R -.-> V["write_pending_q → wr_valid<br/>Leaf commit at edge 2; no storage reset"]'''
        if 'ternary_mul.sv.md' in d['file'] and d['index']==2:
            g=g.replace('acc_mul S12 groups<br/>→ S14 total','Four u_group S12 → group_sum_q<br/>u_total S14 → total_sum_q')
        # Redraw shared control and numeric stages in separate lanes, with
        # concise labels. Native layout is computed afresh, never old geometry.
        scope='current-RTL functional architecture'
        if 'nanofable_hybrid' in d['file']:scope='historical software/application context; no RTL connectivity claim'
        elif '/legacy/' in d['file'] or any(x in d['file'] for x in ['matmul','norm.sv','norm_dispatch','rowwise','ternary_mul','descriptor','ins_mem','PC.sv','mem_mapping','regfile','sram_256','postscale']):scope='current legacy RTL; separate from llm_soc'
        elif '/history/' in d['file']:scope='current RTL replacement in a historical document; prose remains historical'
        source=Path(d['file']).name.removesuffix('.md')
        if not source.endswith('.sv'):source='matmulfree.sv' if '/legacy/' in d['file'] else 'llm_soc.sv'
        if 'llm_pkg' in d['file']:source='llm_pkg.sv'
        result.append({**d,'graph':g,'key':f'{i+1:02d}_{Path(d["file"]).stem}_{d["index"]}',
            'title':Path(d['file']).stem+(' — overview' if d['index']==1 else f' — detail {d["index"]-1}'),
            'scope':scope,'source':source,'kind':'functional'})
    return result

def hierarchy_graphs(man):
    pages=[]
    for config,configdata in man['configurations'].items():
        rs=configdata['instances'];by={r['path']:r for r in rs}
        # One page per distinct parent family/configuration, with generated
        # replicas aggregated but every covered path retained as XML metadata.
        for module in ['llm_soc','llm_parameter_ram','llm_bank_ram','llm_math','llm_linear_engine','llm_attention_engine','llm_attention_normalize','sigmoid','pipelined_word_ram','quartus_word_ram']:
            parents=[r for r in rs if r['module']==module]
            families={}
            for parent in parents:
                key=json.dumps(parent['parameters'],sort_keys=True)
                families.setdefault(key,[]).append(parent)
            for fi,ps in enumerate(families.values()):
                children=[r for r in rs if r['parent']==ps[0]['path']]
                if not children:continue
                groups={}
                for r in children:
                    key=(r['module'],json.dumps(r['parameters'],sort_keys=True))
                    groups.setdefault(key,[]).append(r)
                # llm_soc contains multiple same-type functional instances;
                # keep each except the four identical sigmoid lanes.
                if module=='llm_soc':
                    groups={}
                    for r in children:
                        k=(r['module'],'sigmoid') if r['module']=='sigmoid' else (r['module'],r['name'])
                        groups.setdefault(k,[]).append(r)
                g=['flowchart TB',f'P["{module}<br/>'+html.escape(', '.join(f'{k}={v}' for k,v in ps[0]['parameters'].items()))+'"]']
                coverage={'P':[p['path'] for p in ps]}
                for gi,gs in enumerate(groups.values()):
                    label=f'{gs[0]["name"]}'+(f' × {len(gs)}' if len(gs)>1 else '')+f'<br/>({gs[0]["module"]})'
                    if gs[0]['parameters']:label+='<br/>'+', '.join(f'{k}={v}' for k,v in gs[0]['parameters'].items())
                    if gs[0]['external']:label+='<br/>External vendor primitive'
                    g.append(f'P -.->|"instantiates'+(f' {len(gs)} replicas' if len(gs)>1 else '')+f'"| N{gi}["{html.escape(label).replace("&lt;br/&gt;","<br/>")}"]')
                    coverage[f'N{gi}']=[r['path'] for p in ps for r in rs if r['parent']==p['path'] and r['module']==gs[0]['module'] and r['parameters']==gs[0]['parameters'] and (module!='llm_soc' or r['name']==gs[0]['name'])]
                pages.append({'title':f'{config} — {module}'+(f' configuration {fi+1}' if len(families)>1 else ''),'graph':'\n'.join(g),
                   'key':f'h_{config}_{module}_{fi}','scope':'instantiation only; arrows do not represent signal flow',
                   'source':ps[0]['module_source'],'kind':'hierarchy','config':config,'coverage':coverage})
    return pages

def prepare():
    snapshot();style_reference();man=manifest();spec=Path(__file__).with_name('architecture_pages.json')
    if spec.exists():
        reviewed=json.loads(spec.read_text(encoding='utf-8'))
        assert reviewed['source_hashes']==man['source_hashes'],'RTL changed: review affected pages and rebind their source hashes before rebuilding.'
        ds=reviewed['pages']
    else:ds=reviewed_graphs()+hierarchy_graphs(man)
    save(WORK/'reviewed_graphs.json',json.dumps(ds,ensure_ascii=False,indent=2))
    print(json.dumps({'functional_pages':sum(d['kind']=='functional' for d in ds),'hierarchy_pages':sum(d['kind']=='hierarchy' for d in ds),'modules':len(man['modules']),'backup':str(WORK/'original_diagrams.zip')}))

def intersect(a,b,rect):
    x,y,w,h=rect;eps=0.01
    if abs(a[0]-b[0])<eps:
        return x+eps<a[0]<x+w-eps and max(min(a[1],b[1]),y+eps)<min(max(a[1],b[1]),y+h-eps)
    return y+eps<a[1]<y+h-eps and max(min(a[0],b[0]),x+eps)<min(max(a[0],b[0]),x+w-eps)
def overlaps(a,b):
    return a[0]<b[0]+b[2]-0.1 and b[0]<a[0]+a[2]-0.1 and a[1]<b[1]+b[3]-0.1 and b[1]<a[1]+a[3]-0.1
def rect(n,pad=0):return (n['x']-pad,n['y']-pad,n['width']+pad*2,n['height']+pad*2)
def simplify(ps):
    out=[]
    for p in ps:
        p=(round(p[0],2),round(p[1],2))
        if out and p==out[-1]:continue
        if len(out)>1 and ((out[-2][0]==out[-1][0]==p[0]) or (out[-2][1]==out[-1][1]==p[1])):out.pop()
        out.append(p)
    return out
def route(d):
    by={n['id']:n for n in d['nodes']};bounds=[rect(n,9) for n in d['nodes']]
    xs={15.,float(d['width']-15)};ys={100.,float(d['height']-60)}
    for x,y,w,h in bounds:
        xs.update([x-8,x+w+8]);ys.update([y-8,y+h+8])
    used=[];labels=[];notes=[]
    for e in d['edges']:
        s=by[e['source']];t=by[e['target']]
        sp=e['suggestedPoints'][0];tp=e['suggestedPoints'][-1]
        def anchor(n,p):
            cx=n['x']+n['width']/2;cy=n['y']+n['height']/2
            if abs(p['y']-n['y'])<1:return (min(n['x']+n['width']-20,max(n['x']+20,p['x'])),n['y']),(0,-1)
            if abs(p['y']-n['y']-n['height'])<1:return (min(n['x']+n['width']-20,max(n['x']+20,p['x'])),n['y']+n['height']),(0,1)
            return ((n['x'] if p['x']<cx else n['x']+n['width']),min(n['y']+n['height']-15,max(n['y']+15,p['y']))),(-1 if p['x']<cx else 1,0)
        a,ad=anchor(s,sp);b,bd=anchor(t,tp)
        start=(a[0]+ad[0]*18,a[1]+ad[1]*18);end=(b[0]+bd[0]*18,b[1]+bd[1]*18)
        xx=sorted(xs|{start[0],end[0]});yy=sorted(ys|{start[1],end[1]});si=(xx.index(start[0]),yy.index(start[1]));ti=(xx.index(end[0]),yy.index(end[1]))
        def valid_segment(p,q):return not any(intersect(p,q,r) for r in bounds)
        queue=[(0,0,*si,-1)];dist={(*si,-1):0};prev={};goal=None
        while queue:
            _,cost,xi,yi,di=heapq.heappop(queue);state=(xi,yi,di)
            if cost!=dist.get(state):continue
            if (xi,yi)==ti:goal=state;break
            p=(xx[xi],yy[yi])
            for nx,ny,nd in [(xi-1,yi,0),(xi+1,yi,0),(xi,yi-1,1),(xi,yi+1,1)]:
                if not(0<=nx<len(xx) and 0<=ny<len(yy)):continue
                q=(xx[nx],yy[ny])
                if not valid_segment(p,q):continue
                step=abs(p[0]-q[0])+abs(p[1]-q[1])+(25 if di not in {-1,nd} else 0)
                # Penalize crossings with previously routed connectors. Real
                # fanout endpoints may share a short stem without a junction.
                for u,v in used:
                    if nd==0 and u[0]==v[0] and min(p[0],q[0])<u[0]<max(p[0],q[0]) and min(u[1],v[1])<p[1]<max(u[1],v[1]):step+=45
                    if nd==1 and u[1]==v[1] and min(p[1],q[1])<u[1]<max(p[1],q[1]) and min(u[0],v[0])<p[0]<max(u[0],v[0]):step+=45
                key=(nx,ny,nd);nc=cost+step
                if nc<dist.get(key,float('inf')):
                    dist[key]=nc;prev[key]=state
                    heapq.heappush(queue,(nc+abs(q[0]-end[0])+abs(q[1]-end[1]),nc,nx,ny,nd))
        if goal is None:raise ValueError('No obstacle-free route: '+d['key']+' '+e['id'])
        pts=[];state=goal
        while state in prev:pts.append((xx[state[0]],yy[state[1]]));state=prev[state]
        pts.append(start);pts.reverse();e['points']=simplify([a,*pts,b]);used.extend(zip(e['points'],e['points'][1:]))
        e['anchors']={'exitX':(a[0]-s['x'])/s['width'],'exitY':(a[1]-s['y'])/s['height'],
                      'entryX':(b[0]-t['x'])/t['width'],'entryY':(b[1]-t['y'])/t['height']}
        if not e['label']:continue
        w=min(164,max(len(l) for l in e['lines'])*6+14);h=len(e['lines'])*14+10;found=None
        segs=sorted(zip(e['points'],e['points'][1:]),key=lambda pq:abs(pq[0][0]-pq[1][0])+abs(pq[0][1]-pq[1][1]),reverse=True)
        for p,q in segs:
            cx=(p[0]+q[0])/2;cy=(p[1]+q[1])/2
            options=[(cx-w/2,cy-h/2,w,h),(cx+8,cy-h/2,w,h),(cx-w-8,cy-h/2,w,h),(cx-w/2,cy-h-6,w,h)]
            for r in options:
                if r[0]<5 or r[1]<92 or r[0]+w>d['width']-5 or r[1]+h>d['height']-30:continue
                if any(overlaps(r,b) for b in bounds+labels):continue
                # A white label must not erase an unrelated connector.
                if any(intersect(u,v,r) for other in d['edges'] if other is not e and 'points' in other for u,v in zip(other['points'],other['points'][1:])):continue
                found=r;break
            if found:break
        if not found:
            # Rare crowded branches use an explicit signal key below the
            # drawing; metadata still stores the complete connection label.
            num=len(notes)+1;notes.append(f'{num}. {e["label"]}');e['lines']=[str(num)];w=20;h=20
            p,q=segs[0];found=((p[0]+q[0])/2-10,(p[1]+q[1])/2-10,w,h)
        e['labelRect']=found;labels.append(found)
    # Place labels only after all connectors are known; later routes must not
    # run underneath the white background of an earlier signal label.
    for e in d['edges']:
        if not e.get('labelRect'):continue
        old=e['labelRect'];labels.remove(old);w,h=old[2:];found=None
        segs=sorted(zip(e['points'],e['points'][1:]),key=lambda pq:abs(pq[0][0]-pq[1][0])+abs(pq[0][1]-pq[1][1]),reverse=True)
        candidates=[old]
        for p,q in segs:
            for f in [.5,.25,.75]:
                cx=p[0]+(q[0]-p[0])*f;cy=p[1]+(q[1]-p[1])*f
                candidates.extend([(cx-w/2,cy-h/2,w,h),(cx+8,cy-h/2,w,h),(cx-w-8,cy-h/2,w,h),(cx-w/2,cy-h-6,w,h),(cx-w/2,cy+6,w,h)])
        for r in candidates:
            if r[0]<5 or r[1]<92 or r[0]+w>d['width']-5 or r[1]+h>d['height']-30:continue
            if any(overlaps(r,b) for b in bounds+labels):continue
            if any(intersect(u,v,r) for f in d['edges'] if f is not e for u,v in zip(f['points'],f['points'][1:])):continue
            found=r;break
        if not found:raise ValueError('Signal label cannot fit without crossing a wire: '+d['key']+' '+e['id'])
        e['labelRect']=found;labels.append(found)
    d['notes']=notes
    if notes:d['height']+=sum(len(textwrap.wrap(n,130))*15+4 for n in notes)+24
    return d

def role(label,typ='',classes=()):
    for r in ['control','interface','buffer','compute','output','platform']:
        if r in classes:return r
    s=label.lower()
    if typ=='diamond' or any(x in s for x in ['control','counter','cancel','drain','fsm','valid / ready','eligibility','launch','request credit']):return 'control'
    if any(x in s for x in ['sram','memory array','u_parameters','u_vectors','u_cache','altsyncram','quartus_word_ram','sram_word_tile']):return 'platform'
    if any(x in s for x in ['host','port','interface','handshake','request / ack','input transaction','input handshake']):return 'interface'
    if any(x in s for x in ['fifo','result_q','cache','buffer','register','storage','_q','captured','packet']):return 'buffer'
    if any(x in s for x in ['output','done_o','result /','best token','y_raw','vector_o']):return 'output'
    return 'compute'

def subtitle(d):
    if d['kind']=='hierarchy':return d['scope']+' · containment = instantiation\nExact instance paths, port maps and parameter values are retained in architecture_manifest.json'
    src=d['source']
    if src=='llm_soc.sv':domain='clk; raw rst_n → u_reset → core_rst_n'
    elif src in {'acc_mul.sv','logic_mul.sv','mul.sv','postscale.sv','npu_pkg.sv','llm_pkg.sv'}:domain='Combinational logic / compile-time definitions; no private clock domain'
    elif src=='matmul_wrap.sv':domain='CLOCK_50 → clk; SW[0] → rst_n; no CDC'
    elif src in {'sram_word_tile.sv','banked_word_ram.sv','quartus_word_ram.sv'}:domain='clk; SRAM storage has no reset'
    else:domain='clk / rst_n at module boundary; see configured parent port map'
    if 'historical software' in d['scope']:domain='Software/application context; no RTL clock-domain claim'
    return d['scope']+'\nRTL: '+src+' · '+domain

def emit_page(d,styles):
    dia=ET.Element('diagram',{'id':d['key'],'name':d['title']})
    gm=ET.SubElement(dia,'mxGraphModel',{'dx':str(math.ceil(d['width'])),'dy':str(math.ceil(d['height'])),
       'grid':'1','gridSize':'10','page':'1','pageScale':'1','pageWidth':str(math.ceil(d['width'])),'pageHeight':str(math.ceil(d['height'])),'background':'#ffffff'})
    root=ET.SubElement(gm,'root');ET.SubElement(root,'mxCell',{'id':'0'});ET.SubElement(root,'mxCell',{'id':'1','parent':'0'})
    def vertex(cid,label,style,r,parent='1',**attrs):
        c=ET.SubElement(root,'mxCell',{'id':cid,'value':html.escape(label).replace('\n','<br/>'),'style':style,'vertex':'1','parent':parent,**attrs})
        ET.SubElement(c,'mxGeometry',{'x':str(round(r[0],2)),'y':str(round(r[1],2)),'width':str(round(r[2],2)),'height':str(round(r[3],2)),'as':'geometry'})
        return c
    vertex('title',d['title'],styles['title'],(30,20,d['width']-60,30))
    vertex('subtitle',subtitle(d),styles['subtitle'],(30,52,d['width']-60,42))
    groups={g['id']:g for g in d['groups']}
    for g in d['groups']:vertex('g_'+g['id'],g['label'],styles['group'],rect(g))
    for n in d['nodes']:
        r=rect(n);parent='1';kind=role(n['label'],n.get('type',''),n.get('classes',[]));style=styles[kind]+'fontSize=12;fontFamily=Arial;spacing=8;'
        if d['kind']=='hierarchy' and n['id']=='P':style=styles['group']+'fontSize=14;spacingLeft=14;spacingTop=10;';kind='group'
        elif d['kind']=='hierarchy':
            parent='n_P';p=next(x for x in d['nodes'] if x['id']=='P');r=(r[0]-p['x'],r[1]-p['y'],r[2],r[3])
        elif n.get('parent') in groups:
            gr=groups[n['parent']];parent='g_'+n['parent'];r=(r[0]-gr['x'],r[1]-gr['y'],r[2],r[3])
        n['role']=kind
        if n.get('type')=='diamond':style='rhombus;'+style
        attrs={'rtlSource':str(d['source']),'architectureKind':'functional logic' if d['kind']=='functional' else 'instantiated module'}
        if d['kind']=='hierarchy':attrs['rtlPaths']=json.dumps(d['coverage'][n['id']])
        vertex('n_'+n['id'],'\n'.join(n['lines']),style,r,parent,**attrs)
    for e in d['edges']:
        sty=styles['edge']+'edgeStyle=segmentEdgeStyle;fontSize=11;strokeColor=#444444;'
        if e['control']:sty+='dashed=1;'
        if e['bidirectional']:sty+='startArrow=open;startFill=0;'
        sty+=''.join(f'{k}={v:.5f};' for k,v in e['anchors'].items())+'exitDx=0;exitDy=0;entryDx=0;entryDy=0;'
        c=ET.SubElement(root,'mxCell',{'id':e['id'],'edge':'1','parent':'1','source':'n_'+e['source'],'target':'n_'+e['target'],
            'style':sty,'signalLabel':e['label'],'rtlSource':str(d['source']),'architectureKind':'control' if e['control'] else 'functional flow'})
        geo=ET.SubElement(c,'mxGeometry',{'relative':'1','as':'geometry'});arr=ET.SubElement(geo,'Array',{'as':'points'})
        for x,y in e['points'][1:-1]:ET.SubElement(arr,'mxPoint',{'x':str(x),'y':str(y)})
        if e.get('labelRect'):vertex('label_'+e['id'],'\n'.join(e['lines']),
            'text;html=1;whiteSpace=wrap;strokeColor=none;fillColor=#ffffff;align=center;verticalAlign=middle;fontSize=11;fontFamily=Arial;',e['labelRect'],labelFor=e['id'])
    y=d['height']-30
    if d.get('notes'):
        nh=sum(len(textwrap.wrap(n,130))*15+4 for n in d['notes'])+8
        vertex('signal_key','\n'.join(d['notes']),styles['subtitle'],(30,y-nh,d['width']-60,nh))
    vertex('legend','Red: control   ·   Yellow: interface   ·   Gray: registers / buffers   ·   Blue: compute / output   ·   Purple: memory / technology',styles['subtitle'],(30,y,d['width']-60,22))
    return dia

def preview(d,styles):
    w=math.ceil(d['width']);h=math.ceil(d['height']);s=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">',
      '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto-start-reverse"><path d="M1 1 L7 4 L1 7" fill="none" stroke="#444444"/></marker></defs>',f'<rect width="{w}" height="{h}" fill="white"/>']
    def text(lines,x,y,size=12,anchor='middle',color='#111111',bold=False):
        for i,l in enumerate(lines):s.append(f'<text x="{x:.2f}" y="{y+i*(size+5):.2f}" font-family="Arial" font-size="{size}" text-anchor="{anchor}" fill="{color}"'+(' font-weight="bold"' if bold else '')+'>'+html.escape(l)+'</text>')
    text([d['title']],30,42,20,'start',bold=True)
    text(subtitle(d).splitlines(),30,66,12,'start','#666666')
    for g in d['groups']:
        s.append(f'<rect x="{g["x"]}" y="{g["y"]}" width="{g["width"]}" height="{g["height"]}" fill="none" stroke="#999999" stroke-dasharray="5 4"/>')
        text([g['label']],g['x']+8,g['y']+17,12,'start','#666666',True)
    # Parent containers precede connectors and children in both preview/XML.
    if d['kind']=='hierarchy':
        p=next(n for n in d['nodes'] if n['id']=='P');s.append(f'<rect x="{p["x"]}" y="{p["y"]}" width="{p["width"]}" height="{p["height"]}" fill="none" stroke="#999999" stroke-dasharray="5 4"/>');text(p['lines'],p['x']+14,p['y']+24,14,'start','#666666',True)
    for e in d['edges']:
        pts=' '.join(f'{x},{y}' for x,y in e['points']);s.append(f'<polyline points="{pts}" fill="none" stroke="#444444" marker-end="url(#arrow)"'+(' marker-start="url(#arrow)"' if e['bidirectional'] else '')+(' stroke-dasharray="5 4"' if e['control'] else '')+'/>')
    for n in d['nodes']:
        if n['role']=='group':continue
        style=styles[n['role']];fill=re.search(r'fillColor=([^;]+)',style)[1];stroke=re.search(r'strokeColor=([^;]+)',style)[1]
        x,y,w,h=rect(n)
        if n.get('type')=='diamond':s.append(f'<polygon points="{x+w/2},{y} {x+w},{y+h/2} {x+w/2},{y+h} {x},{y+h/2}" fill="{fill}" stroke="{stroke}"/>')
        else:s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{fill}" stroke="{stroke}"/>')
        text(n['lines'],x+w/2,y+h/2-(len(n['lines'])-1)*8.5+4,12)
    for e in d['edges']:
        if not e.get('labelRect'):continue
        x,y,w,h=e['labelRect'];s.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white"/>');text(e['lines'],x+w/2,y+h/2-(len(e['lines'])-1)*7+4,11)
    if d.get('notes'):
        lines=[l for n in d['notes'] for l in textwrap.wrap(n,130)];text(lines,30,d['height']-40-len(lines)*17,12,'start','#666666')
    text(['Red: control · Yellow: interface · Gray: registers / buffers · Blue: compute / output · Purple: memory / technology'],30,d['height']-14,11,'start','#666666')
    return '\n'.join(s+['</svg>'])

def emit():
    styles=style_reference();man=json.loads((OUT/'architecture_manifest.json').read_text());ds=json.loads((WORK/'layout.json').read_text(encoding='utf-8'))
    for name,expected in man['source_hashes'].items():assert digest(hierarchy.RTL/name)==expected,'Source changed during redesign: '+name
    groups={'architecture.drawio':[d for d in ds if d['kind']=='functional'],
       '../../rtl_hierarchy.drawio':[d for d in ds if d.get('config')=='quartus'],
       'rtl_hierarchy_portable.drawio':[d for d in ds if d.get('config')=='portable']}
    index=[];routes=[]
    for file,pages in groups.items():
        mx=ET.Element('mxfile',{'host':'app.diagrams.net','version':'24.7.17','type':'device'})
        for d in pages:
            if d['kind']=='functional':route(d)
            mx.append(emit_page(d,styles));save(OUT/'previews'/f'{d["key"]}.svg',preview(d,styles));routes.append(d)
            index.append({k:d[k] for k in ['key','title','source','scope','kind']}|{'drawio':file,'preview':'previews/'+d['key']+'.svg','markdown':d.get('file'),'ordinal':d.get('index')})
        ET.indent(mx);save(OUT/file,ET.tostring(mx,encoding='unicode'))
    save(WORK/'routed.json',json.dumps(routes,ensure_ascii=False,indent=2))
    save(OUT/'architecture_index.json',json.dumps(index,ensure_ascii=False,indent=2))
    # Replace each old inline drawing with the new native source's preview.
    byfile={}
    for d in ds:
        if d['kind']=='functional':byfile.setdefault(d['file'],[]).append(d)
    for file,pages in byfile.items():
        p=ROOT/file;original=p.read_text(encoding='utf-8');i=0
        def replace(m):
            nonlocal i
            d=pages[i];i+=1
            rel=os.path.relpath(OUT,p.parent).replace('\\','/')
            historical='Current RTL replacement; surrounding discussion is historical.\n\n' if '/history/' in file else ''
            return historical+f'![{d["title"]}]({rel}/previews/{d["key"]}.svg)\n\n[Editable draw.io — {d["title"]}]({rel}/architecture.drawio) · Page `{d["key"]}`.'
        changed=re.sub(r'```mermaid\s*\n.*?\n```',replace,original,flags=re.S)
        if i:assert i==len(pages),(file,i,len(pages));save(p,changed)
        else:assert all(d['key'] in original for d in pages),(file,'missing diagram embed')
    # Refresh compatibility preview filenames already linked by documentation.
    for prefix,config in [('rtl_hierarchy','quartus'),('rtl_hierarchy_portable','portable')]:
        pages=groups['../../rtl_hierarchy.drawio' if config=='quartus' else 'rtl_hierarchy_portable.drawio']
        for old in OUT.glob(prefix+'_[0-9][0-9]_*.svg'):
            num=int(old.name[len(prefix)+1:len(prefix)+3]);page=pages[min(num,len(pages)-1)];save(old,preview(page,styles))
    print(json.dumps({'files':len(groups),'pages':len(index),'previews':len(index),'updated_markdown':len(byfile)}))

if __name__=='__main__':
    if sys.argv[-1]=='prepare':prepare()
    elif sys.argv[-1]=='emit':emit()
