const fs = require('node:fs');
const path = require('node:path');
const sharp = require('C:/Users/khanh/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp');

const out = __dirname;
const C = { ink:'#18263D', muted:'#5C6C83', faint:'#96A3B5', line:'#D6DFEB', bg:'#F5F7FB', blue:'#3475DA', teal:'#119786', purple:'#8056BD', amber:'#BE8422', ctrl:'#748198' };
const parts=[];
const esc = s => String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const add = s => parts.push(s);
function rect(x,y,w,h,fill,stroke='none',r=0,extra=''){add(`<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}" stroke="${stroke}" ${extra}/>`);}
function line(x1,y1,x2,y2,color,width=2,extra=''){add(`<path d="M${x1} ${y1}L${x2} ${y2}" fill="none" stroke="${color}" stroke-width="${width}" ${extra}/>`);}
function p(d,color,width=3,extra=''){add(`<path d="${d}" fill="none" stroke="${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round" ${extra}/>`);}
function poly(points,fill,stroke='none',extra=''){add(`<polygon points="${points}" fill="${fill}" stroke="${stroke}" ${extra}/>`);}
function circ(x,y,r,fill,stroke='none',extra=''){add(`<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" stroke="${stroke}" ${extra}/>`);}
function txt(x,y,s,size=22,color=C.ink,weight=400,anchor='start',extra=''){add(`<text x="${x}" y="${y}" font-size="${size}" fill="${color}" font-weight="${weight}" text-anchor="${anchor}" ${extra}>${esc(s)}</text>`);}
function wire(d,key,both=false){p(d,C[key],4,`marker-end="url(#${key}Arrow)" ${both?`marker-start="url(#${key}Arrow)"`:''}`);}
function control(d,both=false){p(d,C.ctrl,2.5,`stroke-dasharray="7 7" marker-end="url(#ctrlArrow)" ${both?'marker-start="url(#ctrlArrow)"':''}`);}
function pill(x,y,w,label,color,fill){rect(x,y,w,35,fill,'none',17);txt(x+w/2,y+24,label,16,color,650,'middle');}
function slab(x,y,w,h,color,light){
  poly(`${x},${y+13} ${x+15},${y} ${x+w+15},${y} ${x+w},${y+13}`,light,color,'stroke-width="1.4"');
  poly(`${x+w},${y+13} ${x+w+15},${y} ${x+w+15},${y+h-12} ${x+w},${y+h}`,color,color);
  rect(x,y+13,w,h-13,'#FFFFFF',color,5,'stroke-width="1.6"');
}
function fifo(x,y,n,w,h,color,light){for(let i=0;i<n;i++){rect(x+i*(w+5),y,w,h,light,color,4);}}

