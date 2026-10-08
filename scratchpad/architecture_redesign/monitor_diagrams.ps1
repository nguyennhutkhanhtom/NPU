param([int]$IntervalSeconds = 3)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$renderStatus = Join-Path $PSScriptRoot 'render_status.json'
$validation = Join-Path $taskRoot 'docs/diagrams/architecture_validation.json'
while ($true) {
    if (Test-Path -LiteralPath $renderStatus) {
        $result = Get-Content -LiteralPath $renderStatus -Raw | ConvertFrom-Json
        if ($result.status -eq 'failed') { throw "Diagram render failed. Inspect $renderStatus" }
        if ($result.status -eq 'complete') {
            $audit = Get-Content -LiteralPath $validation -Raw | ConvertFrom-Json
            if ($audit.status -ne 'PASS') { throw "Diagram validation failed. Inspect $validation" }
            foreach ($property in $audit.artifact_sha256.PSObject.Properties) {
                $artifact = Join-Path (Join-Path $taskRoot 'docs/diagrams') $property.Name
                if ((Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value) {
                    throw "Diagram changed after validation: $artifact"
                }
            }
            $manifest = Get-Content -LiteralPath (Join-Path $taskRoot 'docs/diagrams/architecture_manifest.json') -Raw | ConvertFrom-Json
            foreach ($property in $manifest.source_hashes.PSObject.Properties) {
                $sourceFile = Join-Path (Join-Path $taskRoot 'Verilog Source code') $property.Name
                if ((Get-FileHash -LiteralPath $sourceFile -Algorithm SHA256).Hash.ToLowerInvariant() -ne $property.Value) {
                    throw "RTL/LUT changed after diagram review: $sourceFile"
                }
            }
            Write-Host "ARCHITECTURE_DIAGRAMS_PASS: $($result.pages) rendered pages; native XML, artifact hashes and RTL/LUT hashes verified."
            break
        }
    }
    Write-Host 'Architecture preview rendering is still running.'
    Start-Sleep -Seconds $IntervalSeconds
}
