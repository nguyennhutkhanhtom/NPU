"""Refresh source-grounded documentation; never write RTL or hardware evidence."""
from pathlib import Path
from hashlib import sha256
from difflib import SequenceMatcher
from urllib.parse import quote
import html, json, re, zipfile

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / 'Verilog Source code'
GUIDE = ROOT / 'docs/source_guide'
AUDIT = ROOT / 'docs/verification/diagrams_20261006'
CATALOG = json.loads((Path(__file__).with_name('diagram_catalog.json')).read_text())
INIT = '%%{init: ' + json.dumps({'theme':'base','fontFamily':'Arial, sans-serif',
    'themeVariables':{'fontSize':'24px','primaryColor':'#ffffff','primaryTextColor':'#000000',
    'primaryBorderColor':'#000000','secondaryColor':'#ffffff','tertiaryColor':'#ffffff',
    'lineColor':'#000000','textColor':'#000000','mainBkg':'#ffffff','nodeBorder':'#000000',
    'clusterBkg':'#ffffff','clusterBorder':'#000000','edgeLabelBackground':'#ffffff'},
    'flowchart':{'htmlLabels':True,'useMaxWidth':False,'nodeSpacing':32,'rankSpacing':48,
    'curve':'linear','subGraphTitleMargin':{'top':16,'bottom':30}}},separators=(',',':')) + '}%%'

def save(p,s): p.write_text(s.rstrip()+'\n',encoding='utf-8',newline='\n')

def style(g):
    g = re.sub(r'%%\{init:.*?\}%%\s*','',g,flags=re.S).strip()
    # Styling is inline in every source block, so previews and Markdown agree.
    return INIT+'\n'+g+'\n    classDef default fill:white,stroke:black,color:black,font-size:24px;\n    linkStyle default stroke:black,color:black;'

def snapshot():
    AUDIT.mkdir(parents=True,exist_ok=True)
    p = AUDIT / 'before.zip'
    if p.exists(): return
    files = [ROOT/'README.md', *sorted((ROOT/'docs').rglob('*.md')),
             GUIDE/'source_manifest.json',GUIDE/'diagram_validation.json',GUIDE/'validation.json']
    with zipfile.ZipFile(p,'x',zipfile.ZIP_DEFLATED) as z:
        for f in files:
            if f.exists(): z.write(f,f.relative_to(ROOT).as_posix())
    save(AUDIT/'before.json',json.dumps({'archive_sha256':sha256(p.read_bytes()).hexdigest(),
        'rtl':{f.name:sha256(f.read_bytes()).hexdigest() for f in sorted(RTL.iterdir()) if f.suffix in {'.sv','.svh','.v','.mem'}},
        'documents':{f.relative_to(ROOT).as_posix():sha256(f.read_bytes()).hexdigest() for f in files if f.exists()}},indent=2))

REBUILD = {
 'llm_soc.sv':[(1,'Top interface, reset and graph/operator declarations'),(301,'Scalar products, lookup instances and host frontend'),
   (480,'SRAM, engine and shared arithmetic port maps'),(580,'Optional performance counters'),
   (620,'Metadata addresses and graph sequencing'),(690,'Prompt selection and token feedback'),
   (749,'SIMD operand capture and registered numeric stages'),(859,'Scalar completion distribution'),
   (890,'Input-cache payload and reuse contracts'),(930,'Operator control, validity and cancellation')],
 'norm.sv':[(1,'Legacy normalization interface and controller'),(100,'Coefficient, multiplier and numeric datapaths'),
            (220,'Workspace requests and pass sequencing')],
 'banked_word_ram.sv':[(1,'Portable bank interface and tile geometry'),(16,'Generated SRAM leaves and read tags'),(30,'Read reduction network')],
 'pipelined_word_ram.sv':[(1,'Interface, geometry and validity'),(33,'Deep Quartus tiled memory branch'),
                          (92,'Whole-bank Quartus memory branch'),(117,'Portable tiled SRAM branch')],
 'llm_math.sv':[(1,'Interface and operand widths'),(19,'Generated structural byte multipliers'),
               (28,'Streaming acceptance and response validity'),(42,'Registered product and reduction stages')],
 'llm_linear_engine.sv':[(1,'Interface and credit-window state'),(30,'Requests and ternary pipeline wiring'),
                       (42,'Fault, cancellation and drain control'),(74,'FIFO payload and operand registers')],
 'llm_head_engine.sv':[(1,'Parent-facing ports and counters'),(19,'Ordered request/capture and response completion'),(42,'Vocabulary and accumulator registers')],
 'llm_attention_engine.sv':[(1,'Interface and score storage'),(29,'Scale multiplier and causal requests'),(36,'Validity and completion'),(56,'Score rounding, array writes and maximum')],
 'llm_attention_normalize.sv':[(1,'Interface, batching and payload'),(30,'Ready, cancellation and batch control'),(55,'Conditional shared/private dividers'),(89,'Lane output registers')],
 'ternary_dot32.sv':[(1,'Interface and validity pipeline'),(26,'Ternary decode with extended sign'),(39,'Balanced addition and registered stages')],
 'isqrt_u64.sv':[(1,'Interface and working registers'),(15,'Trial subtraction and next arithmetic state'),(30,'Start, iteration and completion control')],
 'sram_word_tile.sv':[(1,'Replaceable memory interface'),(10,'Synchronous read and write storage behavior')]
}

