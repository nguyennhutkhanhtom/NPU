"""Run and report a standalone sigmoid audit without modifying design or LUT files."""
import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SIM = HERE / "sim"
RTL = ROOT / "Verilog Source code" / "sigmoid.sv"
LUT = ROOT / "Verilog Source code" / "sigContent.mif"
DATA_LUT = ROOT / "data" / "sigmoid" / "sigContent.mif"
GENERATOR = ROOT / "python" / "generate_sigmoid_lut.py"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def protected_hashes():
    paths = sorted((ROOT / "Verilog Source code").glob("*"))
    paths += [DATA_LUT, GENERATOR]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in paths if p.is_file()}


def reference():
    # Independent oracle: Decimal exponential, no imports/calls to the LUT generator.
    with localcontext() as ctx:
        ctx.prec = 50
        values = []
        for raw in range(-32768, 32768):
            x = Decimal(raw) / 4096
            result = Decimal(4096) / (1 + (-x).exp())
            values.append(int(result.to_integral_value(rounding=ROUND_HALF_EVEN)))
        return values


def run_command(args, log):
    with log.open("w", encoding="utf-8") as stream:
        completed = subprocess.run([str(a) for a in args], cwd=SIM,
                                   stdout=stream, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise RuntimeError(f"Command failed ({completed.returncode}); inspect {log}")


def as_int(value):
    return None if re.search("[xz]", value.lower()) else int(value, 16)


def stats(rows, output_key, address_key, expected, width):
    exact = wrong = unknown = address_errors = range_errors = 0
    max_error = -1
    worst = None
    decreases = 0
    previous = None
    error_sum = 0
    for row in rows:
        raw = int(row["x_hex"], 16)
        signed = raw if raw < 32768 else raw - 65536
        actual = as_int(row[output_key])
        gold = expected[signed + 32768]
        correct_address = ((raw if width == 16 else raw >> 6) ^ (1 << (width - 1)))
        address_errors += as_int(row[address_key]) != correct_address
        if actual is None:
            unknown += 1
        else:
            error = abs(actual - gold)
            exact += error == 0
            wrong += error != 0
            range_errors += not 0 <= actual <= 4096
            error_sum += error
            if error > max_error:
                max_error = error
                worst = dict(x_hex=row["x_hex"], signed_raw=signed, x=signed / 4096,
                             actual_raw=actual, expected_raw=gold, error_raw=error)
            if previous is not None and actual < previous:
                decreases += 1
        previous = actual
    return dict(samples=len(rows), exact=exact, wrong_known=wrong, unknown=unknown,
                address_errors=address_errors, range_errors_known=range_errors,
                adjacent_decreases_known=decreases, max_abs_error_raw_known=max_error,
                mean_abs_error_raw_known=error_sum / (len(rows) - unknown), worst_known=worst)


def analyze(golden, before):
    lines = LUT.read_text(encoding="ascii").splitlines()
    malformed = [i + 1 for i, line in enumerate(lines) if not re.fullmatch("[01]{16}", line)]
    if malformed:
        raise RuntimeError(f"LUT contains malformed binary words at {malformed[:10]}")
    table = [int(line, 2) for line in lines]
    expected_table = golden[::64]
    table_bad = sum(a != b for a, b in zip(table, expected_table)) + abs(len(table) - 1024)
    quantized_golden = [expected_table[index // 64] for index in range(65536)]
    with (SIM / "observed.csv").open(newline="", encoding="ascii") as stream:
        all_rows = list(csv.DictReader(stream))
    rows = [row for row in all_rows if row["phase"] == "0"]
    transition_rows = [row for row in all_rows if row["phase"] != "0"]
    observed_bits = [int(row["x_hex"], 16) for row in rows]
    if observed_bits != [raw & 65535 for raw in range(-32768, 32768)]:
        raise RuntimeError("Exhaustive input coverage/order is incomplete")
    if len(transition_rows) != 4112:
        raise RuntimeError("Transition coverage is incomplete")
    indexed = {row["x_hex"]: row for row in rows}
    transition_bad = sum(
        any(row[key] != indexed[row["x_hex"]][key]
            for key in ("default_hex", "default_addr_hex", "lut10_hex", "lut10_addr_hex"))
        for row in transition_rows
    )
    default = stats(rows, "default_hex", "default_addr_hex", golden, 16)
    lut10 = stats(rows, "lut10_hex", "lut10_addr_hex", quantized_golden, 10)
    lut10_full = stats(rows, "lut10_hex", "lut10_addr_hex", golden, 10)
    full_lsb_1 = sum(abs(int(row["lut10_hex"], 16) - golden[index]) > 1
                     for index, row in enumerate(rows))
    symmetry_bad = sum(int(indexed[f"{raw:04x}"]["lut10_hex"], 16) +
                       int(indexed[f"{(-raw) & 65535:04x}"]["lut10_hex"], 16) != 4096
                       for raw in range(0, 32768, 64))
    after = protected_hashes()
    if before != after:
        raise RuntimeError("Protected design/LUT files changed during audit")
    report = dict(
        generated_utc=datetime.now(timezone.utc).isoformat(),
        status="FAIL_DEFAULT_Q4_12" if default["wrong_known"] or default["unknown"] else "PASS",
        scope="Standalone sigmoid.sv only; no ALU or rowwise module compiled or simulated",
        oracle="Decimal precision 50; round-half-even(4096 / (1 + exp(-signed_raw / 4096)))",
        contract="Signed 16-bit Q4.12; 4 integer bits include sign; [-8, 7.999755859375]",
        lut=dict(entries=len(table), word_bits=16, equivalent_to_data_lut=digest(LUT) == digest(DATA_LUT),
                 q4_6_reference_mismatches=table_bad, q4_6_grid_symmetry_failures=symmetry_bad),
        default_16bit=default, diagnostic_10bit_against_q4_6_input=lut10,
        diagnostic_10bit_against_original_q4_12_input=lut10_full,
        diagnostic_10bit_over_1_lsb_count=full_lsb_1,
        transition_samples=len(transition_rows), transition_inconsistencies=transition_bad,
        source_files_unchanged=True, protected_sha256_before=before, protected_sha256_after=after,
        test_sha256={name: digest(HERE / name) for name in ("audit.py", "run.ps1", "tb_sigmoid.sv")},
    )
    (HERE / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    examples = [-32768, -32704, -32256, -31745, -31744, -4096, -1, 0, 1, 63, 64, 4096, 32767]
    example_table = []
    for raw in examples:
        row = indexed[f"{raw & 65535:04x}"]
        example_table.append(f"| {raw / 4096:.12g} | `{row['x_hex']}` | `{golden[raw + 32768]:04x}` | "
                             f"`{row['default_hex']}` | `{row['default_addr_hex']}` | `{row['lut10_hex']}` |")
    worst = default["worst_known"]
    worst10 = lut10_full["worst_known"]
    text = f"""# Kiểm thử riêng IP sigmoid — Q4.12

**Kết luận: {report['status']}.** Khối `sigmoid` với tham số mặc định `(inWidth=16, dataWidth=16)` và LUT hiện có **không đáp ứng đầu vào Q4.12 đầy đủ**. Không sửa RTL, LUT hoặc script sinh LUT. Không compile/test ALU, `rowwise_op` hoặc core.

## Phạm vi và chuẩn đối chiếu

- DUT: `Verilog Source code/sigmoid.sv` nguyên trạng; `sigContent.mif` sao chép nguyên byte từ cùng thư mục vào thư mục mô phỏng riêng. Hai bản LUT trong `Verilog Source code` và `data/sigmoid` có SHA-256 giống nhau.
- Q4.12 có 16 bit signed, 4 bit phần nguyên gồm dấu; miền [-8, 7.999755859375], LSB = 1/4096 = 0.000244140625.
- Golden độc lập dùng Python Decimal precision=50: `round_half_even(4096 / (1 + exp(-raw_signed/4096)))`. Không gọi/import script sinh LUT. Quy tắc làm tròn gần nhất khớp script hiện tại; không có kết luận ngầm rằng mọi LUT xấp xỉ phải có sai số 0 nếu yêu cầu cho phép sai số khác.
- Quét **65.536/65.536 mã đầu vào**, theo thứ tự signed tăng dần. Mỗi input giữ 1 ns cho logic tổ hợp ổn định; đây là functional simulation, không xác nhận timing sau synthesis.
- Thêm **4.112 lần đổi đầu vào**: 16 tình huống biên/đổi dấu/lặp giá trị và 4.096 mẫu xorshift seed cố định. Số kết quả khác lần quét đầu: **{transition_bad}**.
- Cấu hình chẩn đoán thứ hai: cùng RTL, override `inWidth=10`, output 16 bit, nhận `x[15:6]` **chỉ trong testbench**, đúng mô tả script sinh LUT. Có đủ 1.024 mã đầu vào Q4.6; mỗi mã được thử với cả 64 tổ hợp bit thấp của Q4.12. Đây không phải thay đổi thiết kế hay kiểm thử tích hợp.

## Kết quả

| Phép kiểm | Kết quả |
|---|---:|
| DUT mặc định 16 bit: trùng golden Q4.12 | {default['exact']}/65536 |
| DUT mặc định: output xác định nhưng sai | {default['wrong_known']}/65536 |
| DUT mặc định: output X/Z | {default['unknown']}/65536 |
| DUT mặc định: mapping địa chỉ khác `raw XOR 0x8000` | {default['address_errors']} |
| LUT 1024 word so golden Q4.6 → Q4.12 | {table_bad} lỗi |
| DUT 10 bit so golden tại đầu vào Q4.6 đã cắt | {lut10['exact']}/65536 đúng, {lut10['unknown']} X/Z |
| DUT 10 bit: mapping địa chỉ / ngoài [0,1] / giảm đơn điệu | {lut10['address_errors']} / {lut10['range_errors_known']} / {lut10['adjacent_decreases_known']} lỗi |
| DUT 10 bit: symmetry `sigmoid(x)+sigmoid(-x)=4096` trên lưới Q4.6 có đối xứng | {symmetry_bad}/512 lỗi |
| DUT 10 bit so golden của Q4.12 ban đầu | {lut10_full['exact']}/65536 trùng, {lut10_full['wrong_known']}/65536 khác |
| DUT 10 bit: sai số tối đa so golden Q4.12 ban đầu | {lut10_full['max_abs_error_raw_known']} LSB = {lut10_full['max_abs_error_raw_known']/4096:.12g} |
| DUT 10 bit: số input sai quá 1 LSB so golden Q4.12 ban đầu | {full_lsb_1}/65536 |

## Sai ở đâu

### F01 — Không tương thích độ rộng IP với số entry/scale LUT (FAIL)

- `Verilog Source code/sigmoid.sv:1` mặc định `inWidth=16`; dòng 6 tạo `2**16=65536` word; dòng 11 nạp `sigContent.mif`.
- Bảng đang có **1024 dòng**, được sinh cho **input 10-bit Q4.6**, bước 1/64. Xem `python/generate_sigmoid_lut.py:7` và các default ở dòng 44–47. Bảng đúng số học trong miền/scale riêng của nó.
- DUT 16 bit truy cập địa chỉ 0..65535 nhưng chỉ 0..1023 được nạp. **Địa chỉ 1024..65535 cho output X**, tương ứng input signed raw -31744..32767 (x từ -7.75 đến 7.999755859375). Đây là nguyên nhân {default['unknown']} input không có kết quả số; không gán X thành 0 và không tính X vào sai số số học.
- **Ngay cả 1024 địa chỉ đã nạp cũng lệch scale**: với DUT16, địa chỉ `a` phải biểu diễn `x=-8+a/4096`; LUT hiện biểu diễn `x=-8+a/64`. Trong vùng này có {default['wrong_known']} output sai và {default['exact']} output tình cờ bằng golden sau làm tròn.
- Sai số lớn nhất trong vùng output xác định: raw input `{worst['x_hex']}`, x={worst['x']}, actual={worst['actual_raw']}, expected={worst['expected_raw']}, lệch **{worst['error_raw']} LSB**. Không coi đây là sai số tối đa toàn miền vì phần còn lại là X.
- `sigmoid.sv:17–20` ánh xạ dấu/địa chỉ đúng trong cả hai cấu hình được kiểm tra; không tìm thấy lỗi riêng trong phép cộng/trừ offset này.

### F02 — Cấu hình 10 bit là xấp xỉ đầu vào, không bảo toàn 12 bit phần lẻ (giới hạn độ chính xác)

- Cấu hình 10 bit hoạt động đúng với input Q4.6 và LUT hiện tại: toàn bộ 1.024 mã đều cho giá trị Q4.12 đúng theo làm tròn gần nhất.
- Nếu bắt đầu từ Q4.12 rồi lấy `x[15:6]`, input bị lượng tử xuống lưới Q4.6 (floor, kể cả số âm). So với sigmoid của **input Q4.12 gốc**, sai số có thể **{lut10_full['max_abs_error_raw_known']} LSB**. Ví dụ raw `{worst10['x_hex']}` (x={worst10['x']}): actual={worst10['actual_raw']}, golden={worst10['expected_raw']}.
- Q4.12 chỉ xác định cách mã hóa; nếu yêu cầu chính xác là đúng giá trị sau làm tròn hoặc ≤1 LSB trên toàn miền, cấu hình chẩn đoán này cũng không đạt. Nếu được phép LUT xấp xỉ với ngưỡng khác, phải đánh giá theo ngưỡng đó. Nó không làm thay đổi kết luận FAIL của cấu hình mặc định hiện tại do output X.

## Ví dụ từ mô phỏng thực

Giá trị đều là raw hex 16 bit, output chia 4096 để ra số thực. `xxxx` là unknown. Cột 10 bit là cấu hình chẩn đoán trong testbench.

| x thực Q4.12 | Input | Golden Q4.12 | DUT mặc định | Địa chỉ DUT | DUT 10 bit |
|---:|---|---|---|---|---|
{chr(10).join(example_table)}

## Tái lập và bằng chứng

- Chạy từ workspace: `& '.\\review\\sigmoid_20260918\\run.ps1'`.
- Runner chỉ compile `sigmoid.sv` và `tb_sigmoid.sv`, dùng ModelSim Intel FPGA Starter 2020.1. Exit code 1 là audit chạy hoàn tất nhưng DUT mặc định FAIL; lỗi hạ tầng cũng được báo bằng exception riêng.
- `sim/compile.log`: compile; `sim/simulation.log`: transcript; `sim/observed.csv`: đủ 69.648 dòng dữ liệu, gồm input, output và địa chỉ của hai DUT.
- `verification.json`: số đo và SHA-256 trước/sau của mọi file trực tiếp trong thư mục RTL, cả hai LUT và generator; xác nhận **không thay đổi các file thiết kế**.
- `$readmemb("sigContent.mif",...)` dùng đường dẫn tương đối với working directory. Audit đã cung cấp đúng bản LUT hiện có bằng cách copy nguyên byte vào thư mục mô phỏng riêng, không dùng fixture zero, không sinh đè LUT và không sửa path của RTL.

Chưa tự sửa bất kỳ lỗi nào. Các file mới chỉ nằm trong `review/sigmoid_20260918` để kiểm thử và báo cáo.
"""
    (HERE / "REVIEW.md").write_text(text, encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim-bin", default=r"C:\intelFPGA\20.1\modelsim_ase\win32aloem")
    args = parser.parse_args()
    sim_bin = Path(args.sim_bin)
    before = protected_hashes()
    SIM.mkdir(exist_ok=True)
    print("Preparing independent Decimal Q4.12 oracle...", flush=True)
    golden = reference()
    shutil.copyfile(LUT, SIM / "sigContent.mif")
    if digest(LUT) != digest(SIM / "sigContent.mif"):
        raise RuntimeError("Simulation LUT copy differs from source")
    print("Compiling only sigmoid.sv and standalone testbench...", flush=True)
    if not (SIM / "work").exists():
        run_command([sim_bin / "vlib.exe", "work"], SIM / "library.log")
    run_command([sim_bin / "vlog.exe", "-sv", "-work", "work", RTL, HERE / "tb_sigmoid.sv"], SIM / "compile.log")
    print("Running exhaustive standalone RTL simulation...", flush=True)
    run_command([sim_bin / "vsim.exe", "-c", "-onfinish", "exit", "-l", "simulation.log",
                 "work.tb_sigmoid", "-do", "run -all; quit -f"], SIM / "console.log")
    transcript = (SIM / "simulation.log").read_text(errors="replace")
    if "SIGMOID_AUDIT_COMPLETE exhaustive=65536 transitions=4112" not in transcript:
        raise RuntimeError("Simulation completion marker missing")
    if re.search(r"^# \*\* (?:Error|Fatal):", transcript, re.MULTILINE):
        raise RuntimeError("Simulator reported an unexpected error/fatal")
    report = analyze(golden, before)
    print(json.dumps({k: report[k] for k in ("status", "default_16bit", "diagnostic_10bit_against_q4_6_input",
                                            "diagnostic_10bit_against_original_q4_12_input",
                                            "transition_inconsistencies", "source_files_unchanged")}, indent=2), flush=True)
    print(f"Report: {HERE / 'REVIEW.md'}", flush=True)
    raise SystemExit(1 if report["status"].startswith("FAIL") else 0)


if __name__ == "__main__":
    main()