add(`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="2080" height="1580" viewBox="0 0 2080 1580" role="img" aria-labelledby="title desc">
<title id="title">Kiến trúc ASIC ternary cho mô hình hồi quy</title>
<desc id="desc">Sơ đồ kiến trúc đề xuất cho HF-Mamba-2: bộ nhớ ngoài kết nối DMA, bộ đệm trọng số A/B, giải mã ternary, mảng PE và bộ tích lũy INT32, khối convolution và cập nhật trạng thái, chuẩn hóa và lượng tử hóa, SRAM chia bank cho activation, tổng tích lũy và trạng thái riêng của từng yêu cầu. Các đường liền có màu là dữ liệu; đường xám nét đứt là điều khiển.</desc>
<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="7" stdDeviation="9" flood-color="#213B61" flood-opacity="0.07"/></filter>
  <linearGradient id="die" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#F9FBFE"/></linearGradient>
  <linearGradient id="screen" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#213752"/><stop offset="1" stop-color="#13263D"/></linearGradient>
  <pattern id="dots" x="0" y="0" width="22" height="22" patternUnits="userSpaceOnUse"><circle cx="2" cy="2" r="1" fill="#E1E7F0"/></pattern>
`);
for(const key of ['blue','teal','purple','amber','ctrl'])add(`<marker id="${key}Arrow" markerWidth="9" markerHeight="9" refX="8" refY="4.5" orient="auto-start-reverse" markerUnits="userSpaceOnUse"><path d="M0 0L9 4.5L0 9Z" fill="${C[key]}"/></marker>`);
add('</defs><g font-family="Segoe UI, Arial, sans-serif">');
rect(0,0,2080,1580,C.bg);
rect(0,196,2080,1224,'url(#dots)');
txt(65,77,'ASIC TERNARY CHO MÔ HÌNH HỒI QUY',43,C.ink,750);
txt(67,120,'Bộ nhớ chia bank · tính toán theo tile · nhiều yêu cầu độc lập',24,C.muted);
pill(65,145,325,'HF-Mamba-2  |  130M → 780M',C.blue,'#E7EFFD');
pill(405,145,249,'W1.58 × A8  |  ACC INT32',C.teal,'#E0F3EF');
txt(1999,62,'KIẾN TRÚC ĐỀ XUẤT',18,C.muted,700,'end','letter-spacing="2"');
txt(1999,92,'B = 1 / 2 / 4 / 8 yêu cầu',20,C.ink,600,'end');
txt(1999,124,'Cấu hình số học cần khớp mô hình tham chiếu',17,C.muted,400,'end');

// ASIC boundary and controller band.
rect(380,220,1640,1185,'url(#die)',C.line,32,'stroke-width="2" filter="url(#shadow)"');
txt(421,269,'BÊN TRONG ASIC',21,C.ink,700,'start','letter-spacing="1.4"');
txt(1977,269,'Các khối phối hợp qua dữ liệu, descriptor và tín hiệu hoàn tất',18,C.muted,400,'end');
for(const x of [400,1997])for(let y=570;y<870;y+=32)rect(x,y,7,14,'#DCE4EF','none',2);
rect(430,310,1530,126,'#F0F3F9','#D9E1EC',20);
line(974,332,974,414,'#D0DAE8');line(1463,332,1463,414,'#D0DAE8');
rect(456,335,53,59,'#C5D3E6','none',7);rect(465,326,53,59,'#DDE6F3','none',7);rect(475,338,53,59,'#FFF','#AFC0D5',7);
for(let i=0;i<3;i++){circ(486,351+i*14,2.5,C.ctrl);line(495,351+i*14,516,351+i*14,C.ctrl,2);}
txt(552,350,'BỘ ĐIỀU KHIỂN',22,C.ink,750);
txt(552,380,'Lịch tile · địa chỉ · phụ thuộc dữ liệu',20,C.muted);
txt(552,408,'Descriptor sequencer',16,C.muted);
txt(1004,350,'BẢNG THEO DÕI YÊU CẦU',21,C.ink,700);
for(let i=0;i<4;i++){const x=1006+i*64;rect(x,369,51,36,'#FFF','#BBC8DA',8);txt(x+25.5,394,'C'+i,18,C.purple,650,'middle');}
txt(1283,391,'1–8 state riêng',18,C.muted);
txt(1494,350,'CHỌN CẤU HÌNH',21,C.ink,700);
txt(1494,380,'Số yêu cầu · tile · bank SRAM',20,C.muted);
for(let i=0;i<4;i++)rect(1496+i*19,413-9-i*4,11,9+i*4,'#9BAFCB','none',2);
txt(1591,413,'Đếm chu kỳ, chờ DMA và bank',16,C.muted);
rect(658,1138,1307,206,'#F4F7FC','#D9E2EE',18,'stroke-width="1.4"');