def refresh_sources():
    old = json.loads((GUIDE/'source_manifest.json').read_text(encoding='utf-8'))
    entries = {e['file']:e for e in old['files']}
    for src in sorted(RTL.iterdir()):
        if src.suffix not in {'.sv','.v','.svh','.mem'}: continue
        raw=src.read_bytes(); lines=raw.decode('utf-8-sig').splitlines(); digest=sha256(raw).hexdigest()
        p=GUIDE/'blocks'/f'{src.name}.md'; link='../../../Verilog%20Source%20code/'+quote(src.name)
        olddoc=p.read_text(encoding='utf-8') if p.exists() else ''
        entry=entries.get(src.name,{}).copy()
        if src.name in REBUILD:
            cfg=CATALOG.get(src.name)
            if not cfg:
                cfg={'summary':'Legacy three-pass RMS normalization and quantization. Two shared structural multipliers, one divider and the separately defined isqrt_u64 serve the explicit pass controller. Workspace scratch and final quantized values are packed in 256-bit words.',
                     'graph':re.findall(r'```mermaid\n(.*?)\n```',olddoc,re.S)[0]}
            detail=re.findall(r'```mermaid\n(.*?)\n```',olddoc,re.S)[1:]
            # The square-root module moved out of norm.sv; document it with its own source.
            if src.name=='norm.sv': detail=detail[1:]
            doc=f'# {src.name}\n\n[Documentation](../../README.md) → [Source guide](../full_graph.md) → [RTL index](README.md)\n\n**Source:** [{src.name}](<{link}>). **Số dòng:** {len(lines)}. **SHA-256:** `{digest}`.\n\n## Khối này làm gì?\n\n{cfg["summary"]}\n\n## Sơ đồ kiến trúc\n\n```mermaid\n{cfg["graph"]}\n```\n\n## Cách hoạt động chi tiết\n\n{cfg["summary"]}\n\n'
            for i,g in enumerate(detail,1):doc+=f'### Datapath detail {i}\n\n```mermaid\n{g}\n```\n\n'
            doc+='## Các nhóm logic trong source\n\n'
            groups=REBUILD[src.name]
            for i,(start,title) in enumerate(groups):
                end=groups[i+1][0]-1 if i+1<len(groups) else len(lines)
                assert 1<=start<=end<=len(lines),(src.name,start,end)
                excerpt='\n'.join(lines[start-1:end])
                doc+=f'### [Dòng {start}–{end}: {title}](<{link}#L{start}>)\n\n<!-- source-range:{start}:{end} -->\n```systemverilog\n{excerpt}\n```\n\n'
            entry['groups']=len(groups)
        else:
            doc=olddoc
            assert doc,src.name
            # Update unchanged-source diagrams and explanations selectively.
            if src.name in CATALOG:
                cfg=CATALOG[src.name]
                doc=re.sub(r'```mermaid\n.*?\n```',lambda m:'```mermaid\n'+cfg['graph']+'\n```',doc,count=1,flags=re.S)
                doc=re.sub(r'(## Khối này làm gì\?\n\n).*?(?=\n## )',lambda m:m[1]+cfg['summary']+'\n',doc,count=1,flags=re.S)
            doc=re.sub(r'\*\*Số dòng:\*\* \d+\. \*\*SHA-256:\*\* `[a-f0-9]+`',f'**Số dòng:** {len(lines)}. **SHA-256:** `{digest}`',doc)
            assert entry.get('sha256')==digest, f'Unreviewed source change: {src.name}'
        entry.update(file=src.name,path=f'Verilog Source code/{src.name}',document=f'blocks/{src.name}.md',sha256=digest,lines=len(lines))
        entries[src.name]=entry
        save(p,doc)
    old.update(snapshot_date='2026-10-06',files=list(entries.values()))
    save(GUIDE/'source_manifest.json',json.dumps(old,ensure_ascii=False,indent=2))
    idx=GUIDE/'blocks/README.md'; doc=idx.read_text(encoding='utf-8')
    doc=doc.replace('Danh mục RTL và chú giải snapshot','Danh mục RTL và chú giải hiện tại')
    doc=re.sub(r'Cột \*\*Source hiện tại\*\*.*?(?=\n## Toàn bộ)',
        'Cột **Source hiện tại** dẫn tới RTL đang compile. **Chú giải hiện tại** cung cấp sơ đồ và code excerpts khớp source_manifest.json ngày 06/10/2026. Hash xác nhận source; regression và timing có evidence riêng.\n',doc,flags=re.S)
    doc=doc.replace('Chú giải snapshot','Chú giải hiện tại').replace('Xem snapshot','Xem chú giải').replace('Snapshot cũ','Khớp hash')
    for name in REBUILD:
        doc=re.sub(r'^(\| \['+re.escape(name)+r'\].*?)\| Chưa có \| Chưa có snapshot \|$',
                   lambda m:m[1]+f'| [Xem chú giải]({name}.md) | Khớp hash |',doc,flags=re.M)
    doc=re.sub(r'Các sơ đồ, source_manifest và code\nexcerpts.*?\.',
        'Sơ đồ, source_manifest và code excerpts đã được đối chiếu lại với source hiện tại.',doc,flags=re.S)
    save(idx,doc)

