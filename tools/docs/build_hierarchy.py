"""Expand the reviewed llm_soc hierarchy and emit editable draw.io plus SVG previews.

Expansion rules below describe this fixed configuration, not a general SV elaborator.
Each rule is checked against parsed source instance templates and port maps.
"""
from pathlib import Path
from hashlib import sha256
from collections import Counter, defaultdict
import html, json, re, textwrap
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
RTL=ROOT/'Verilog Source code'
OUT=ROOT/'docs/diagrams'
CATALOG=json.loads(Path(__file__).with_name('diagram_catalog.json').read_text())
DESC={
 'reset_release':'Asynchronous reset assertion; internal release after two rising edges. clk/rst_n -> core_rst_n.',
 'logic_mul':'Combinational bit products and carry-save reduction; a/b -> product. No runtime multiply operator.',
 'llm_exp_sample':'Combinational exp table: index U9 -> value U25; default zero outside the table.',
 'llm_gumbel_sample':'Combinational Gumbel table: index U8 -> signed value S24.',
 'sigmoid_sample':'Combinational 257-entry sigmoid table: index U9 -> value U16.',
 'llm_parameter_ram':'Eight 32-bit lanes; compute row read / valid, host lane read and post-commit write acknowledgement.',
 'llm_bank_ram':'Thirty-two S24 banks; rd_en/rd_addr -> rd_data/rd_valid; masked writes and wr_busy drain.',
 'pipelined_word_ram':'Registered SRAM adapter; rd_en/address -> data/valid; wr_en/address/data -> wr_valid after commit.',
 'quartus_word_ram':'Replaceable Quartus memory leaf; common-clock 1R/1W, OLD_DATA, no storage reset.',
 'altsyncram':'External Quartus library primitive, unavailable as repository RTL. q_b read and port-A writes.',
 'sram_word_tile':'Portable behavior leaf: one-edge read, separate write; same-edge collision returns old data.',
 'sigmoid':'start/x_raw/frac_bits -> y_raw/busy/done; one table lookup and registered interpolation.',
 'div':'Unsigned restoring shift/subtract divider: start/numerator/denominator -> busy/done/quotient/remainder.',
 'isqrt_u64':'32-step unsigned floor square root: start/radicand -> busy/done/root.',
 'ternary_dot32':'32 ternary selectors; four registered stages; valid_i -> valid_o/sum_o/reserved_o.',
 'llm_linear_engine':'Two-word parameter prefetch, ternary dot issue, S39 accumulation; start/ready, done/fault and cancellation drain.',
 'llm_head_engine':'Four ordered int8 chunks per row; parameter requests and parent math issue; sum_valid/sum -> S39 accumulator/done.',
 'llm_attention_engine':'Causal K reads and parent math issue; rounded/scaled QK scores, score array, maximum and done.',
 'llm_attention_normalize':'Eight four-lane batches; lane zero shared at top, three private dividers; RNE/sign/clamp -> vector/done.',
 'llm_math':'STREAMING=1, 32 S24xS32 lanes; accept E0, product_valid E3, sum_valid E8, legacy done E9.',
 'llm_soc':'Host frontend and autonomous graph; parent muxes, operand caches, scaling, softmax/V pass, vector writes and token selection.'
}
ROLES={
 'TOP.u_parameters':'Parameter image: 24576 x 256 bits; host accesses 32-bit lanes, compute reads complete rows.',
 'TOP.u_vectors':'Intermediate vector workspace: 96 x 768 bits; v_address_q/v_data/v_valid and masked write_vector_q.',
 'TOP.u_cache':'Causal K/V storage: 4096 x 768 bits; attention or parent k_read_address, k_data/k_valid and cache writes.',
 'TOP.u_div':'Shared U64/U32 divider: parent RMS reciprocal or attention-normalizer lane zero via numerator/start mux.',
 'TOP.u_root':'Parent RMS coefficient square root from root_input_q; root_busy/root_done/root return to operator control.',
 'TOP.u_scalar_lo':'Low unsigned byte of scalar_b_q multiplied by signed scalar_a_q.',
 'TOP.u_scalar_mid':'Middle unsigned byte of scalar_b_q multiplied by signed scalar_a_q.',
 'TOP.u_scalar_hi':'High signed nine-bit part of scalar_b_q multiplied by signed scalar_a_q.',
 'TOP.u_exp_mul':'Softmax endpoint delta times twelve-bit interpolation fraction.',
 'TOP.u_noise_mul':'Signed Gumbel lookup value times unsigned temperature_q.',
 'TOP.u_exp_hi':'Exp lookup at the selected interval index.',
 'TOP.u_exp_lo':'Exp lookup at the adjacent index plus one.',
 'TOP.u_gumbel_lookup':'Gumbel lookup indexed by random_q[31:24].'
}

