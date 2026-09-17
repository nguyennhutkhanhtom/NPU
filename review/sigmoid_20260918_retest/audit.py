"""Standalone clocked sigmoid retest. Writes only inside this audit directory."""
import argparse
import csv
import hashlib
import json
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from decimal import Decimal, ROUND_HALF_EVEN, localcontext
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
SIM = HERE / "sim"
RTL = ROOT / "Verilog Source code" / "sigmoid.sv"
LUT = RTL.with_name("sigContent.mif")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_hashes():
    paths = sorted(RTL.parent.glob("*"))
    paths += [ROOT / "data/sigmoid/sigContent.mif", ROOT / "python/generate_sigmoid_lut.py"]
    return {p.relative_to(ROOT).as_posix(): digest(p) for p in paths if p.is_file()}


def golden_values():
    with localcontext() as ctx:
        ctx.prec = 50
        return [int((Decimal(4096) / (1 + (-Decimal(raw) / 4096).exp()))
                    .to_integral_value(rounding=ROUND_HALF_EVEN))
                for raw in range(-32768, 32768)]


def command(args, filename):
    with (SIM / filename).open("w", encoding="utf-8") as log:
        run = subprocess.run([str(a) for a in args], cwd=SIM, stdout=log, stderr=subprocess.STDOUT)
    if run.returncode:
        raise RuntimeError(f"Command failed, inspect sim/{filename}")


def number(value):
    return None if re.search("[xz]", value.lower()) else int(value, 16)


