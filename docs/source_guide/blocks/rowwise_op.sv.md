# rowwise_op.sv — ALU vector nhỏ và cập nhật state

> **Category: GUIDE. Scope: LEGACY.** RTL is authoritative; diagrams are preserved from the existing guide.
[Tài liệu](../../README.md) → [Hierarchy RTL](<../legacy/README.md>) → [Mục lục từng file](README.md)

**Trạng thái:** Đang dùng — datapath rowwise.

**Source:** [rowwise_op.sv](<../../../Verilog%20Source%20code/rowwise_op.sv>).

## At a glance

| Item | Description |
|---|---|
| Responsibility | Khối chốt tối đa 16 phần tử trong một word rồi xử lý các batch lần lượt. ADD/SUB/MUL/RELU xử lý hai phần tử qua năm pha; REC xử lý một state bằng hai tích song song qua cùng năm pha. SIG dùng một instance sigmoid. Các register tách chọn lane, multiplier, raw arithmetic, RNE và saturation/pack; hai multiplier 16×16 vẫn dùng chung cho MUL và REC. |

## Sơ đồ kiến trúc tổng quan

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
IN["A / B / old state words 256 bit<br/>Format + fractional bits + valid_elems"]
    subgraph CORE["rowwise_op — registered datapath"]
        CTRL["Opcode controller + element index<br/>LOAD / MULTIPLY / RAW / ROUND / PACK"]
        BUF["Input word buffers"]
        LANE@{ shape: trap-t, label: "Lane and multiplier operand selectors<hr/>Magnitude / sign / gate complement" }
        LREG["Lane registers<br/>2 × S17 for A and B"]
        MREG["Magnitude + sign registers<br/>2 × U16 pairs"]
        MUL["Two shared unsigned<br/>16 × 16 multipliers"]
        PREG["Product registers<br/>2 × U32"]
        SIGN["Product sign correction<br/>REC sum S33"]
        AS["ADD / SUB / ReLU<br/>Extended arithmetic"]
        RAW@{ shape: trap-t, label: "Raw-value selectors<hr/>MUL / REC / ADD / SUB / ReLU" }
        RREG["Raw result registers<br/>2 × S33"]
        RNE["Two shared scale / RNE paths<br/>REC shift=15"]
        SREG["Rounded result registers<br/>2 × S64"]
        SAT["S16 / U16 saturation<br/>Tail and result position selection"]
        SQ["Sigmoid input register S16"]
        SIG["sigmoid<br/>ROM + interpolation"]
        RES@{ shape: trap-t, label: "Result selector<hr/>Arithmetic PACK / SIG done" }
        RBUF["Result buffer 256 bit"]
    end
    IN --> BUF
    IN -.-> CTRL
    BUF --> LANE
    CTRL -.->|"Index / opcode"| LANE
    LANE --> LREG
    LANE --> MREG
    LANE --> SQ
    MREG --> MUL
    MUL --> PREG
    PREG --> SIGN
    LREG --> AS
    AS --> RAW
    SIGN --> RAW
    RAW --> RREG
    RREG --> RNE
    CTRL -.->|"Latched shift"| RNE
    RNE --> SREG
    SREG --> SAT
    CTRL -.->|"Index / valid lanes"| SAT
    SAT --> RES
    SQ --> SIG
    SIG --> RES
    CTRL -.->|"Enable / state"| RES
    RES --> RBUF
    RBUF --> OUT["result_word 256 bit"]
    CTRL -.-> STATUS["busy / done / overflow / format_error"]
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

Nét liền là dữ liệu, nét đứt là control. MUX dùng hình thang thu hẹp về ngõ ra. Các hộp mang tên register là ranh giới clock thực trong datapath; các batch vẫn chạy tuần tự, không nhận một batch mới mỗi clock. Sơ đồ mô tả phần cứng, không phải pipeline instruction CPU.

## Main flow