// Shared command bus. The same dashed style is used for host command/status.
control('M1200 436V480H1905');p('M1200 480H518',C.ctrl,2.5,'stroke-dasharray="7 7"');
for(const x of [528,1020,1357,1815]){
  circ(x,480,4,C.ctrl);
  if(x===1020)control(`M${x} 480V599`);
  else {p(`M${x} 480V517`,C.ctrl,2.5,'stroke-dasharray="7 7"');control(`M${x} 562V${x===528?581:574}`);}
}
p('M1139 480V678',C.ctrl,2.5,'stroke-dasharray="7 7"');control('M1139 704V975H1131');
txt(664,470,'Điều khiển: start / done · địa chỉ · chọn bank',18,C.ctrl,500);

// Main data routes, kept in reserved corridors.
wire('M314 691H449','blue',true);
wire('M625 681H665V633H701','blue');
wire('M665 681V748H701','blue');circ(665,681,4,C.blue);
p('M888 633H918V691M888 748H918V691',C.blue,3.5);circ(918,691,4,C.blue);wire('M918 691H949','blue');
wire('M1110 691H1174','blue');
wire('M1566 742H1668','teal');txt(1617,720,'Projection',17,C.teal,550,'middle');
p('M449 773H416V1099Q416 1118 435 1118H625Q644 1118 644 1137V1328H1905',C.blue,3.5,'marker-start="url(#blueArrow)"');
for(const x of [1000,1340,1740]){wire(`M${x} 1326V1287`,'blue',true);circ(x,1328,3.5,C.blue);}
txt(455,918,'Transferts SRAM',17,C.blue,500);
txt(455,944,'lecture / écriture',16,C.muted);
wire('M1060 1177V1148H800V1050H859','teal');
txt(720,1080,'Vecteur',18,C.teal,600);
wire('M1091 947V922H1285V895','teal');txt(1245,912,'Activation INT8',18,C.teal,550,'middle');
wire('M1490 897V1177','amber',true);
txt(1470,1041,'Tổng tích lũy',18,C.amber,600,'end');txt(1470,1068,'giữa các tile',17,C.muted,400,'end');
wire('M1814 887V1118H1921V1177','purple',true);
txt(1787,1005,'Đọc → cập nhật → ghi',18,C.purple,600,'end');txt(1787,1033,'State riêng theo yêu cầu',17,C.muted,400,'end');
for(let i=0;i<4;i++){rect(1603+i*43,1053,35,29,'#F0E8FA','#C5AEDF',7);txt(1620+i*43,1073,String.fromCharCode(65+i),16,C.purple,650,'middle');}
wire('M1956 797H1985Q1998 797 1998 811V1338Q1998 1355 1981 1355H845Q829 1355 829 1340V1338C813 1338 813 1318 829 1318V1287','teal',true);
txt(1441,1384,'Đọc / ghi activation, residual và kết quả',20,C.teal,600,'middle');

// Host monitor.
txt(76,271,'HOST CPU',23,C.ink,750);
rect(72,311,246,148,'#D1DAE7','#A9B8CB',12,'stroke-width="1.5"');rect(83,322,224,123,'url(#screen)','none',7);
txt(101,351,'> descriptor',18,'#B6D9FE',600);txt(101,379,'> token đầu vào',17,'#DCEBFA');txt(101,409,'< token đầu ra',17,'#9BE5D0');
poly('167,459 222,459 229,482 160,482','#B9C6D8');rect(140,481,110,9,'#A2B3C9','none',4);
txt(76,520,'Tokenizer · sampling',19,C.muted);
control('M319 369H429',true);txt(366,347,'Lệnh',16,C.ctrl,600,'middle');

// External DRAM, drawn as stacked packages with pins and embedded dies.
txt(75,579,'BỘ NHỚ NGOÀI',23,C.ink,750);
for(let layer=2;layer>=0;layer--){
  const x=77+layer*9,y=627+layer*46;
  poly(`${x},${y+15} ${x+24},${y} ${x+226},${y} ${x+204},${y+15}`,'#DCE7F7','#97AED1');
  poly(`${x+204},${y+15} ${x+226},${y} ${x+226},${y+80} ${x+204},${y+95}`,'#7F9CC8','#7F9CC8');
  rect(x,y+15,204,80,'#F0F5FC','#97AED1',4);
  for(let j=0;j<5;j++){rect(x+18+j*35,y+36,27,32,'#4F6E9C','none',4);for(let k=0;k<3;k++)line(x+21+j*35+k*8,y+70,x+21+j*35+k*8,y+76,'#91A8C8',2);}
}
txt(80,862,'Trọng số · trạng thái tràn',19,C.muted);txt(80,890,'Dữ liệu vào / ra',19,C.muted);
txt(353,672,'Burst',16,C.blue,600,'middle');

