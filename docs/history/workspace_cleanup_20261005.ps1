# One-time workspace cleanup authorized by the user's "cleanup workspace" request.
# Preserve source changes, immutable evidence, current unit library and RAM model.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot))).TrimEnd('\')
$manifestPath = Join-Path $PSScriptRoot 'workspace_cleanup_20261005.json'
$archivePath = Join-Path $PSScriptRoot 'optimization_implementation_20261005.zip'
if ((Test-Path -LiteralPath $manifestPath) -or (Test-Path -LiteralPath $archivePath)) {
    throw 'Cleanup history already exists; do not overwrite or replay.'
}
$active = @(Get-Process -Name quartus*,vsim*,vlog,vopt -ErrorAction SilentlyContinue)
if ($active.Count) { throw 'EDA processes are active; cache cleanup must wait.' }

function Resolve-WorkspaceTarget([string]$relative) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $repo $relative))
    if (-not $absolute.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target escapes workspace: $relative"
    }
    $cursor = $absolute
    while ($cursor -ne $repo) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point in target: $cursor"
            }
        }
        $cursor = Split-Path $cursor
    }
    return $absolute
}
function Relative-Name([string]$absolute) {
    return $absolute.Substring($repo.Length + 1).Replace('\','/')
}
function File-Hash([string]$absolute) {
    return (Get-FileHash -LiteralPath $absolute -Algorithm SHA256).Hash.ToLowerInvariant()
}

$tracked = @{}
Push-Location $repo
try {
    $gitBefore = @(git status --short)
    foreach ($name in @(git ls-files)) { $tracked[$name] = $true }
} finally { Pop-Location }

# Capture exact protected bytes before deleting only derived caches/history helpers.
$protected = @{}
$protectedRoots = @('Verilog Source code','docs/verification','tests/full_rtl/evidence')
foreach ($relative in $protectedRoots) {
    foreach ($file in Get-ChildItem -LiteralPath (Resolve-WorkspaceTarget $relative) -Recurse -File -Force) {
        $protected[(Relative-Name $file.FullName)] = File-Hash $file.FullName
    }
}
foreach ($relative in @('quartus/llm_soc.qpf','quartus/llm_soc.qsf','quartus/llm_soc.sdc',
                       'quartus/matmul_free.qpf','quartus/matmul_free.qsf','quartus/matmul_free.sdc',
                       'tests/full_rtl/unit_results.json','AGENTS.md','ARCH_RESEARCH.md','TASK_STATE.md')) {
    $absolute = Resolve-WorkspaceTarget $relative
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { $protected[$relative] = File-Hash $absolute }
}
# Also preserve every tracked file's current bytes, including pre-existing dirty changes.
foreach ($relative in $tracked.Keys) {
    $absolute = Resolve-WorkspaceTarget $relative
    if (Test-Path -LiteralPath $absolute -PathType Leaf) { $protected[$relative] = File-Hash $absolute }
}

$targets = [Collections.Generic.List[object]]::new()
$quartusRoots = @('quartus','quartus_attention1','quartus_cache1','quartus_cache2',
    'quartus_explicit1','quartus_explicit2','quartus_fanout1','quartus_fanout2',
    'quartus_logic5','quartus_logic6','quartus_logic7','quartus_pipeline1')
foreach ($project in $quartusRoots) {
    foreach ($cache in @('db','incremental_db')) {
        $relative = "$project/$cache"
        $absolute = Resolve-WorkspaceTarget $relative
        if (Test-Path -LiteralPath $absolute -PathType Container) {
            $targets.Add([pscustomobject]@{path=$relative;absolute=$absolute;reason='Regenerable Quartus database'})
        }
    }
}
$build = Resolve-WorkspaceTarget 'tests/full_rtl/build'
foreach ($library in Get-ChildItem -LiteralPath $build -Directory -Force) {
    if ($library.Name -ne 'opt_final4' -and (Test-Path -LiteralPath (Join-Path $library.FullName '_info'))) {
        $relative = Relative-Name $library.FullName
        $absolute = Resolve-WorkspaceTarget $relative
        $targets.Add([pscustomobject]@{path=$relative;absolute=$absolute;reason='Inactive compiled Questa work library'})
    }
}
foreach ($cache in Get-ChildItem -LiteralPath (Join-Path $repo 'tools') -Directory -Recurse -Force -Filter '__pycache__') {
    $relative = Relative-Name $cache.FullName
    $absolute = Resolve-WorkspaceTarget $relative
    $targets.Add([pscustomobject]@{path=$relative;absolute=$absolute;reason='Regenerable Python bytecode'})
}
$tmp = Resolve-WorkspaceTarget 'tmp'
if ((Test-Path -LiteralPath $tmp -PathType Container) -and
    @(Get-ChildItem -LiteralPath $tmp -Force).Count -eq 0) {
    $targets.Add([pscustomobject]@{path='tmp';absolute=$tmp;reason='Empty temporary directory'})
}

# Preserve the one-shot transformations as history rather than live runnable tools.
$historyFiles = @()
foreach ($name in @('optimization_wave1.py','optimization_wave2.py','optimization_wave3.py',
    'optimization_wave4.py','optimization_wave5.py','optimization_cleanup.py',
    'optimization_cleanup_repair.py','optimization_genvar_compat.py','optimization_share_divider.py')) {
    $absolute = Resolve-WorkspaceTarget ('tools/' + $name)
    if (Test-Path -LiteralPath $absolute -PathType Leaf) {
        $historyFiles += Get-Item -LiteralPath $absolute
        $targets.Add([pscustomobject]@{path=('tools/' + $name);absolute=$absolute;reason='One-shot script preserved in verified history ZIP'})
    }
}
$staging = Resolve-WorkspaceTarget 'tools/optimization_staging'
if (Test-Path -LiteralPath $staging -PathType Container) {
    $historyFiles += @(Get-ChildItem -LiteralPath $staging -Recurse -File -Force)
    $targets.Add([pscustomobject]@{path='tools/optimization_staging';absolute=$staging;reason='Superseded staging preserved in verified history ZIP'})
}

$removed = @()
foreach ($target in $targets) {
    $item = Get-Item -LiteralPath $target.absolute -Force
    $items = @($item)
    if ($item.PSIsContainer) { $items += @(Get-ChildItem -LiteralPath $target.absolute -Recurse -Force) }
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
        throw "Reparse point below target: $($target.path)"
    }
    $files = @($items | Where-Object { -not $_.PSIsContainer })
    foreach ($file in $files) {
        $relative = Relative-Name $file.FullName
        if ($tracked.ContainsKey($relative) -or $protected.ContainsKey($relative)) {
            throw "Target contains protected/tracked file: $relative"
        }
    }
    $removed += [ordered]@{path=$target.path;resolved_path=$target.absolute;files=$files.Count;
        bytes=[long](($files | Measure-Object -Property Length -Sum).Sum);reason=$target.reason}
}

