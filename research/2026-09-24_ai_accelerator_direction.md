# Đề xuất nâng cấp thiết kế thành ASIC tăng tốc mô hình ngôn ngữ

*Tổng hợp từ khảo sát ngày 24/09/2026. Bản này được biên tập lại để dễ đọc hơn, không bổ sung nghiên cứu mới.*

**Hướng đề xuất là xây ASIC cho mô hình ngôn ngữ dùng trọng số ít bit và có trạng thái hồi quy, tận dụng khối tính toán ternary hiện tại.** Trọng tâm nghiên cứu là cách dùng chung trọng số giữa các yêu cầu suy luận, đồng thời bố trí bộ nhớ để giảm năng lượng tiêu thụ mà vẫn đáp ứng giới hạn độ trễ.

Mô hình thử nghiệm đầu tiên nên là **HF-Mamba-2 130M**, sau đó mở rộng lên bản **780M**. Hai bản này có mã nguồn và bộ trọng số đã huấn luyện được công bố. Kiến trúc hybrid như Qwen là một hướng mở rộng đáng quan tâm, nhưng cần thêm nhiều phần cứng và công sức kiểm chứng.

Đề xuất này phù hợp với điều kiện bạn đã nêu: có công cụ Synopsys/Cadence để thiết kế ASIC, dùng FPGA Xilinx để kiểm chứng, và có thể dùng GPU cá nhân hoặc thuê GPU để tinh chỉnh mô hình. Những thông số còn cần xác định là PDK, thư viện SRAM, băng thông bộ nhớ ngoài và thời gian thực hiện.

Mục tiêu công bố Q1 đòi hỏi một đóng góp mới có bằng chứng thuyết phục. Vì vậy, tài liệu phân biệt hai việc: **hoàn thiện một accelerator chạy đúng mô hình** và **chứng minh cơ chế kiến trúc mới tốt hơn các phương án đã có**.

**Phạm vi nghiên cứu đề xuất là phục vụ từ 1 đến 8 yêu cầu suy luận độc lập.** Mỗi yêu cầu có dữ liệu đầu vào và trạng thái riêng. Khi nhiều yêu cầu cùng chạy một mô hình, phần cứng có thể đọc một khối trọng số rồi dùng khối đó cho cả nhóm. Cách gom một nhóm nhỏ như vậy gọi là *microbatch*.

Đây là phạm vi được đề xuất, chưa phải yêu cầu đã được bạn xác nhận. Nếu ứng dụng chỉ phục vụ một người dùng tại một thời điểm, lợi ích chia sẻ trọng số giữa nhiều yêu cầu sẽ không áp dụng. Khi đó, cần chọn lại câu hỏi nghiên cứu cho bài toán một luồng sinh token.

**Thiết kế hiện tại đã có nền tính toán có thể tái sử dụng.** Khối ternary đã dùng pipeline và phép cộng carry-save (CSA), thay vì triển khai toàn bộ ma trận 512×512 song song như mô tả cũ trong lịch sử trò chuyện. Tuy nhiên, các khối số học, bộ nhớ và điều khiển vẫn cần được thống nhất trước khi chạy một mô hình hoàn chỉnh.

| Thành phần | Hiện trạng đã kiểm tra | Việc cần làm |
|---|---|---|
| Khối ternary | Xử lý 32 cặp đầu vào–trọng số mỗi chu kỳ; lưu 512 giá trị đầu vào và một từ trọng số | Giữ làm nền, bổ sung xử lý theo khối và nhiều bộ tích lũy |
| Định dạng số | Mặc định đầu vào 16 bit, bộ tích lũy 26 bit; kết quả đầu ra giữ các bit thấp khi tràn | Chốt cách nhân hệ số, làm tròn và bão hòa theo mô hình |
| Tốc độ tính toán | Với 512 cột, khoảng cách giữa hai hàng là 16+6 chu kỳ; một ma trận mất khoảng 11.300 chu kỳ khi không phải chờ | Đo và giảm thời gian pipeline phải chờ giữa các hàng |
| Bộ nhớ | Mảng mô phỏng 524288×512 bit, tương đương 32 MiB; chưa chứng minh đường DDR tích hợp hoạt động | Thay bằng giao diện DMA và các khối SRAM từ thư viện công nghệ |
| NORM | Tính RMS riêng cho từng nhóm 32 phần tử, dùng thống kê Q4.6, không có epsilon hoặc gamma | Làm đúng phép chuẩn hóa của mô hình được chọn |
| MUL và DIV | Cách lấy bit của MUL chưa tương đương phép nhân Q4.12; DIV chia trực tiếp các số nguyên biểu diễn | Viết mô hình số học tham chiếu và kiểm tra lại |
| Kiểm chứng và PPA | Có báo cáo kiểm thử cũ, nhưng một số file hiện tại đã thay đổi; chưa có kết quả ASIC sau bố trí và đi dây | Kiểm thử đúng phiên bản hiện tại, sau đó đo công suất, tốc độ và diện tích |