1. Cạnh start hợp lệ chốt opcode, word, format, số phần tử và shift signed 7 bit. Start khi busy bị bỏ qua; input ngoài thay đổi không làm đổi giao dịch đã chốt.
2. LOAD chọn lane, kiểm tra gate/format và chốt magnitude/sign cho multiplier. `sig_x_q` cũng được chốt tại đây.
3. MULTIPLY chốt hai tích magnitude U32. RAW khôi phục sign và chọn ADD/SUB, ReLU, hai product MUL hoặc tổng REC S33.
4. ROUND sign-extend raw S33 rồi rescale/RNE qua hai đường dùng chung. REC đưa cả tổng vào lane 0 với shift 15, chỉ làm tròn một lần.
5. PACK saturation, ghi hai lane arithmetic hoặc một state REC, gom overflow/format_error và tiến index. Padding ngoài `valid_elems` giữ zero.
6. SIG đi từ LOAD sang SIG_WAIT, chờ sigmoid done rồi ghi một lane. Không dùng các payload RAW/ROUND của giao dịch trước.

| Phép toán, word có n phần tử hữu ích | Chu kỳ từ accepted start đến done |
|---|---:|
| ADD/SUB/MUL/RELU | `5 × ceil(n/2)` |
| REC | `5 × n` |
| SIG | `6 × n` |

Payload magnitude/product/raw/rounded không async reset; FSM chỉ consume sau đúng enable ghi. Reset xóa trạng thái giao dịch, result/status và ngăn payload cũ đi tới output. [Timing report](../../verification/timing/README.md) ghi critical path, constraint và ảnh hưởng chu kỳ model.

**Quy ước RTL.** Magnitude U16 giữ được abs(S16 min) và gate `0x8000`. RAW S33 chứa tổng hai tích REC; rescale dùng S64 để giữ shift trái tối đa 24 bit. Có đúng hai multiplier trong datapath này; chia sẻ hai multiplier toàn chip vẫn là mục tiêu kiến trúc riêng.

## Important state / datapath groups

Mỗi nhóm giữ nguyên source và phạm vi dòng để đối chiếu. Giải thích tập trung vào register boundary, enable và số học.

### [Dòng 1–39: Giao diện, controller và sigmoid](<../../../Verilog%20Source%20code/rowwise_op.sv#L1>)

**Mục đích.** Opcode và FSM xác định pha. Sigmoid nhận sig_x_q đã chốt tại LOAD; sig_start chỉ hợp lệ ở SIG_WAIT khi core con sẵn sàng.

**Cách hoạt động.** source_a_q/source_b_q/state_word_q giữ giao dịch, result_shift_q S7 giữ shift và operation_q giữ opcode.

### [Dòng 40–68: Payload số học và cờ](<../../../Verilog%20Source%20code/rowwise_op.sv#L40>)

**Mục đích.** Hai lane S17 phân biệt S16 có dấu với gate U16/F15. Magnitude U16, product U32, raw S33 và scaled S64 là các ranh giới clock riêng.

**Cách hoạt động.** product_negative_q khôi phục dấu sau multiplier; lane_valid_q và source_format_error_q đi cùng batch, không đọc lại input ngoài.

### [Dòng 69–98: Chọn lane, magnitude và tổng REC](<../../../Verilog%20Source%20code/rowwise_op.sv#L69>)

**Mục đích.** MUL chọn hai cặp A/B; REC chọn H×F và C×(0x8000−F). Magnitude 16 bit cộng sign flag cho phép dùng chung hai multiplier. Sign correction đọc product đã chốt; tổng REC giữ S33.

**Cách hoạt động.** Các kết quả tổ hợp chỉ được consume ở LOAD hoặc RAW tương ứng. Gate raw lớn hơn 0x8000 báo format_error; ReLU có quy tắc signed riêng.

### [Dòng 99–140: Chốt operand, product, raw result và RNE](<../../../Verilog%20Source%20code/rowwise_op.sv#L99>)

**Mục đích.** Clocked payload block không có reset asynchronous. LOAD chốt lane/magnitude/sign; MULTIPLY chốt tích; RAW tạo S33; ROUND chốt scale_shift64 của toàn raw value.

**Cách hoạt động.** rst_n và pha FSM là validity của payload. Mỗi đường đến PACK đi qua mọi capture cần thiết; reset hủy chuỗi, start mới ghi lại payload trước khi dùng.

#### Sơ đồ khối phần cứng của nhóm