// Legend in the exterior margin.
txt(76,1007,'CÁCH ĐỌC SƠ ĐỒ',20,C.ink,700);
const legends=[['blue','Trọng số / truyền bộ nhớ'],['teal','Dữ liệu trung gian'],['amber','Tổng tích lũy'],['purple','Trạng thái hồi quy'],['ctrl','Điều khiển / trạng thái']];
legends.forEach(([key,label],i)=>{const y=1050+i*51;p(`M78 ${y}H125`,C[key],key==='ctrl'?2.5:4,key==='ctrl'?'stroke-dasharray="6 6"':'');txt(139,y+6,label,17,C.muted);});
txt(77,1340,'Nét liền: luồng dữ liệu',17,C.muted);txt(77,1367,'Hai mũi tên: đọc và ghi',17,C.muted);

// DMA: opposing transfer arrows and two FIFO queues.
txt(535,548,'DMA / STREAM',22,C.ink,750,'middle');
rect(450,585,175,225,'#F5F8FD','#CCD9EC',22,'stroke-width="1.7"');
poly('475,618 566,618 566,607 594,632 566,657 566,646 475,646',C.blue);
poly('598,679 508,679 508,668 479,693 508,718 508,707 598,707','#88A9DD');
fifo(471,746,4,27,31,C.blue,'#E4EDFB');
txt(537,845,'Burst + hàng đợi',18,C.muted,550,'middle');
txt(537,872,'valid / ready',16,C.muted,400,'middle');

// Ping-pong weight buffers, explicitly two separate memory slabs.
txt(790,548,'WEIGHT BUFFER',22,C.ink,750,'middle');
slab(705,593,182,81,C.blue,'#DBE9FE');slab(705,708,182,81,'#87AADD','#EAF1FD');
for(let row=0;row<2;row++)for(let col=0;col<5;col++){rect(752+col*23,619+row*20,17,13,row===0?'#5C91E0':'#B4CEF3','none',2);rect(752+col*23,734+row*20,17,13,'#CFDDF0','none',2);}
txt(729,646,'A',25,C.blue,750,'middle');txt(729,761,'B',25,'#6F90BE',750,'middle');
txt(799,692,'đang dùng',16,C.blue,600,'middle');txt(799,814,'nạp trước',16,C.muted,500,'middle');
txt(800,845,'Luân phiên A ↔ B',18,C.muted,550,'middle');

// Decoder is a shaped unpacking block, rather than a generic box.
poly('950,632 981,604 1079,604 1110,637 1110,759 1079,792 981,792 950,762','#EBF2FE','#A6C0E9','stroke-width="1.8"');
txt(1030,640,'01 · 00 · 11',19,C.blue,700,'middle');
for(let i=0;i<3;i++){line(993+i*36,656,993+i*36,677,C.blue,2);poly(`${989+i*36},673 ${997+i*36},673 ${993+i*36},680`,C.blue);}
txt(1030,714,'+1  0  −1',25,C.blue,750,'middle');
pill(977,738,107,'scale',C.blue,'#D6E5FB');
txt(1030,833,'Giải mã ternary',18,C.muted,550,'middle');