def balanced(s,i):
    assert s[i]=='('
    depth=1; j=i+1; quoted=False
    while depth:
        c=s[j]
        if c=='"' and s[j-1]!='\\': quoted=not quoted
        if not quoted:
            if c=='(': depth+=1
            if c==')': depth-=1
        j+=1
    return s[i+1:j-1],j

def named(s):
    out={}; i=0
    while i<len(s):
        m=re.search(r'\.(\w+)\s*\(',s[i:])
        if not m: break
        start=i+m.end()-1; value,end=balanced(s,start)
        out[m[1]]=value.strip(); i=end
    return out

def parse():
    modules={}
    for p in sorted(RTL.iterdir()):
        if p.suffix not in {'.sv','.v','.svh'}:continue
        raw=p.read_text(encoding='utf-8-sig')
        # Preserve character offsets and newlines for exact source references.
        s=re.sub(r'/\*.*?\*/',lambda m:re.sub(r'[^\n]',' ',m[0]),raw,flags=re.S)
        s=re.sub(r'//[^\n]*',lambda m:' '*len(m[0]),s)
        for m in re.finditer(r'\bmodule\s+(\w+)',s):
            end=s.index('endmodule',m.end())+len('endmodule')
            body=s[m.start():end]
            modules[m[1]]={'file':p.name,'line':raw[:m.start()].count('\n')+1,'body':body,'offset':m.start(),'full':s}
    rx=re.compile(r'\b('+ '|'.join(sorted([*modules,'altsyncram'],key=len,reverse=True))+r')\b\s*')
    for name,mod in modules.items():
        ts=[];s=mod['body']
        for m in rx.finditer(s):
            if re.search(r'module\s*$',s[max(0,m.start()-12):m.start()]):continue
            i=m.end(); params={}
            if i<len(s) and s[i]=='#':
                i+=1
                while s[i].isspace():i+=1
                p,i=balanced(s,i);params=named(p)
            n=re.match(r'\s*(\w+)\s*\(',s[i:])
            if not n:continue
            payload,end=balanced(s,i+n.end()-1)
            if not re.match(r'\s*;',s[end:]):continue
            ports=named(payload)
            if not ports:continue
            ts.append({'name':n[1],'module':m[1],'parameters':params,'ports':ports,
                'line':mod['line']+s[:m.start()].count('\n')})
        mod['templates']=ts
    return modules

MODULES=parse()
def template(parent,module,name,branch=None):
    ts=[t for t in MODULES[parent]['templates'] if t['module']==module and t['name']==name]
    if branch is not None: return ts[branch]
    assert len(ts)==1,(parent,module,name,len(ts))
    return ts[0]

