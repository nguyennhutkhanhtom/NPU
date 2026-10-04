"""Refresh byte-exact source excerpts while retaining authored explanations.

Existing group boundaries are mapped by line diff. Newly introduced modules
have explicit architectural groups below; review explanations after RTL edits.
Rendering and validation remain separate commands.
"""
from pathlib import Path
from hashlib import sha256
from difflib import SequenceMatcher
from urllib.parse import quote
import html
import json
import re

ROOT = Path(__file__).resolve().parents[2]
GUIDE = ROOT / "docs/source_guide"
RTL = ROOT / "Verilog Source code"

NEW = {
    "quartus_word_ram.sv": (
        "FPGA memory technology binding", "IP duy nhất của Quartus trong graph là altsyncram M10K. Một read và một write dùng chung clock, raw read một cạnh; OLD_DATA khi cùng địa chỉ. Storage/output không reset, không khởi tạo. ASIC thay module này phía sau adapter, giữ nguyên interface và contract.",
        "WR[Write address data enable] --> IP[altsyncram M10K 1R 1W]\n    RD[Read address enable] --> IP\n    CLK[Common clock] --> IP\n    IP --> Q[Raw read after one edge]\n    CONTRACT[OLD_DATA and no storage reset] -.-> IP",
        [(1, "Technology boundary and ports", "Compute/control không instantiate vendor primitive. Client chỉ truy cập qua pipelined_word_ram; địa chỉ phải nhỏ hơn ROWS."),
         (16, "Memory configuration", "Port A write và port B read. Address/read control B chốt CLOCK0; output unregistered giữ raw latency một cạnh. M10K không dùng DSP hay PLL."),
         (30, "Clock and port binding", "Clock enables bypass và các cổng không dùng tie constant. Reset/cancellation thuộc adapter ngoài; memory không có reset.")]),
    "pipelined_word_ram.sv": (
        "Memory technology và response pipeline", "USE_QUARTUS_MEMORY chọn altsyncram cho toàn bank hoặc model SRAM portable chia tile. Hai backend có cùng throughput một read/write mỗi clock; read ba cạnh khi ROWS≤4096, bốn cạnh nếu lớn hơn; write commit cạnh thứ hai. Reset hủy enables/valid và queued write, giữ nội dung và payload. OLD_DATA collision theo request nhận cùng cạnh.",
        "REQ[Read and write requests] --> CAP[Registered addresses data enables]\n    CAP --> IP[FPGA altsyncram whole bank]\n    CAP --> MODEL[ASIC behavioral tiled SRAM model]\n    IP --> RESPONSE[Registered response]\n    MODEL --> RESPONSE\n    RESPONSE --> FINAL[Optional extra edge for rows above 4096]\n    FINAL --> DATA[Identical data valid contract]\n    CAP --> VALID[Read and write validity pipeline]",
        [(1, "Interface and pipeline control", "Valid phải đi cùng dữ liệu. wr_valid xuất hiện khi leaf write thực thi; storage/payload không reset."),
         (33, "FPGA memory IP backend", "Một altsyncram toàn bank, không tạo decoder/mux tile trong compute RTL. Request E1, raw read/write E2, response E3; bank lớn thêm E4. Queued write bị hủy khi reset trước E2."),
         (60, "Portable ASIC behavior model", "Model chia tile 1024 word để giữ contract trước khi có macro ASIC. dont_merge chỉ trong model boundary; grouped response giữ cùng latency với IP.")]),
    "llm_parameter_ram.sv": (
        "Parameter SRAM và host commit", "USE_QUARTUS_MEMORY chọn FPGA IP hoặc model ASIC qua word adapter. Compute read bốn cạnh khi DEPTH≤4096, năm cạnh ở cấu hình24576. Host read thêm một cạnh chọn lane trước frontend ACK. Write ACK chỉ sau leaf commit. Valid/tag pipeline loại response host đã hủy hoặc khác địa chỉ; reset giữ SRAM nhưng hủy queue.",
        "HOST[Host active address and explicit requests] --> BANK[Eight local lane requests]\n    CORE[Compute row request] --> BANK\n    BANK --> SRAM[Technology-selected word banks]\n    SRAM --> ROW[256-bit row after five edges]\n    ROW --> LANE[Registered host lane selection]\n    TAG[Address owner and cancellation tags] --> VALID[Compute and host validity]\n    SRAM --> COMMIT[Write commit acknowledgement]",
        [(1, "Interface and ownership", "Compute và host truy cập độc quyền do top arbitration. Host data/config không phải intermediate graph."),
         (30, "Validity and cancellation", "Host response chỉ hợp lệ khi active, loại read/write và địa chỉ vẫn khớp. ACK write theo wr_valid từ leaf, tránh báo xong trước commit."),
         (51, "Tags and host payload", "Địa chỉ/lane đi cùng latency suy ra theo DEPTH; output host register tách tile reduction khỏi pin host_rdata."),
         (61, "Local lane banks", "Tám lane U32 có request registers riêng, rồi technology adapter. Nội dung và payload không reset; reset chỉ hủy enables/valid.")]),
    "scale_compose.sv": (
        "Ghép scale bằng lựa chọn shift song song", "Ghép factor_m/factor_r với quant_d thành result_m U24 và result_r U6. Chốt tích U48, đánh giá song song 48 threshold hằng, chọn shift lớn nhất còn vừa U24, rồi thực hiện một divider U48/U25 và RNE. Không còn vòng decrement candidate.",
        "IN[U24 factors and U6 base shift] --> MUL[Registered U48 product]\n    MUL --> FIT[48 constant threshold comparisons]\n    FIT --> SELECT[Prefix boundary and signed target shift]\n    SELECT --> SHIFT[Registered numerator and denominator]\n    SHIFT --> DIV[Divider U48 by U25]\n    DIV --> RNE[Remainder RNE and range checks]\n    SELECT --> OUT[Result M and r]\n    RNE --> OUT",
        [(1, "Interface and state", "Valid factors dùng factor_r≤47 và quant_d khác zero. factor_m=0 trả zero hợp lệ. Control dùng MULTIPLY, SELECT_SHIFT và SHIFT trước DIV_START."),
         (30, "Parallel threshold selection", "positive_fit là prefix ones. COEFFICIENT_LIMIT=0x7EFF_FFC0_8000; strict inequality loại tie U24_max+1/2. Boundary encoder chọn shift mà không tạo chuỗi decrement."),
         (54, "Registered multiplication and shift", "Multiply không asynchronous reset; control bảo đảm capture trước use. Shift âm tối thiểu −2, nên denominator không vượt U25."),
         (68, "Divider", "Một lần chia 48 bước. Quotient U48, remainder U25; twice_rem U26 và rounded U49 giữ carry để RNE ties-even."),
         (77, "Launch and selection control", "Target r=base_r+selected_shift. Nếu target>47, clamp r về47 và điều chỉnh shift; target âm hoặc input sai báo format_error."),
         (117, "Result and completion", "DIV_WAIT kiểm tra zero, underflow và range; kết quả vượt U24 không thể xuất hiện khi selector đúng. Unit regression ghi compose_max_clocks=54.")]),
    "banked_word_ram.sv": (
        "SRAM tiles và mux đọc", "Một read port đồng bộ và một write port độc lập, old-data khi cùng địa chỉ. Mỗi tile tối đa 1024 word; read_tile_q giữ tag để mux output đúng tile. Nội dung và output không reset; client dùng valid riêng. ASIC macro hoặc Quartus IP có thể thay sram_word_tile sau cùng hợp đồng.",
        "REQ[Read and write requests] --> TILE[1024-word leaf SRAM]\n    REQ --> TAG[Registered tile selection]\n    TILE --> MUX[One-hot data reduction]\n    TAG --> MUX\n    MUX --> OUT[Read data after one edge]",
        [(1, "Leaf SRAM", "Hai nonblocking assignment trả dữ liệu trước write khi read/write cùng địa chỉ. Không initialize hoặc reset memory."),
         (21, "Bank organization", "Chia ROWS thành tile; tile cuối có thể ngắn hơn. ADDR_W phải đủ cho ROWS và client chỉ phát địa chỉ hợp lệ."),
         (34, "Tile decoding", "High address bits chọn tile, low 10 bits chọn word; tag đọc được chốt cùng cạnh với SRAM."),
         (48, "Read output", "OR của các output được mask bằng tag one-hot. Latency logic là một cạnh; mux cuối vẫn phải đáp ứng STA.")]),
    "llm_bank_ram.sv": (
        "SRAM lane-masked cho graph", "32 lane S24 tạo row 768 bit. USE_QUARTUS_MEMORY chọn FPGA IP hoặc model ASIC qua word adapter. Request qua group bốn lane, lane register và adapter register trước storage; read valid năm cạnh với ROWS≤4096, write commit ở cạnh thứ tư. wr_busy buộc operator drain trước completion. Reset hủy queue/valid, giữ storage/payload.",
        "REQ[Shared row requests] --> GROUP[Requests per four lanes]\n    MASK[Lane write mask] --> GROUP\n    GROUP --> LOCAL[Per-lane request registers]\n    LOCAL --> BANK[Technology-selected word banks]\n    BANK --> DATA[768-bit row after five edges]\n    MASK --> DRAIN[Four-stage write pending and wr_busy]",
        [(1, "Interface and write pending", "Client dùng rd_valid; operator phải chờ wr_busy hạ trước báo done. Latency bao gồm group, lane và tile stages."),
         (25, "Group request distribution", "Địa chỉ/data payload chốt không enable mux. SRAM-only dont_merge giữ locality; read/write enables reset để hủy queued requests."),
         (48, "Lane banks and response", "Leaf old-data collision theo cùng accepted cycle. Lane-valid có cùng latency; output dùng lane0 valid để xác nhận cả row.")]),
    "llm_math.sv": (
        "SIMD byte-product pipeline và reduction", "32 tích S24×S32 tạo S56 bằng partial products byte: ba byte thấp U8, byte cao S8. Partial S33, cặp S41, ghép product S56 rồi cây cộng cân bằng tới S61. Done chín cạnh sau cạnh nhận start. Chỉ dùng logic cells; input chốt khi start và không busy. Payload không reset; pipeline valid reset hủy transaction.",
        "IN[32 pairs S24 and S32] --> CAP[Input registers]\n    CAP --> MUL[Four byte products per lane S33]\n    MUL --> PAIR[Registered pair sums S41]\n    PAIR --> PRODUCT[Registered product S56]\n    PRODUCT --> TREE[Five registered reduction levels]\n    TREE --> SUM[Sum S61]\n    CTRL[10-bit validity pipeline] -.-> CAP\n    CTRL -.-> TREE\n    CTRL --> DONE[busy and done after nine clocks]",
        [(1, "Interface and payload", "Dải product và sum đủ cho signed extremes; payload chỉ hợp lệ sau transaction đã hoàn thành."),
         (12, "Widths and control pipeline", "busy là OR valid; request trong busy bị bỏ qua. done tại valid_q[9], chín cạnh sau cạnh nhận start. Signed casts giữ sign extension."),
         (27, "Operand capture and byte multiplication", "Các byte thấp có leadingzero trước signed cast; byte cao giữ dấu. Partial products giữ đủ S33 trước shift."),
         (39, "Pair and product reconstruction", "Hai pair dùng shift8/S41; product ghép shift16/S56. Không truncate intermediate trước khi dấu và độ rộng đã đúng."),
         (48, "Balanced reduction", "Mỗi level tăng một bit; S61 chứa tổng32tích. Numeric expectations S128 giữ nguyên, chỉ latency/reset coverage đổi7→9.")]),
    "llm_pkg.sv": (
        "Layout, saturation và sampler", "Hằng số graph cố định NanoFable, địa chỉ parameter rows, S24 saturation, sign extension và xorshift32. LUT exp/Gumbel được include thành logic portable.",
        "LAYOUT[Fixed graph and SRAM offsets] --> CTRL[llm_soc]\n    SAT[S24 saturation and S56 extension] --> MATH[Numeric datapath]\n    EXP[Exponential LUT] --> ATT[Softmax]\n    RANDOM[Xorshift32 and Gumbel LUT] --> HEAD[Token selection]",
        [(1, "Layout constants", "PARAM_ROWS=24576; địa chỉ tính theo row 256 bit. EMB_SCALE, matrix metadata, gains và RoPE nằm sau trọng số."),
         (10, "Numeric helpers", "Saturation ở biên ±2^23; llm_extend56 giữ sign của SIMD product trước RNE64."),
         (20, "Sampler", "Xorshift32 deterministic, seed zero được controller thay bằng one. Temperature zero cho greedy argmax.")]),
    "llm_soc.sv": (
        "Autonomous autoregressive graph", "Host chỉ cấp parameter words, prompt IDs và cấu hình. Graph FSM chạy prefill và decode qua bốn transformer block rồi head; operator FSM điều phối SRAM, SIMD, sqrt, divide và sigmoid. Xem full_rtl_language.md cho memory map và numeric contracts.",
        "HOST[32-bit registered host] --> PARAM[Parameter SRAM]\n    HOST --> TOKENS[Prompt and generation config]\n    TOKENS --> GRAPH[Graph and operator FSMs]\n    GRAPH --> SIMD[32-lane math plus sqrt divide sigmoid]\n    PARAM --> SIMD\n    VECTOR[Vector SRAM] <--> SIMD\n    KV[KV cache SRAM] <--> SIMD\n    SIMD --> GRAPH\n    GRAPH --> OUTPUT[RTL-selected output token buffer]",
        [(1, "Interface and FSM state", "graph_t biểu diễn toàn graph; op_t biểu diễn micro-operations và return states. Fixed graph không có instruction CPU trong execution path."),
         (75, "Host and parameter SRAM", "Request chốt trước decode, response giữ đến host_en hạ. Host write bị chặn trong core_running. Reset chỉ xóa control/config, không clear parameter SRAM."),
         (153, "Compute memories and arithmetic", "Vector/KV và parameter compute read năm cạnh ở cấu hình hiện tại; host thêm một cạnh chọn lane. Shared SIMD có transaction valid; sqrt/div/sigmoid dùng busy/done."),
         (206, "Request helpers and graph sequencing", "Registered addresses xuất hiện trước enable. Graph xử lý mọi prompt position, bốn layer mỗi position, rồi chọn token và quay lại embedding."),
         (295, "Per-lane datapath", "Constant slices giúp synthesis thấy từng lane. RNE và saturation dùng helper portable; signedness cần tường minh cho bit slices."),
         (381, "Operator launch and memory handshakes", "O_IDLE chọn source/destination theo graph; request/wait states đợi SRAM hoặc arithmetic response; O_WRITE ghi lane mask."),
         (434, "Embedding and ternary linears", "Embedding S8×U24/F24 tới S24/F16. Linear accumulate S39, multiply coefficient rồi RNE24, write từng output lane."),
         (487, "Affine RMSNorm and RoPE", "Mean-square, epsilon, floor sqrt, rounded reciprocal và signed gains. RoPE ghép hai nửa 16 channel bằng cos/sin S16/F15."),
         (533, "KV and causal attention", "Địa chỉ cache layer/position/KV/head. Softmax trừ max, exp LUT interpolation, weighted values và rounded divide."),
         (616, "Residual and SwiGLU", "Residual saturates S24; gate activation dùng sigmoid S16/F12, rồi multiply up branch và down projection."),
         (644, "Language head and sampling", "Tied S8 embedding matrix, per-row scale, Gumbel temperature và stable lowest eligible token ID. EOS masked theo min_new; không nhận logits từ CPU.")]),
}

