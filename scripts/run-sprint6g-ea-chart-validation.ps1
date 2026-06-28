# Sprint 6G — EA chart OrderSendAsync validation runner.
# Does NOT change MT5 login/account. Uses the active terminal data folder only.
# Prerequisites: demo account, terminal + chart Algo Trading enabled, BTCUSD chart symbol.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-sprint6g-ea-chart-validation.ps1

param(
    [switch]$Reseed,
    [string]$TerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
)

# Hard safety: only this FTMO / VantageMarkets-Demo terminal data folder is permitted.
$Script:AllowedDemoTerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
$Script:BlockedLiveTerminalDataIds = @(
    "D0E8209F77C8CF37AD8BF550E51FF075"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"

function Resolve-TerminalPaths {
    param([string]$DataId)
    $terminalData = Join-Path $terminalRoot $DataId
    if (-not (Test-Path $terminalData)) {
        throw "Terminal data folder not found: $terminalData"
    }
    $originPath = Join-Path $terminalData "origin.txt"
    if (-not (Test-Path $originPath)) {
        throw "origin.txt missing for terminal $DataId"
    }
    $installRoot = (Get-Content $originPath -First 1).Trim()
    $terminalExe = Join-Path $installRoot "terminal64.exe"
    $metaeditor = Join-Path $installRoot "metaeditor64.exe"
    if (-not (Test-Path $terminalExe)) {
        throw "terminal64.exe not found: $terminalExe"
    }
    return @{
        TerminalData = $terminalData
        Mql5Path     = Join-Path $terminalData "MQL5"
        TerminalExe  = $terminalExe
        MetaEditor   = $metaeditor
    }
}

function Assert-DemoTerminalConfigured {
    param([string]$DataId)
    if ($DataId -ne $Script:AllowedDemoTerminalDataId) {
        throw "Refusing to run: TerminalDataId '$DataId' is not the configured demo terminal ($Script:AllowedDemoTerminalDataId). Do not pass a live or unknown terminal id."
    }
    if ($Script:BlockedLiveTerminalDataIds -contains $DataId) {
        throw "Refusing to run: TerminalDataId '$DataId' is a blocked live terminal."
    }
}

function Assert-SeedSafetyReport {
    param([string]$ReportPath, [string]$ExpectedTerminalData)
    $text = Get-Content $ReportPath -Raw
    $mode = Read-ReportFlag -ReportPath $ReportPath -Key "account_trade_mode"
    $server = Read-ReportFlag -ReportPath $ReportPath -Key "account_server"
    $serverClass = Read-ReportFlag -ReportPath $ReportPath -Key "server_classification"
    $terminalTrade = Read-ReportFlag -ReportPath $ReportPath -Key "terminal_trade_allowed"
    $chartTrade = Read-ReportFlag -ReportPath $ReportPath -Key "chart_trade_allowed"
    $seedTerminal = Read-ReportFlag -ReportPath $ReportPath -Key "seed_terminal_data_path"
    $symbol = Read-ReportFlag -ReportPath $ReportPath -Key "symbol"
    $positionsBefore = Read-ReportFlag -ReportPath $ReportPath -Key "positions_before"
    $ordersBefore = Read-ReportFlag -ReportPath $ReportPath -Key "orders_before"
    $symbolPositions = Read-ReportFlag -ReportPath $ReportPath -Key "symbol_positions_before"
    $symbolOrders = Read-ReportFlag -ReportPath $ReportPath -Key "symbol_orders_before"

    if ($mode -ne "DEMO") {
        throw "Refusing to continue: account_trade_mode=$mode (expected DEMO). Connected account is not demo."
    }
    if ($serverClass -ne "DEMO") {
        throw "Refusing to continue: server_classification=$serverClass on server '$server' (expected DEMO)."
    }
    if ($server -match "Live" -and $server -notmatch "Demo") {
        throw "Refusing to continue: broker server '$server' appears to be LIVE."
    }
    if ($terminalTrade -ne "true") {
        throw "Refusing to continue: terminal Algo Trading is disabled (terminal_trade_allowed=false)."
    }
    if ($chartTrade -ne "true") {
        throw "Refusing to continue: chart-level EA trading permission is disabled (chart_trade_allowed=false)."
    }
    if ($null -eq $symbol -or $symbol -eq "") {
        throw "Refusing to continue: BTCUSD (or alias) unavailable - symbol missing from seed report."
    }
    if ($seedTerminal -and ($seedTerminal -ne $ExpectedTerminalData)) {
        throw "Refusing to continue: MT5 started with unexpected data folder '$seedTerminal' (expected '$ExpectedTerminalData')."
    }
    if ($symbolPositions -and [int]$symbolPositions -gt 0) {
        throw "Refusing to continue: existing positions on $symbol ($symbolPositions). Clear symbol before validation."
    }
    if ($symbolOrders -and [int]$symbolOrders -gt 0) {
        throw "Refusing to continue: existing orders on $symbol ($symbolOrders). Clear symbol before validation."
    }

    Write-Host "Demo safety OK | server=$server | classification=$serverClass | symbol=$symbol | positions_before=$positionsBefore | orders_before=$ordersBefore"
}

function Assert-StartupUsedDemoTerminal {
    param([string]$TerminalData, [string]$IniFileName)
    $pattern = [regex]::Escape($IniFileName)
    $journalMatches = Select-String -Path (Join-Path $TerminalData "logs\*.log") -Pattern $pattern -ErrorAction SilentlyContinue
    if ($null -eq $journalMatches -or $journalMatches.Count -eq 0) {
        throw "StartUp ini '$IniFileName' not found in terminal journal. MT5 may not have started with the demo data folder."
    }
    $latestJournal = Get-ChildItem (Join-Path $TerminalData "logs") -Filter "*.log" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $latestJournal) {
        throw "Terminal journal missing under $TerminalData\logs"
    }
    $tail = Get-Content $latestJournal.FullName -Tail 80 -ErrorAction SilentlyContinue
    $pathLine = $tail | Where-Object { $_ -match "Terminal\s+$([regex]::Escape($TerminalData))" } | Select-Object -Last 1
    if ($null -eq $pathLine) {
        $demoLine = $tail | Where-Object { $_ -match "VantageMarkets-Demo" } | Select-Object -Last 1
        if ($null -eq $demoLine) {
            throw "Could not confirm demo terminal startup in $($latestJournal.Name). Check journal for Live server connection."
        }
    }
}