def hierarchy(vendor):
    records=[]
    def add(parent,module,name,params=None,which=None):
        scope=name.rsplit('.',1)[0] if '.' in name else ''
        if parent:
            t=template(parent['module'],module,name.rsplit('.',1)[-1],which)
            source=MODULES[parent['module']]['file']; line=t['line']; ports=t['ports']; overrides=t['parameters']
            path=parent['path']+'.'+name; depth=parent['depth']+1
        else:
            path='TOP';depth=0;source='llm_soc.sv';line=3;ports={};overrides={}
        r={'path':path,'parent':parent['path'] if parent else None,'depth':depth,'name':name.rsplit('.',1)[-1],
           'scope':scope,'module':module,'parameters':params or {},'parameter_expressions':overrides,
           'port_map':ports,'instantiation_source':source,'instantiation_line':line,
           'module_source':MODULES[module]['file'] if module in MODULES else None,
           'module_line':MODULES[module]['line'] if module in MODULES else None,
           'external':module not in MODULES}
        records.append(r)
        return r
    top=add(None,'llm_soc','TOP',{'USE_QUARTUS_MEMORY':vendor,'PERF_COUNTERS':0,'ENABLE_DEBUG_INDEX':0,'ATTN_DIV_LANES':4,'SIGMOID_LANES':4})
    for t in MODULES['llm_soc']['templates']:
        if t['name']=='u_sig':
            for i in range(4):add(top,'sigmoid',f'g_sigmoid[{i}].u_sig')
        else:
            p={k:int(v) if re.fullmatch(r'\d+',v) else v for k,v in t['parameters'].items()}
            if t['name']=='u_parameters':p={'ADDR_W':15,'DEPTH':24576,'USE_QUARTUS_MEMORY':vendor}
            if t['name']=='u_vectors':p={'LANES':32,'WIDTH':24,'ROWS':96,'ADDR_W':7,'USE_QUARTUS_MEMORY':vendor}
            if t['name']=='u_cache':p={'LANES':32,'WIDTH':24,'ROWS':4096,'ADDR_W':12,'USE_QUARTUS_MEMORY':vendor}
            if t['name']=='u_math':p={'STREAMING':1}
            if t['name']=='u_attention_normalize':p={'DIV_LANES':4,'USE_SHARED':1}
            if t['name']=='u_div':p={'NUM_W':64,'DEN_W':32}
            add(top,t['module'],t['name'],p)
    for parent in list(records[1:]):
        m=parent['module']
        if m=='llm_parameter_ram':
            for i in range(8):add(parent,'pipelined_word_ram',f'g_ram_lane[{i}].u_storage',{'WIDTH':32,'ROWS':24576,'ADDR_W':15,'USE_QUARTUS_MEMORY':vendor})
        elif m=='llm_bank_ram':
            for i in range(32):add(parent,'pipelined_word_ram',f'g_bank[{i}].u_storage',{k:parent['parameters'][k] for k in ['WIDTH','ROWS','ADDR_W','USE_QUARTUS_MEMORY']})
        elif m=='llm_math':
            for lane in range(32):
                for byte in range(4):add(parent,'logic_mul',f'g_mul_lane[{lane}].g_byte[{byte}].u_mul',{'A_W':24,'B_W':8,'OUT_W':33,'SIGNED_A':1,'SIGNED_B':int(byte==3)})
        elif m=='llm_attention_normalize':
            for i in range(1,4):add(parent,'div',f'g_divider[{i}].g_private.u_div',{'NUM_W':64,'DEN_W':32})
        elif m in ['llm_linear_engine','llm_attention_engine','sigmoid']:
            for t in MODULES[m]['templates']:add(parent,t['module'],t['name'],t['parameters'])
    for parent in [r for r in records if r['module']=='pipelined_word_ram']:
        p=parent['parameters'];rows=p['ROWS'];tiles=(rows+1023)//1024
        if vendor:
            if rows>4096:
                for i in range(tiles):add(parent,'quartus_word_ram',f'g_ip_tiled.g_tile[{i}].u_storage',{'WIDTH':p['WIDTH'],'ROWS':min(1024,rows-i*1024),'ADDR_W':10},0)
            else:add(parent,'quartus_word_ram','g_ip.u_storage',{'WIDTH':p['WIDTH'],'ROWS':rows,'ADDR_W':p['ADDR_W']},1)
        else:
            for i in range(tiles):add(parent,'sram_word_tile',f'g_model.g_tile[{i}].u_tile',{'WIDTH':p['WIDTH'],'ROWS':min(1024,rows-i*1024),'ADDR_W':10})
    for parent in [r for r in records if r['module']=='quartus_word_ram']:
        add(parent,'altsyncram','u_memory',parent['parameters'])
    assert len({r['path'] for r in records})==len(records)
    for r in records:
        if not r['external']:
            body=MODULES[r['module']]['body']; end=body.index(';'); header=body[:end]
            assert all(re.search(r'\b'+re.escape(port)+r'\b',header) for port in r['port_map']),r['path']
    return records

