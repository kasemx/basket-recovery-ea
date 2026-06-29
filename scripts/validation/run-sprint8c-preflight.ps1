# Sprint 8C — DEMO hedging preflight only (no seed, no submit).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-preflight.ps1

param(
    [string]$TerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
)

$Script:AllowedDemoTerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"

function Resolve-TerminalPaths {
    param([string]$DataId)
    $terminalData = Join-Path $terminalRoot $DataId
    if (-not (Test-Path $terminalData)) { throw "Terminal data folder not found: $terminalData" }
    $installRoot = (Get-Content (Join-Path $terminalData "origin.txt") -First 1).Trim()
    return @{
        TerminalData = $terminalData
        Mql5Path     = Join-Path $terminalData "MQL5"
        TerminalExe  = Join-Path $installRoot "terminal64.exe"
        MetaEditor   = Join-Path $installRoot "metaeditor64.exe"
    }
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

if ($TerminalDataId -ne $Script:AllowedDemoTerminalDataId) {
    throw "Refusing: TerminalDataId '$TerminalDataId' is not the configured demo terminal."
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

New-Item -ItemType Directory -Force -Path $validationDir, $presetDir, $configDir | Out-Null
& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null

$running = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw "MT5 already running. Close demo terminal and retry."
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

Write-Host "=== Sprint 8C Hedging Demo Preflight ==="
Write-Host "Target terminal data: $($script:terminalData)"
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
$blocked = Read-ReportFlag $resultPath "preflight_verification"
if ($ready -ne "true") {
    Write-Host "PREFLIGHT BLOCKED: hedging DEMO account not ready. Do not seed or submit."
    exit 2
}
Write-Host "PREFLIGHT OK: hedging DEMO account ready for controlled rerun."
exit 0