```mermaid
%%{init: {"theme":"base","fontFamily":"Arial, sans-serif","themeVariables":{"fontSize":"24px","primaryColor":"#ffffff","primaryTextColor":"#000000","primaryBorderColor":"#000000","secondaryColor":"#ffffff","tertiaryColor":"#ffffff","lineColor":"#000000","textColor":"#000000","mainBkg":"#ffffff","nodeBorder":"#000000","clusterBkg":"#ffffff","clusterBorder":"#000000","edgeLabelBackground":"#ffffff"},"flowchart":{"htmlLabels":true,"useMaxWidth":false,"nodeSpacing":32,"rankSpacing":48,"curve":"linear","subGraphTitleMargin":{"top":16,"bottom":30}}}}%%
flowchart TB
    SELECT["Lane selection + magnitude / sign"] --> INREG["LOAD registers<br/>Magnitude U16 pairs + sign + lane S17"]
    INREG --> MUL["2 shared unsigned 16 × 16 multipliers"]
    MUL --> PREG["MULTIPLY registers<br/>2 × U32"]
    PREG --> RAW["Sign correction / REC S33 sum<br/>Raw operation selection"]
    INREG --> RAW
    RAW --> RREG["RAW registers<br/>2 × S33"]
    RREG --> RNE["Shared scale_shift64 / RNE"]
    RNE --> SREG["ROUND registers<br/>2 × S64"]
    SREG --> PACK["Saturation / tail / pack<br/>Result register write at PACK"]
    OP["Latched opcode / shift"] -.-> RAW
    OP -.-> RNE
    CTRL["FSM phase enables"] -.-> INREG
    CTRL -.-> PREG
    CTRL -.-> RREG
    CTRL -.-> SREG
    CTRL -.-> PACK
    classDef default fill:white,stroke:black,color:black,font-size:24px;
    linkStyle default stroke:black,color:black;
```

### [Dòng 141–172: Saturation, tail và pack](<../../../Verilog%20Source%20code/rowwise_op.sv#L141>)

**Mục đích.** Hai rounded result được clamp S16 hoặc U16/F15. Chỉ lane_valid mới ghi. SIG chọn sig_y; REC chỉ ghi lane 0 sau RNE của tổng.

**Cách hoạt động.** result_buffer_next mặc định giữ buffer hiện tại, lane_overflow được gom. Tail không được ghi và buffer khởi tạo zero ở start.

### [Dòng 173–191: Reset control và output](<../../../Verilog%20Source%20code/rowwise_op.sv#L173>)

**Mục đích.** Reset đưa FSM về IDLE, busy/done/error/overflow về zero và xóa result/control. Payload số học nằm ở block clocked riêng.

**Cách hoạt động.** Không cần reset payload để bảo đảm output kiến trúc sạch: IDLE không consume và giao dịch mới phải qua LOAD/MULTIPLY/RAW/ROUND.

### [Dòng 192–215: Nhận start và từ chối cấu hình](<../../../Verilog%20Source%20code/rowwise_op.sv#L192>)

**Mục đích.** Start chỉ nhận khi !busy. Chốt format, valid_elems, opcode và shift một lần; reset index/buffer/cờ. Length=0/>16, F_t>24 hoặc opcode lạ kết thúc ngay với format_error.

**Cách hoạt động.** Shift của REC cố định 15; MUL dùng F_A+F_B−F_dst; ADD/SUB/ReLU dùng F_A−F_dst. Dải signed 7 bit đủ các format được phép.

### [Dòng 216–232: Tiến pha và handshake SIG](<../../../Verilog%20Source%20code/rowwise_op.sv#L216>)

**Mục đích.** LOAD chọn SIG_WAIT hoặc MULTIPLY. Arithmetic đi qua RAW và ROUND trước PACK. SIG chỉ ghi khi sig_done, xong lane cuối thì pulse done, nếu chưa xong quay lại LOAD.

**Cách hoạt động.** sig_x_q giữ ổn định khi sigmoid busy. LOAD tận dụng khoảng trống done/start giữa các lane; latency SIG tăng một clock mỗi word so với bản trước.

### [Dòng 233–248: PACK, gom cờ và kết thúc](<../../../Verilog%20Source%20code/rowwise_op.sv#L233>)

**Mục đích.** PACK chốt result, OR overflow/error và kết thúc khi hết lane hoặc có format_error. REC tăng index một, các phép arithmetic khác tăng hai rồi quay về LOAD.

**Cách hoạt động.** Mỗi batch arithmetic cần năm clock; batch kế tiếp chỉ bắt đầu sau PACK. Dispatcher chờ done, nên số chu kỳ mới không đổi ISA hoặc memory contract.