def emit(records,path,config):
    mx=ET.Element('mxfile',host='app.diagrams.net',version='26.0.0',type='device')
    pages=[]
    for depth in range(max(r['depth'] for r in records)+1):
        name='00_TOP' if depth==0 else f'{depth:02d}_LEVEL_{depth}'
        d=ET.SubElement(mx,'diagram',id=f'depth-{depth}',name=name)
        model=ET.SubElement(d,'mxGraphModel',dx='1800',dy='1000',grid='1',gridSize='10',guides='1',tooltips='1',connect='1',arrows='1',fold='1',page='1',pageScale='1',pageWidth='1800',pageHeight='1200',math='0',shadow='0',background='#ffffff')
        root=ET.SubElement(model,'root');ET.SubElement(root,'mxCell',id='0');ET.SubElement(root,'mxCell',id='1',parent='0')
        shapes=[];edges=[];ids={};pos={};counter=0
        def node(label,x,y,w,h,kind='text',external=False,pathkey=None):
            nonlocal counter
            counter+=1;key=f'n{counter}'
            style='whiteSpace=wrap;html=0;fillColor=#ffffff;strokeColor=#000000;fontColor=#000000;fontFamily=Arial;fontSize=24;shadow=0;'
            style+= 'align=center;verticalAlign=middle;rounded=0;' if kind=='module' else 'align=left;verticalAlign=top;spacing=12;'
            if kind=='text':style+='strokeColor=none;'
            if external:style+='dashed=1;'
            c=ET.SubElement(root,'mxCell',id=key,value=label,style=style,vertex='1',parent='1')
            if pathkey:c.set('rtlPath',pathkey)
            ET.SubElement(c,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'})
            shapes.append({'id':key,'label':label,'x':x,'y':y,'w':w,'h':h,'kind':kind,'external':external})
            if pathkey:ids[pathkey]=key;pos[pathkey]=(x+w/2,y+h/2,w,h)
            return key
        def block(r,x,y):
            label=r['name']+'\n('+r['module']+')';w=max(220,max(len(t) for t in label.splitlines())*14+32)
            return node(label,x,y,w,80,'module',r['external'],r['path']),w
        def edge(a,b,label='',functional=False):
            nonlocal counter
            counter+=1;c=ET.SubElement(root,'mxCell',id=f'e{counter}',value=label,style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=0;strokeColor=#000000;fontColor=#000000;fontFamily=Arial;fontSize=24;endArrow=block;endFill=1;labelBackgroundColor=#ffffff;strokeWidth='+('2.5;exitX=1;exitY=0.5;entryX=0;entryY=0.5' if functional else '1;exitX=0.5;exitY=1;entryX=0.5;entryY=0')+';',edge='1',parent='1',source=ids[a],target=ids[b])
            geometry=ET.SubElement(c,'mxGeometry',relative='1',attrib={'as':'geometry'})
            if not functional:
                x1,y1,w1,h1=pos[a];x2,y2,w2,h2=pos[b];gutter=max(18,x1-w1/2-16)
                points=ET.SubElement(geometry,'Array',attrib={'as':'points'})
                for x,y in [(gutter,y1+h1/2),(gutter,y2-h2/2-12),(x2,y2-h2/2-12)]:
                    ET.SubElement(points,'mxPoint',x=str(x),y=str(y))
            edges.append({'a':a,'b':b,'label':label,'functional':functional,'start':pos[a],'end':pos[b]})
        node(f'{name}: llm_soc / {config}',30,20,1660,50)
        node('18 pt = 24 px. Thin arrows: instantiation. Thick arrows: traced functional ports. Dashed blocks: external library.',30,70,1660,60)
        y=160;visible=[]
        if depth==0:
            block(records[0],60,y);visible=records[:1]
            node('External host: host_en / host_we / host_addr[31:0] / host_wdata[31:0]\nReturn: host_ready / host_rdata[31:0]. Hold request until ACK; deassert enable between transactions.\nStatus: running / ready / error / overflow_out. Debug: pc_debug[8:0] / instr_debug[12:0].\nClock/reset: clk / rst_n. This is an internal request/acknowledge interface; AXI/APB are not implemented.',60,y+110,1540,180,'panel')
            y+=320
        else:
            current=[r for r in records if r['depth']==depth]
            lookup={r['path']:r for r in records};groups=defaultdict(list)
            for r in current:groups[r['parent']].append(r)
            compact=[(p,c) for p,c in groups.items() if len(c)<=2]
            wide=[(p,c) for p,c in groups.items() if len(c)>2]
            for parent_path,children in wide:
                parent=lookup[parent_path];visible.append(parent)
                node('Parent context: '+parent_path,40,y,1600,48)
                _,pw=block(parent,40,y+52);y+=152
                # Long generated scopes are placed outside the exact two-line module label.
                columns=3;cell_w=535;row_h=160
                for i,r in enumerate(children):
                    x=40+(i%columns)*cell_w;by=y+(i//columns)*row_h
                    block(r,x,by+56);scope=r['scope'] or 'Direct instance'
                    wrapped='\n'.join(textwrap.wrap(scope,35,break_long_words=False))
                    node(wrapped,x,by,cell_w-18,56)
                    edge(parent_path,r['path']);visible.append(r)
                y+=((len(children)+columns-1)//columns)*row_h+50
            for offset in range(0,len(compact),3):
                batch=compact[offset:offset+3]
                for column,(parent_path,children) in enumerate(batch):
                    x=40+column*535;parent=lookup[parent_path];visible.append(parent)
                    context='\n'.join(textwrap.wrap(parent_path.replace('.','. '),36,break_long_words=False)).replace('. ','.')
                    node(context,x,y,517,120)
                    block(parent,x,y+130)
                    for i,r in enumerate(children):
                        block(r,x,y+285+i*140);edge(parent_path,r['path']);visible.append(r)
                        node(r['scope'] or 'Direct child',x,y+240+i*140,517,45)
                y+=460 if any(len(c)>1 for _,c in batch) else 395
            if depth==1:
                # A dedicated, compact view keeps functional labels out of the structural fanout.
                node('Functional port connections (same instances repeated for routing clarity)',40,y,1600,48);y+=70
                for source,target,label in [
                  ('u_math','u_head_engine','math_sum / math_sum_valid -> sum_i / sum_valid_i'),
                  ('u_math','u_attention_engine','math_sum / math_sum_valid -> sum_i / sum_valid_i'),
                  ('u_div','u_attention_normalize','div_busy / div_done / quotient / remainder -> shared_*_i'),
                  ('u_parameters','u_linear_engine','p_data / p_valid -> parameter_data_i / parameter_valid_i')]:
                    a='TOP.'+source;b='TOP.'+target
                    block(lookup[a],40,y);block(lookup[b],1100,y)
                    edge(a,b,label,True);y+=125
                node('Request and issue paths use parent muxes: head/linear addresses select u_parameters; QK selects u_cache;\nhead_math_issue / attention_math_issue select u_math.start and parent operand capture.\nattention_div_start selects u_div.start and numerator/denominator. See port-map manifest and functional overview.',40,y,1600,135,'panel');y+=160
        functions=defaultdict(list)
        for r in visible:
            if r['path'] not in functions[r['module']]:functions[r['module']].append(r['path'])
        panel_lines=['Block Functions & Interfaces']
        for mod,paths in functions.items():
            paths=list(dict.fromkeys(paths))
            # All covered instance paths remain explicit in the panel, even for replicated leaves.
            panel_lines.extend(textwrap.wrap(mod+': '+DESC.get(mod,''),102,break_long_words=False))
            # Generated ranges cover every separate block; exact paths are also enumerated in the manifest.
            indexed=defaultdict(list)
            for rp in paths:indexed[re.sub(r'\[\d+\]','[]',rp)].append(rp)
            for pattern,covered in indexed.items():
                if len(covered)==1:label=covered[0]
                else:
                    indices=[list(map(int,re.findall(r'\[(\d+)\]',rp))) for rp in covered]
                    axis=[sorted({row[i] for row in indices}) for i in range(len(indices[0]))]
                    cursor=iter(axis)
                    def span(_):
                        values=next(cursor)
                        return '['+(f'{values[0]}:{values[-1]}' if values==list(range(values[0],values[-1]+1)) else ','.join(map(str,values)))+']'
                    label=re.sub(r'\[\]',span,pattern)+f' ({len(covered)} instances; inclusive ranges)'
                panel_lines.extend(textwrap.wrap('  '+label,102,break_long_words=False))
                if len(covered)==1 and covered[0] in ROLES:
                    panel_lines.extend(textwrap.wrap('  Role: '+ROLES[covered[0]],102,break_long_words=False))
                records_by_path={r['path']:r for r in records}
                dictionaries=[records_by_path[rp]['parameters'] for rp in covered]
                common={k:v for k,v in dictionaries[0].items() if all(p.get(k)==v for p in dictionaries)}
                if common:
                    panel_lines.extend(textwrap.wrap('  Parameters: '+', '.join(f'{k}={v}' for k,v in common.items()),102,break_long_words=False))
            if mod in MODULES:panel_lines.append('Source: '+MODULES[mod]['file']+':'+str(MODULES[mod]['line']))
            else:panel_lines.append('Source: external Quartus library; not resolved in repository.')
            panel_lines.append('')
        panel_lines.extend(['Configuration: USE_QUARTUS_MEMORY='+str(records[0]['parameters']['USE_QUARTUS_MEMORY'])+', ATTN_DIV_LANES=4, SIGMOID_LANES=4.',
          'PERF_COUNTERS=0 and ENABLE_DEBUG_INDEX=0. Other configurations require a separate expansion.',
          'USE_SHARED=1: normalizer lane zero is connected to top u_div; only lanes 1, 2, 3 are children.',
          'Packages are source context, not instances. Generate scopes are annotations, not modules.',
          'Alternate memory hierarchy: see rtl_hierarchy_portable.drawio. Quartus is a demonstration backend.'])
        ph=len(panel_lines)*30+24;node('\n'.join(panel_lines),30,y,1700,ph,'panel');y+=ph+30
        model.set('pageWidth','1760');model.set('pageHeight',str(y))
        pages.append({'name':name,'width':1760,'height':y,'shapes':shapes,'edges':edges,'positions':pos})
    ET.indent(mx);ET.ElementTree(mx).write(path,encoding='utf-8',xml_declaration=True)
    # Render from the exact same cell geometry, keeping the editable XML authoritative.
    for page in pages:
        svg=['<svg xmlns="http://www.w3.org/2000/svg" width="1760" height="'+str(page['height'])+'" viewBox="0 0 1760 '+str(page['height'])+'">',
             '<rect width="100%" height="100%" fill="white"/>',
             '<defs><marker id="arrow" markerWidth="10" markerHeight="8" refX="9" refY="4" orient="auto"><path d="M0,0 L10,4 L0,8 Z" fill="black"/></marker></defs>']
        for e in page['edges']:
            x1,y1,w1,h1=e['start'];x2,y2,w2,h2=e['end']
            if e['functional']:
                x1+=w1/2;x2-=w2/2;d=f'M{x1},{y1} H{x2}'
                svg.append(f'<path d="{d}" stroke="black" stroke-width="2.5" fill="none" marker-end="url(#arrow)"/>')
                svg.append(f'<rect x="{x1+12}" y="{y1-56}" width="{max(100,x2-x1-24)}" height="45" fill="white"/>')
                svg.append(f'<text x="{x1+16}" y="{y1-28}" font-family="Arial" font-size="24">{html.escape(e["label"])}</text>')
            else:
                y1+=h1/2;y2-=h2/2
                # Route structural fans in a narrow side gutter to avoid module text.
                gutter=max(18,x1-w1/2-16);d=f'M{x1},{y1} H{gutter} V{y2-12} H{x2} V{y2}'
                svg.append(f'<path d="{d}" stroke="black" stroke-width="1" fill="none" marker-end="url(#arrow)"/>')
        for s in page['shapes']:
            x,y,w,h=s['x'],s['y'],s['w'],s['h']
            if s['kind']!='text':svg.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="white" stroke="black"'+(' stroke-dasharray="7 5"' if s['external'] else '')+'/>')
            lines=s['label'].splitlines()
            for i,line in enumerate(lines):
                tx=x+w/2 if s['kind']=='module' else x+12
                ty=y+(h-len(lines)*30)/2+24+i*30 if s['kind']=='module' else y+28+i*30
                svg.append(f'<text x="{tx}" y="{ty}" font-family="Arial" font-size="24" fill="black" text-anchor="'+('middle' if s['kind']=='module' else 'start')+f'">{html.escape(line)}</text>')
        svg.append('</svg>')
        (OUT/f'{path.stem}_{page["name"]}.svg').write_text('\n'.join(svg),encoding='utf-8')
    return [{k:p[k] for k in ['name','width','height']} for p in pages]

if __name__=='__main__':
    OUT.mkdir(parents=True,exist_ok=True)
    vendor=hierarchy(1);portable=hierarchy(0)
    vp=emit(vendor,ROOT/'rtl_hierarchy.drawio','Quartus memory binding')
    pp=emit(portable,OUT/'rtl_hierarchy_portable.drawio','portable SRAM behavior')
    manifest={'date':'2026-10-06','top':'llm_soc','rtl_root':str(RTL),'scope':'Reviewed structural expansion of current source; not synthesis or functional verification.',
      'source_hashes':{p.name:sha256(p.read_bytes()).hexdigest() for p in RTL.iterdir() if p.suffix in {'.sv','.v','.svh','.mem'}},
      'source_modules':{n:{k:v[k] for k in ['file','line','templates']} for n,v in MODULES.items()},
      'configurations':{'quartus':{'pages':vp,'instances':vendor,'counts_by_depth':dict(Counter(r['depth'] for r in vendor))},
                        'portable':{'pages':pp,'instances':portable,'counts_by_depth':dict(Counter(r['depth'] for r in portable))}}}
    (OUT/'hierarchy_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'quartus_instances':len(vendor),'portable_instances':len(portable),'quartus_pages':vp,'portable_pages':pp}))
