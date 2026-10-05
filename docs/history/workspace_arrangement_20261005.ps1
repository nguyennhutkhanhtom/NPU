# Record byte-preserving moves before separate documentation/link updates.
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Split-Path (Split-Path $PSScriptRoot))).TrimEnd('\')
$manifestPath = Join-Path $PSScriptRoot 'workspace_arrangement_20261005.json'
if (Test-Path -LiteralPath $manifestPath) { throw 'Arrangement already recorded; do not replay.' }
if (@(Get-Process -Name quartus*,vsim*,vlog,vopt -ErrorAction SilentlyContinue).Count) {
    throw 'EDA processes are active.'
}
function Checked-Path([string]$relative) {
    $absolute = [IO.Path]::GetFullPath((Join-Path $repo $relative))
    if (-not $absolute.StartsWith($repo + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escapes workspace: $relative"
    }
    $cursor = $absolute
    while ($cursor -ne $repo) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point: $cursor"
            }
        }
        $cursor = Split-Path $cursor
    }
    return $absolute
}
$plan = @(
    @('rtl_change_review.md','docs/reviews/rtl_change_review.md'),
    @('rtl_change_review_v2.md','docs/reviews/rtl_change_review_v2.md'),
    @('rtl_change_review_v3.md','docs/reviews/rtl_change_review_v3.md'),
    @('ARCH_RESEARCH.md','docs/design/architecture_research.md'),
    @('TASK_STATE.md','docs/history/task_state_20261004.md'),
    @('tools/optimization_checkpoint.py','tools/optimization/checkpoint.py')
)
foreach ($name in @('quartus_attention1','quartus_cache1','quartus_cache2','quartus_explicit1',
    'quartus_explicit2','quartus_fanout1','quartus_fanout2','quartus_logic5',
    'quartus_logic6','quartus_logic7','quartus_pipeline1')) {
    $plan += ,@($name,('quartus/archive/' + $name))
}
$records = @()
foreach ($pair in $plan) {
    $source = Checked-Path $pair[0]
    $destination = Checked-Path $pair[1]
    if (-not (Test-Path -LiteralPath $source)) { throw "Source missing: $source" }
    if (Test-Path -LiteralPath $destination) { throw "Destination exists: $destination" }
    $item = Get-Item -LiteralPath $source -Force
    $files = @($item)
    if ($item.PSIsContainer) {
        $items = @(Get-ChildItem -LiteralPath $source -Recurse -Force)
        if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) {
            throw "Reparse point below: $source"
        }
        $files = @($items | Where-Object { -not $_.PSIsContainer })
    }
    $hashes = [ordered]@{}
    foreach ($file in $files) {
        $relative = if ($item.PSIsContainer) { $file.FullName.Substring($source.Length + 1).Replace('\','/') } else { '.' }
        $hashes[$relative] = (Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    }
    $records += [pscustomobject]@{source=$pair[0];destination=$pair[1];files=$files.Count;
        bytes=[long](($files | Measure-Object Length -Sum).Sum);sha256_at_move=$hashes}
}
foreach ($record in $records) {
    $source = Checked-Path $record.source
    $destination = Checked-Path $record.destination
    $parent = Split-Path $destination
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    Move-Item -LiteralPath $source -Destination $destination
    foreach ($name in $record.sha256_at_move.Keys) {
        $file = if ($name -eq '.') { $destination } else { Join-Path $destination $name }
        if ((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -ne $record.sha256_at_move[$name]) {
            throw "Move changed bytes: $file"
        }
    }
}
[ordered]@{status='MOVE_PASS';completed_utc=[DateTime]::UtcNow.ToString('o');
    authorization='User requested arrange files';moves=$records;
    scope='Reports, research, historical task state, checkpoint helper and retired Quartus projects';
    immutable_evidence='Verification evidence and source snapshots remain at their original paths; retired Quartus files verified byte-exact after moving';
    subsequent_edits='Documentation links and navigation may be updated; the relocated checkpoint helper requires its repository-root calculation to follow the new depth; TASK_STATE.md becomes a current navigation entry'
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Write-Output "ARRANGEMENT_MOVE_PASS: $($records.Count) moves; all file hashes match."
