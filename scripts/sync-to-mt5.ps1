# Sync repository mt5/ sources into every MetaTrader 5 terminal MQL5 folder.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/sync-to-mt5.ps1 [-TerminalId <hash>]

param(
    [string]$TerminalId = "D0E8209F77C8CF37AD8BF550E51FF075"
)

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

$terminalDataPath = Join-Path $terminalRoot $TerminalId
if (-not (Test-Path $terminalDataPath)) {
    throw "Terminal data folder not found for TerminalId=$TerminalId under $terminalRoot"
}

$activeMql5 = Join-Path $terminalDataPath "MQL5"
if (-not (Test-Path $activeMql5)) {
    throw "Terminal MQL5 folder not found for TerminalId=$TerminalId under $terminalRoot"
}

$mql5Paths = @($activeMql5)
$syncReport = New-Object System.Collections.Generic.List[string]
Write-Host "sync_target_terminal_id=$TerminalId"
Write-Host "sync_target_mql5_path=$activeMql5"
Write-Host "sync_destination_count=1"
Write-Host "sync_multi_terminal_mode=false"
Write-Host "Syncing to: $activeMql5"
Sync-ToTerminal -Mql5Path $activeMql5 -Report $syncReport

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
