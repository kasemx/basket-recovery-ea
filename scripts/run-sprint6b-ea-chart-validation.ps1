# Sprint 6B.4 — EA chart OrderCheck validation after CRC fix.
# Does NOT change MT5 login/account. Uses the terminal's active data folder only.
# Prerequisites: demo account synced, terminal + chart Algo Trading enabled.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-sprint6b-ea-chart-validation.ps1

param(
    [switch]$ReseedBasket
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$terminalExe = "C:\Program Files\MetaTrader 5\terminal64.exe"
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$validationDir = Join-Path $repo "build\validation"
$basketId = "sprint6b-demo-btc-001"
$symbol = "BTCUSD"
$phase2TriggerToken = "sprint6b-ea-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

New-Item -ItemType Directory -Force -Path $validationDir | Out-Null

function Stop-Mt5Instances {
    Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  stopping pid $($_.Id)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

function Compile-Mq5 {
    param([string]$RelativePath, [string]$Label)
    $source = Join-Path $mql5 $RelativePath
    $compileLog = Join-Path $validationDir "$Label.compile.log"
    & $metaeditor /compile:"$source" /log:"$compileLog" | Out-Null
    Start-Sleep -Seconds 3
    if (-not (Test-Path $compileLog)) { throw "$Label compile log missing" }
    $content = Get-Content $compileLog -Raw
    if ($content -notmatch 'Result: 0 errors') {
        throw "$Label compile failed. See $compileLog"
    }
}

function Write-StartupIni {
    param(
        [string]$Path,
        [string]$Mode,
        [string]$ExpertOrScript,
        [string]$Parameters,
        [int]$ShutdownTerminal = 1
    )
    $ini = @"
[StartUp]
$Mode=$ExpertOrScript
${Mode}Parameters=$Parameters
Symbol=$symbol
Period=M1
ShutdownTerminal=$ShutdownTerminal

[Experts]
Enabled=1
AllowLiveTrading=1
AllowDllImport=0
AllowAlgoTrading=1
"@
    Set-Content -Path $Path -Value $ini -Encoding ASCII
}

function Find-ValidationFile {
    param([string]$RelativePath)
    $paths = @(
        Join-Path $mql5 "Files\$RelativePath"
        Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\$RelativePath"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

function Get-LatestExpertsJournal {
    $journalDir = Join-Path $terminalData "logs"
    return Get-ChildItem $journalDir -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-ExecutionLogPaths {
    $relative = "BasketRecovery\logs\basket_recovery.log"
    $paths = @()
    foreach ($base in @(
            (Join-Path $mql5 "Files\$relative"),
            (Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\$relative")
        )) {
        if (Test-Path $base) { $paths += $base }
    }
    return $paths
}

function Test-JournalContent {
    param(
        [string[]]$RequiredPatterns,
        [string[]]$ForbiddenPatterns = @(),
        [string[]]$ExecutionLogPaths = @()
    )
    $journal = Get-LatestExpertsJournal
    $content = ""
    if ($null -ne $journal) {
        $content += Get-Content $journal.FullName -Raw
    }
    foreach ($logPath in $ExecutionLogPaths) {
        if (Test-Path $logPath) {
            $content += Get-Content $logPath -Raw
        }
    }
    if ($content -eq "") {
        throw "No Experts journal or execution log content available for validation"
    }
    foreach ($pattern in $RequiredPatterns) {
        if ($content -notmatch [regex]::Escape($pattern)) {
            return @{ Ok = $false; Journal = $(if ($journal) { $journal.FullName } else { "" }); Missing = $pattern }
        }
    }
    foreach ($pattern in $ForbiddenPatterns) {
        if ($content -match [regex]::Escape($pattern)) {
            return @{ Ok = $false; Journal = $(if ($journal) { $journal.FullName } else { "" }); Forbidden = $pattern }
        }
    }
    return @{ Ok = $true; Journal = $(if ($journal) { $journal.FullName } else { "" }); Content = $content }
}

function Launch-Mt5 {
    param(
        [string]$IniPath,
        [string]$Label,
        [int]$PostWaitSeconds = 8,
        [int]$ExitTimeoutSeconds = 120
    )
    Write-Host "Launching MT5 | $Label | ini=$IniPath"
    $proc = Start-Process -FilePath $terminalExe -ArgumentList "/config:`"$IniPath`"" -PassThru
    if (-not $proc.WaitForExit($ExitTimeoutSeconds * 1000)) {
        Write-Host "MT5 did not exit within ${ExitTimeoutSeconds}s ($Label); stopping terminal..."
        Stop-Mt5Instances
        throw "MT5 launch timed out for $Label. Close login/update dialogs, ensure demo account sync completes, enable Algo Trading, then re-run."
    }
    Write-Host "MT5 exit code: $($proc.ExitCode) ($Label)"
    Start-Sleep -Seconds $PostWaitSeconds
    return $proc.ExitCode
}

function Assert-NoAlgoTradingDisabled {
    param([string]$PhaseLabel)
    $journal = Get-LatestExpertsJournal
    if ($null -eq $journal) { return }
    $tail = Get-Content $journal.FullName -Tail 120 -ErrorAction SilentlyContinue
    if ($tail -match "automated trading is disabled because the account has been changed") {
        throw @"
$PhaseLabel failed: MT5 reported 'automated trading is disabled because the account has been changed'.
Preconditions required before re-run:
  1. Open the intended demo account in MT5 manually.
  2. Wait for terminal synchronization to finish.
  3. Enable terminal-level Algo Trading after the account change.
  4. Enable chart-level algorithmic trading permission for BasketRecoveryEA.
Journal: $($journal.FullName)
"@
    }
}

function Read-ReportFlag {
    param([string]$ReportPath, [string]$Key)
    if (-not (Test-Path $ReportPath)) { return $null }
    $line = Get-Content $ReportPath | Where-Object { $_ -like "$Key=*" } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1]
}

Write-Host "=== Sprint 6B.4 EA Chart OrderCheck Validation ==="
Write-Host "NOTE: This runner does NOT set MT5 login credentials."
Write-Host "      Use the demo account already configured in the active terminal data folder."
Write-Host ""

$sync = & (Join-Path $repo "scripts\sync-to-mt5.ps1")
$mql5 = $sync.Mql5Path
if (-not $mql5 -or -not (Test-Path $mql5)) {
    throw "Active MQL5 path unavailable from sync-to-mt5.ps1"
}
$terminalData = Split-Path $mql5 -Parent
$presetDir = Join-Path $mql5 "Presets"
$configDir = Join-Path $terminalData "config"
New-Item -ItemType Directory -Force -Path $presetDir, $configDir, $validationDir | Out-Null

Write-Host "Compiling validation scripts and EA..."
Compile-Mq5 "Scripts\BasketRecovery\Validation\InspectSprint6bBasketPersistence.mq5" "InspectSprint6bBasketPersistence"
Compile-Mq5 "Scripts\BasketRecovery\Validation\SeedSprint6bOrderCheckBasket.mq5" "SeedSprint6bOrderCheckBasket"
Compile-Mq5 "Scripts\BasketRecovery\Validation\CollectSprint6bEaChartOrderCheckEvidence.mq5" "CollectSprint6bEaChartOrderCheckEvidence"
Compile-Mq5 "Experts\BasketRecovery\BasketRecoveryEA.mq5" "BasketRecoveryEA"

Stop-Mt5Instances

if ($ReseedBasket) {
    Write-Host "Phase 0: optional production seed (ReseedBasket)..."
    $seedPreset = "SeedSprint6bOrderCheckBasket.set"
    @"
InpPreferredSymbol=$symbol
InpBasketId=$basketId
"@ | Set-Content -Path (Join-Path $presetDir $seedPreset) -Encoding ASCII
    $seedIni = Join-Path $configDir "sprint-6b4-seed-startup.ini"
    Write-StartupIni -Path $seedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\SeedSprint6bOrderCheckBasket" -Parameters $seedPreset
    Launch-Mt5 -IniPath $seedIni -Label "seed" -PostWaitSeconds 3 | Out-Null
    $seedResultPath = Find-ValidationFile "BasketRecovery\validation\sprint-6b-seed-result.txt"
    if ($null -eq $seedResultPath) { throw "Basket seed result file not found" }
    Copy-Item $seedResultPath (Join-Path $validationDir "sprint-6b-seed-result.txt") -Force
    if ((Get-Content $seedResultPath -Raw) -notmatch "seed_verification=OK") {
        throw "Production seed verification failed. See $seedResultPath"
    }
    Stop-Mt5Instances
} else {
    Write-Host "Phase 0: verify persisted basket CRC (no reseed)..."
    $inspectPreset = "InspectSprint6bBasketPersistence.set"
    "InpBasketId=$basketId" | Set-Content -Path (Join-Path $presetDir $inspectPreset) -Encoding ASCII
    $inspectIni = Join-Path $configDir "sprint-6b4-inspect-startup.ini"
    Write-StartupIni -Path $inspectIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\InspectSprint6bBasketPersistence" -Parameters $inspectPreset
    Launch-Mt5 -IniPath $inspectIni -Label "inspect" -PostWaitSeconds 2 | Out-Null
    $inspectPath = Find-ValidationFile "BasketRecovery\validation\sprint-6b-basket-inspect-result.txt"
    if ($null -eq $inspectPath) { throw "Basket inspect result file not found" }
    Copy-Item $inspectPath (Join-Path $validationDir "sprint-6b-basket-inspect-result.txt") -Force
    $inspectText = Get-Content $inspectPath -Raw
    if ($inspectText -notmatch "validation_stage=ok" -or $inspectText -notmatch "repository_load=ok") {
        throw "Persisted basket CRC verification failed. Re-run with -ReseedBasket or execute SeedSprint6bOrderCheckBasket.mq5. See $inspectPath"
    }
    Stop-Mt5Instances
}

$executionLogPaths = Get-ExecutionLogPaths

Write-Host "Phase 1: chart EA CRC diagnostic (trigger=0)..."
$phase1Preset = "BasketRecoveryEA.sprint6b4-phase1-crc.set"
@"
InpProfileName=default
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpLogLevel=2
InpApplicationTimerIntervalMs=250
InpMaxSpreadPoints=500000
InpExecutionMode=1
InpEnableExecutionDryRun=false
InpEnableExecutionDiagnostics=true
InpManualExecutionDryRunBasketId=$basketId
InpManualExecutionDryRunTriggerToken=
InpManualExecutionDryRunLotSize=0.01
"@ | Set-Content -Path (Join-Path $presetDir $phase1Preset) -Encoding ASCII

$phase1Ini = Join-Path $configDir "sprint-6b4-ea-phase1-startup.ini"
Write-StartupIni -Path $phase1Ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters $phase1Preset
Launch-Mt5 -IniPath $phase1Ini -Label "ea-phase1-crc" -PostWaitSeconds 4 | Out-Null
Assert-NoAlgoTradingDisabled -PhaseLabel "Phase 1 (CRC diagnostic)"

$phase1Journal = Test-JournalContent -RequiredPatterns @(
    "BRE basket-load diagnostic",
    "validation_stage=ok",
    "repository_load=ok"
) -ExecutionLogPaths $executionLogPaths
if (-not $phase1Journal.Ok) {
    $journal = Get-LatestExpertsJournal
    Write-Host "--- Experts journal tail ($($journal.FullName)) ---"
    Get-Content $journal.FullName -Tail 80
    throw "Phase 1 CRC diagnostic missing required evidence. Missing pattern: $($phase1Journal.Missing)"
}
Write-Host "Phase 1 OK | journal=$($phase1Journal.Journal)"

Stop-Mt5Instances

Write-Host "Phase 2: chart EA OrderCheck dry-run (one timer cycle)..."
$phase2Preset = "BasketRecoveryEA.sprint6b4-phase2-ordercheck.set"
@"
InpProfileName=default
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpLogLevel=2
InpApplicationTimerIntervalMs=250
InpMaxSpreadPoints=500000
InpExecutionMode=1
InpEnableExecutionDryRun=true
InpEnableExecutionDiagnostics=true
InpManualExecutionDryRunBasketId=$basketId
InpManualExecutionDryRunTriggerToken=$phase2TriggerToken
InpManualExecutionDryRunLotSize=0.01
"@ | Set-Content -Path (Join-Path $presetDir $phase2Preset) -Encoding ASCII

$phase2Ini = Join-Path $configDir "sprint-6b4-ea-phase2-startup.ini"
Write-StartupIni -Path $phase2Ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters $phase2Preset
Launch-Mt5 -IniPath $phase2Ini -Label "ea-phase2-ordercheck" -PostWaitSeconds 4 | Out-Null
Assert-NoAlgoTradingDisabled -PhaseLabel "Phase 2 (OrderCheck dry-run)"

Stop-Mt5Instances

Write-Host "Phase 3: collect EA chart evidence..."
$latestJournal = Get-LatestExpertsJournal
$journalPathForCollector = ""
if ($null -ne $latestJournal) {
    $journalPathForCollector = $latestJournal.FullName
}

$collectPreset = "CollectSprint6bEaChartOrderCheckEvidence.set"
@"
InpBasketId=$basketId
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpTriggerToken=$phase2TriggerToken
InpExpertsJournalPath=$journalPathForCollector
"@ | Set-Content -Path (Join-Path $presetDir $collectPreset) -Encoding ASCII

$collectIni = Join-Path $configDir "sprint-6b4-ea-collect-startup.ini"
Write-StartupIni -Path $collectIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\CollectSprint6bEaChartOrderCheckEvidence" -Parameters $collectPreset
Launch-Mt5 -IniPath $collectIni -Label "collect-evidence" -PostWaitSeconds 2 | Out-Null

$resultPath = Find-ValidationFile "BasketRecovery\validation\sprint-6b-ea-chart-result.txt"
if ($null -eq $resultPath) {
    throw "EA chart evidence file not found after collection"
}

Write-Host "--- EA Chart Validation Report ($resultPath) ---"
Get-Content $resultPath
Copy-Item $resultPath (Join-Path $validationDir "sprint-6b-ea-chart-result.txt") -Force

$chartPassed = Read-ReportFlag -ReportPath $resultPath -Key "chart_validation_passed"
$orderCheckInvoked = Read-ReportFlag -ReportPath $resultPath -Key "order_check_invoked"
$orderCheckRetcode = Read-ReportFlag -ReportPath $resultPath -Key "ordercheck_retcode"
$orderCheckText = Read-ReportFlag -ReportPath $resultPath -Key "ordercheck_text"
$mappedStatus = Read-ReportFlag -ReportPath $resultPath -Key "mapped_status"
$brokerMutation = Read-ReportFlag -ReportPath $resultPath -Key "broker_mutation"

@{
    Sprint = "6B.4"
    TriggerToken = $phase2TriggerToken
    BasketId = $basketId
    Symbol = $symbol
    TerminalData = $terminalData
    ResultPath = $resultPath
    ChartValidationPassed = $chartPassed
    OrderCheckInvoked = $orderCheckInvoked
    OrderCheckRetcode = $orderCheckRetcode
    OrderCheckText = $orderCheckText
    MappedStatus = $mappedStatus
    BrokerMutation = $brokerMutation
} | ConvertTo-Json | Set-Content -Path (Join-Path $validationDir "sprint-6b-ea-chart-meta.json") -Encoding UTF8

if ($chartPassed -ne "true") {
    if ($orderCheckInvoked -ne "true") {
        throw "Chart validation FAILED: order_check_invoked is not true. Enable terminal + chart Algo Trading on the demo account, then re-run."
    }
    $orderCheckReached = Read-ReportFlag -ReportPath $resultPath -Key "ordercheck_reached"
    if ($orderCheckReached -ne "true") {
        throw "Chart validation FAILED: real OrderCheck path not reached (ordercheck_reached=false). See $resultPath"
    }
    throw "Chart validation FAILED: chart_validation_passed=false. See $resultPath"
}

Write-Host ""
Write-Host "Sprint 6B.4 chart validation PASSED"
Write-Host "  order_check_invoked=$orderCheckInvoked"
Write-Host "  ordercheck_retcode=$orderCheckRetcode"
Write-Host "  ordercheck_text=$orderCheckText"
Write-Host "  mapped_status=$mappedStatus"
Write-Host "  broker_mutation=$brokerMutation"
Write-Host "Copied to build/validation/sprint-6b-ea-chart-result.txt"
