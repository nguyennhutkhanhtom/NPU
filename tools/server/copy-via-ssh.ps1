# Copy a file, or the CONTENTS of a folder, through SSH to a Linux directory.
# Use only after administrator authorization for this transfer method.
# Example: .\tools\server\copy-via-ssh.ps1 -AdminApprovedTransfer -SourcePath '.\tests\full_rtl\build\bundle_TAG' -TargetPath '~/project/test_khanh/bundle_TAG'
# Requires Windows OpenSSH and Linux bash, realpath, base64, sha256sum.
# Enter the SSH password at its normal console prompt; no password is saved.
[CmdletBinding()]
param(
    [string]$SourcePath,
    [string]$TargetPath,
    [switch]$AdminApprovedTransfer,
    [ValidatePattern('^[A-Za-z0-9.-]+$')][string]$Server = 'red.doelab.site',
    [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$User = 'ee5303_09',
    [ValidateRange(1, 65535)][int]$Port = 22,
    [switch]$UseRunbookPassword,
    [string]$RunbookPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'SERVER_ACCESS.md')
)

$ErrorActionPreference = 'Stop'
if (-not $AdminApprovedTransfer) { throw 'Administrator authorization for SSH file transfer is required. Do not use this script to bypass lab transfer restrictions.' }
if (-not $SourcePath) { $SourcePath = Read-Host 'Local file/folder path' }
if (-not $TargetPath) { $TargetPath = Read-Host 'Remote task directory (e.g. ~/project/test_khanh/bundle_TAG)' }
if ([string]::IsNullOrWhiteSpace($TargetPath) -or $TargetPath.Contains("`n") -or $TargetPath.Contains("`r")) {
    throw 'Target directory must be a nonempty, single-line path.'
}
$source = Get-Item -LiteralPath $SourcePath
if ($source.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Source symlinks/junctions are not supported.' }
$entries = @()
if ($source.PSIsContainer) {
    # Traverse explicitly so a junction cannot lead outside the chosen source.
    $pending = New-Object 'System.Collections.Generic.Queue[System.IO.DirectoryInfo]'
    $pending.Enqueue($source)
    while ($pending.Count -gt 0) {
        foreach ($entry in Get-ChildItem -LiteralPath $pending.Dequeue().FullName -Force) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Source contains a symlink/junction: $($entry.FullName)"
            }
            $entries += $entry
            if ($entry.PSIsContainer) { $pending.Enqueue($entry) }
        }
    }
} else { $entries = @($source) }
foreach ($entry in $entries) {
    if ($entry.Name -in @('SERVER_ACCESS.md', 'ee5303_09.conf') -or
        ($entry.PSIsContainer -and $entry.Name -in @('.git', '.ssh', '.aws'))) {
        throw "Protected local file/folder found: $($entry.FullName). Choose a source folder containing only files intended for transfer."
    }
}

