# Sprint 8C — DEMO hedging preflight only (no seed, no submit).
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-preflight.ps1
#   powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-preflight.ps1 -TerminalDataId <32-char-id>

param(
    [string]$TerminalDataId = ""
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"

function Get-TerminalDataFolderIds {
    if (-not (Test-Path $terminalRoot)) { return @() }
    return @(Get-ChildItem $terminalRoot -Directory |
        Where-Object { $_.Name -match '^[A-F0-9]{32}$' } |
        ForEach-Object { $_.Name })
}

function Assert-TerminalConfigurationExists {
    param([string]$DataId)
    $terminalData = Join-Path $terminalRoot $DataId
    if (-not (Test-Path $terminalData)) {
        throw "Terminal data folder not found: $terminalData"
    }
    $originPath = Join-Path $terminalData "origin.txt"
    if (-not (Test-Path $originPath)) {
        throw "Terminal configuration missing (origin.txt): $originPath"
    }
    $configDir = Join-Path $terminalData "config"
    if (-not (Test-Path $configDir)) {
        throw "Terminal configuration missing (config folder): $configDir"
    }
    return $terminalData
}

function Resolve-TerminalPaths {
    param([string]$DataId)
    $terminalData = Assert-TerminalConfigurationExists -DataId $DataId
    $installRoot = (Get-Content (Join-Path $terminalData "origin.txt") -First 1).Trim()
    if (-not (Test-Path (Join-Path $installRoot "terminal64.exe"))) {
        throw "Terminal executable not found for data id '$DataId': $installRoot\terminal64.exe"
    }
    return @{
        TerminalDataId = $DataId
        TerminalData   = $terminalData
        InstallRoot    = $installRoot
        Mql5Path       = Join-Path $terminalData "MQL5"
        TerminalExe    = Join-Path $installRoot "terminal64.exe"
        MetaEditor     = Join-Path $installRoot "metaeditor64.exe"
    }
}

function Get-LatestTerminalLogFile {
    param([string]$TerminalData)
    $logsDir = Join-Path $TerminalData "logs"
    if (-not (Test-Path $logsDir)) { return $null }
    return Get-ChildItem $logsDir -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-TerminalDiscoveryHints {
    param([string]$TerminalData)
    $hints = [ordered]@{
        InstallOrigin      = ""
        LatestServer       = ""
        LatestLogin        = ""
        TerminalClassification = "UNKNOWN"
        MarginModeHint     = ""
    }
    $originPath = Join-Path $TerminalData "origin.txt"
    if (Test-Path $originPath) {
        $hints.InstallOrigin = (Get-Content $originPath -First 1).Trim()
    }
    $logFile = Get-LatestTerminalLogFile -TerminalData $TerminalData
    if ($null -eq $logFile) { return $hints }
    $lines = Get-Content $logFile.FullName -Tail 400 -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match "authorized on ([^']+)'?") {
            $hints.LatestServer = $matches[1].Trim()
        }
        if ($line -match "'([0-9]+)': authorized on") {
            $hints.LatestLogin = $matches[1]
        }
        if ($line -match "trading has been enabled - hedging mode") {
            $hints.MarginModeHint = "hedging mode (network log)"
        }
        if ($line -match "trading has been enabled - netting mode") {
            $hints.MarginModeHint = "netting mode (network log)"
        }
    }
    $serverUpper = $hints.LatestServer.ToUpperInvariant()
    if ($serverUpper -match "DEMO") {
        $hints.TerminalClassification = "DEMO"
    }
    elseif ($serverUpper -ne "") {
        $hints.TerminalClassification = "NON_DEMO_OR_UNKNOWN"
    }
    return $hints
}

function Find-TerminalDataIdsFromRunningProcesses {
    $processes = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) { return @() }

    $since = ($processes | Sort-Object StartTime | Select-Object -First 1).StartTime.AddMinutes(-2)
    $discoveredMap = @{}
    foreach ($folderId in Get-TerminalDataFolderIds) {
        $terminalData = Join-Path $terminalRoot $folderId
        $logFile = Get-LatestTerminalLogFile -TerminalData $terminalData
        if ($null -eq $logFile -or $logFile.LastWriteTime -lt $since) { continue }
        $lines = Get-Content $logFile.FullName -Tail 400 -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match 'Terminal\s+(.+\\Terminal\\([A-F0-9]{32}))\s*$') {
                $id = $Matches[2]
                if ($id -eq $folderId) {
                    $discoveredMap[$id] = @{
                        TerminalDataId = $id
                        LogPath        = $logFile.FullName
                        LogTime        = $logFile.LastWriteTime
                    }
                }
            }
        }
    }
    return @($discoveredMap.Values)
}

function Select-TerminalDataIdAuto {
    $running = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) {
        throw "Terminal auto-selection failed: no running terminal64.exe instance. Pass -TerminalDataId explicitly."
    }
    if ($running.Count -gt 1) {
        $pids = ($running.Id -join ", ")
        throw "Terminal auto-selection failed: multiple terminal64.exe instances running (pids: $pids). Pass -TerminalDataId explicitly."
    }

    $discovered = @(Find-TerminalDataIdsFromRunningProcesses)
    if ($discovered.Count -eq 0) {
        throw "Terminal auto-selection failed: one terminal64.exe is running but no unambiguous terminal data path was discovered from recent logs. Pass -TerminalDataId explicitly."
    }
    if ($discovered.Count -gt 1) {
        $ids = ($discovered | ForEach-Object { $_.TerminalDataId }) -join ", "
        throw "Terminal auto-selection failed: multiple terminal data candidates detected ($ids). Pass -TerminalDataId explicitly."
    }

    $selectedId = $discovered[0].TerminalDataId
    $hints = Get-TerminalDiscoveryHints -TerminalData (Join-Path $terminalRoot $selectedId)
    if ($hints.TerminalClassification -ne "DEMO") {
        throw "Terminal auto-selection failed: discovered terminal '$selectedId' is not classified as DEMO from latest server log ('$($hints.LatestServer)'). Pass -TerminalDataId only for an intended DEMO terminal."
    }
    return $selectedId
}