// The compute block is an actual PE lattice with a broadcast spine and local sums.
txt(1370,548,'MẢNG PE TERNARY',23,C.ink,750,'middle');
rect(1175,578,390,318,'#F1F8F8','#B7D6DA',24,'stroke-width="1.8"');
txt(1199,610,'Dùng chung trọng số',17,C.blue,650);
p('M1227 628H1526',C.blue,2.3);
const symbols=['+','0','−','+','−','0','+','−'];
for(let col=0;col<8;col++){line(1240+col*40,628,1240+col*40,646,C.blue,2);}
for(let row=0;row<4;row++){
  txt(1192,665+row*38,'C'+row,14,C.teal,650);
  for(let col=0;col<8;col++){
    const x=1223+col*40,y=645+row*38;
    rect(x,y,33,30, row%2?'#DCEFED':'#E8F4F2','#9BC8C3',5);
    txt(x+16.5,y+22,symbols[(col+row)%8],23,C.teal,650,'middle');
    if(col<7)line(x+33,y+15,x+40,y+15,'#9BC8C3',1.5);
  }
}
poly('1224,804 1538,804 1519,822 1243,822','#E5C993');txt(1380,818,'CSA / REDUCTION',13,'#82591C',700,'middle');
for(let i=0;i<4;i++){rect(1211+i*84,835,74,35,'#FFF2D9','#D8B572',6);txt(1248+i*84,859,'Σ INT32',16,'#8A611D',650,'middle');}
txt(1370,884,'PE et accumulateurs reconfigurables',15,C.muted,400,'middle');

// Vector/state engine: shift-register history, multiplier, outer product, reduction and ReLU.
txt(1815,548,'VECTOR / STATE',23,C.ink,750,'middle');
rect(1670,578,287,309,'#F8F4FD','#D2BFE7',24,'stroke-width="1.8"');
txt(1694,609,'Lịch sử convolution',17,C.purple,650);
for(let i=0;i<4;i++){rect(1698+i*58,625,45,38,'#EEE5F9','#B69AD5',6);txt(1720.5+i*58,651,'z⁻¹',19,C.purple,650,'middle');if(i<3)line(1744+i*58,644,1755+i*58,644,C.purple,2,'marker-end="url(#purpleArrow)"');}
line(1721,664,1721,683,C.purple,2);
circ(1721,712,24,'#EAE0F7','#B99BD8','stroke-width="1.5"');txt(1721,721,'×',31,C.purple,500,'middle');
line(1745,712,1786,712,C.purple,2,'marker-end="url(#purpleArrow)"');
for(let row=0;row<4;row++)for(let col=0;col<4;col++)rect(1791+col*15,686+row*15,11,11,(row+col)%2?'#CDB5E7':'#E6D9F3','none',2);
line(1849,712,1870,712,C.purple,2,'marker-end="url(#purpleArrow)"');
circ(1895,712,23,'#EAE0F7','#B99BD8','stroke-width="1.5"');txt(1895,721,'Σ',26,C.purple,600,'middle');
line(1699,800,1773,800,'#BCA6D6',1.8);line(1717,808,1717,763,'#BCA6D6',1.8);p('M1701 795H1730L1758 766',C.purple,3);
txt(1734,832,'Phi tuyến',15,C.muted,500,'middle');
circ(1853,788,26,'#EEE5F8','#BDA4D9');txt(1853,795,'hₜ',23,C.purple,650,'middle');
p('M1828 801C1810 783 1828 751 1856 752C1887 752 1901 777 1885 798',C.purple,2,'marker-end="url(#purpleArrow)"');
txt(1853,832,'State update',15,C.muted,500,'middle');
txt(1814,862,'Conv · phi tuyến · hồi quy',18,C.muted,550,'middle');