Add-Type -AssemblyName System.IO.Compression
$historyHashes = @{}
$zip = [IO.Compression.ZipFile]::Open($archivePath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($file in $historyFiles) {
        $relative = Relative-Name $file.FullName
        $historyHashes[$relative] = File-Hash $file.FullName
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative,
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $zip.Dispose() }
$zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
try {
    foreach ($entry in $zip.Entries) {
        $stream = $entry.Open()
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $hash = [Convert]::ToHexString($algorithm.ComputeHash($stream)).ToLowerInvariant() }
        finally { $stream.Dispose(); $algorithm.Dispose() }
        if ($hash -ne $historyHashes[$entry.FullName]) { throw "History ZIP mismatch: $($entry.FullName)" }
    }
    if ($zip.Entries.Count -ne $historyHashes.Count) { throw 'History ZIP entry count mismatch' }
} finally { $zip.Dispose() }

Write-Output "Preflight PASS: $($targets.Count) checked targets; $($protected.Count) protected files; $($historyHashes.Count) archived helper files."
foreach ($target in $targets) {
    # Resolve and verify the absolute boundary again immediately before deletion.
    $absolute = Resolve-WorkspaceTarget $target.path
    Remove-Item -LiteralPath $absolute -Recurse -Force
}
foreach ($relative in $protected.Keys) {
    $absolute = Resolve-WorkspaceTarget $relative
    if (-not (Test-Path -LiteralPath $absolute -PathType Leaf) -or
        (File-Hash $absolute) -ne $protected[$relative]) { throw "Protected file changed: $relative" }
}
Push-Location $repo
try { $gitAfter = @(git status --short) } finally { Pop-Location }
$removedBytes = [long]0
foreach ($record in $removed) { $removedBytes += [long]$record.bytes }
$archiveBytes = (Get-Item -LiteralPath $archivePath).Length
[ordered]@{
    status='PASS';completed_utc=[DateTime]::UtcNow.ToString('o');
    authorization='User requested cleanup workspace';
    scope='Inactive generated caches; one-shot optimization helpers archived before removal';
    removed=$removed;removed_bytes=$removedBytes;archive_bytes=$archiveBytes;
    net_bytes_freed=($removedBytes-$archiveBytes);
    history_archive=(Relative-Name $archivePath);history_archive_sha256=(File-Hash $archivePath);
    history_entry_sha256=$historyHashes;protected_files_verified=$protected.Count;
    protected_file_sha256=$protected;git_status_before=$gitBefore;git_status_after=$gitAfter;
    preserved='All RTL, tracked-file working contents, configurations, baseline/results/log/source archives, current opt_final4 library, RAM models, mixed source/probe folders and Git history';
    reproduction='Fresh simulation libraries and timing databases are regenerated by existing verification runners; the archived one-shot transformations must not be replayed against current RTL'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "CLEANUP_PASS: freed $([math]::Round(($removedBytes-$archiveBytes)/1GB,3)) GiB; protected bytes unchanged."
