# Checkpoint application với context đầy đủ

- Tác vụ hiện tại: điều tra application bị lỗi/đình trệ và chạy đủ context 128 token. Các bản sửa cho Windows PowerShell runner vẫn được giữ nguyên: loại bỏ UTF-8 BOM khỏi source list và dùng đường dẫn RAM tương đối tương thích với .NET Framework. Testbench hiện báo tiến độ nạp checkpoint mỗi 1024 hàng, thời điểm graph bắt đầu và tiến độ tính toán mỗi 100000 cycle; không thay đổi expected value, watchdog hoặc RTL.
- Kết quả điều tra: tiến trình 8 token trước đó đã kết thúc nhưng không có marker application FAIL/PASS hoặc marker kết thúc simulator. Session tương ứng không còn tồn tại và chưa xác định được nguyên nhân dừng. Các lượt chẩn đoán mô phỏng giới hạn ở 100 ns và 10 us đều tiến triển rồi kết thúc mà không có lỗi/cảnh báo từ simulator, qua đó loại trừ tình trạng treo zero-time khi khởi động. Chưa có bằng chứng về lỗi số học trong RTL.
- Đã xác minh: quá trình export reference cho context đầy đủ đã hoàn tất (`prompt=4 continuation=124`); lần compile thực tế trước đó hoàn tất với `Errors: 0, Warnings: 0`. Kết quả application PASS đầy đủ vẫn đang chờ.
- Đang chạy từ 2026-10-07 20:23:59 theo giờ địa phương: tool session `67680`, PowerShell runner PID `12796`, `vsim.exe` PID `35164`, `vsimk.exe` PID `11492`. Prompt `Once upon a time`, NewTokens=124, MinNew=124, Temperature=0, Seed=7 (4 prompt + 124 continuation = context 128 token). Timing manifest `docs/verification/timing/nanofable_max_20261006/manifest.json` chỉ dùng để xác định RAM model; hardware gate được bỏ qua.
- Job wrapper/archive: `tests/full_rtl/build/full128_20261007_2022/run.ps1`. `status.json` ghi RUNNING/PASS/FAIL, PID và timestamp. Input/log trước đó được giữ dưới tên `previous_*`; log/kết quả cuối được sao chép vào đây khi wrapper kết thúc. Các lượt chạy detached đã thoát trước khi khởi động; lượt hiện tại được khởi chạy bình thường và còn tool session hoạt động. Không giả định các PID detached trước đó vẫn đang chạy.
- Log: `tests/full_rtl/build/application.log` (lần kiểm tra trạng thái đầu tiên đã thấy `run -all`). Console: `tests/full_rtl/build/application.log.console`. Không poll lặp lại trong khi lượt này đang chạy.
- Lệnh kiểm tra trạng thái một lần, có giới hạn: `Get-Process -Id 12796,35164,11492 -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,CPU`.
- Lệnh kiểm tra tiến độ một lần, có giới hạn: `Get-Content tests/full_rtl/build/application.log -Tail 20`.
- Điều kiện hoàn tất: simulator phát marker `FULL_RTL_APPLICATION_PASS tokens=124`, sau đó runner phát marker `FULL_RTL_APPLICATION_FUNCTIONAL_PASS` và `status.json` của job ghi PASS. Khi thất bại, runner ném lỗi `Application failed` hoặc `Application evidence failed` và ghi trạng thái job là FAIL. Output dự kiến: `tests/full_rtl/application_functional_results.json` và `tests/full_rtl/generated_functional_text.md`.
- Hành động tiếp theo: sau khi tiến trình hiện tại kết thúc, chỉ kiểm tra kết quả cuối một lần; xác nhận các hash source/config/reference hiện tại và 124 token khớp chính xác; sau đó tiếp tục tác vụ Codex này. Không khởi chạy lại hoặc sửa source đang được đo trong khi tiến trình còn chạy. Nếu các tiến trình biến mất mà không có trạng thái cuối, hãy điều tra nguyên nhân dừng trước khi quy lỗi cho RTL hoặc chạy lại.

## Baseline tài liệu trước đó

> **Category: CURRENT.** Milestone tài liệu hoàn tất ngày 2026-10-07; tác vụ này không thay đổi RTL/backend/test.

- Kiến trúc canonical: [full RTL language](docs/design/full_rtl_language.md).
- Baseline đã xác minh và blocker triển khai còn lại: [optimization status](docs/verification/optimization_status.md).
- Cơ sở lựa chọn triển khai P0/P1: [review](review/architecture_optimization_20261007.md).
- Lượt timing với placement đã sửa đã hoàn tất. Milestone triển khai trước đó vẫn cần quyết định KEEP/REVISE/REJECT; không khởi chạy lại job đã hoàn tất hoặc tự động bắt đầu lượt tối ưu khác.
- Các sơ đồ Mermaid hiện tuân theo [diagram style](docs/diagrams/diagram_style.md), bao gồm các view row-overlap/greedy-selection hiện tại. Cả 73 sơ đồ Mermaid đều đã vượt qua kiểm tra syntax/render; các bản Mermaid trùng lặp liên kết đến canonical owner. Sơ đồ Draw.io và ASCII không thay đổi. Milestone tài liệu/sơ đồ đã hoàn tất.