// Norm/quantizer: a reduction tree and a staircase quantizer.
poly('884,948 1105,948 1130,973 1130,1087 1105,1110 884,1110 860,1087 860,973','#EDF8F4','#ABD5C8','stroke-width="1.8"');
txt(995,977,'NORM + QUANT',21,C.teal,750,'middle');
for(let i=0;i<4;i++)circ(889+i*17,1005,4,C.teal);
p('M889 1011L898 1025H915L923 1011M923 1011L932 1025H941L940 1011M906 1025L920 1043L936 1025',C.teal,2);
circ(920,1050,15,'#D2EDE3',C.teal);txt(920,1057,'Σ',19,C.teal,650,'middle');
line(946,1040,996,1040,C.teal,2.5,'marker-end="url(#tealArrow)"');
line(1011,1064,1090,1064,'#A4C9BE',1.5);line(1011,1064,1011,1003,'#A4C9BE',1.5);
p('M1011 1057H1027V1045H1045V1031H1063V1017H1086',C.teal,3);
txt(995,1092,'Thống kê → hệ số → INT8',17,C.muted,550,'middle');

// One shared scratchpad pool, shown as three logical bank groups.
txt(683,1167,'ACTIVATION / RESIDUAL',19,C.teal,750);
txt(1164,1167,'PARTIAL SUM',19,C.amber,750);
txt(1580,1167,'STATE + CONV HISTORY',19,C.purple,750);
slab(679,1179,414,107,C.teal,'#DDF1E9');
for(let row=0;row<3;row++)for(let col=0;col<10;col++)rect(696+col*37,1210+row*21,28,14,row===0?'#88CABA':'#D4EDE5','none',2);
slab(1164,1179,340,107,C.amber,'#F5E9CC');
for(let row=0;row<3;row++)for(let col=0;col<8;col++)rect(1182+col*38,1210+row*21,28,14,row===0?'#DABB7F':'#F1E4C8','none',2);
slab(1580,1179,345,107,C.purple,'#EADDF7');
for(let i=0;i<4;i++){
  const x=1595+i*81;
  rect(x,1201,72,48,i%2?'#F0E8F8':'#E5D7F3','#D0B9E6',5);txt(x+36,1231,'C'+i,19,C.purple,650,'middle');
  fifo(x,1257,4,13,11,'#B59ACA','#DDCEEE');
}
txt(696,1315,'BUS SRAM / DMA',15,C.blue,650);
txt(77,1287,'SRAM: các phân vùng logic',17,C.muted);
// Restore short port segments above the module fills, so both arrowheads remain visible.
wire('M1964 797H1957','teal');

// Footer with a plain explanation of the three visual ideas.
line(64,1450,2015,1450,'#D8E1EC',1.5);
const footer=[
  [65,'01',C.blue,'DÙNG CHUNG TRỌNG SỐ','Một tile phục vụ nhiều yêu cầu độc lập.'],
  [758,'02',C.purple,'GIỮ TRẠNG THÁI RIÊNG','Mỗi yêu cầu có state và lịch sử convolution.'],
  [1450,'03',C.ctrl,'SƠ ĐỒ CHỨC NĂNG','Hình khối không biểu diễn tỉ lệ diện tích chip.']
];
for(const [x,n,color,title,body] of footer){circ(x+22,1503,22,color);txt(x+22,1510,n,17,'#FFF',700,'middle');txt(x+60,1495,title,20,C.ink,700);txt(x+60,1528,body,18,C.muted);}
add('</g></svg>');

// All artwork is native SVG geometry and editable text; no embedded bitmaps.
const svg=parts.join('\n')
  .replace('Transferts SRAM','Truyền dữ liệu SRAM')
  .replace('lecture / écriture','đọc / ghi')
  .replace('Vecteur','Vector')
  .replace('PE et accumulateurs reconfigurables','PE và bộ tích lũy chia theo cấu hình');
const svgPath=path.join(out,'asic_ternary_architecture.svg');
const pngPath=path.join(out,'asic_ternary_architecture.png');
fs.writeFileSync(svgPath,svg,'utf8');
sharp(Buffer.from(svg)).png().toFile(pngPath).then(meta=>console.log(JSON.stringify({svg:svgPath,png:pngPath,width:meta.width,height:meta.height,bytes:fs.statSync(svgPath).size}))).catch(err=>{console.error(err);process.exitCode=1;});