def score(rows, golden):
    errors = []
    unknown = address_bad = lut_bad = range_bad = 0
    for row in rows:
        raw = int(row["x_hex"], 16)
        signed = raw if raw < 32768 else raw - 65536
        # Arithmetic floor onto Q4.6 grid; independently derived in signed space.
        grid_raw = (signed // 64) * 64
        address_bad += number(row["addr_hex"]) != signed // 64 + 512
        actual = number(row["out_hex"])
        if actual is None:
            unknown += 1
            continue
        lut_bad += actual != golden[grid_raw + 32768]
        range_bad += not 0 <= actual <= 4096
        errors.append(actual - golden[signed + 32768])
    return dict(samples=len(rows), unknown=unknown, address_errors=address_bad,
                lookup_mismatches=lut_bad, output_range_errors=range_bad,
                exact_q4_12=sum(e == 0 for e in errors),
                different_q4_12=sum(e != 0 for e in errors),
                over_1_lsb=sum(abs(e) > 1 for e in errors),
                max_abs_error_lsb=max(map(abs, errors), default=None),
                min_signed_error_lsb=min(errors, default=None),
                max_signed_error_lsb=max(errors, default=None),
                mean_abs_error_lsb=sum(map(abs, errors)) / len(errors) if errors else None)


def analyze(golden, before, transcript):
    with (SIM / "observed.csv").open(newline="", encoding="ascii") as stream:
        all_rows = list(csv.DictReader(stream))
    sweep = [r for r in all_rows if r["phase"] == "0"]
    extra = [r for r in all_rows if r["phase"] != "0"]
    if [int(r["x_hex"], 16) for r in sweep] != [r & 65535 for r in range(-32768, 32768)]:
        raise RuntimeError("Incomplete exhaustive coverage")
    if len(extra) != 4112:
        raise RuntimeError("Incomplete directed/random coverage")
    primary = score(sweep, golden)
    transitions = score(extra, golden)
    indexed = {r["x_hex"]: r for r in sweep}
    transition_changed = sum(any(r[k] != indexed[r["x_hex"]][k] for k in ("out_hex", "addr_hex")) for r in extra)
    values = [number(r["out_hex"]) for r in sweep]
    decreases = sum(a is not None and b is not None and b < a for a, b in zip(values, values[1:]))
    lines = LUT.read_text(encoding="ascii").splitlines()
    if any(not re.fullmatch("[01]{16}", line) for line in lines):
        raise RuntimeError("Malformed LUT word")
    table = [int(line, 2) for line in lines]
    table_errors = sum(a != b for a, b in zip(table, golden[::64])) + abs(len(table) - 1024)
    clock_match = re.search(r"CLOCK_CHECKS count=(\d+) errors=(\d+)", transcript)
    if not clock_match or int(clock_match[1]) != 3 * len(all_rows):
        raise RuntimeError("Missing/incomplete clock checks")
    startup = re.search(r"STARTUP_BEFORE_FIRST_POSEDGE out=(\w+) addr=(\w+)", transcript)
    after = source_hashes()
    if before != after:
        raise RuntimeError("Design files changed while this audit was running")
    structural_fail = any(primary[k] or transitions[k] for k in
                          ("unknown", "address_errors", "lookup_mismatches", "output_range_errors"))
    structural_fail |= bool(int(clock_match[2]) or transition_changed or table_errors or decreases)
    report = dict(
        generated_utc=datetime.now(timezone.utc).isoformat(),
        status="FAIL_LOOKUP_OR_CLOCK" if structural_fail else "PASS_LOOKUP_AND_CLOCK_WITH_Q4_12_APPROXIMATION",
        exact_q4_12_status="FAIL" if primary["different_q4_12"] or primary["unknown"] else "PASS",
        one_lsb_status="FAIL" if primary["over_1_lsb"] or primary["unknown"] else "PASS",
        scope="Only sigmoid.sv and standalone clocked testbench; no ALU/core compilation or simulation",
        oracle="Independent Decimal precision 50, nearest ties-to-even, signed Q4.12",
        sweep=primary, transitions=transitions, transition_inconsistencies=transition_changed,
        monotonicity_decreases=decreases, lut_entries=len(table), lut_q4_6_mismatches=table_errors,
        clock_checks=int(clock_match[1]), clock_errors=int(clock_match[2]),
        startup_out=startup[1] if startup else None, startup_addr=startup[2] if startup else None,
        source_files_unchanged=True, protected_sha256_before=before, protected_sha256_after=after,
        test_sha256={n: digest(HERE / n) for n in ("audit.py", "run.ps1", "tb_sigmoid.sv")},
    )
    (HERE / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    examples = [-32768, -32256, -31744, -4096, -1473, -1, 0, 1, 63, 64, 4096, 32767]
    example_lines = []
    for raw in examples:
        r = indexed[f"{raw & 65535:04x}"]
        actual = number(r["out_hex"])
        expected = golden[raw + 32768]
        example_lines.append(f"| {raw / 4096:.12g} | `0x{r['x_hex']}` | `0x{r['out_hex']}` | `0x{expected:04x}` | "
                             f"{actual - expected if actual is not None else 'X'} |")
    body = f"""# Kiểm thử lại sigmoid sau chỉnh sửa — 18/09/2026

**Kết quả:** `{report['status']}`. So với chuẩn sigmoid Q4.12 làm tròn gần nhất: `{report['exact_q4_12_status']}`; nếu yêu cầu sai số ≤1 LSB: `{report['one_lsb_status']}`.

IP mới nhận 16-bit Q4.12, dùng 10 bit cao tra ROM 1024 phần tử và chốt địa chỉ tại cạnh lên `clk`. Lỗi thiếu entry/lệch ánh xạ của lần trước đã hết trong bản này. Giá trị output mã hóa Q4.12 đúng, nhưng sigmoid được tính tại đầu vào đã lượng tử xuống Q4.6, nên chưa đạt độ chính xác đầy đủ theo đầu vào Q4.12 gốc.

## Cách kiểm thử

- ModelSim Intel FPGA Starter 2020.1, chỉ compile RTL `Verilog Source code/sigmoid.sv` và testbench mới có `clk`. Không dùng testbench tổ hợp cũ; không compile/test ALU, rowwise hoặc core.
- Quét đủ **65.536 đầu vào** signed Q4.12 [-8, 7.999755859375], thêm **4.112 mẫu** đổi dấu, biên, lặp giá trị và ngẫu nhiên có seed cố định.
- Golden độc lập: Decimal precision=50, `round_half_even(4096 / (1 + exp(-raw_signed/4096)))`. Không gọi generator. Oracle thứ hai lấy input `floor(raw_signed/64)*64` để phân biệt lỗi lookup với sai số cắt bit.
- Đưa input ổn định 2 ns trước cạnh lên, đọc output 1 ns sau cạnh lên để tránh race với NBA. Chủ động thay đổi input khi clock thấp, khi clock cao và kiểm tra cạnh xuống. Đây là functional RTL simulation, không xác nhận timing sau synthesis.
- Copy nguyên byte LUT hiện tại vào thư mục mô phỏng riêng, kiểm tra SHA-256; không sinh lại hoặc sửa LUT.

## Kết quả đo

| Phép kiểm | Kết quả |
|---|---:|
| Output X/Z sau cạnh lên trên toàn miền | {primary['unknown']}/65536 |
| Địa chỉ sai so với `floor(raw_signed/64)+512` | {primary['address_errors']}/65536 |
| Sai lookup so với sigmoid tại input đã cắt xuống Q4.6 | {primary['lookup_mismatches']}/65536 |
| LUT so với golden Q4.6 → Q4.12 | {table_errors}/1024 sai |
| Output nằm ngoài [0,1] | {primary['output_range_errors']}/65536 |
| Vi phạm đơn điệu trên miền signed tăng dần | {decreases} |
| Sai giữ giá trị giữa cạnh lên / tại cạnh xuống | {clock_match[2]}/{clock_match[1]} |
| Mẫu bổ sung: X / sai lookup / khác lần quét trước | {transitions['unknown']} / {transitions['lookup_mismatches']} / {transition_changed} trên 4112 mẫu |
| Trùng sigmoid chính xác của input Q4.12 sau làm tròn | {primary['exact_q4_12']}/65536 |
| Khác chuẩn Q4.12 sau làm tròn | {primary['different_q4_12']}/65536 |
| Sai quá 1 LSB so chuẩn Q4.12 | {primary['over_1_lsb']}/65536 |
| Sai số tuyệt đối tối đa so chuẩn đã làm tròn | {primary['max_abs_error_lsb']} LSB = {primary['max_abs_error_lsb'] / 4096:.12g} |
| Khoảng sai số có dấu actual − golden | [{primary['min_signed_error_lsb']}, {primary['max_signed_error_lsb']}] LSB |

## Vị trí còn gây sai lệch

**`Verilog Source code/sigmoid.sv:16`: `assign x_lut = x[15:6];`** bỏ 6 bit phần lẻ thấp. Do đó 64 mã Q4.12 liên tiếp cùng dùng một kết quả. LUT lấy mẫu với bước 1/64 trong khi input Q4.12 có bước 1/4096. Phép cắt này tương đương floor với số âm, không phải round-to-nearest.

Ví dụ input `0xFFFF` = −0.000244140625: sau cắt bit thành −0.015625, output `0x07F0` = 0.49609375, trong khi sigmoid của input gốc làm tròn Q4.12 phải là `0x0800` = 0.5. Sai **−16 LSB**.

Đây là giới hạn độ chính xác của LUT 10-bit theo cách lấy mẫu hiện tại. Q4.12 tự nó là định dạng mã hóa, không xác định ngưỡng sai số cho xấp xỉ. Nếu yêu cầu chỉ là input/output Q4.12 với LUT xấp xỉ cho phép sai số nêu trên thì lookup và clock đã đạt. Nếu yêu cầu kết quả làm tròn chính xác hoặc sai số ≤1 LSB trên toàn miền thì **chưa đạt**. Không tự chọn ngưỡng 16 LSB làm tiêu chí pass.

## Hành vi clock và khởi động

- `sigmoid.sv:18–23` chốt địa chỉ tại cạnh lên. Output phản ánh input được lấy mẫu ở cạnh đó sau khi register cập nhật và phép đọc ROM ổn định; không cập nhật ngay khi chỉ thay đổi input. Test đủ mọi input liên tiếp theo từng cạnh lên để kiểm tra không lệch mẫu.
- Trước cạnh lên đầu tiên, đo được `out={report['startup_out']}`, `y={report['startup_addr']}` vì thanh ghi `y` không có reset/initial. Sau cạnh lên có input xác định, output hợp lệ. Không kết luận đây là lỗi nếu đặc tả cho phép bỏ qua output lúc khởi động; chỉ ghi nhận giới hạn giao tiếp của IP.

## Ví dụ mô phỏng

Golden là sigmoid của input Q4.12 gốc, làm tròn gần nhất; actual được đọc sau cạnh lên.

| x | Input | Actual | Golden | Lệch LSB |
|---:|---|---|---|---:|
{chr(10).join(example_lines)}

## Bằng chứng và tái lập

- Chạy: `& '.\\review\\sigmoid_20260918_retest\\run.ps1'`. Exit code 1 biểu thị đã hoàn tất kiểm thử nhưng không trùng chuẩn Q4.12 chính xác; 2 là lỗi chạy audit; 3 là lỗi chức năng lookup/clock.
- `sim/compile.log`, `sim/simulation.log`, `sim/observed.csv`: log mới và 69.648 mẫu thực tế. Transcript có marker hoàn tất và số kiểm tra giữ output.
- `verification.json`: kết quả máy đọc và hash trước/sau của các file thiết kế, LUT, generator.
- Báo cáo lần trước được giữ nguyên tại `review/sigmoid_20260918/REVIEW.md`.

**Không sửa RTL, LUT, generator hoặc các file thiết kế khác.** Hash trước/sau trong lần kiểm thử này giống nhau.
"""
    (HERE / "REVIEW.md").write_text(body, encoding="utf-8")
    return report


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sim-bin", default=r"C:\intelFPGA\20.1\modelsim_ase\win32aloem")
    args = parser.parse_args()
    sim_bin = Path(args.sim_bin)
    before = source_hashes()
    SIM.mkdir(exist_ok=True)
    print("Preparing independent Q4.12 reference...", flush=True)
    golden = golden_values()
    shutil.copyfile(LUT, SIM / "sigContent.mif")
    if digest(LUT) != digest(SIM / "sigContent.mif"):
        raise RuntimeError("LUT copy mismatch")
    if not (SIM / "work").exists():
        command([sim_bin / "vlib.exe", "work"], "library.log")
    print("Compiling only updated sigmoid and clocked standalone testbench...", flush=True)
    command([sim_bin / "vlog.exe", "-sv", "-work", "work", RTL, HERE / "tb_sigmoid.sv"], "compile.log")
    print("Running exhaustive clocked simulation...", flush=True)
    command([sim_bin / "vsim.exe", "-c", "-onfinish", "exit", "-l", "simulation.log",
             "work.tb_sigmoid", "-do", "run -all; quit -f"], "console.log")
    transcript = (SIM / "simulation.log").read_text(errors="replace")
    if "SIGMOID_RETEST_COMPLETE exhaustive=65536 transitions=4112" not in transcript:
        raise RuntimeError("Missing completion marker")
    if re.search(r"^# \*\* (?:Error|Fatal):", transcript, re.MULTILINE):
        raise RuntimeError("Simulation error/fatal; inspect transcript")
    report = analyze(golden, before, transcript)
    print(json.dumps({k: report[k] for k in ("status", "exact_q4_12_status", "one_lsb_status", "sweep",
                     "transitions", "clock_checks", "clock_errors", "startup_out", "source_files_unchanged")}, indent=2))
    print(f"Report: {HERE / 'REVIEW.md'}", flush=True)
    return 3 if report["status"].startswith("FAIL") else (1 if report["exact_q4_12_status"] == "FAIL" else 0)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"AUDIT EXECUTION ERROR: {error}", file=sys.stderr)
        sys.exit(2)
