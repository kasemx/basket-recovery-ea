# Compile BasketRecovery EA and all test scripts after syncing to the active MT5 terminal.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/compile-all.ps1 [-TerminalId <hash>]

param(
    [string]$TerminalId = "D0E8209F77C8CF37AD8BF550E51FF075"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$logDir = Join-Path $repo "build\logs"
$testLogDir = Join-Path $logDir "tests"
$summaryPath = Join-Path $repo "build\compile-summary.json"

if (-not (Test-Path $metaeditor)) {
    Write-Error "metaeditor64.exe not found at: $metaeditor"
}

$sync = & (Join-Path $repo "scripts\sync-to-mt5.ps1") -TerminalId $TerminalId
$mql5 = $sync.Mql5Path
$terminalId = Split-Path (Split-Path $mql5 -Parent) -Leaf

New-Item -ItemType Directory -Force -Path $logDir, $testLogDir | Out-Null

function Invoke-Mq5Compile {
    param([string]$RelativePath, [string]$LogPath)
    $source = Join-Path $mql5 $RelativePath
    & $metaeditor /compile:"$source" /log:"$LogPath" | Out-Null
    Start-Sleep -Seconds 2
    if (-not (Test-Path $LogPath)) {
        return @{ Errors = -1; Warnings = -1; WarningsList = @() }
    }
    $content = Get-Content $LogPath -Raw
    $errors = -1
    $warnings = -1
    if ($content -match 'Result: (\d+) errors, (\d+) warnings') {
        $errors = [int]$Matches[1]
        $warnings = [int]$Matches[2]
    }
    $warningLines = @()
    Get-Content $LogPath | Where-Object { $_ -match ' : warning ' } | ForEach-Object { $warningLines += $_ }
    return @{ Errors = $errors; Warnings = $warnings; WarningsList = $warningLines }
}

$results = @()
$eaLog = Join-Path $logDir "BasketRecoveryEA.compile.log"
$ea = Invoke-Mq5Compile "Experts\BasketRecovery\BasketRecoveryEA.mq5" $eaLog
$results += [PSCustomObject]@{
    File = "BasketRecoveryEA.mq5"
    Errors = $ea.Errors
    Warnings = $ea.Warnings
    Log = $eaLog
}

$validationScripts = @(
    "Scripts\BasketRecovery\Validation\Sprint8C\IssueSprint8cProfitCloseAuthToken.mq5"
)
foreach ($rel in $validationScripts) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($rel)
    $logPath = Join-Path $logDir "$baseName.compile.log"
    $r = Invoke-Mq5Compile $rel $logPath
    $results += [PSCustomObject]@{
        File = [System.IO.Path]::GetFileName($rel)
        Errors = $r.Errors
        Warnings = $r.Warnings
        Log = $logPath
    }
}

Get-ChildItem (Join-Path $repo "mt5\Scripts\BasketRecovery\Tests\Test*.mq5") | Sort-Object Name | ForEach-Object {
    $logName = "$($_.BaseName).compile.log"
    $logPath = Join-Path $testLogDir $logName
    $rel = "Scripts\BasketRecovery\Tests\$($_.Name)"
    $r = Invoke-Mq5Compile $rel $logPath
    $results += [PSCustomObject]@{
        File = $_.Name
        Errors = $r.Errors
        Warnings = $r.Warnings
        Log = $logPath
    }
}

$allWarnings = @()
foreach ($row in $results) {
    if (Test-Path $row.Log) {
        Get-Content $row.Log | Where-Object { $_ -match ' : warning ' } | ForEach-Object {
            $allWarnings += [PSCustomObject]@{ File = $row.File; Message = $_ }
        }
    }
}

$summary = [ordered]@{
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    metaEditorPath = $metaeditor
    terminalMql5Path = $mql5
    syncReportPath = $sync.SyncReportPath
    syncedFileCount = $sync.SyncedCount
    ea = @{
        file = "BasketRecoveryEA.mq5"
        errors = $ea.Errors
        warnings = $ea.Warnings
        log = $eaLog
    }
    tests = @($results | Where-Object { $_.File -ne "BasketRecoveryEA.mq5" } | ForEach-Object {
        @{
            file = $_.File
            errors = $_.Errors
            warnings = $_.Warnings
            log = $_.Log
        }
    })
    totalErrors = ($results | Where-Object { $_.Errors -gt 0 -or $_.Errors -lt 0 } | Measure-Object).Count
    warnings = @($allWarnings | ForEach-Object { @{ file = $_.File; message = $_.Message } })
}

$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $summaryPath -Encoding UTF8

$results | Format-Table -AutoSize
Write-Host "Summary: $summaryPath"
Write-Host "MetaEditor: $metaeditor"
Write-Host "Terminal MQL5: $mql5"

$failed = $results | Where-Object { $_.Errors -ne 0 }
if ($failed.Count -gt 0) {
    Write-Host "COMPILE GATE FAILED: $($failed.Count) file(s) with errors" -ForegroundColor Red
    exit 1
}
Write-Host "COMPILE GATE PASSED" -ForegroundColor Green

$deploymentProof = @()
$deployTargets = @(
    @{ Relative = "Experts\BasketRecovery\BasketRecoveryEA.ex5"; RuntimeMarker = "S8C_PROFIT_CLOSE_SUBMIT_V2" },
    @{ Relative = "Scripts\BasketRecovery\Validation\Sprint8C\IssueSprint8cProfitCloseAuthToken.ex5"; RuntimeMarker = "S8C_AUTH_ISSUE_SCRIPT_V2" }
)
foreach ($target in $deployTargets) {
    $ex5Path = Join-Path $mql5 $target.Relative
    if (Test-Path $ex5Path) {
        $item = Get-Item $ex5Path
        $deploymentProof += [PSCustomObject]@{
            terminalId = $terminalId
            relativePath = $target.Relative
            fullPath = $ex5Path
            lastWriteTime = $item.LastWriteTime.ToString("o")
            sizeBytes = $item.Length
            runtimeMarker = $target.RuntimeMarker
        }
    } else {
        $deploymentProof += [PSCustomObject]@{
            terminalId = $terminalId
            relativePath = $target.Relative
            fullPath = $ex5Path
            lastWriteTime = "MISSING"
            sizeBytes = 0
            runtimeMarker = $target.RuntimeMarker
        }
    }
}

$proofPath = Join-Path $repo "build\deployment-proof-sprint8c.json"
$deploymentProof | ConvertTo-Json -Depth 4 | Set-Content -Path $proofPath -Encoding UTF8
Write-Host "Deployment proof: $proofPath"
$deploymentProof | Format-Table -AutoSize

exit 0
