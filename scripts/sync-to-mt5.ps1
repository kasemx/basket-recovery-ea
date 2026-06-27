# Sync repository mt5/ sources into every MetaTrader 5 terminal MQL5 folder.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/sync-to-mt5.ps1

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$mt5Source = Join-Path $repo "mt5"
$terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"

function Get-TerminalMql5Paths {
    if (-not (Test-Path $terminalRoot)) {
        throw "MetaQuotes Terminal folder not found: $terminalRoot"
    }

    return @(Get-ChildItem $terminalRoot -Directory |
        ForEach-Object { Join-Path $_.FullName "MQL5" } |
        Where-Object { Test-Path $_ })
}

function Sync-Directory {
    param(
        [string]$SourceRelative,
        [string]$TargetRoot,
        [System.Collections.Generic.List[string]]$Report
    )

    $source = Join-Path $mt5Source $SourceRelative
    if (-not (Test-Path $source)) {
        return
    }

    $target = Join-Path $TargetRoot $SourceRelative
    New-Item -ItemType Directory -Force -Path $target | Out-Null

    robocopy $source $target /E /MIR /NFL /NDL /NJH /NJS /nc /ns /np `
        /XD ".git" "build" "__pycache__" ".vs" `
        /XF "*.ex5" "*.log" "*.tmp" "*.bak" | Out-Null

    Get-ChildItem $source -Recurse -File |
        Where-Object {
            $_.Extension -notin @(".ex5", ".log", ".tmp", ".bak") -and
            $_.FullName -notmatch '\\\.git\\|\\build\\'
        } |
        ForEach-Object {
            $relative = $_.FullName.Substring($source.Length).TrimStart('\')
            [void]$Report.Add((Join-Path $SourceRelative $relative))
        }
}

function Sync-ToTerminal {
    param(
        [string]$Mql5Path,
        [System.Collections.Generic.List[string]]$Report
    )

    Sync-Directory -SourceRelative "Experts" -TargetRoot $Mql5Path -Report $Report
    Sync-Directory -SourceRelative "Include" -TargetRoot $Mql5Path -Report $Report
    Sync-Directory -SourceRelative "Scripts" -TargetRoot $Mql5Path -Report $Report

    $filesSource = Join-Path $mt5Source "Files\BasketRecovery"
    $filesTarget = Join-Path $Mql5Path "Files\BasketRecovery"
    if (Test-Path $filesSource) {
        New-Item -ItemType Directory -Force -Path $filesTarget | Out-Null
        robocopy $filesSource $filesTarget /E /NFL /NDL /NJH /NJS /nc /ns /np `
            /XF "*.ex5" "*.log" "*.tmp" | Out-Null
        Get-ChildItem $filesSource -Recurse -File | ForEach-Object {
            $relative = $_.FullName.Substring($filesSource.Length).TrimStart('\')
            [void]$Report.Add((Join-Path "Files\BasketRecovery" $relative))
        }
    }
}

$mql5Paths = Get-TerminalMql5Paths
if ($mql5Paths.Count -eq 0) {
    throw "No terminal data folders with MQL5 found under $terminalRoot"
}

$preferredId = "D0E8209F77C8CF37AD8BF550E51FF075"
$activeMql5 = $mql5Paths | Where-Object { $_ -like "*\$preferredId\MQL5" } | Select-Object -First 1
if (-not $activeMql5) {
    $activeMql5 = $mql5Paths | Sort-Object { (Get-Item (Split-Path $_ -Parent)).LastWriteTime } -Descending | Select-Object -First 1
}

$syncReport = New-Object System.Collections.Generic.List[string]
foreach ($path in $mql5Paths) {
    Write-Host "Syncing to: $path"
    Sync-ToTerminal -Mql5Path $path -Report $syncReport
}

$uniqueReport = $syncReport | Sort-Object -Unique
$reportPath = Join-Path $repo "build\sync-report.txt"
New-Item -ItemType Directory -Force -Path (Join-Path $repo "build") | Out-Null
$uniqueReport | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Active terminal MQL5 (compile target): $activeMql5"
Write-Host "Synchronized terminals: $($mql5Paths.Count)"
Write-Host "Unique relative paths: $($uniqueReport.Count)"
Write-Host "Sync report: $reportPath"
foreach ($line in $uniqueReport) {
    Write-Host "  synced: $line"
}

return @{
    Mql5Path = $activeMql5
    AllMql5Paths = $mql5Paths
    SyncReportPath = $reportPath
    SyncedCount = $uniqueReport.Count
}
