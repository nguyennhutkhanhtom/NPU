// Parse reviewed functional flowcharts as an interchange format, then compute
// entirely new native draw.io geometry. No Mermaid SVG enters the deliverable.
import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';
import {Graph} from './node_modules/dagre-d3-es/src/graphlib/index.js';
import {layout} from './node_modules/dagre-d3-es/src/dagre/index.js';
const require=createRequire(import.meta.url);
const {chromium}=require('playwright');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const work=path.join(root,'scratchpad/architecture_redesign');
const ds=JSON.parse(fs.readFileSync(path.join(work,'reviewed_graphs.json'),'utf8'));
const browser=await chromium.launch({headless:true,executablePath:process.env.DOCS_BROWSER_PATH || 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
const page=await browser.newPage();
await page.setContent('<html><body></body></html>');
const moduleDirectory=path.dirname(require.resolve('mermaid'));
await page.route('https://npu-docs.local/mermaid/**',async route=>{
 const relative=decodeURIComponent(new URL(route.request().url()).pathname.slice('/mermaid/'.length));
 const file=path.resolve(moduleDirectory,relative);
 if(!file.startsWith(moduleDirectory+path.sep)||!fs.existsSync(file)){await route.abort();return;}
 await route.fulfill({path:file,contentType:'application/javascript',headers:{'Access-Control-Allow-Origin':'*'}});
});
await page.addScriptTag({type:'module',content:'import mermaid from "https://npu-docs.local/mermaid/mermaid.esm.min.mjs"; window.mermaid=mermaid;'});
await page.waitForFunction(()=>Boolean(window.mermaid));
await page.evaluate(()=>mermaid.initialize({startOnLoad:false,securityLevel:'strict'}));
function plain(s){return String(s??'').replace(/<br\s*\/?\s*>/gi,'\n').replace(/<[^>]*>/g,'').replace(/&ﬂ°°(\d+)¶ß/g,(_,n)=>String.fromCodePoint(Number(n))).replace(/&lt;/g,'<').replace(/&gt;/g,'>').replace(/&amp;/g,'&').replace(/&#91;/g,'[').replace(/&#93;/g,']').replace(/&quot;/g,'"').replace(/&#x27;/g,"'");}
function wrap(s,max=34){return plain(s).split('\n').flatMap(l=>{
 const a=[];let buf='';for(const word of l.split(/\s+/)){if(buf.length+word.length+1>max&&buf){a.push(buf);buf='';}buf+=(buf?' ':'')+word;}a.push(buf);return a;
});}
let results=[];
try{
 for(const d of ds){
  const parsed=await page.evaluate(async code=>{
   const dg=await mermaid.mermaidAPI.getDiagramFromText(code);
   return {nodes:[...dg.db.getVertices().values()],edges:dg.db.getEdges(),groups:dg.db.getSubGraphs()};
  },d.graph);
  const nodes=parsed.nodes.map(n=>({id:n.id,label:plain(n.text),lines:wrap(n.text),type:n.type,classes:n.classes||[]}));
  for(const n of nodes){n.width=Math.max(200,Math.min(300,Math.max(...n.lines.map(x=>x.length))*7+30));n.height=Math.max(64,n.lines.length*17+24);if(n.type==='diamond'){n.width+=80;n.height+=36;}}
  const edges=parsed.edges.map((e,i)=>({id:'e'+i,source:e.start,target:e.end,label:plain(e.text),lines:wrap(e.text,24),control:e.stroke==='dotted',bidirectional:e.type==='double_arrow_point',type:e.type}));
  if(d.kind==='hierarchy'){
   const p=nodes.find(n=>n.id==='P');const children=nodes.filter(n=>n.id!=='P');const cols=Math.min(4,children.length);
   const cw=290;const rh=Math.max(100,...children.map(n=>n.height));
   const width=Math.max(800,cols*(cw+24)+96);
   p.x=30;p.y=100;p.width=width-60;p.height=Math.ceil(children.length/cols)*(rh+30)+100;p.lines=wrap(p.label,100);
   for(let i=0;i<children.length;i++){const n=children[i];n.x=(width-cols*(cw+24)+24)/2+(i%cols)*(cw+24);n.y=180+Math.floor(i/cols)*(rh+30);n.width=cw;n.height=rh;}
   results.push({...d,nodes,edges:[],groups:[],width,height:p.height+160});continue;
  }
  // A top-to-bottom backbone and spacious control side branches keep pages
  // usable at normal document width. Detailed pipelines are separate pages.
  const g=new Graph({multigraph:true,compound:true});
  g.setGraph({rankdir:'TB',nodesep:50,edgesep:22,ranksep:70,marginx:40,marginy:30});g.setDefaultEdgeLabel(()=>({}));
  for(const n of nodes)g.setNode(n.id,{width:n.width,height:n.height});
  const groups=[];
  for(const gr of parsed.groups){if(!gr.nodes?.length)continue;g.setNode(gr.id,{label:plain(gr.title),width:0,height:0});for(const id of gr.nodes)if(g.hasNode(id))g.setParent(id,gr.id);groups.push({id:gr.id,label:plain(gr.title),children:gr.nodes});}
  for(const e of edges)g.setEdge(e.source,e.target,{width:e.label?Math.min(164,Math.max(...e.lines.map(x=>x.length))*6+10):0,height:e.label?e.lines.length*14+10:0,weight:e.control?0.4:2},e.id);
  layout(g);
  for(const n of nodes){const p=g.node(n.id);n.x=p.x-n.width/2;n.y=p.y-n.height/2+90;n.parent=g.parent(n.id);}
  for(const gr of groups){const p=g.node(gr.id);gr.x=p.x-p.width/2;gr.y=p.y-p.height/2+90;gr.width=p.width;gr.height=p.height;}
  for(const e of edges){const p=g.edge({v:e.source,w:e.target,name:e.id});e.suggestedPoints=p.points.map(p=>({x:p.x,y:p.y+90}));}
  let width=Math.max(800,g.graph().width+80),height=g.graph().height+180;
  if(g.graph().width+80<800){const offset=(800-(g.graph().width+80))/2;for(const n of nodes)n.x+=offset;for(const gr of groups)gr.x+=offset;for(const e of edges)for(const p of e.suggestedPoints)p.x+=offset;}
  if(d.graph.startsWith('flowchart TB\n H["Host request / ACK')){
   // Top resource overview: host/control above, memory at left, engines and
   // epilogues to the right of the explicit parent mux boundary.
   const coords={H:[40,130],F:[360,130],C:[680,130],P:[40,340],V:[40,510],K:[40,680],M:[360,480],O:[680,340],L:[680,510],E:[680,680],A:[1000,510],S:[1000,340],T:[1000,130]};
   for(const n of nodes){[n.x,n.y]=coords[n.id];n.width=280;n.height=110;}
   width=1330;height=890;
   for(const e of edges){const a=nodes.find(n=>n.id===e.source),b=nodes.find(n=>n.id===e.target);let p,q;if(Math.abs(a.x-b.x)>Math.abs(a.y-b.y)){p={x:a.x+(a.x<b.x?a.width:0),y:a.y+a.height/2};q={x:b.x+(a.x<b.x?0:b.width),y:b.y+b.height/2};}else{p={x:a.x+a.width/2,y:a.y+(a.y<b.y?a.height:0)};q={x:b.x+b.width/2,y:b.y+(a.y<b.y?0:b.height)};}e.suggestedPoints=[p,q];}
  }
  if(d.graph.includes('linear_pipe_row_q[0:8] U10')){
   const coords={E:[40,140],I:[360,140],P:[680,140],A:[680,340],S:[360,340],R:[40,340],F:[40,540],C:[360,540],G:[680,540],W:[680,740],V:[360,740],D:[40,740],T:[40,930]};
   for(const n of nodes){[n.x,n.y]=coords[n.id];n.width=n.id==='T'?920:280;n.height=n.id==='T'?70:110;if(n.id==='T')n.lines=wrap(n.label,120);}
   // Stage labels already carry each exact tag index. A single tag strip
   // replaces nine redundant fanout arrows that obscured the datapath.
   for(let i=edges.length-1;i>=0;i--)if(edges[i].source==='T')edges.splice(i,1);
   width=1010;height=1060;
   for(const e of edges){const a=nodes.find(n=>n.id===e.source),b=nodes.find(n=>n.id===e.target);if(a.y===b.y){e.suggestedPoints=[{x:a.x+(a.x<b.x?a.width:0),y:a.y+a.height/2},{x:b.x+(a.x<b.x?0:b.width),y:b.y+b.height/2}];}else{e.suggestedPoints=[{x:a.x+a.width/2,y:a.y+a.height},{x:b.x+b.width/2,y:b.y}];}}
  }
  let folded;
  if(d.graph.includes('Ordered 4096-row vocabulary stream'))folded={S:[40,130],C:[360,130],D:[680,130],A:[40,330],W:[360,330],P:[680,330],R:[680,530],O:[360,530],M:[40,530],K:[680,730],F:[360,730],U:[40,730],E:[360,930],Z:[40,930]};
  if(d.graph.includes('Two parameter-word credits<br/>request_q'))folded={S:[40,130],C:[360,130],Q:[680,130],P:[680,330],F:[360,330],W:[40,330],X:[40,530],R:[360,530],D:[680,530],A:[680,730],B:[360,730],O:[40,730],Z:[680,930],V:[360,930]};
  if(folded){
   for(const n of nodes){[n.x,n.y]=folded[n.id];n.x=40+(n.x-40)/320*480;n.width=280;n.height=110;}
   width=1330;height=1120;
   for(const e of edges){const a=nodes.find(n=>n.id===e.source),b=nodes.find(n=>n.id===e.target);const shift=e.control?30:0;if(a.y===b.y){e.suggestedPoints=[{x:a.x+(a.x<b.x?a.width:0),y:a.y+a.height/2+shift},{x:b.x+(a.x<b.x?0:b.width),y:b.y+b.height/2+shift}];}else{e.suggestedPoints=[{x:a.x+a.width/2+shift,y:a.y+(a.y<b.y?a.height:0)},{x:b.x+b.width/2+shift,y:b.y+(a.y<b.y?0:b.height)}];}}
  }
  results.push({...d,nodes,edges,groups,width,height});
 }
 fs.writeFileSync(path.join(work,'layout.json'),JSON.stringify(results,null,2)+'\n');
 console.log(JSON.stringify({pages:results.length,nodes:results.reduce((s,d)=>s+d.nodes.length,0),edges:results.reduce((s,d)=>s+d.edges.length,0)}));
}finally{await browser.close();}
