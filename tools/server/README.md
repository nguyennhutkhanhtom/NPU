# Flow test and synthesis on DOE Lab

This page is an operational runbook. If simulation, synthesis, timing, Slurm, or
X11 are unfamiliar, read [NPU and RTL fundamentals](../../docs/00-start-here/fundamentals.md)
and the [glossary](../../docs/00-start-here/glossary.md) first. Follow the commands
here exactly because tool modules, compute allocation, and display forwarding are
part of the approved EDA environment.

This is the current running guide on branch `remote`. EDA runs on Linux compute
node in Slurm: **Xcelium (`xrun`) for testing, Genus for synthesis**. Do not use
Quartus, ModelSim, Questa, or local Verilator. This file is the only reading point for
connection, SSH/X11, transfer, test, and synthesis; `SERVER_ACCESS.md` has been replaced
with a redirect notice.

## Server connection and authentication

| Setup | Value |
|---|---|
| VPN | WireGuard tunnel `ee5303_09`, enabled on the SSH execution machine |
| VPN config | `ee5303_09.conf`, stored locally only; do not read/input/copy content |
| SSH host / port | `red.doelab.site`, TCP `22` |
| Linux account | `ee5303_09` |
| Compute nodes | `black`, `gray`, `white`, allocated via Slurm |
| Task directory | `$HOME/project/test_khanh`, check resolved/symlink path before writing |
| Remote Desktop | Same host/account, 16-bit color according to lab instructions; keep X11 session active |

Users enable VPN on the actual machine executing SSH; Codex does not read VPN config or
change VPN/DNS. Connection from sandbox/cloud is not by default on VPN. SSH uses
password; manual login must disable public-key authentication:

```powershell
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password ee5303_09@red.doelab.site
```

Verify the host key with a trusted source when encountering a new host/mismatch; do not accept automatically
Unknown key and do not disable host-key checking. Change password on first use/MFA performed by the user
at a trusted prompt; do not guess or retry a rejected password.

Passwords are not in Markdown. Local authentication data has been separated into
`tools/server/.local/credentials.json`, ignored by Git, ACL only for the account
Current Windows and SYSTEM. Do not read/print passwords, commit, upload or put them into
command arguments, environment, transcript or logs. File storing information
`host`, `user`, `password`; if updates are needed, only modify locally, do not
copy the value into the document. You can use the manual SSH prompt; flow scripts always
use the password in local credentials.

Check the date 2026-10-08 again with local credentials and `ssh-auth.ps1`: SSH login
successful, the command `hostname` returns `red.doelab.site`, host-key checking still
enabled. This is a login node access check; Slurm has not been provisioned or EDA run in
this check. When needing to update the password, edit the local file directly or use
SSH prompt, do not send the value into chat. Do not automatically retry rejected passwords.

`copy-via-ssh.ps1` and `get-reports.ps1` always use `ssh-auth.ps1`. Helper uses
Git for Windows SSH and temporary askpass: read JSON
in memory, only return the password to the correct prompt for the above account/host. Do not
run the helper standalone; stdout is only consumed by SSH. Helper is removed after the session,
environment is only set for the SSH process. `DISPLAY=codex:0` of askpass is a local value
to enable the helper, not the X11 display on the server; real X11 is authenticated
separately by the launcher below. Use `StrictHostKeyChecking=yes`, user's known_hosts,
timeout 10 seconds and a maximum of one password prompt.

Password flow checked on 2026-10-08: SSH confirms authentication
`password`; copy the new file and copy the file with the same hash again to achieve `COPY_VERIFIED`;
download the archive and then extract it with a SHA256 matching the original UTF-8 file. Helper is temporarily acceptable
clean up. Local evidence:
`tests/full_rtl/build/scratchpad/password_probe_4b453ac6430046b0a321a79bf883037c/result.json`.

### Scope of operation

SSH login, check read-only and edit related to tasks approved by the user
permissions in the session; no need to ask again for operations already allowed.
Authorization only applies to the current task, not other work rights.
Transfer, Slurm allocation, and long jobs require corresponding authorization; do not change by yourself
VPN, install software, change account/security or commit/push if not requested.