function Find-ValidationFile {
    param([string]$RelativePath)
    foreach ($path in @(
        (Join-Path $script:mql5 "Files\$RelativePath"),
        (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\$RelativePath")
    )) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Read-ReportFlag {
    param([string]$ReportPath, [string]$Key)
    if (-not (Test-Path $ReportPath)) { return $null }
    $line = Get-Content $ReportPath | Where-Object { $_ -like "$Key=*" } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1]
}

function Stop-Mt5Instances {
    Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

if ([string]::IsNullOrWhiteSpace($TerminalDataId)) {
    Write-Host "No -TerminalDataId supplied; discovering from running terminal64.exe..."
    $TerminalDataId = Select-TerminalDataIdAuto
}
else {
    $TerminalDataId = $TerminalDataId.Trim()
    if ($TerminalDataId -notmatch '^[A-F0-9]{32}$') {
        throw "Invalid -TerminalDataId format (expected 32-char hex folder id): $TerminalDataId"
    }
    Assert-TerminalConfigurationExists -DataId $TerminalDataId | Out-Null
}

$paths = Resolve-TerminalPaths -DataId $TerminalDataId
$script:mql5 = $paths.Mql5Path
$script:terminalExe = $paths.TerminalExe
$script:metaeditor = $paths.MetaEditor
$script:terminalData = $paths.TerminalData
$script:symbol = "BTCUSD"
$presetDir = Join-Path $script:mql5 "Presets"
$configDir = Join-Path $script:terminalData "config"
$validationDir = Join-Path $repo "build\validation"
$discoveryHints = Get-TerminalDiscoveryHints -TerminalData $script:terminalData
$runningBefore = @(Get-Process terminal64 -ErrorAction SilentlyContinue)

Write-Host "=== Sprint 8C Hedging Demo Preflight ==="
Write-Host "Selected TerminalDataId: $($paths.TerminalDataId)"
Write-Host "Selected terminal data path: $($paths.TerminalData)"
Write-Host "Install origin: $($paths.InstallRoot)"
Write-Host "Terminal currently running: $(if ($runningBefore.Count -gt 0) { 'yes (' + ($runningBefore.Id -join ', ') + ')' } else { 'no' })"
Write-Host "Discoverable server (latest log): $($discoveryHints.LatestServer)"
Write-Host "Discoverable login (latest log): $($discoveryHints.LatestLogin)"
Write-Host "Discoverable classification (latest log): $($discoveryHints.TerminalClassification)"
Write-Host "Discoverable margin hint (latest log): $($discoveryHints.MarginModeHint)"

New-Item -ItemType Directory -Force -Path $validationDir, $presetDir, $configDir | Out-Null
& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null

if ($runningBefore.Count -gt 0) {
    throw "MT5 already running on selected terminal or another instance. Close terminal64.exe and retry."
}

$source = Join-Path $script:mql5 "Scripts\BasketRecovery\Validation\Sprint8C\PreflightSprint8cDemoProfitClose.mq5"
$compileLog = Join-Path $validationDir "PreflightSprint8c.compile.log"
& $script:metaeditor /compile:"$source" /log:"$compileLog" | Out-Null
Start-Sleep -Seconds 3
if ((Get-Content $compileLog -Raw) -notmatch 'Result: 0 errors') {
    throw "Preflight compile failed: $compileLog"
}

$preset = "PreflightSprint8cDemoProfitClose.set"
"InpPreferredSymbol=$script:symbol" | Set-Content -Path (Join-Path $presetDir $preset) -Encoding ASCII
$ini = Join-Path $configDir "sprint-8c-preflight-startup.ini"
@"
[StartUp]
Script=BasketRecovery\Validation\Sprint8C\PreflightSprint8cDemoProfitClose
ScriptParameters=$preset
Symbol=$script:symbol
Period=M1
ShutdownTerminal=1

[Experts]
Enabled=1
AllowLiveTrading=1
AllowDllImport=0
AllowAlgoTrading=1
"@ | Set-Content -Path $ini -Encoding ASCII

Write-Host "Launching preflight against selected terminal only..."
$proc = Start-Process -FilePath $script:terminalExe -ArgumentList "/config:`"$ini`"" -PassThru
if (-not $proc.WaitForExit(120000)) {
    Stop-Mt5Instances
    throw "Preflight MT5 launch timed out"
}
Stop-Mt5Instances

$resultPath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-preflight-result.txt"
if ($null -eq $resultPath) { throw "Preflight result missing" }
Copy-Item $resultPath (Join-Path $validationDir "sprint-8c-preflight-result.txt") -Force
Get-Content $resultPath

$ready = Read-ReportFlag $resultPath "hedging_demo_ready"
if ($ready -ne "true") {
    Write-Host "PREFLIGHT BLOCKED: hedging DEMO account not ready. Do not seed or submit."
    exit 2
}
Write-Host "PREFLIGHT OK: hedging DEMO account ready for controlled rerun."
exit 0
