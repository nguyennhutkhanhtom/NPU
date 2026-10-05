const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '../..');
const input = path.join(root, 'docs/diagrams');
const output = path.join(__dirname, 'output/hierarchy');
(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ headless: true, executablePath: process.env.DOCS_BROWSER_PATH });
  const page = await browser.newPage({ viewport: { width: 1760, height: 1000 } });
  const results = [];
  try {
    for (const name of fs.readdirSync(input).filter(n => n.endsWith('.svg')).sort()) {
      await page.goto(pathToFileURL(path.join(input, name)).href);
      const audit = await page.evaluate(() => {
        const svg = document.querySelector('svg');
        const vb = svg.viewBox.baseVal;
        const errors = [];
        const fonts = new Set();
        for (const t of svg.querySelectorAll('text')) {
          const b = t.getBBox(); fonts.add(getComputedStyle(t).fontSize);
          if (b.x < 0 || b.y < 0 || b.x+b.width > vb.width+1 || b.y+b.height > vb.height+1)
            errors.push({ text: t.textContent, issue: 'Text outside page', bbox: {x:b.x,y:b.y,width:b.width,height:b.height} });
        }
        return { height: vb.height, width: vb.width, texts: svg.querySelectorAll('text').length, fonts: [...fonts], errors };
      });
      const screenshots=[];
      // Every rendered band is retained for complete visual review without giant screenshots.
      for (let y=0, i=0; y<audit.height; y+=1000, i++) {
        await page.evaluate(y => window.scrollTo(0,y),y);
        const png = name.replace('.svg','')+'-'+String(i).padStart(3,'0')+'.png';
        await page.screenshot({ path:path.join(output,png) }); screenshots.push(png);
      }
      results.push({ file:'docs/diagrams/'+name,...audit,screenshots });
    }
    fs.writeFileSync(path.join(input,'preview_validation.json'),JSON.stringify({ date:new Date().toISOString(),scope:'SVG previews generated from the same geometry and labels as editable draw.io. Every page rendered in viewport bands; text page bounds and 18 pt fonts checked.',pages:results },null,2)+'\n');
    console.log(JSON.stringify({pages:results.length,bands:results.reduce((n,r)=>n+r.screenshots.length,0),errors:results.filter(r=>r.errors.length),fonts:[...new Set(results.flatMap(r=>r.fonts))]}));
    process.exitCode=results.some(r=>r.errors.length || r.fonts.some(f=>f!=='24px'))?1:0;
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1;});