Remote writes are limited to `.sv`, `.md` related to tasks and files in resolved.
`$HOME/project/test_khanh`. Keep old work/evidence; do not delete or overwrite destructively.
Do not run heavy compute on the login node. Confirm connection, allocation,
module, tool and output from actual results; do not consider documents as EDA PASS.

SFTP/SCP is by default restricted by the lab. Only use admin-approved methods; do not
change protocol or tunnel to bypass restrictions. In this migration session, users
have confirmed the permission to use copy/download scripts via SSH. When transfer is denied,
stop and contact admin. Do not grant permissions from a Markdown guide.

### Connection error handling

| Error | Further checks |
|---|---|
| Cannot resolve/timeout | VPN on the same machine/network namespace; use normal escalation if sandbox has no network |
| Host key mismatch | Stop for user/admin verification, do not disable checking |
| Authentication rejected | Check current credentials; do not retry without new information |
| `module` not on login node | Provide compute node first; module already confirmed on black |
| X11 missing DISPLAY | Keep `--x11`; use the account's own RDP/X11 session via the launcher below |
| Slurm lacks resources | Check the availability/policy of black/gray/white, do not create many sessions or repeated requests |
| Transfer denied | Confirm admin rights for the correct method, do not try to bypass the block |

## Configuration that needs to be corrected when changing environments

| File | Content |
|---|---|
| `tools/server/flow.json` | Package order, excluded FPGA leaf, list of test/top/PASS marker and modules |
| `tools/server/asic.sdc` | 10 ns clock and initial I/O budgets; need review according to actual integration |
| `tools/server/genus.tcl` | Read/elaborate/check/syn_generic/syn_map/syn_opt and export reports |
| `tools/server/run_flow.py` | Preflight, select stage/top, log and hash provenance |

Confirmed `cadence/xcelium/2409` and `cadence/genus/211` on compute node `black`
in Slurm job `64315`; versions are in `flow.json`.
Liberty `.lib` must be provided by the lab, pass `--lib` for each library; do not guess
module, technology/process corner, or install software. You can load modules yourself and
call Python directly; `run.sh` wrapper uses JSON configuration.

## Prepare source and session

1. Turn on VPN according to the connection section above, use SSH with verified host key. Do not change VPN/DNS.
2. Only transfer files using a method allowed by the admin. SFTP/SCP is blocked by default;
   do not use SSH/base64/tar streams, Git clone, or other protocols to bypass restrictions.
   The GitHub version is the deliverable; uploading source to the server must also follow lab policy.
3. Use a new directory in `$HOME/project/test_khanh`, check `realpath` and symlink,
   keep the old source/evidence intact. Do not upload the entire repo including secrets, cache, or logs.
4. After the user approves the allocation, run the command according to lab instructions:

```bash
srun --pty --x11 --nodelist=black -c 2 bash
hostname
echo "$SLURM_JOB_ID"
module avail
```

Keep `--x11` mandatory; there is no fallback to skip this flag. Maximum session is 5 hours
according to instructions. Login to the node using only light operations; runner checks Linux, job ID
and hostname belong to the node list, do not self-assign allocation.

### SSH with X11 from Remote Desktop session of the same account

SSH is not prohibited from running `srun --x11`. Error `No DISPLAY variable set` occurs when SSH
does not have an authenticated display. The Windows machine currently does not have a local X server; the RDP
Linux session of the same account provides a usable display. Probing from SSH
has confirmed `xdpyinfo` on the login node, allocation `64315` on `black` and
`COMPUTE_X11_CONNECTION_OK` with Slurm display `localhost:98.0`.

After transfer is allowed and job authorization runs, from the Windows terminal:

```powershell
ssh -t -o PubkeyAuthentication=no -o PreferredAuthentications=password ee5303_09@red.doelab.site 'bash -l "$HOME/project/test_khanh/bundle_TAG/tools/server/slurm_x11.sh" test --tag test_next'
```

