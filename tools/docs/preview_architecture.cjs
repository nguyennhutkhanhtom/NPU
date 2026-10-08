// Render every native-geometry SVG and measure labels using the browser's real
// font metrics. This is preview QA; it does not claim diagrams.net CLI export.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'../..');
const work=path.join(root,'scratchpad/architecture_redesign');
(async()=>{
 fs.writeFileSync(path.join(work,'render_status.json'),JSON.stringify({status:'running',pid:process.pid}));
 const browser=await chromium.launch({headless:true,executablePath:process.env.DOCS_BROWSER_PATH||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe'});
 const page=await browser.newPage({viewport:{width:1600,height:1200}});
 const ds=JSON.parse(fs.readFileSync(path.join(root,'docs/diagrams/architecture_index.json'),'utf8'));
 const results=[];fs.mkdirSync(path.join(work,'png'),{recursive:true});
 try{
  for(const d of ds){
   await page.goto(pathToFileURL(path.join(root,'docs/diagrams',d.preview)).href);
   const r=await page.evaluate(()=>{
    const svg=document.querySelector('svg'),v=svg.viewBox.baseVal,errors=[];
    for(const t of svg.querySelectorAll('text')){const b=t.getBBox();if(b.x<0||b.y<0||b.x+b.width>v.width+1||b.y+b.height>v.height+1)errors.push({label:t.textContent,issue:'outside page',bbox:{x:b.x,y:b.y,w:b.width,h:b.height}});}
    return {width:v.width,height:v.height,texts:svg.querySelectorAll('text').length,errors};
   });
   await page.locator('svg').screenshot({path:path.join(work,'png',d.key+'.png'),timeout:15000});
   results.push({page:d.key,preview:d.preview,sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'docs/diagrams',d.preview))).digest('hex'),...r});
  }
  const reference=path.join(work,'reference_legend.svg');
  if(fs.existsSync(reference)){
   await page.goto(pathToFileURL(reference).href);
   await page.locator('svg').screenshot({path:path.join(work,'reference_legend.png'),timeout:15000});
  }
  const result={status:results.some(x=>x.errors.length)?'failed':'complete',pages:results,renderer:'Local SVG generated from native draw.io geometry + Edge headless; no diagrams.net CLI installed'};
  fs.writeFileSync(path.join(root,'docs/diagrams/architecture_preview_validation.json'),JSON.stringify(result,null,2)+'\n');
  fs.writeFileSync(path.join(work,'render_status.json'),JSON.stringify({status:result.status,pid:process.pid,pages:results.length}));
  console.log(JSON.stringify({pages:results.length,failures:results.filter(x=>x.errors.length)}));
 }finally{await browser.close();}
})().catch(error=>{fs.writeFileSync(path.join(work,'render_status.json'),JSON.stringify({status:'failed',error:String(error)}));console.error(error);process.exitCode=1;});