Assert-DemoTerminalConfigured -DataId $TerminalDataId
$terminalPaths = Resolve-TerminalPaths -DataId $TerminalDataId
$terminalExe = $terminalPaths.TerminalExe
$metaeditor = $terminalPaths.MetaEditor
$validationDir = Join-Path $repo "build\validation"
$basketId = "sprint6g-demo-btc-001"
$requestId = "sprint6g-req-001"
$symbol = "BTCUSD"
$phase1Trigger = "sprint6g-submit-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$phase2Trigger = "sprint6g-dup-" + ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 1)

New-Item -ItemType Directory -Force -Path $validationDir | Out-Null

function Stop-Mt5Instances {
    Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  stopping pid $($_.Id)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

function Assert-Mt5NotRunning {
    $running = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
    if ($running.Count -eq 0) { return }
    $ids = ($running | ForEach-Object { $_.Id }) -join ", "
    throw @"
MT5 is already running (terminal64 pid: $ids). StartUp config scripts cannot run while MT5 is open.
Close all MetaTrader 5 terminals manually, then re-run:
  powershell -ExecutionPolicy Bypass -File scripts/run-sprint6g-ea-chart-validation.ps1 -Reseed
Use the demo terminal only (default TerminalDataId=$TerminalDataId / VantageMarkets-Demo).
"@
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
    $candidates = @(
        Join-Path $mql5 "Logs"
        Join-Path $terminalData "logs"
    )
    $best = $null
    foreach ($dir in $candidates) {
        if (-not (Test-Path $dir)) { continue }
        $file = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $file) {
            if ($null -eq $best -or $file.LastWriteTime -gt $best.LastWriteTime) {
                $best = $file
            }
        }
    }
    return $best
}