def update_all_styles():
    replacements={
      '32 × signed S9 ở ternary core':'signed terms in the legacy ternary core',
      'Điều khiển và cấu hình':'Control and configuration','Các engine tính toán':'Compute engines',
      'Ctrl/desc: 2 cạnh · SRAM/imem: 4 cạnh':'Ctrl/desc: 2 edges · SRAM/imem: 4 edges',
      'Opcode decode + điều phối engine':'Opcode decode and engine scheduling',
      'Scale tĩnh hoặc ghép scale động':'Static scale or dynamic composition',
      '32 lane chọn dấu/zero':'32 sign/zero selection lanes','sigmoid: ROM + nội suy':'sigmoid: ROM and interpolation',
      'Chọn request/write theo active_unit':'Select requests/writes using active_unit',
      'Phân phối read data/valid tới active engine':'Route read data/valid to the active engine',
      'Nạp/đọc chương trình, descriptor, control/status':'Load/read program, descriptors and control/status',
      'Nạp/đọc; ready':'Load/read; ready','Host: nạp model/input':'Host loads model and input',
      'Đọc logits và argmax/tokenization':'Read logits; argmax and tokenization',
      'NORM + QUANT số nguyên':'Integer NORM and QUANT','Ảnh 16×16, hàng ảnh hoặc ký tự':'Image 16x16, image row or character',
      'Host: checkpoint đã train và exporter':'Host: pretrained checkpoint and exporter',
      'Packed weights và scale số nguyên':'Packed weights and integer scales','Rescale, ReLU / SIG / SiLU':'Rescale / ReLU / SIG / SiLU',
      'Chọn nhãn hoặc ký tự có điểm cao nhất':'Host selects highest-scoring label or character',
      'Checkpoint và tokenizer đã pin':'Pinned checkpoint and tokenizer','CPU: toàn graph NanoFable':'CPU executes the NanoFable graph',
      'lặp lại và so token':'Repeat and compare tokens','28 linear · 6 activation mỗi tensor':'28 linears; six activations per tensor',
      'Host nạp từng tensor':'Host loads each tensor','168 lượt · 33.792 đầu ra':'168 runs; 33792 outputs',
      'so bit-exact và flags':'Compare bit-exact outputs and flags','Host write ưu tiên · mask 8 lane':'Host write priority; eight-lane mask',
      'Host hoặc compute':'Host or compute','8 bank RAM, mỗi bank DEPTH × 32 bit':'Eight RAM banks; DEPTH x 32 bits per bank',
      'Không reset nội dung':'Storage has no reset','Register dữ liệu không asynchronous reset':'Data register has no asynchronous reset',
      'Kiểm tra request hiện tại':'Current-request check','Hai bộ tag khớp row + lane':'Both tags match row and lane',
      'Host read đang được giữ':'Host holds the read request','write_mask mỗi bank':'write_mask per bank',
      'rd_valid khi response là compute':'rd_valid for compute-owned response','Current read + hai tag khớp':'Current read and both tags match',
      'DEPTH word mỗi bank':'DEPTH words per bank','rd_valid: response không phải host':'rd_valid: compute-owned response',
      'Một ROM lookup dùng chung':'One shared ROM lookup','index hoặc bounded index+1':'index or bounded index+1',
      'Pipeline nội suy':'Interpolation pipeline','RNE theo parity toàn tổng':'RNE uses full integer-sum parity',
      'Chọn +q / 0 / −q · mask ngoài K':'Select +q / zero / minus q; mask outside K',
      'Cây cộng tổ hợp 32 term S9':'Four 8-input S12 trees and one 4-input S14 tree',
      'Bộ cộng tích lũy + accumulator S18':'S18 accumulation adder and register','S16 hoặc S32':'S16 or S32',
      'Hai tag':'Both tags','Ba cổng đọc descriptor tổ hợp':'Three combinational workspace descriptor ports',
      'Một cổng đọc descriptor tổ hợp':'One combinational matrix descriptor port','Enable riêng từng entry / word 32 bit':'Independent entry / 32-bit word enable',
      'reset đủ 1.024 FF':'Reset all 1024 FFs','Một datapath số học dùng lặp':'One reused arithmetic datapath',
      'Điều khiển cấp top trong matmulfree':'Top-level matmulfree control',
      'npu_pkg — định nghĩa dùng khi elaboration, không phải instance phần cứng':'npu_pkg: elaboration definitions; no module instance',
      'Hằng số độ rộng / dung lượng':'Width and capacity constants','Kiểu tensor + descriptor':'Tensor and descriptor types',
      'Hàm số học tổ hợp':'Pure combinational arithmetic helpers','Hàm kiểm tra descriptor':'Pure descriptor checks',
      'Kích thước RTL':'RTL geometry','Kiểu cổng và metadata':'Port and metadata types',
      'Logic triển khai tại nơi gọi':'Combinational logic at call sites','Logic kiểm tra tại nơi gọi':'Checks at call sites',
      '32 PE → reduction → ACC18':'32 selectors; S12/S14 reductions; S18 accumulator',
      'Tái dùng tối đa 4 chunk':'Reuse for up to four chunks','q S8 và scratch':'q S8 and scratch'
    }
    for p in [ROOT/'README.md',*sorted((ROOT/'docs').rglob('*.md'))]:
        doc=p.read_text(encoding='utf-8')
        if '```mermaid' not in doc: continue
        def convert(m):
            g=m[1]
            for a,b in replacements.items():g=g.replace(a,b)
            # Remove old style lines before applying the single shared convention.
            g=re.sub(r'^\s*(classDef default|linkStyle default).*\n?','',g,flags=re.M)
            return '```mermaid\n'+style(g)+'\n```'
        doc=re.sub(r'```mermaid\r?\n(.*?)\r?\n```',convert,doc,flags=re.S)
        save(p,doc)

if __name__=='__main__':
    snapshot()
    refresh_sources()
    update_all_styles()
    print('SOURCE_DIAGRAM_REFRESH: current source excerpts and black/white 18 pt diagram styles written')