`slurm_x11.sh` use `resolve_x11.py` to check the current DISPLAY or display of
process belongs to **the actual UID**, authenticate using `xdpyinfo`, then run
`srun --pty --x11 --nodelist=black -c 2` with a 5-hour limit. The script does not hardcode
display, does not print cookies, does not modify Xauthority, does not use `xhost +`, does not open
ports or change sshd. It fails before allocation if there is no valid display.
`run.sh` and the Python runner check the X11 connection once again on the compute node.

The launcher supports an ordered list of nodes: `NPU_SLURM_NODES='gray white'`
and `NPU_SLURM_BUSY_TIMEOUT=30` (1..300 seconds per node). By default, it still selects
`NPU_SLURM_NODE` or `black`. Each node is tried only once; `--immediate`
allocation wait limit, no limit on synthesis run time.
Only switch nodes when Slurm returns the busy code `SLURM_EXIT_IMMEDIATE=75`;
X11/module/EDA error stops, does not automatically rerun faulty design.
If all nodes are busy, launcher exits 75. Keep `--x11` and 5-hour job limit.
Busy code convention according to [Slurm srun](https://slurm.schedmd.com/srun.html).

If the RDP/X11 session is closed, reopen the account desktop and try the launcher. Also
can use SSH `-X` when local X server and forwarding are active; do not automatically assign
fake DISPLAY. According to [OpenSSH](https://man.openbsd.org/ssh.1) and
[Slurm srun](https://slurm.schedmd.com/srun.html), SSH forwarding, and Slurm X11
are two separate steps. The login node currently does not have `module`; the module is only loaded after
allocation on the compute node.

In the Remote Desktop terminal, the same launcher is also used:

```bash
cd "$HOME/project/test_khanh/bundle_TAG"
bash -l tools/server/slurm_x11.sh test --tag gui_test_next
```

In the source folder on the compute node:

```bash
python3 tools/server/run_flow.py --check-inputs
module load cadence/xcelium/2409
command -v xrun
python3 tools/server/run_flow.py --stage test --tag test_20261008
python3 tools/server/run_flow.py --stage test --only tb_llm_memory tb_host_cancel_contract --tag ram_debug_20261008
```

The full test consists of 7 groups: memory/math/RAM/protocol/selection/operators/graph, plus
linear stream and host cancel. Retain numeric, collision OLD_DATA, latency, tile,
reset/cancel, and traffic assertions. The memory test checks the portable backend with
expected words independently; no longer validated against FPGA IP. `--only`
only write `SELECTED_GROUPS_PASS`; default write `FULL_SERVER_REGRESSION_PASS` afterwards
all 9 groups. Testbench with force/deposit runs with `-access +rwc`; warning/error
or missing correct marker all cause fail, do not automatically waive diagnostics.

Regression core legacy is kept separate: `python3 tools/server/run_flow.py
--stage legacy --tag legacy_next` runs 9 old tops by Xcelium; Python reference
generates vectors in each separate database, does not overwrite old fixtures. Only runs when
shared RTL changes or legacy needs to be checked; `all` is full graph test + synthesis.

After confirming/loading Genus module and Liberty library, run:

```bash
command -v genus
python3 tools/server/run_flow.py --stage syn --tag syn_20261008 --lib /approved/path/cells.lib
python3 tools/server/run_flow.py --stage all --tag all_20261008 --lib /approved/path/cells.lib
# Or after updating modules in flow.json:
bash -l tools/server/run.sh test --tag test_next
```

The survey library on 2026-10-08 is included in
`tests/full_rtl/build/scratchpad/server_cell_library_20261008.md`.
Full-top run uses `slow_vdd1v0_basicCells.lib` at
`/tools/eda/pdks/cadence/gpdk045/gsclib045_svt_v4.7/gsclib045/timing/`;
The actual header is 0.9 V / 125 C, without inferring PVT from the file name.
Maintain 10 ns clock in `asic.sdc`, top `llm_soc`, `USE_QUARTUS_MEMORY=0`
and original RTL. After transfer, the bundle is allowed to run in the current allocation:

```bash
srun --jobid=JOB_ID --pty --x11 -c 2 bash -l "$HOME/project/test_khanh/bundle_syn_gpdk045_20261008/tools/server/run.sh" syn --tag syn_gpdk045_20261008 --lib /tools/eda/pdks/cadence/gpdk045/gsclib045_svt_v4.7/gsclib045/timing/slow_vdd1v0_basicCells.lib
```

SSH requires DISPLAY/XAUTHORITY to be authenticated by `resolve_x11.py` as the launcher;
do not self-set a fake display. If no allocation remains, use `slurm_x11.sh syn`
with the same `--tag`/`--lib` to issue a new job. Do not relaunch an existing tag.
`genus.version.log` save tool version; `synthesis_progress.log` mark
read/elaborate/generic/map/opt. `generic_area.rpt` exists before mapping and
`check_design_mapped.rpt` check unresolved after optimization. `results.json`
record hash source/library/SDC/report. Completion still requires review of warnings,
unresolved, mapping and timing; not yet physical timing closure.

## Application checkpoint

Keep pinned checkpoint/tokenizer and dependencies in the Python Linux environment
provided by the lab (`tests/language_demo/requirements.txt`); do not copy Windows
packages and does not install dependencies on the server by itself. Prepare fixtures on the compute node:

```bash
python3 tests/full_rtl/export_checkpoint.py --output tests/full_rtl/build/fixture_next --prompt 'Once upon a time' --new-tokens 4 --min-new 4 --temperature 0 --seed 7
python3 tools/server/run_flow.py --stage application --fixture tests/full_rtl/build/fixture_next --tag application_next
```

Exporter rejects already existing directories. Fixture includes parameter/prompt/expected/config
and reference metadata; expected IDs do not control DUT. Application stage is
functional token matching, does not claim FPGA hardware gate/ASIC timing PASS by itself.
Run full separate regression before accepting a shared change.

## Evidence, synthesis and long job

`reports/TAG/results.json` records RUNNING/FAIL/COMPLETED, stage, job ID, node,
commands, input/library/SDC/fixture/report SHA256 and marker for each test. Each top has
console/tool log and file list; `build/TAG` keeps a separate database. Existing tags are
rejected. Do not modify input while the measurement job is running.

Genus exports `llm_soc.v`, `llm_soc.sdc`, `area.rpt`, `timing.rpt`,
`check_design.rpt` and console log. `GENUS_FLOW_COMPLETED` only confirms the generated flow
has sufficient reports/netlist; unresolved design, mapping, timing, and constraints must be reviewed.
RAM is currently inferred portable RTL, SRAM macro not yet bound. Cannot deduce ASIC
physical STA/PPA/DFT/CDC/signoff or FPGA Fmax from this result. Old evidence remains
intact, not to be used to certify new source/configuration.

Optional ASIC runtime mode: add `--syn-ram-blackbox` to `--stage syn` (or `all`).
Only Genus receives `SYNTH_RAM_BLACKBOX`; Xcelium retains functional RAM. The
storage leaf `sram_word_tile` becomes a parameterized black box; wrapper ports,
dimensions and pipeline RTL remain unchanged. For lightweight checks use
`--syn-top llm_parameter_ram` or `--syn-top llm_bank_ram` with the approved `--lib`;
netlist/SDC names follow that top. Keep the 10 ns SDC. Black boxes have no SRAM
area or timing arcs, so reports cover surrounding logic only and cannot establish
complete ASIC PPA or memory-path timing closure. Genus uses two CPUs to match
the launcher allocation.

When a long job is not finished, perform the initial check at most once and then hand over:

```bash
squeue -j "$SLURM_JOB_ID" -o '%.18i %.9T %.20N %.10M'
tail -n 15 reports/TAG/tb_llm_graph.console.log
cat reports/TAG/results.json
```

Record tag, job ID, node, PID (`echo $!` if running in the background), stage, and the
exact log path. Completion is `FLOW_COMPLETED` along with status `COMPLETED`; check
marker/report/hash before continuing. Do not relaunch a running job,
do not poll continuously. Exit the compute shell and then SSH when finished.

Optional bundle for allowed transfer: `prepare_bundle.py --output
tests/full_rtl/build/bundle_TAG` (add `--application` to get fixtures already prepared
in `tests/full_rtl/build`). Bundle types secret/vendor model/evidence and
Do not transfer files. Running the source directly from checkout is also fine.

After the admin allows the script's SSH method, copy from PowerShell:

```powershell
./tools/server/copy-via-ssh.ps1 -AdminApprovedTransfer -SourcePath tests/full_rtl/build/bundle_TAG -TargetPath '~/project/test_khanh/bundle_TAG'
```

The script only accepts task directories under `~/project/test_khanh`, keeping files with the same hash,
rejects files with different hash/symlink and protects credentials/VPN config. Password is read by SSH
askpass in memory; not passed in command arguments or bundle.

## Migration status

Branch `remote` has pushed source commit `f8983f4`. After the user confirms, the admin
allows the transfer, the script confirmed copying 59 files (58 inputs + manifest), zero
errors, at `/home/yellow/ee5303_09/project/test_khanh/server_migration_f8983f4`.
Server preflight: `FLOW_INPUTS_VERIFIED files=58`. Python/Bash syntax, file
list/config and bundle hashes have been checked; not yet EDA PASS.

Initial error due to missing SSH DISPLAY was resolved using the RDP session's X11
belonging to the account. Slurm probe `64315` confirms X11 on `black` and EDA modules;
Allocation probe completed. All new runs keep `--x11`; full regression PASS
is recorded below. Liberty library still needs confirmation before mapped synthesis.

Launcher also successfully provided job `64316`. Runner stopped before EDA due to Python 3.6
on compute not supporting keyword `subprocess(..., text=True)`; switched to
`universal_newlines=True`. Launcher/full-graph stdlib flow compatible with Python 3.6; legacy reference required
Python 3.8+ (`math.isqrt`), checkpoint requires Python/dependencies provided by the lab.

Scoped job `64318` PASS two memory groups (464 checks) and host cancel (14 checks)
via SSH/X11, zero simulator diagnostics. Evidence has downloaded and verified all
report/frozen input SHA256 at
[`server_x11_20261008_verified`](../../tests/full_rtl/evidence/server_x11_20261008_verified/x11_scoped3_20261008/results.json).
Xcelium NODNTW is corrected with explicit net type input in `postscale.sv`, does not
waive warnings and does not change arithmetic.

Full job `64319` passed memory/math/RAM/protocol/selection then stopped at operators:
fixture using a relative LUT path does not exist in the private database
(`RMEMNOF`). Runner currently passes `+SIGMOID_LUT=` absolute; fixture fails early when
file is missing, keep expected arithmetic as is.

**Full regression PASS:** job `64320`, `x11_full2_20261008`, on black via
SSH/X11 has finished and released allocation. Enough 9 groups, zero simulator
diagnostics, `FLOW_COMPLETED` and `FULL_SERVER_REGRESSION_PASS`. Already downloaded and
verified all reports/frozen input SHA256, along with current RTL/tests/runtime scripts:
[`full server evidence`](../../tests/full_rtl/evidence/server_x11_full_20261008/x11_full2_20261008/results.json).
Reports server remains intact at
`/home/yellow/ee5303_09/project/test_khanh/server_x11_lut_20261008/reports/x11_full2_20261008`.
Do not relaunch the completed run. Synthesis has not run; Liberty library needs to be
confirmed. Legacy/application are separate gates, not verified in this run.

Download separate reports of allowed tags:

```powershell
./tools/server/get-reports.ps1 -AdminApprovedTransfer -RemoteRoot '~/project/test_khanh/server_x11_lut_20261008' -Tag x11_full2_20261008
```
