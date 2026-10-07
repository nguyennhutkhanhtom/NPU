# sigmoid.sv — Sigmoid bằng ROM và nội suy

> **Category: GUIDE. Scope: CURRENT (may also have legacy callers).** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Source guide](../README.md) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng — gọi từ rowwise_op.

**Source:** [sigmoid.sv](<../../../Verilog%20Source%20code/sigmoid.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Input là S16 với F_t=0…24, output gate U16/F15. LUT có 257 mẫu từ −8 đến +8, bước 1/16. Với điểm giữa hai mẫu, khối đọc lần lượt y0 và y1 rồi nội suy bằng fraction 24 bit. Bảng tính sẵn, nên runtime không cần exp. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
X["x_raw S16 + frac_bits"]
    subgraph SIG["sigmoid"]
        COORD["Coordinate S45 + boundary clamp<br/>Index U9 · fraction U24"]
        CTRL["Controller + index/fraction storage"]
        ADDR@{ shape: trap-t, label: "ROM address selector<br/>index or bounded index+1" }
        ROM@{ shape: rect, label: "One shared ROM lookup<hr/>257 × 16 bit · sigmoid_lut.svh" }
        SAMPLES["Sample storage y0 / y1"]
        INTERP["Interpolation pipeline<br/>Slope U10 → product U34 → integer sum U17<br/>RNE uses full integer-sum parity"]
        OUT["Output storage U16/F15"]
    end
    X --> COORD
    COORD --> CTRL
    START["start"] -.-> CTRL
    CTRL -.-> ADDR
    ADDR --> ROM
    ROM --> SAMPLES
    CTRL -.->|"Sample load selects"| SAMPLES
    SAMPLES --> INTERP
    CTRL -->|"fraction"| INTERP
    INTERP --> OUT
    CTRL -.->|"Output enable"| OUT
    OUT --> Y["y_raw U16/F15"]
    CTRL -.-> STATUS["busy / done"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

## Main flow

`IDLE → READ0 → READ1 → SLOPE → MULTIPLY → ADD → ROUND → IDLE`. Index/fraction chốt lúc start; thay x_raw sau đó không đổi kết quả. Product U34 được chốt sau slope U10, rồi chốt tổng nguyên U17 và remainder U24 trước RNE. Parity của toàn tổng giữ ties-to-even đúng. Payload không reset; control reset hủy giao dịch. Ngoài miền LUT dùng mẫu biên; constant case LUT dùng chung simulation/synthesis.

1. Input S16/F_t được đổi thành tọa độ `(16×x_real+0x80)` với 24 fractional bit; −8 ánh xạ index 0x000 và +8 ánh xạ 0x100.
2. Tọa độ ngoài bảng bị clamp. Index/fraction được chốt lúc start, nên thay input sau đó không ảnh hưởng giao dịch.
3. Một cổng ROM được dùng hai chu kỳ: READ0 lấy y0, READ1 lấy mẫu kế y1. Endpoint 0x100 dùng lại cùng mẫu.
4. SLOPE/MULTIPLY/ADD/ROUND chốt slope, product, tổng nguyên/remainder và RNE, trả U16/F15 với parity toàn tổng.
5. `sigmoid_lut.svh` là nguồn ROM duy nhất trong RTL. `sigmoid_257.mem` giữ cùng các giá trị để generator/test đối chiếu, không được load lúc chạy.

**Quy ước RTL.** Tọa độ S45 chứa đủ toàn miền S16/F_t=0…24 với offset 128×2^24; index U9 và fraction U24 giữ nguyên. LUT đơn điệu và chênh hai mẫu kề nhau tối đa 512, nên slope U10 và product U34 đủ, thay cho slope U16/product U40. Tích được zero-extend khi cộng y0<<24 rồi dùng hàm RNE trên toàn tổng; parity và output U16/F15 không đổi.

## Important state / datapath groups

Các đoạn dưới đây bao phủ nguyên văn toàn bộ source hiện tại, theo thứ tự dòng.

### [Dòng 1–34: Giao diện và ROM lookup dùng chung](<../../../Verilog%20Source%20code/sigmoid.sv#L1>)

**Cách hoạt động.** `sigmoid_sample` từ include chứa 257 hằng U16/F15. Selector chọn `index_q` ở READ0 và `index_q+1` ở READ1, trừ endpoint 0x100 dùng lại cùng mẫu. Một lookup tổ hợp dùng chung cho cả hai sample registers. Không cần parameter đường dẫn file hoặc initialize array.

**Tín hiệu chính.** `x_raw`, `frac_bits`, `index_q/index_next`, `fraction_q/fraction_next`, `rom_address/rom_data`, `y0/y1`, `busy/done/y_raw`.

### [Dòng 35–71: Tọa độ và nội suy RNE](<../../../Verilog%20Source%20code/sigmoid.sv#L35>)

**Cách hoạt động.** `grid=(x_raw×2^(28−F_t))+(0x80×2^24)` dùng S45 đưa input lên lưới LUT Q24. Logic clamp bảo đảm index 0…256; phần fraction là U24. `difference` U10 giữ slope lớn nhất 512; product U34 từ difference×fraction_q được zero-extend để cộng với y0×2^24, rồi RNE toàn tổng để xét đúng parity của y0 khi tie.

**Điểm cần đọc kỹ.** Host descriptor giới hạn F_t trong 0…24. Điểm ngoài miền ±8 dùng mẫu biên. Không làm tròn riêng phần delta vì có thể lệch một LSB.

#### Sơ đồ khối phần cứng của nhóm

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
X["x_raw S16 / frac_bits 0…24"] --> COORD["Coordinate conversion S45 + clamp"]
    COORD --> IDX["Index U9 / fraction U24 storage"]
    IDX -.-> ADDR@{ shape: trap-t, label: "Bounded index / index+1 address selector" }
    CTRL["Sample controller"] -.-> ADDR
    ADDR --> ROM@{ shape: rect, label: "One shared ROM lookup<hr/>257 samples × 16 bit" }
    ROM --> SAMPLE["y0 / y1 sample storage"]
    CTRL -.-> SAMPLE
    SAMPLE --> SUB["Monotone adjacent-sample difference U10<br/>0 ≤ y1 − y0 ≤ 512"]
    SUB --> MUL["U10 × U24 interpolation multiplier<br/>Exact product U34"]
    IDX -->|"fraction"| MUL
    MUL --> ADD["Upper product U10 + sample y0<br/>Registered integer sum U17"]
    SAMPLE -->|"y0 zero-extended to U17"| ADD
    MUL --> REM["Registered low product U24<br/>Fractional remainder"]
    REM --> RNE["RNE from remainder<br/>Use entire integer sum parity on ties"]
    ADD --> RNE
    RNE --> Y["U16/F15 output storage"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

### [Dòng 72–106: FSM lấy hai mẫu và chốt output](<../../../Verilog%20Source%20code/sigmoid.sv#L72>)

**Cách hoạt động.** IDLE chốt index/fraction; READ0/READ1 lấy samples; SLOPE/MULTIPLY/ADD chốt từng bước arithmetic. ROUND xuất U16/F15, hạ busy và phát done một clock. Sáu pha pipeline đã được thử reset/cancel/restart; toàn 1.638.400 input ở 25 format giữ kết quả reference. Payload dùng nonblocking assignment và không reset; control về IDLE khi reset.
