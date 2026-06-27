# Compile BasketRecovery EA and all test scripts after syncing to the active MT5 terminal.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/compile-all.ps1

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$logDir = Join-Path $repo "build\logs"
$testLogDir = Join-Path $logDir "tests"
$summaryPath = Join-Path $repo "build\compile-summary.json"

if (-not (Test-Path $metaeditor)) {
    Write-Error "metaeditor64.exe not found at: $metaeditor"
}

$sync = & (Join-Path $repo "scripts\sync-to-mt5.ps1")
$mql5 = $sync.Mql5Path

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
exit 0
