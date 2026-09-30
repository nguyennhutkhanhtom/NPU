# Mô hình ternary nhỏ để demo ASIC inference

**Cập nhật RTL ngày 29/09/2026:** project chính đã chuyển sang v2 và qua regression số học bằng tensor tổng hợp, bao gồm LUT và NORM→TMATMUL. Xem [báo cáo tích hợp](<implementation_review.md>). Việc này chưa xác nhận inference của một checkpoint hoàn chỉnh trong bảng model bên dưới.

Ngày kiểm tra nguồn: 28/09/2026. Tài liệu này bổ sung cho [đề xuất độ rộng bit và SRAM](<architecture.md>). Mục tiêu là chạy trọn mô hình trên một core nhỏ: 32 phần tử xử lý (PE), activation INT8, weight ternary mã hóa bằng 2 bit, accumulator 18 bit (ACC18), K≤512, parameter SRAM 32 KiB và workspace SRAM 8 KiB. Ở đây, K là số phần tử trong một phép dot product; S16/S32 là số nguyên có dấu rộng 16/32 bit. NORM + QUANT gồm chuẩn hóa RMS rồi lượng tử hóa activation sang INT8. Một mô hình chạy được trên máy tính chưa chắc chạy được trọn vẹn trên ASIC này.

**Phạm vi sau yêu cầu mới nhất:** giả định model đã train; NPU chỉ chạy inference. Mục tiêu ứng dụng là model ngôn ngữ nhỏ có thể sinh câu ngắn. MLP ternary 256→64→32→10 và Seq64 là các bài kiểm tra phần cứng bổ trợ. Các mục về QAT bên dưới mô tả nguồn gốc/cách tạo model, không phải yêu cầu thêm khối training vào NPU hoặc bắt buộc train lại một checkpoint đã tương thích.

**Giữ 32 PE và format của cấu hình cơ sở.** Số PE quyết định mức song song, không quyết định khả năng ngôn ngữ hay trực tiếp quyết định bit-width. Model đã train vẫn cần được kiểm tra graph, operator, K, memory và export sang đúng quy tắc số học của ASIC. Cột tình trạng weight bên dưới ghi lại mức kiểm chứng thực tế; giả định đã train dùng cho đánh giá phần cứng không thay thế việc xác minh checkpoint.

| Khối / dữ liệu | Format giữ sau rà soát | Khi nào mới cần đổi? |
|---|---|---|
| Activation vào core / weight | **S8 / ternary 2 bit** | Checkpoint không phù hợp với quantization này; phải đánh giá chuyển đổi trước |
| Ternary accumulator | **S18, K≤512** | K≤1024 cần S19; K≤2048 cần S20; chia thành các lượt 32 PE không giảm yêu cầu này |
| State, residual, embedding của Char32 | **S16 với scale riêng** | Kết quả đối chiếu checkpoint cho thấy range hoặc độ chính xác không đủ |
| NORM + QUANT | **S16→S8**; ΣX² **U40**, scratch **S24/F16**, mean-square/epsilon **U64** | K tăng hoặc checkpoint có norm khác; cần xem lại cả intermediate và scratch memory |
| Gate / cập nhật state | **U16/F15**; tích **S32**, tổng **S33→S16** | Kiểm tra sai số chuỗi yêu cầu precision khác; không đổi chỉ vì model đã train |
| Bias / logits | **S32**; logits cùng scale để argmax | Exporter xác định range hoặc sai số vượt khả năng hiện tại |
| Token ID | **U8 cho Char32 với 128 ký tự** | Với V=4096: tối thiểu U12, đề xuất lưu U16; output index U12 và output-count U13 |
| SRAM | **Word 256 bit; parameter 32 KiB + workspace 8 KiB** | Model không vừa: tính lại depth/bank, địa chỉ và lịch nạp; không nhất thiết tăng word width |