function Quote-Bash([string]$Value) { "'" + $Value.Replace("'", "'\''") + "'" }
function Relative-Name($Entry) {
    if ($source.PSIsContainer) {
        return $Entry.FullName.Substring($source.FullName.TrimEnd('\').Length + 1).Replace('\', '/')
    }
    return $Entry.Name
}
$ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$auth = $null
if ($UseRunbookPassword) {
    . (Join-Path $PSScriptRoot 'ssh-auth.ps1')
    $auth = New-NpuSshAuth $Server $User $RunbookPath
    $ssh = $auth.Ssh
}
$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $ssh
$knownHosts = Join-Path $env:USERPROFILE '.ssh/known_hosts'
$start.Arguments = "-T -p $Port -o StrictHostKeyChecking=yes -o UserKnownHostsFile=`"$knownHosts`" -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 $User@$Server bash -s"
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.StandardInputEncoding = New-Object System.Text.UTF8Encoding($false)
if ($auth) { foreach ($key in $auth.Environment.Keys) { $start.EnvironmentVariables[$key] = $auth.Environment[$key] } }
$process = New-Object System.Diagnostics.Process
$process.StartInfo = $start
Write-Host "Copying $($source.FullName) -> ${User}@${Server}:$TargetPath"
Write-Host 'Existing identical files are kept; different files cause CONFLICT and are never overwritten.'
$null = $process.Start()
try {
    $writer = $process.StandardInput
    $writer.NewLine = "`n"
    $writer.WriteLine('set -eu')
    $writer.WriteLine('task_requested=' + (Quote-Bash $TargetPath))
    $writer.WriteLine(@'
case "$task_requested" in
    '~') task_requested="$HOME" ;;
    '~/'*) task_requested="$HOME/${task_requested#\~/}" ;;
    /*) ;;
    *) task_requested="$HOME/$task_requested" ;;
esac
task_dest=$(realpath -m -- "$task_requested")
task_base=$(realpath -m -- "$HOME/project/test_khanh")
case "$task_dest" in
    "$task_base"/*) ;;
    *) printf 'Target must be a task directory under %s\n' "$task_base" >&2; exit 3 ;;
esac
printf 'TARGET %s\n' "$task_dest"
mkdir -p -- "$task_dest"
cd -- "$task_dest"
task_errors=0
task_verified=0
task_created=0
task_identical=0
safe_parent() {
    task_parent=$(dirname -- "$1")
    while [ "$task_parent" != '.' ]; do
        [ ! -L "$task_parent" ] || return 1
        task_parent=$(dirname -- "$task_parent")
    done
}
'@)
    foreach ($entry in $entries) {
        $relative = './' + (Relative-Name $entry)
        $writer.WriteLine('task_file=' + (Quote-Bash $relative))
        if ($entry.PSIsContainer) {
            $writer.WriteLine('if safe_parent "$task_file" && [ ! -L "$task_file" ]; then mkdir -p -- "$task_file"; else printf "CONFLICT %s\n" "$task_file"; task_errors=$((task_errors+1)); fi')
            continue
        }
        $bytes = [IO.File]::ReadAllBytes($entry.FullName)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $writer.WriteLine('task_hash=' + (Quote-Bash $hash))
        $writer.WriteLine(@'
if ! safe_parent "$task_file" || [ -L "$task_file" ]; then
    printf 'CONFLICT %s\n' "$task_file"; task_errors=$((task_errors+1))
elif [ -e "$task_file" ]; then
    if [ -f "$task_file" ] && [ "$(sha256sum -- "$task_file" | cut -d ' ' -f1)" = "$task_hash" ]; then
        printf 'IDENTICAL %s\n' "$task_file"
        task_verified=$((task_verified+1)); task_identical=$((task_identical+1))
    else
        printf 'CONFLICT %s\n' "$task_file"; task_errors=$((task_errors+1))
    fi
else
    mkdir -p -- "$(dirname -- "$task_file")"
    if (set -C; base64 -d > "$task_file" <<'CODEX_SOURCE_BYTES'
'@)
        $writer.WriteLine([Convert]::ToBase64String($bytes))
        $writer.WriteLine(@'
CODEX_SOURCE_BYTES
    ); then
        if [ "$(sha256sum -- "$task_file" | cut -d ' ' -f1)" = "$task_hash" ]; then
            printf 'CREATED_VERIFIED %s\n' "$task_file"
            task_verified=$((task_verified+1)); task_created=$((task_created+1))
        else
            printf 'HASH_FAILURE %s\n' "$task_file"; task_errors=$((task_errors+1))
        fi
    else
        printf 'WRITE_FAILURE %s\n' "$task_file"; task_errors=$((task_errors+1))
    fi
fi
'@)
    }
    $writer.WriteLine('printf "RESULT verified=%s created=%s identical=%s errors=%s destination=%s\n" "$task_verified" "$task_created" "$task_identical" "$task_errors" "$task_dest"')
    $writer.WriteLine('[ "$task_errors" -eq 0 ] && echo COPY_VERIFIED || exit 3')
    $writer.Close()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "SSH/copy failed (exit $($process.ExitCode)). Review messages above; some files may already have been copied. Rerunning keeps identical files." }
} finally {
    if (-not $process.HasExited) {
        $process.StandardInput.Close()
        $process.WaitForExit()
    }
    $process.Dispose()
    if ($auth) { Remove-NpuSshAuth $auth }
}