function Launch-Mt5 {
    param(
        [string]$IniPath,
        [string]$Label,
        [int]$PostWaitSeconds = 8,
        [int]$ExitTimeoutSeconds = 180
    )
    Write-Host "Launching MT5 | $Label | ini=$IniPath"
    $proc = Start-Process -FilePath $terminalExe -ArgumentList "/config:`"$IniPath`"" -PassThru
    if (-not $proc.WaitForExit($ExitTimeoutSeconds * 1000)) {
        Write-Host "MT5 did not exit within ${ExitTimeoutSeconds}s ($Label); stopping terminal..."
        Stop-Mt5Instances
        throw "MT5 launch timed out for $Label. Ensure demo account sync, Algo Trading enabled, no login dialogs."
    }
    Write-Host "MT5 exit code: $($proc.ExitCode) ($Label)"
    Start-Sleep -Seconds $PostWaitSeconds
}

function Read-ReportFlag {
    param([string]$ReportPath, [string]$Key)
    if (-not (Test-Path $ReportPath)) { return $null }
    $line = Get-Content $ReportPath | Where-Object { $_ -like "$Key=*" } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1]
}

Write-Host "=== Sprint 6G EA Chart OrderSendAsync Validation ==="
Write-Host "NOTE: Demo account + Algo Trading required. No credentials are set by this runner."
Write-Host "Target terminal data: $($terminalPaths.TerminalData)"
Write-Host ""

& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null
$mql5 = $terminalPaths.Mql5Path
if (-not (Test-Path $mql5)) {
    throw "MQL5 path unavailable: $mql5"
}
$terminalData = $terminalPaths.TerminalData
Assert-Mt5NotRunning
$presetDir = Join-Path $mql5 "Presets"
$configDir = Join-Path $terminalData "config"
New-Item -ItemType Directory -Force -Path $presetDir, $configDir, $validationDir | Out-Null

Write-Host "Compiling validation scripts and EA..."
Compile-Mq5 "Scripts\BasketRecovery\Validation\SeedSprint6gDemoSubmission.mq5" "SeedSprint6gDemoSubmission"
Compile-Mq5 "Scripts\BasketRecovery\Validation\CollectSprint6gEaChartOrderSendAsyncEvidence.mq5" "CollectSprint6gEaChartOrderSendAsyncEvidence"
Compile-Mq5 "Experts\BasketRecovery\BasketRecoveryEA.mq5" "BasketRecoveryEA"

Stop-Mt5Instances

if ($Reseed -or -not (Find-ValidationFile "BasketRecovery\validation\sprint-6g-seed-result.txt")) {
    Write-Host "Phase 0: seed basket + prepared QUEUED request..."
    $seedPreset = "SeedSprint6gDemoSubmission.set"
    @"
InpPreferredSymbol=$symbol
InpBasketId=$basketId
InpExecutionRequestId=$requestId
"@ | Set-Content -Path (Join-Path $presetDir $seedPreset) -Encoding ASCII
    $seedIni = Join-Path $configDir "sprint-6g-seed-startup.ini"
    Write-StartupIni -Path $seedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\SeedSprint6gDemoSubmission" -Parameters $seedPreset
    Launch-Mt5 -IniPath $seedIni -Label "seed" -PostWaitSeconds 1 | Out-Null
    Assert-StartupUsedDemoTerminal -TerminalData $terminalData -IniFileName "sprint-6g-seed-startup.ini"
}

$seedPath = Find-ValidationFile "BasketRecovery\validation\sprint-6g-seed-result.txt"
if ($null -eq $seedPath) { throw "Seed result file not found at Common\Files or terminal Files after seed phase" }
Copy-Item $seedPath (Join-Path $validationDir "sprint-6g-seed-result.txt") -Force

$seedText = Get-Content $seedPath -Raw
if ($seedText -notmatch "seed_verification=OK") {
    throw "Seed verification failed. See $seedPath"
}
Assert-SeedSafetyReport -ReportPath $seedPath -ExpectedTerminalData $terminalData

$authToken = Read-ReportFlag -ReportPath $seedPath -Key "authorization_token"
$minVolume = Read-ReportFlag -ReportPath $seedPath -Key "min_volume"
$resolvedSymbol = Read-ReportFlag -ReportPath $seedPath -Key "symbol"
if ($null -eq $authToken -or $authToken -eq "") { throw "authorization_token missing from seed result" }

Write-Host "Phase 1: first manual demo submission (trigger=$phase1Trigger)..."
Assert-Mt5NotRunning
$phase1Preset = "BasketRecoveryEA.sprint6g-phase1-submit.set"
@"
InpProfileName=default
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpLogLevel=2
InpApplicationTimerIntervalMs=250
InpMaxSpreadPoints=500000
InpExecutionMode=4
InpEnableLiveDemoExecution=true
InpRequireManualDemoAuthorization=true
InpEnableExecutionDiagnostics=true
InpGlobalExecutionKillSwitch=false
InpBasketExecutionKillSwitch=false
InpMaxAuthorizedRequestsPerSession=1
InpMaxManualDemoOpenVolume=$minVolume
InpManualDemoAuthorizationBasketId=$basketId
InpManualDemoSubmissionRequestId=$requestId
InpManualDemoAuthorizationToken=$authToken
InpManualDemoSubmissionTriggerToken=$phase1Trigger
InpManualDemoValidationAutoShutdown=true
"@ | Set-Content -Path (Join-Path $presetDir $phase1Preset) -Encoding ASCII

$phase1Ini = Join-Path $configDir "sprint-6g-ea-phase1-startup.ini"
Write-StartupIni -Path $phase1Ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters $phase1Preset
Launch-Mt5 -IniPath $phase1Ini -Label "ea-phase1-submit" -PostWaitSeconds 5 -ExitTimeoutSeconds 180 | Out-Null
Stop-Mt5Instances

Write-Host "Phase 2: duplicate token negative test (same auth + trigger)..."
$phase2Preset = "BasketRecoveryEA.sprint6g-phase2-duplicate.set"
@"
InpProfileName=default
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpLogLevel=2
InpApplicationTimerIntervalMs=250
InpMaxSpreadPoints=500000
InpExecutionMode=4
InpEnableLiveDemoExecution=true
InpRequireManualDemoAuthorization=true
InpEnableExecutionDiagnostics=true
InpGlobalExecutionKillSwitch=false
InpBasketExecutionKillSwitch=false
InpMaxAuthorizedRequestsPerSession=1
InpMaxManualDemoOpenVolume=$minVolume
InpManualDemoAuthorizationBasketId=$basketId
InpManualDemoSubmissionRequestId=$requestId
InpManualDemoAuthorizationToken=$authToken
InpManualDemoSubmissionTriggerToken=$phase1Trigger
InpManualDemoValidationAutoShutdown=true
"@ | Set-Content -Path (Join-Path $presetDir $phase2Preset) -Encoding ASCII

$phase2Ini = Join-Path $configDir "sprint-6g-ea-phase2-startup.ini"
Write-StartupIni -Path $phase2Ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters $phase2Preset
Launch-Mt5 -IniPath $phase2Ini -Label "ea-phase2-duplicate" -PostWaitSeconds 3 -ExitTimeoutSeconds 60 | Out-Null
Stop-Mt5Instances

Write-Host "Phase 3: collect evidence..."
$journal = Get-LatestExpertsJournal
$journalPath = ""
$journalRelative = ""
if ($null -ne $journal) {
    $journalPath = $journal.FullName
    if ($journal.FullName.StartsWith($mql5, [System.StringComparison]::OrdinalIgnoreCase)) {
        $journalRelative = $journal.FullName.Substring($mql5.Length).TrimStart('\')
    }
}

$collectPreset = "CollectSprint6gEaChartOrderSendAsyncEvidence.set"
@"
InpBasketId=$basketId
InpExecutionRequestId=$requestId
InpTriggerToken=$phase1Trigger
InpDuplicateTriggerToken=$phase1Trigger
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpExpertsJournalPath=$journalRelative
InpExpertsJournalAbsolutePath=$journalPath
"@ | Set-Content -Path (Join-Path $presetDir $collectPreset) -Encoding ASCII

$collectIni = Join-Path $configDir "sprint-6g-collect-startup.ini"
Write-StartupIni -Path $collectIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\CollectSprint6gEaChartOrderSendAsyncEvidence" -Parameters $collectPreset
Launch-Mt5 -IniPath $collectIni -Label "collect-evidence" -PostWaitSeconds 2 | Out-Null

$resultPath = Find-ValidationFile "BasketRecovery\validation\sprint-6g-ea-chart-result.txt"
if ($null -eq $resultPath) { throw "Evidence file not found" }
Copy-Item $resultPath (Join-Path $validationDir "sprint-6g-ea-chart-result.txt") -Force

Write-Host "--- Sprint 6G Chart Validation Report ($resultPath) ---"
Get-Content $resultPath

$passed = Read-ReportFlag -ReportPath $resultPath -Key "chart_validation_passed"
$asyncTrue = Read-ReportFlag -ReportPath $resultPath -Key "ordersend_async_true"
$asyncFalse = Read-ReportFlag -ReportPath $resultPath -Key "ordersend_async_false"
$callCount = Read-ReportFlag -ReportPath $resultPath -Key "ordersend_async_call_count"
$immediateStatus = Read-ReportFlag -ReportPath $resultPath -Key "immediate_status"
$dupReject = Read-ReportFlag -ReportPath $resultPath -Key "duplicate_trigger_rejected"

@{
    Sprint = "6G"
    Symbol = $resolvedSymbol
    MinVolume = $minVolume
    BasketId = $basketId
    RequestId = $requestId
    TriggerToken = $phase1Trigger
    ResultPath = $resultPath
    ChartValidationPassed = $passed
    OrderSendAsyncTrue = $asyncTrue
    OrderSendAsyncFalse = $asyncFalse
    OrderSendAsyncCallCount = $callCount
    ImmediateStatus = $immediateStatus
    DuplicateTriggerRejected = $dupReject
} | ConvertTo-Json | Set-Content -Path (Join-Path $validationDir "sprint-6g-ea-chart-meta.json") -Encoding UTF8

if ($passed -ne "true") {
    throw "Sprint 6G chart validation FAILED. See $resultPath"
}

Write-Host ""
Write-Host "Sprint 6G chart validation PASSED"
Write-Host "  ordersend_async_call_count=$callCount"
Write-Host "  immediate_status=$immediateStatus"
Write-Host "  duplicate_trigger_rejected=$dupReject"