Các width chi tiết cho từng module, tích trung gian và trường hợp mở rộng nằm trong [bảng bit của thiết kế](<architecture.md#bảng-bit-cho-từng-khối>). `F16`/`F15` trong ký hiệu trên là số bit phần lẻ, không phải floating-point.

## Chọn mô hình theo mục đích demo

| Ứng viên | Tình trạng weight | Dung lượng ước tính trên ASIC | Cách dùng |
|---|---|---|---|
| **FCMNIST ternary 256→64→32→10**, dựa trên [mã BitNetMCU](https://github.com/cpldcpu/BitNetMCU/blob/main/models.py) | Có mã huấn luyện; chưa xác minh được checkpoint đã huấn luyện đúng cấu hình này | 18.752 weight; **5.440 B** sau padding từng hàng. Dự phòng cả bias và scale: **5.876 B**, chưa kể metadata khác | Kiểm tra NORM + QUANT, phép nhân ternary và phân loại ảnh |
| **BitNetMCU Binary-MNIST width160_160_160** trong [modeldata](https://github.com/cpldcpu/BitNetMCU/tree/main/modeldata) | Có tệp `.pth` công khai; chưa tải hoặc kiểm tra nội dung | Nếu kích thước là 256→160→160→160→10: 93.760 weight, **31.360 B** khi đóng gói 2 bit theo hàng; còn **1.408 B** cho metadata | **Kiểm tra core với weight có sẵn:** weight binary dùng được trên PE ternary, nhưng chưa kiểm tra được mã 0 |
| **Tiny-MLGRU-Seq64** | Kiến trúc đề xuất; chưa xác minh checkpoint | Dự phòng **11.904 B** cho tham số; state 128 B | Kiểm tra NORM + QUANT, sigmoid, SiLU và phép cập nhật state |
| **Tiny-Char-MLGRU32** | Kiến trúc đề xuất; chưa xác minh checkpoint | Dự phòng **25.504 B** gồm embedding S16; state 64 B | Demo inference sinh ký tự trong bộ 128 ký tự ASCII; chưa có số liệu chất lượng hội thoại |
| **[NanoFable-1M-ternary](https://huggingface.co/adrahmana/NanoFable-1M-ternary)** | Có tệp `safetensors` và `.tpack`; khoảng 1,4 triệu tham số | Tệp nén khoảng **1,16 MiB**, lớn gấp khoảng **37 lần** parameter SRAM | Có thể thử trên máy tính; toàn mô hình còn cần attention và các thành phần ngoài core đề xuất |

Dung lượng của ba mô hình đề xuất được tính từ kích thước các tầng và cách xếp weight vào SRAM 256 bit; đây chưa phải kích thước của tệp xuất thực tế. Tên gọi “2 bit” cũng không đồng nghĩa với ternary: `2bitsym` của BitNetMCU có bốn mức, còn weight ternary chỉ có {-1, 0, +1}. Xem [mã lượng tử hóa](https://github.com/cpldcpu/BitNetMCU/blob/main/BitNetMCU.py). Mô hình [MMfreeLM-370M](https://github.com/ridgerchu/matmulfreellm) của tác giả bài báo quá lớn cho SRAM này; dùng làm tài liệu tham chiếu MLGRU/GLU.

## Demo kiểm tra core: FCMNIST ternary

FCMNIST cho phép đặt số nút của từng hidden layer và bỏ hidden layer thứ ba khi `network_width3=0`. Cấu hình khởi tạo trong mã nguồn:

```python
from models import FCMNIST

model = FCMNIST(
    network_width1=64,
    network_width2=32,
    network_width3=0,
    QuantType="Ternary",
    WScale="PerTensor",
    NormType="RMS",
    num_classes=10,
)
```

Đoạn mã trên chỉ tạo mô hình để huấn luyện; nó không tải weight đã huấn luyện. Tệp [trainingparameters.yaml](https://github.com/cpldcpu/BitNetMCU/blob/main/trainingparameters.yaml) hiện mặc định chọn CNN và `4bitsym`. Để huấn luyện MLP ternary, cần đặt `model: FCMNIST`, `QuantType: Ternary` và ba độ rộng 64/32/0.

Với giả định checkpoint đã train, bắt đầu từ việc load weight, xác nhận kiến trúc và export thông số lượng tử hóa. Chỉ cân nhắc calibration hoặc QAT/fine-tune nếu kết quả chuyển đổi không đạt yêu cầu; training không nằm trong datapath hay lịch chạy của NPU.

| Tầng | K→N | Số weight | Weight 2 bit chưa padding | SRAM sau padding theo word 256 bit | Lượt tính với 32 PE |
|---|---:|---:|---:|---:|---:|
| Ẩn 1 | 256→64 | 16.384 | 4.096 B | 4.096 B | 512 |
| Ẩn 2 | 64→32 | 2.048 | 512 B | 1.024 B | 64 |
| Phân loại | 32→10 | 320 | 80 B | 320 B | 10 |
| **Tổng** | | **18.752** | **4.688 B** | **5.440 B** | **586** |

Con số 586 chỉ tính lượt thực hiện phép dot product; thời gian của NORM + QUANT, rescale, truy cập SRAM và điều khiển chưa được tính. Hai buffer S16 dài 256 phần tử, scratch buffer `z` S32 dài 256, vùng `q` S8 dài 256 và 10 giá trị đầu ra S32 cần khoảng **2.344 B** trước khi tính phần alignment. Model compiler vẫn phải kiểm tra sơ đồ cấp phát thực tế trong workspace SRAM 8 KiB.

Exporter và reference model cần xử lý hai điểm trước khi đưa weight vào ASIC:

1. **Khớp số học NORM + QUANT:** mã BitNetMCU tính RMS bằng cách lấy căn trung bình bình phương rồi chia trực tiếp. Bản tham chiếu của ASIC cần xác định `epsilon`, cách xử lý vector toàn số 0, scale S16, quy tắc làm tròn RNE, bão hòa và các phép tính gần đúng bằng số nguyên. Đối chiếu inference trước và sau export; checkpoint đã train không tự bảo đảm khớp các quy tắc này.
2. **Đóng gói weight:** chuyển {-1, 0, +1} sang mã `11/00/01`, thêm số 0 để mỗi hàng khớp ranh giới 128 weight/word. Không nạp trực tiếp kiểu đóng gói cơ số 3 của BitNetMCU. Thiết kế chọn 2 bit/weight để giải mã đơn giản; giới hạn thông tin của ba giá trị là xấp xỉ 1,585 bit/weight, không phải độ rộng ô nhớ thực tế.

Một số đường inference bằng C của BitNetMCU dùng ShiftNorm. Nếu so với đường C đó, phải áp dụng đúng ShiftNorm; kết quả này không chứng minh RMSNorm + QUANT của ASIC đã đúng. Demo MLP đề xuất dùng NORM + QUANT và cần đo lại độ chính xác. Ví dụ ternary mới trong [tài liệu BitNetMCU](https://github.com/cpldcpu/BitNetMCU/blob/main/docs/documentation.md#jan-2-2026-finally-introducing-ternary-158-bit-inference) còn có convolution layer và tầng weight 4 bit, nên không thể nạp toàn bộ ví dụ đó vào core chỉ hỗ trợ linear layer ternary.

## Checkpoint có sẵn để kiểm tra core

Danh sách công khai của BitNetMCU có tệp:

```text
a11_Opt12k_cos_Aug_BitMnist_PerTensor_Binary_RMS_width160_160_160_lr0.001_decay0.1_stepsize10_bs128_epochs60.pth
```

[Xem thư mục chứa checkpoint](https://github.com/cpldcpu/BitNetMCU/tree/main/modeldata). Dung lượng SRAM ở bảng trên được suy ra từ tên tệp và cấu trúc FCMNIST; cần đọc kích thước tensor để xác nhận. Trước khi dùng, tải tệp, khôi phục đúng phiên bản kiến trúc, kiểm tra các tầng và quantizer, chạy inference tham chiếu trên CPU với MNIST, rồi mới xuất weight theo cách xếp của ASIC. Tệp cũ có thể cần ánh xạ lại tên tầng.

Weight binary dùng các mức -1 và +1 mà PE ternary đã hỗ trợ; mã 0 vẫn cần một bài kiểm tra riêng. Đổi nhãn `QuantType` của checkpoint binary thành `Ternary` không tạo ra mô hình ba mức hoặc bảo đảm giữ độ chính xác. Muốn dùng cả ba mức, phải huấn luyện hoặc fine-tune với quantizer ternary. Mã FCMNIST hiện tại dùng linear layer không có bias; nếu checkpoint có thêm bias, hệ số chuẩn hóa học được hoặc kích thước khác dự kiến, phải tính lại dung lượng.

Tệp này là ứng viên để kiểm tra core bằng weight đã huấn luyện. Nó vẫn cần được chuyển đổi và đối chiếu với reference model; chưa thể nạp trực tiếp vào RTL hiện tại.

## Demo gần kiến trúc của bài báo 2406.02528v5

Với **Seq64**, xem 28 hàng của mỗi ảnh MNIST là 28 bước thời gian. Mỗi hàng 28 pixel đi qua tầng 28→64, sau đó qua một MLGRU; state ở bước cuối đi qua tầng 64→10 để phân loại. Mô hình dùng RMSNorm không có tham số affine, NORM + QUANT, sigmoid LUT và state S16. Bias được biểu diễn bằng số nguyên nếu mô hình có bias. Cấu hình này kiểm tra phép cập nhật state trong [bài báo MatMul-free LM](https://arxiv.org/html/2406.02528v5) bằng một bài toán có thể đo độ chính xác.

Với **Char32**, dùng vocabulary gồm 128 ký tự ASCII, embedding INT16, một MLGRU có state dimension 32, một GLU có hidden dimension 96 và output head ternary 32→128. Checkpoint giả định phải có output head ternary được train cùng mô hình. Các logits dùng cùng scale để chọn ký tự có điểm cao nhất bằng argmax; greedy decoding không cần softmax. Kích thước mô hình và định dạng số nguyên là lựa chọn riêng cho demo, không phải cấu hình đã huấn luyện trong bài báo.

**“Chưa có chất lượng hội thoại được xác nhận” không có nghĩa là thiếu PE để sinh một câu.** Model có thể lặp inference để sinh nhiều ký tự, nhưng câu có phù hợp với prompt hay không phải được kiểm tra trên checkpoint. Riêng bộ 128 ký tự ASCII không chứa trực tiếp các ký tự tiếng Việt có dấu; muốn demo tiếng Việt phải chốt tokenizer/encoding rồi tính lại vocabulary và embedding. Yêu cầu một câu ngắn không tự quyết định số bit cho datapath.

NanoFable là trường hợp khác: dự toán đã nêu khoảng 1,16 MiB cùng attention và embedding/output head FP16. Điểm chưa đáp ứng nằm ở memory, operator và quá trình export, không phải kết luận rằng 32 PE không thể lần lượt thực hiện các linear layer được hỗ trợ. Nếu chọn triển khai model này, phải lập cấu hình mở rộng riêng. Với vocabulary 4096, token ID có thể lưu U16. Vocabulary lớn hơn không tự buộc tăng width của logits; vẫn đề xuất S32 cùng scale, nhưng phải kiểm tra range và sai số khi export checkpoint. Lưu cả vector logits S32 sẽ cần 16 KiB, còn streaming argmax cho greedy decoding có thể tránh buffer đó; cách này không giải quyết các operator attention còn thiếu.

```mermaid
flowchart LR
    PC["Host: checkpoint đã train và exporter"] --> P["Packed weights và scale số nguyên"]
    P --> W["Parameter SRAM: 32 KiB"]
    IN["Ảnh 16×16, hàng ảnh hoặc ký tự"] --> S["Workspace SRAM: 8 KiB"]
    S --> N["NORM + QUANT số nguyên"]
    N --> T["32 PE ternary, ACC18"]
    W --> T
    T --> V["Rescale, ReLU / SIG / SiLU"]
    V --> S
    V --> OUT["Chọn nhãn hoặc ký tự có điểm cao nhất"]
```

## Cách kiểm tra demo

Độ rộng và format cần đổi trong từng module RTL được liệt kê tại [bảng chuyển đổi module](<architecture.md#bảng-chuyển-đổi-từng-module-rtl-hiện-có>). Dùng cùng cấu hình K_MAX=512, ACC18 và bus SRAM256 cho các demo trong tài liệu này; scale của từng tensor được chốt khi calibration/QAT.

- Cố định checkpoint, tokenizer hoặc cách xử lý ảnh đầu vào, và tập đánh giá. Kiểm tra graph, operator, K, vocabulary và memory trước khi nạp. Đo chất lượng trước và sau khi xuất sang số nguyên.
- Xuất SRAM image chứa weight, các hệ số scale, bias, dữ liệu đầu vào và giá trị trung gian để đối chiếu. Gắn chung phiên bản và checksum cho các file.
- So kết quả ở từng tầng hoặc từng bước thời gian với reference model số nguyên. Đặt lại state giữa hai chuỗi đầu vào độc lập.
- Đo số chu kỳ cho cả nạp dữ liệu, NORM + QUANT và xử lý vector; ghi nhận mức sử dụng SRAM cao nhất và số lần bão hòa. Số PE không đủ để suy ra latency hoặc điện năng.

**Trạng thái hiện tại:** đã đối chiếu mã nguồn và lập ngân sách bộ nhớ; chưa tải checkpoint, huấn luyện hoặc chạy inference mới. Môi trường Python hiện có NumPy nhưng chưa có PyTorch. Để chạy demo MNIST trên máy tính, cần cài PyTorch bản CPU và chuẩn bị dữ liệu MNIST.