def save(path, text):
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")

manifest = json.loads((GUIDE / "source_manifest.json").read_text(encoding="utf-8"))
entries = {entry["file"]: entry for entry in manifest["files"]}
for source in sorted(RTL.iterdir()):
    if source.suffix not in {".sv", ".v", ".svh", ".mem"}:
        continue
    raw = source.read_bytes()
    try:
        lines = raw.decode("utf-8-sig").splitlines()
    except UnicodeDecodeError:
        lines = raw.decode("gb18030", errors="replace").splitlines()
    digest = sha256(raw).hexdigest()
    document = GUIDE / "blocks" / (source.name + ".md")
    entry = entries.get(source.name)
    if entry and source.name not in {'scale_compose.sv', 'llm_bank_ram.sv', 'llm_parameter_ram.sv', 'pipelined_word_ram.sv', 'quartus_word_ram.sv', 'llm_math.sv'}:
        doc = document.read_text(encoding="utf-8")
        if source.suffix in {".sv", ".v"}:
            pattern = re.compile(r"### \[Dòng (\d+)–(\d+): (.*?)\]\(<([^>]+)>\)\n\n<!-- source-range:\d+:\d+ -->\n```systemverilog\n(.*?)\n```", re.S)
            groups = list(pattern.finditer(doc))
            old = [line for group in groups for line in group[5].splitlines()]
            if not groups:
                raise ValueError(f"No excerpt groups: {source.name}")
            boundary = {0: 0, len(old): len(lines)}
            for tag, a, b, c, d in SequenceMatcher(None, old, lines, autojunk=False).get_opcodes():
                for point in range(a, b + 1):
                    boundary[point] = c + ((point - a) * (d - c) // (b - a) if b > a else 0)
            ends = [0] + [boundary[int(g[2])] for g in groups[:-1]] + [len(lines)]
            replacements = []
            for i, group in enumerate(groups):
                start, end = ends[i] + 1, ends[i + 1]
                if end < start:
                    raise ValueError(f"Empty mapped group: {source.name}:{group[1]}")
                link = re.sub(r"#L\d+$", f"#L{start}", group[4])
                excerpt = "\n".join(lines[start - 1:end])
                replacements.append((group.start(), group.end(), f"### [Dòng {start}–{end}: {group[3]}](<{link}>)\n\n<!-- source-range:{start}:{end} -->\n```systemverilog\n{excerpt}\n```"))
            for start, end, text in reversed(replacements):
                doc = doc[:start] + text + doc[end:]
            entry["groups"] = len(groups)
        doc = re.sub(r"\*\*Số dòng:\*\* \d+\. \*\*SHA-256:\*\* `[a-f0-9]+`", f"**Số dòng:** {len(lines)}. **SHA-256:** `{digest}`", doc)
        save(document, doc)
    else:
        link = "../../../Verilog%20Source%20code/" + quote(source.name)
        if source.suffix in {".sv", ".v"}:
            title, summary, diagram, groups = NEW[source.name]
            doc = f"# {source.name} — {title}\n\n[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục](README.md)\n\n**Source:** [{source.name}](<{link}>). **Số dòng:** {len(lines)}. **SHA-256:** `{digest}`.\n\n## Khối này làm gì?\n\n{summary}\n\n## Sơ đồ kiến trúc\n\n```mermaid\nflowchart TB\n    {diagram}\n```\n\n## Cách hoạt động chi tiết\n\n{summary}\n\n## Các nhóm logic trong source\n\n"
            for index, (start, title, explanation) in enumerate(groups):
                end = groups[index + 1][0] - 1 if index + 1 < len(groups) else len(lines)
                excerpt = "\n".join(lines[start - 1:end])
                doc += f"### [Dòng {start}–{end}: {title}](<{link}#L{start}>)\n\n<!-- source-range:{start}:{end} -->\n```systemverilog\n{excerpt}\n```\n\n{explanation}\n\n"
            entry = {"groups": len(groups)}
        else:
            title = "Exp Q24: exp(-index/16)" if "exp" in source.name else "Gumbel S24/F16: -ln(-ln((index+0.5)/256))"
            doc = f"# {source.name} — {title}\n\n[Source guide](../README.md) · [Mục lục](README.md)\n\n**Source:** [{source.name}](<{link}>). **Số dòng:** {len(lines)}. **SHA-256:** `{digest}`.\n\nGenerator: [generate_tables.py](../../../tools/llm/generate_tables.py). Math units independently verify every numeric entry using real exp/log.\n\n| Dòng | Code gốc | Giải thích |\n|---|---|---|\n"
            for n, line in enumerate(lines, 1):
                meaning = "Entry được làm tròn từ công thức ở tiêu đề; default bảo vệ chỉ số ngoài miền." if ":" in line else "Khai báo hoặc điều khiển function LUT portable."
                doc += f"| [{n}](<{link}#L{n}>) | <code>{html.escape(line or chr(160))}</code> | {meaning} |\n"
            entry = {}
        entry.update(file=source.name, path=f"Verilog Source code/{source.name}", document=f"blocks/{source.name}.md")
        entries[source.name] = entry
        save(document, doc)
    entry.update(sha256=digest, lines=len(lines))
manifest["files"] = list(entries.values())
save(GUIDE / "source_manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
index_path = GUIDE / 'blocks/README.md'
index = index_path.read_text(encoding='utf-8')
for name, entry in entries.items():
    row_pattern = re.compile(r'^\| \[' + re.escape(name) + r'\].*$', re.M)
    found = row_pattern.search(index)
    if found:
        columns = found[0].split('|')
        columns[-3] = ' ' + str(entry.get('groups', '—')) + ' '
        columns[-2] = ' ' + str(entry['lines']) + ' '
        index = index[:found.start()] + '|'.join(columns) + index[found.end():]
    else:
        title = NEW[name][0] if name in NEW else 'LUT portable của graph'
        row = f"| [{name}]({name}.md) | {title} | Full RTL graph | {entry.get('groups', '—')} | {entry['lines']} |\n"
        separator = '|---|---|---|---:|---:|\n'
        index = index.replace(separator, separator + row, 1)
save(index_path, index)
print(f"SOURCE_GUIDE_REFRESH: files={len(entries)}; authored explanations require review")
