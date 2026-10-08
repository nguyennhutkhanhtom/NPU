# Download only reports/TAG as a binary-safe archive; never overwrite a local archive.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_-]{1,64}$')][string]$Tag,
    [Parameter(Mandatory=$true)][ValidatePattern('^[A-Za-z0-9_./~-]+$')][string]$RemoteRoot,
    [switch]$AdminApprovedTransfer,
    [string]$OutputDirectory = (Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'tests/full_rtl/build/server_reports'),
    [Alias('RunbookPath')][string]$CredentialPath = (Join-Path $PSScriptRoot '.local/credentials.json')
)
$ErrorActionPreference = 'Stop'
if (-not $AdminApprovedTransfer) { throw 'Administrator authorization for report transfer is required.' }
. (Join-Path $PSScriptRoot 'ssh-auth.ps1')
$auth = New-NpuSshAuth 'red.doelab.site' 'ee5303_09' $CredentialPath
$ssh = $auth.Ssh
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$archive = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) ($Tag + '.tar.gz')
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = $ssh
$start.Arguments = '-T -o PubkeyAuthentication=no -o PreferredAuthentications=password -o StrictHostKeyChecking=yes -o ConnectTimeout=10 -o NumberOfPasswordPrompts=1 ee5303_09@red.doelab.site bash -s'
$start.UseShellExecute = $false
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
if ($auth) { foreach ($key in $auth.Environment.Keys) { $start.EnvironmentVariables[$key] = $auth.Environment[$key] } }
$process = New-Object Diagnostics.Process
$process.StartInfo = $start
$stream = $null
try {
    $stream = [IO.File]::Open($archive, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    $null = $process.Start()
    $process.StandardInput.NewLine = "`n"
    $process.StandardInput.WriteLine('set -eu')
    $process.StandardInput.WriteLine('task_root=' + "'$RemoteRoot'")
    $process.StandardInput.WriteLine('case "$task_root" in "~/"*) task_root="$HOME/${task_root#\~/}" ;; esac')
    $process.StandardInput.WriteLine('task_root=$(realpath -e -- "$task_root")')
    $process.StandardInput.WriteLine('task_base=$(realpath -m -- "$HOME/project/test_khanh")')
    $process.StandardInput.WriteLine('case "$task_root" in "$task_base"/*) ;; *) echo "Unexpected task directory" >&2; exit 2 ;; esac')
    $process.StandardInput.WriteLine('cd "$task_root/reports"')
    $process.StandardInput.WriteLine("test -d '$Tag'")
    $process.StandardInput.WriteLine("tar -czf - -- '$Tag'")
    $process.StandardInput.Close()
    $process.StandardOutput.BaseStream.CopyTo($stream)
    $stream.Dispose(); $stream = $null
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Report download failed; partial archive retained at $archive" }
    Write-Output "REPORT_ARCHIVE: $archive"
    Get-FileHash -LiteralPath $archive -Algorithm SHA256
} finally {
    if ($stream) { $stream.Dispose() }
    $process.Dispose()
    if ($auth) { Remove-NpuSshAuth $auth }
}
