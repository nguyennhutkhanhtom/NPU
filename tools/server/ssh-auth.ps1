# Local-only SSH askpass setup. The password is read in memory by SSH's helper.
function New-NpuSshAuth([string]$Server, [string]$User, [string]$CredentialPath) {
    if ($Server -ne 'red.doelab.site' -or $User -ne 'ee5303_09') {
        throw 'Saved password authentication is restricted to the documented lab account.'
    }
    $credential = (Resolve-Path -LiteralPath $CredentialPath).Path
    $ssh = Join-Path $env:ProgramFiles 'Git/usr/bin/ssh.exe'
    if (-not (Test-Path -LiteralPath $ssh)) { throw 'Git for Windows SSH is required for askpass.' }
    $python = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
    if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python.exe -ErrorAction Stop).Source }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $helperDir = Join-Path $tempRoot ('codex-npu-askpass-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $helperDir
    $helper = Join-Path $helperDir 'askpass.py'
    $shim = Join-Path $helperDir 'askpass.sh'
    $helperCode = @'
import json, os, sys
if len(sys.argv) != 2 or sys.argv[1].strip() != "ee5303_09@red.doelab.site's password:":
    sys.exit(1)
with open(os.environ['DOELAB_CREDENTIAL_FILE'], encoding='utf-8-sig') as f:
    credential = json.load(f)
if credential.get('host') != 'red.doelab.site' or credential.get('user') != 'ee5303_09':
    sys.exit(1)
password = credential.get('password', '')
if not isinstance(password, str) or not password or '\n' in password or '\r' in password:
    sys.exit(1)
sys.stdout.write(password + '\n')
'@
    [IO.File]::WriteAllText($helper, $helperCode, [Text.UTF8Encoding]::new($false))
    $shell = "#!/bin/sh`nexec `"$($python.Replace('\','/'))`" `"$($helper.Replace('\','/'))`" `"`$@`"`n"
    [IO.File]::WriteAllText($shim, $shell, [Text.UTF8Encoding]::new($false))
    [pscustomobject]@{ Ssh = $ssh; HelperDir = $helperDir; TempRoot = $tempRoot; Environment = @{
        SSH_ASKPASS = $shim.Replace('\','/'); SSH_ASKPASS_REQUIRE = 'force'; DISPLAY = 'codex:0'; DOELAB_CREDENTIAL_FILE = $credential
    } }
}
function Remove-NpuSshAuth($Auth) {
    if ($Auth) {
        $resolved = [IO.Path]::GetFullPath($Auth.HelperDir)
        if (-not $resolved.StartsWith($Auth.TempRoot, [StringComparison]::OrdinalIgnoreCase) -or
            (Split-Path $resolved -Leaf) -notlike 'codex-npu-askpass-*') { throw 'Unsafe helper cleanup path.' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