Nguồn trong dự án: [khối ternary](<D:/2151097_Nguyen Nhut Khanh/Verilog Source code/ternary_mul.sv>), [mô tả TMATMUL](<D:/2151097_Nguyen Nhut Khanh/tmatmul/README.md>), [mô tả NORM](<D:/2151097_Nguyen Nhut Khanh/norm/README.md>), [MUL](<D:/2151097_Nguyen Nhut Khanh/Verilog Source code/mul.sv>) và [DIV](<D:/2151097_Nguyen Nhut Khanh/Verilog Source code/div.sv>).

Phần nên giữ là khối số học ternary, giao thức truyền dữ liệu có xác nhận và các bài kiểm thử phù hợp. Phần cần xây lại là cách chia dữ liệu thành khối nhỏ, tổ chức bộ nhớ và điều phối các khối tính toán.

**Các nghiên cứu gần đây ủng hộ hướng low-bit và hồi quy, nhưng cũng cho thấy nhiều ý tưởng cơ bản đã được khai thác.**

| Hướng phát triển | Nghiên cứu tiêu biểu | Ý nghĩa đối với dự án |
|---|---|---|
| Kết hợp hồi quy với attention | [Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/config.json), [Qwen3.8-Next](https://arxiv.org/abs/2608.30320) | Nên để khả năng mở rộng về sau; khối MLGRU hiện tại chưa đủ để chạy Gated DeltaNet |
| Mô hình có trọng số ternary ngay từ quá trình huấn luyện | [BitNet 2B4T](https://arxiv.org/abs/2504.12285) | Có mô hình thật để đánh giá phần cứng, không cần tự chuyển mọi mô hình sang ternary |
| Mô hình hồi quy phù hợp phần cứng ít bit | [HF-Mamba-2 của AIST](https://aist.repo.nii.ac.jp/records/2003437) | Có mã nguồn và trọng số 130M/780M; gần với nền ternary hiện tại |
| Chọn độ chính xác riêng cho từng loại dữ liệu | [DAMP](https://arxiv.org/abs/2608.27513), [nghiên cứu W4A4 cho GDN](https://arxiv.org/abs/2609.04098) | Trọng số, dữ liệu trung gian và trạng thái lưu giữa các token không nhất thiết dùng cùng số bit |
| Tổ chức xử lý khác nhau cho đầu vào và sinh token | [FlexLLM](https://arxiv.org/abs/2601.15710), [DUET](https://arxiv.org/abs/2603.15530) | Cần phân biệt giai đoạn xử lý chuỗi đầu vào (*prefill*) và giai đoạn sinh từng token (*decode*) |
| Sinh token dự đoán rồi xác minh | [SpecMamba](https://arxiv.org/abs/2509.19873) | Có thể tạo cơ hội dùng lại trọng số cho một yêu cầu, nhưng cần thêm cơ chế xác minh và khôi phục trạng thái |

HF trong HF-Mamba-2 nghĩa là *Hardware-Friendly*. AIST công bố mô hình dùng trọng số ternary và dữ liệu trung gian INT8 ngày 19/05/2026. Đây là mô hình và kiến trúc tham chiếu đã có; việc chạy được nó trên ASIC của bạn là nền thực nghiệm, chưa phải đóng góp mới.

Các hướng như MoE, attention thưa và mô hình đa phương thức làm tăng đáng kể phạm vi phần cứng. Với bài đầu tiên, nên chọn một mô hình cụ thể và thực hiện đầy đủ đường suy luận của mô hình đó. Muốn nghiên cứu tính toán trong bộ nhớ, trước hết phải có công nghệ nhớ và mô hình mạch phù hợp để triển khai và đánh giá.

**Lý do chưa chuyển ngay sang hybrid Qwen là chi phí triển khai lớn, trong khi lợi ích cần được đo trước.** Gated DeltaNet lưu trạng thái dạng ma trận; attention vẫn cần bộ nhớ KV, softmax và các phép xử lý vị trí. Những phần này đòi hỏi nhiều hơn khối ternary và phép nhân từng phần tử hiện có.

Một phép tính từ [cấu hình Qwen3.5-0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B/blob/main/config.json) cho thấy:

| Dữ liệu cần lưu | Dung lượng tính từ cấu hình |
|---|---:|
| Trạng thái của 18 lớp hồi quy, lưu FP32 | 18 MiB |
| Cùng trạng thái đó, lưu FP16 | 9 MiB |
| KV của 6 lớp attention, lưu FP16, chuỗi dài 4.096 token | 48 MiB |
| Cùng bộ KV, chuỗi dài 32.768 token | 384 MiB |

Các số trạng thái trên chưa tính lịch sử convolution. Chúng cho thấy trạng thái có kích thước cố định theo chiều dài chuỗi vẫn có thể quá lớn để giữ toàn bộ trong SRAM.

Trong một ví dụ đơn giản, giả sử 0,8 tỷ trọng số đều dùng 4 bit và được đọc một lần cho mỗi token. Khi cộng lưu lượng đọc trọng số, đọc–ghi trạng thái FP32 và đọc KV ở chuỗi 4K, tổng vào khoảng **488 MB/token**. Ngay cả khi loại bỏ hoàn toàn lưu lượng trạng thái, mức tăng tốc lý tưởng do giảm lưu lượng cũng chỉ khoảng **1,084 lần**. Giữ thêm 1 MiB trạng thái trong SRAM chỉ giảm khoảng **0,43% tổng số byte** của ví dụ này.

Đây là ước lượng để sàng lọc ý tưởng, chưa phải số đo của chip. Số tham số được làm tròn; dữ liệu phụ, các lớp dùng độ chính xác khác và chi phí đầu ra cần được thống kê từ mô hình thật. Bài học thiết kế là: **hãy đo phần nào chi phối thời gian và năng lượng trước khi đầu tư tối ưu phần đó**.

**Kiến trúc ASIC nên gồm một khối projection ternary, một khối xử lý trạng thái và hệ thống bộ nhớ dùng chung.** Projection là phép biến đổi tuyến tính bằng ma trận trọng số. Trạng thái hồi quy là dữ liệu được giữ lại để xử lý token tiếp theo.

![Sơ đồ ASIC ternary với bộ nhớ chia bank, mảng PE và các luồng dữ liệu](<D:/2151097_Nguyen Nhut Khanh/research/asic_ternary_architecture.svg>)

[Mở bản SVG để phóng to hoặc chỉnh sửa](<D:/2151097_Nguyen Nhut Khanh/research/asic_ternary_architecture.svg>) · [Bản PNG](<D:/2151097_Nguyen Nhut Khanh/research/asic_ternary_architecture.png>)

Trong hình, các phiến nhớ biểu diễn những bank SRAM; lưới PE biểu diễn các phần tử tính toán ternary. Đường liền có màu là luồng dữ liệu, đường xám nét đứt là điều khiển. Đây là sơ đồ chức năng của kiến trúc đề xuất, không biểu diễn tỉ lệ diện tích hoặc số lượng ô nhớ thực tế.

| Khối | Thiết kế đề xuất |
|---|---|
| Mảng ternary | Mỗi cặp đầu vào–trọng số tạo một giá trị `+x`, `0` hoặc `−x`, rồi được cộng bằng cấu trúc CSA. Khởi đầu với đầu vào INT8, bộ tích lũy INT32, sau đó đổi về định dạng đầu ra theo mô hình |
| Khối trạng thái | Thực hiện đầy đủ phép cập nhật và cộng gộp để đọc kết quả. Bổ sung phép nhân hoặc tích ngoài khi phương trình của mô hình yêu cầu |
| Convolution và phi tuyến | Có bộ đệm lịch sử riêng cho từng yêu cầu. Lấy đúng phép toán từ mã nguồn HF-Mamba-2 |
| Chuẩn hóa và lượng tử hóa | Làm đúng phạm vi các phần tử cần tính chung, hệ số, epsilon và quy tắc làm tròn |
| SRAM | Chia thành các bank có thể truy cập độc lập; bố trí theo số cổng và kích thước của macro SRAM thực tế |
| Điều khiển | Thực hiện các lịch đã tính trước; khi chạy chỉ chọn giữa một số cấu hình đã kiểm chứng |
| Đường vào và ra của mô hình | Tính đủ embedding, các lớp còn lại và phép chiếu ra từ vựng. Nếu CPU xử lý một phần thì cộng chi phí đó vào kết quả toàn hệ thống |

Với HF-Mamba-2, cần tái lập đúng định dạng số, hệ số và phép cập nhật trạng thái của mã nguồn công bố trước khi thay đổi chúng. Không suy ra độ rộng trạng thái chỉ từ thông tin “đầu vào INT8”, cũng không mặc định dùng toàn bộ phép phi tuyến của Mamba-2 gốc.

Khi xử lý INT8, cần mở rộng số có dấu trước phép đổi dấu để biểu diễn được trường hợp `−(−128) = 128`. Nếu phép lượng tử hóa cần thống kê trên toàn vector, việc thay bằng thống kê riêng từng tile là thay đổi thuật toán và phải đánh giá lại chất lượng mô hình.

Một lựa chọn để khảo sát là giữ tổng khả năng tính toán ở **256 cặp đầu vào–trọng số mỗi chu kỳ**, rồi phân chia giữa số đầu ra và số yêu cầu:

| Cấu hình | Số đầu ra đồng thời | Số yêu cầu dùng chung trọng số | Số phần tử cộng cho mỗi đầu ra/yêu cầu |
|---|---:|---:|---:|
| Một yêu cầu | 8 | 1 | 32 |
| Hai yêu cầu | 4 | 2 | 32 |
| Bốn yêu cầu | 2 | 4 | 32 |

Cùng số phép tính không có nghĩa là cùng diện tích. Cấu hình nhiều yêu cầu cần thêm bộ tích lũy, cổng đọc dữ liệu và dây nối.

Ở cấu hình 8×32, nếu clock là 250 MHz và mỗi trọng số lưu bằng 2 bit, khối tính toán cần **16 GB/s** trọng số để hoạt động liên tục mà không dùng lại dữ liệu. Cách đóng gói 5 giá trị ternary trong một byte giảm phần dữ liệu trọng số xuống **12,8 GB/s**, chưa tính hệ số và phần đệm. Đây là băng thông cần cung cấp, chưa phải băng thông bộ nhớ ngoài đạt được.

**Đóng góp cần nghiên cứu nằm ở cách tổ chức dữ liệu để việc dùng chung trọng số mang lại lợi ích thực tế.** Câu hỏi nên được phát biểu rõ:

> Với cùng dung lượng SRAM và băng thông bộ nhớ ngoài, việc phối hợp số yêu cầu chạy chung, kích thước khối dữ liệu và cách bố trí bank có giảm năng lượng trên mỗi token tốt hơn các phương án tối ưu riêng lẻ, đồng thời giữ nguyên chất lượng mô hình và giới hạn độ trễ hay không?

Một khối dữ liệu nhỏ được đưa vào tính toán gọi là *tile*. Cơ chế phần cứng đề xuất gồm bốn bước:

1. **Giữ lại tile trọng số để phục vụ cả nhóm yêu cầu.** Mỗi yêu cầu có bộ tích lũy riêng. Chỉ ghi đè vùng đệm của tile hiện tại sau khi mọi yêu cầu trong nhóm dùng xong; tile tiếp theo có thể được nạp trước vào vùng đệm khác.
2. **Bố trí SRAM phù hợp với từng pha tính toán.** Khi tính projection, SRAM cấp dữ liệu đầu vào và tổng tích lũy cho từng yêu cầu. Khi cập nhật trạng thái, SRAM phục vụ các lần đọc–sửa–ghi. Cần tìm cách đổi cách truy cập mà hạn chế sao chép dữ liệu và tranh chấp cổng.
3. **Theo dõi dữ liệu của từng yêu cầu.** Lệnh điều khiển ghi rõ yêu cầu, lớp, tile, định dạng số và vùng nhớ. Chỉ dùng trạng thái cho token tiếp theo sau khi cập nhật hoàn tất.
4. **Chọn cấu hình theo tải và giới hạn độ trễ.** Bộ điều khiển chọn trong bảng cấu hình đã chuẩn bị. Khi chỉ có một yêu cầu, dùng cấu hình một yêu cầu; khi gom nhóm, phải tính cả thời gian chờ vào độ trễ.

Việc đổi cấu hình ở đây là đổi cách ánh xạ dữ liệu và điều khiển. Vị trí các khối và dây nối vật lý trên chip được cố định sau khi triển khai.

Ví dụ, bốn yêu cầu A, B, C và D đang xử lý token hiện tại có thể dùng chung một tile trọng số. Mỗi yêu cầu vẫn cập nhật trạng thái riêng. Trong giai đoạn prefill, các token đầu vào đã biết nên cũng có thể dùng lại trọng số cho các phép projection. Trong decode của một yêu cầu, token tương lai chưa biết nên không thể đạt cách dùng lại này chỉ bằng đổi lịch thực thi.

**Cơ chế trên phải được so sánh với các công trình đã làm những phần gần nó.** Đây là các đối chiếu cần giữ trong bài:

| Công trình | Nội dung đã có |
|---|---|
| [TeLLMe v2](https://arxiv.org/abs/2510.15926) | Tra bảng ternary, quản lý bộ đệm, ghép phép toán và xử lý prefill/decode |
| [TENET](https://arxiv.org/abs/2509.13765) | Tra bảng ternary, khai thác phần tử bằng không, giải nén trọng số và nhiều mức độ chính xác |
| [VitaLLM](https://arxiv.org/abs/2604.27396) | Kết hợp ternary với attention và lập lịch theo phụ thuộc dữ liệu |
| [Persistent-state GDN](https://arxiv.org/abs/2603.05931) | Giữ trạng thái trên FPGA và ghép các bước cập nhật trạng thái |
| [HEMERA](https://arxiv.org/abs/2607.22022) | Tổ chức Mamba-2 theo luồng hồi quy và tách khối tuyến tính với khối trạng thái |
| [E-BATCH](https://arxiv.org/abs/2009.10656) | Gom nhóm yêu cầu RNN để dùng lại trọng số, điều chỉnh theo độ trễ và năng lượng |

Do đó, dùng CSA, chia bank SRAM, hỗ trợ Mamba hay gom nhóm động đều chưa đủ để trở thành đóng góp mới. Cần chỉ ra **cơ chế bố trí và truy cập bộ nhớ nào tạo thêm lợi ích**, rồi đo lợi ích đó trên cùng điều kiện so sánh.

Nếu phương án tốt nhất cuối cùng chỉ là “chọn nhóm lớn nhất còn kịp giới hạn độ trễ”, trong khi cách bố trí SRAM mới không giúp đáng kể, giả thuyết nghiên cứu này chưa tạo đủ khác biệt.

**Các phép tính lưu lượng giúp loại sớm những ý tưởng có trần cải thiện quá thấp.** Với một nhóm `B` yêu cầu, có thể dùng ước lượng sau cho số byte truyền ngoài chip trên mỗi token đầu ra:

\[
D(B)\gtrsim \frac{D_W}{B}
+\frac{2\max(0,BS-C_S)}{B}
+D_{\text{khác}}(B).
\]

| Ký hiệu | Ý nghĩa |
|---|---|
| `B` | Số yêu cầu trong nhóm |
| `D_W` | Dữ liệu trọng số chưa nằm thường trực trên chip, cần đọc ít nhất một lần cho cả nhóm |
| `S` | Dung lượng trạng thái hồi quy của một yêu cầu cần đọc và ghi toàn bộ ở mỗi bước |
| `C_S` | Phần SRAM dành để giữ thường trực loại trạng thái đó |
| `D_khác(B)` | Lưu lượng còn lại trên mỗi token: lịch sử convolution, dữ liệu trung gian, tổng tích lũy, hệ số, phần đệm và các lần đọc lại |

Số hạng đầu mô tả lợi ích dùng chung trọng số. Số hạng thứ hai mô tả phần trạng thái phải đọc và ghi vì không đủ SRAM. Công thức giả định một lượt đọc trọng số cho cả nhóm, trạng thái hồi quy chưa được nén thêm và không có chuyển đổi sang nhóm khác giữa chừng.

Đây là mô hình sàng lọc dưới các giả định trên. Lịch sử convolution có thể được cập nhật bằng bộ đệm vòng nên không được áp hệ số đọc–ghi hai lần một cách máy móc. Dung lượng SRAM tổng vẫn phải tính đủ mọi loại bộ đệm.

Khi tăng `B`, tổng dung lượng trạng thái tăng, nhưng lưu lượng trạng thái trên mỗi token không nhất thiết tăng tuyến tính. Vì vậy, việc chọn `B` phải xét thêm thời gian chờ, giới hạn tính toán, số cổng SRAM và dữ liệu phải đẩy ra bộ nhớ ngoài; công thức lưu lượng riêng lẻ chưa quyết định được cấu hình tốt nhất.

**Kết quả cần đánh giá ở cả mô hình, phần cứng và toàn hệ thống.** Nên dùng bản 130M để đưa hệ thống vào hoạt động, rồi dùng bản 780M để kiểm tra khả năng mở rộng.

| Phần đánh giá | Bằng chứng cần có |
|---|---|
| Chất lượng mô hình | Chạy bộ trọng số thật; đo perplexity và các bài đánh giá tác vụ; kiểm tra sai số tích lũy trên chuỗi dài |
| Số học | Đối chiếu từng phép toán và từng lớp với mô hình tham chiếu; chốt hệ số, làm tròn và bão hòa |
| RTL | Kiểm tra dữ liệu phải chờ, reset, khối dữ liệu cuối không đầy và việc tách trạng thái giữa các yêu cầu |
| Hiệu năng hệ thống | Thời gian ra token đầu tiên, thời gian sinh mỗi token, thông lượng và độ trễ p95 — mức mà 95% mẫu không vượt quá |
| Bộ nhớ | Đếm số byte của trọng số, trạng thái và dữ liệu trung gian; đo thời gian chờ DMA và tranh chấp bank |
| ASIC | Đo diện tích, timing và công suất sau bố trí, đi dây; dùng SRAM macro và hoạt động chuyển mạch đại diện |
| Năng lượng toàn hệ thống | Tính thêm bộ nhớ ngoài và phần xử lý trên CPU nếu có |

Các phương án đối chứng phải được tối ưu trong cùng điều kiện: cùng độ chính xác số, dung lượng SRAM, băng thông và thư viện công nghệ. Ít nhất cần có cấu hình một yêu cầu đã tối ưu, các kích thước nhóm cố định tốt nhất, cách gom nhóm theo giới hạn độ trễ, và các cách giữ hoặc truyền trạng thái thông thường.

Sau đó bật riêng từng cải tiến — gom nhóm, đổi tile, đổi cách bố trí SRAM và phối hợp cả ba — để biết lợi ích đến từ đâu. So sánh với core cũ có lỗi số học sẽ không phản ánh đúng giá trị của kiến trúc mới.

Dải khảo sát ban đầu có thể dùng:

| Biến khảo sát | Giá trị dự kiến |
|---|---|
| Số yêu cầu chạy chung | 1, 2, 4, 8 |
| Dung lượng SRAM | 256 KiB, 512 KiB, 1 MiB, 2 MiB, 4 MiB |
| Băng thông bộ nhớ ngoài | 2, 4, 8, 16, 32 GB/s |
| Dữ liệu đầu vào | Nhiều độ dài chuỗi, số token sinh ra và mức tải |

Đây là dải để tìm vùng có lợi ích. Các cấu hình không phù hợp với công nghệ hoặc hệ thống mục tiêu cần được loại bỏ. Giới hạn suy giảm chất lượng mô hình phải được chốt trước khi thử nghiệm; nếu cần tinh chỉnh hoặc huấn luyện có xét lượng tử hóa, các phương án so sánh phải dùng điều kiện tương đương.

Nếu chưa chế tạo chip, kết quả cần được gọi đúng là **ước lượng PPA sau layout**. FPGA dùng để chứng minh chức năng và giao tiếp. Khi so năng lượng, phải dùng cùng phạm vi đo; số watt của riêng khối tính toán ASIC không tương đương số watt của cả bo mạch GPU.

**Lộ trình nên bắt đầu bằng việc xác minh mô hình và giới hạn bộ nhớ, rồi mới mở rộng RTL.**

| Giai đoạn | Công việc | Kết quả cần đạt |
|---|---|---|
| Khảo sát khả thi | Chạy lại HF-Mamba-2 130M, thống kê phép toán và lưu lượng; chọn PDK cùng SRAM phù hợp | Biết phần nào thực sự chi phối thời gian và năng lượng |
| Xây nền chạy đúng | Hoàn thiện số học, chia tile, DMA và bộ điều khiển; chạy từng lớp rồi cả mô hình | Đầu ra đúng với mô hình tham chiếu |
| Thử cơ chế mới | Thêm nhiều bộ trạng thái, bố trí bank và chính sách chọn cấu hình | Có cải thiện trước các phương án đối chứng mạnh |
| Triển khai ASIC | Tổng hợp, bố trí, đi dây, kiểm tra timing và công suất; kiểm chứng chức năng trên FPGA | Có số liệu vật lý cho vài cấu hình tiêu biểu |
| Hoàn thiện bài báo | Phân tích từng cải tiến, giới hạn áp dụng và khả năng tái lập | Chứng minh rõ cơ chế tạo lợi ích và điều kiện có lợi |

Có thể dành khoảng hai tuần đầu cho khảo sát khả thi, tùy khả năng chạy mô hình và truy cập PDK. Một mục tiêu nội bộ để quyết định đầu tư tiếp là giảm khoảng **20% năng lượng/token hoặc tích năng lượng–độ trễ (EDP)** so với phương án đối chứng mạnh, ở cùng chất lượng và giới hạn độ trễ. Con số này là mục tiêu quản lý nghiên cứu, không phải tiêu chuẩn Q1.

Nếu ứng dụng chỉ có một luồng sinh token, hoặc kết quả đo cho thấy cơ chế mới cải thiện quá ít, cần đổi hướng trước khi viết thêm nhiều RTL. Hai lựa chọn đã được nhận diện là nghiên cứu hybrid Qwen tại điểm nghẽn đã đo được, hoặc dùng speculative decoding để tạo cơ hội dùng lại trọng số trong một yêu cầu. Mỗi lựa chọn cần một phạm vi nghiên cứu riêng.

Tên đề tài tạm thời có thể là **“Thiết kế ASIC cho mô hình ngôn ngữ ít bit dưới giới hạn bộ nhớ và độ trễ”** (*Memory- and Latency-Constrained ASIC Acceleration for Low-Bit State-Space Language Models*). Tên và mô tả đóng góp cuối cùng nên bám vào cơ chế thực sự được chứng minh.

*Phạm vi xác minh của tài liệu: đã đọc RTL, tài liệu trong dự án và các nguồn nghiên cứu được dẫn. Chưa tải hoặc chạy lại HF-Mamba-2, chưa thực hiện khảo sát hiệu năng và chưa xác minh PDK/SRAM của bạn. Những kết quả do các bài báo công bố chưa được tái lập trong dự án. Lượt biên tập này chỉ sửa văn bản, không sửa RTL hoặc bổ sung nguồn nghiên cứu.*
