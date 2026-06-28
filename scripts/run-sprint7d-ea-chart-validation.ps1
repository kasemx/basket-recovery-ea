# Sprint 7D — EA chart manual recovery candidate validation runner.
# Demo terminal only. Does NOT change MT5 login/account.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-sprint7d-ea-chart-validation.ps1 [-Reseed]

param(
    [switch]$Reseed,
    [string]$TerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
)

$Script:AllowedDemoTerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
$Script:BlockedLiveTerminalDataIds = @("D0E8209F77C8CF37AD8BF550E51FF075")

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
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

function Assert-DemoTerminalConfigured {
    param([string]$DataId)
    if ($DataId -ne $Script:AllowedDemoTerminalDataId) {
        throw "Refusing: TerminalDataId '$DataId' is not the configured demo terminal."
    }
    if ($Script:BlockedLiveTerminalDataIds -contains $DataId) {
        throw "Refusing: blocked live terminal id."
    }
}

function Read-ReportFlag {
    param([string]$ReportPath, [string]$Key)
    if (-not (Test-Path $ReportPath)) { return $null }
    $line = Get-Content $ReportPath | Where-Object { $_ -like "$Key=*" } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1]
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

function Stop-Mt5Instances {
    Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

function Assert-Mt5NotRunning {
    $running = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        throw "MT5 already running (pids: $(($running.Id -join ', ')). Close demo terminal and retry."
    }
}

function Compile-Mq5 {
    param([string]$RelativePath, [string]$Label)
    $source = Join-Path $script:mql5 $RelativePath
    $compileLog = Join-Path $script:validationDir "$Label.compile.log"
    & $script:metaeditor /compile:"$source" /log:"$compileLog" | Out-Null
    Start-Sleep -Seconds 3
    if (-not (Test-Path $compileLog)) { throw "$Label compile log missing" }
    $content = Get-Content $compileLog -Raw
    if ($content -notmatch 'Result: 0 errors') { throw "$Label compile failed: $compileLog" }
}

function Write-StartupIni {
    param([string]$Path, [string]$Mode, [string]$ExpertOrScript, [string]$Parameters, [int]$ShutdownTerminal = 1)
    @"
[StartUp]
$Mode=$ExpertOrScript
${Mode}Parameters=$Parameters
Symbol=$script:symbol
Period=M1
ShutdownTerminal=$ShutdownTerminal

[Experts]
Enabled=1
AllowLiveTrading=1
AllowDllImport=0
AllowAlgoTrading=1
"@ | Set-Content -Path $Path -Encoding ASCII
}

function Launch-Mt5 {
    param(
        [string]$IniPath,
        [string]$Label,
        [int]$ExitTimeoutSeconds = 180,
        [switch]$AllowTimeout
    )
    Write-Host "Launching MT5 | $Label"
    $proc = Start-Process -FilePath $script:terminalExe -ArgumentList "/config:`"$IniPath`"" -PassThru
    if (-not $proc.WaitForExit($ExitTimeoutSeconds * 1000)) {
        Write-Host "MT5 did not exit within ${ExitTimeoutSeconds}s ($Label); stopping terminal..."
        Stop-Mt5Instances
        if (-not $AllowTimeout) {
            throw "MT5 timed out: $Label"
        }
        return
    }
    Write-Host "Exit code $($proc.ExitCode) ($Label)"
    Start-Sleep -Seconds 2
}

function Get-LatestExpertsJournal {
    $best = $null
    foreach ($dir in @(
        (Join-Path $script:mql5 "Logs"),
        (Join-Path $script:terminalData "logs")
    )) {
        if (-not (Test-Path $dir)) { continue }
        $file = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($null -ne $file -and ($null -eq $best -or $file.LastWriteTime -gt $best.LastWriteTime)) {
            $best = $file
        }
    }
    return $best
}

function Write-EaPreset {
    param(
        [string]$PresetName,
        [string]$BasketId,
        [string]$CandidateId = "",
        [string]$AuthToken = "",
        [string]$TriggerToken = "",
        [string]$MinVolume = "0.01",
        [switch]$EvaluateOnly
    )
    $lines = @(
        "InpProfileName=default",
        "InpLogFilePath=BasketRecovery/logs/basket_recovery.log",
        "InpLogLevel=2",
        "InpApplicationTimerIntervalMs=250",
        "InpTickSilenceFallbackMs=1000",
        "InpMaxSpreadPoints=500000",
        "InpExecutionMode=4",
        "InpEnableLiveDemoExecution=true",
        "InpRequireManualDemoAuthorization=true",
        "InpEnableExecutionDiagnostics=true",
        "InpGlobalExecutionKillSwitch=false",
        "InpBasketExecutionKillSwitch=false",
        "InpMaxManualDemoOpenVolume=$MinVolume",
        "InpManualRecoveryCandidateExpirySeconds=60",
        "InpManualDemoValidationAutoShutdown=true",
        "InpManualDemoAuthorizationBasketId=$BasketId"
    )
    if ($EvaluateOnly) {
        $lines += "InpManualExecutionDryRunBasketId=$BasketId"
        $lines += "InpManualExecutionDryRunTriggerToken=0"
    }
    if ($CandidateId -ne "") { $lines += "InpManualRecoveryCandidateId=$CandidateId" }
    if ($AuthToken -ne "") { $lines += "InpManualDemoAuthorizationToken=$AuthToken" }
    if ($TriggerToken -ne "") { $lines += "InpManualRecoverySubmissionTriggerToken=$TriggerToken" }
    $lines | Set-Content -Path (Join-Path $script:presetDir $PresetName) -Encoding ASCII
}

function Invoke-EvaluatePhase {
    param([string]$BasketId, [string]$MinVolume, [string]$Label)
    Assert-Mt5NotRunning
    Write-EaPreset -PresetName "BasketRecoveryEA.sprint7d-evaluate.set" -BasketId $BasketId -MinVolume $MinVolume
    $ini = Join-Path $script:configDir "sprint-7d-eval-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters "BasketRecoveryEA.sprint7d-evaluate.set"
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 60 -AllowTimeout
    Stop-Mt5Instances
}

function Invoke-RegisterPhase {
    param([string]$BasketId, [string]$Label)
    Assert-Mt5NotRunning
    $preset = "RegisterSprint7dLiveRecoveryCandidate.$Label.set"
    @"
InpBasketId=$BasketId
InpManualRecoveryCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $preset) -Encoding ASCII
    $ini = Join-Path $script:configDir "sprint-7d-register-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\RegisterSprint7dLiveRecoveryCandidate" -Parameters $preset
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 120
    $registerPath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-register-result.txt"
    if ($null -eq $registerPath) { throw "Register result missing for $Label" }
    if ((Read-ReportFlag $registerPath "register_verification") -ne "OK") { throw "Register failed for ${Label}: $registerPath" }
}

function Invoke-RecoverySubmitPhase {
    param(
        [string]$BasketId,
        [string]$CandidateId,
        [string]$AuthToken,
        [string]$TriggerToken,
        [string]$MinVolume,
        [string]$Label
    )
    Assert-Mt5NotRunning
    Write-EaPreset -PresetName "BasketRecoveryEA.sprint7d-submit.set" -BasketId $BasketId `
        -CandidateId $CandidateId -AuthToken $AuthToken -TriggerToken $TriggerToken -MinVolume $MinVolume
    $ini = Join-Path $script:configDir "sprint-7d-submit-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters "BasketRecoveryEA.sprint7d-submit.set"
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 120
    Stop-Mt5Instances
}

Assert-DemoTerminalConfigured -DataId $TerminalDataId
$terminalPaths = Resolve-TerminalPaths -DataId $TerminalDataId
$script:terminalExe = $terminalPaths.TerminalExe
$script:metaeditor = $terminalPaths.MetaEditor
$script:mql5 = $terminalPaths.Mql5Path
$script:terminalData = $terminalPaths.TerminalData
$script:validationDir = Join-Path $repo "build\validation"
$script:basketId = "sprint7d-demo-btc-001"
$script:symbol = "BTCUSD"
$script:presetDir = Join-Path $script:mql5 "Presets"
$script:configDir = Join-Path $script:terminalData "config"
$primaryTrigger = "sprint7d-recovery-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$negExpiryTrigger = "sprint7d-exp-" + ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 2)
$negPendingTrigger = "sprint7d-pend-" + ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 3)

New-Item -ItemType Directory -Force -Path $script:validationDir, $script:presetDir, $script:configDir | Out-Null
& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null

Write-Host "=== Sprint 7D Manual Recovery Chart Validation ==="
Write-Host "Target: $($script:terminalData)"
Assert-Mt5NotRunning

Compile-Mq5 "Scripts\BasketRecovery\Validation\SeedSprint7dManualRecoveryCandidate.mq5" "SeedSprint7d"
Compile-Mq5 "Scripts\BasketRecovery\Validation\RegisterSprint7dLiveRecoveryCandidate.mq5" "RegisterSprint7d"
Compile-Mq5 "Scripts\BasketRecovery\Validation\IssueSprint7dRecoveryAuthToken.mq5" "IssueSprint7dAuth"
Compile-Mq5 "Scripts\BasketRecovery\Validation\PrepareSprint7dNegativeRecoveryBlockers.mq5" "PrepareSprint7dNegative"
Compile-Mq5 "Scripts\BasketRecovery\Validation\CollectSprint7dManualRecoveryEvidence.mq5" "CollectSprint7d"
Compile-Mq5 "Experts\BasketRecovery\BasketRecoveryEA.mq5" "BasketRecoveryEA"

if ($Reseed -or -not (Find-ValidationFile "BasketRecovery\validation\sprint-7d-seed-result.txt")) {
    Write-Host "Phase 0: seed recovery basket..."
    $seedPreset = "SeedSprint7dManualRecoveryCandidate.set"
    @"
InpPreferredSymbol=$script:symbol
InpBasketId=$script:basketId
InpManualRecoveryCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $seedPreset) -Encoding ASCII
    $seedIni = Join-Path $script:configDir "sprint-7d-seed-startup.ini"
    Write-StartupIni -Path $seedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\SeedSprint7dManualRecoveryCandidate" -Parameters $seedPreset
    Launch-Mt5 -IniPath $seedIni -Label "seed" -ExitTimeoutSeconds 120
}

$seedPath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-seed-result.txt"
if ($null -eq $seedPath) { throw "Seed result missing" }
Copy-Item $seedPath (Join-Path $script:validationDir "sprint-7d-seed-result.txt") -Force
if ((Read-ReportFlag $seedPath "seed_verification") -ne "OK") { throw "Seed failed: $seedPath" }
$minVolume = Read-ReportFlag $seedPath "min_volume"

Write-Host "Phase 1: register live recovery candidate..."
Assert-Mt5NotRunning
$registerPreset = "RegisterSprint7dLiveRecoveryCandidate.set"
@"
InpBasketId=$script:basketId
InpManualRecoveryCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $registerPreset) -Encoding ASCII
$registerIni = Join-Path $script:configDir "sprint-7d-register-startup.ini"
Write-StartupIni -Path $registerIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\RegisterSprint7dLiveRecoveryCandidate" -Parameters $registerPreset
Launch-Mt5 -IniPath $registerIni -Label "phase1-register" -ExitTimeoutSeconds 120
$registerPath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-register-result.txt"
if ($null -eq $registerPath) { throw "Register result missing" }
if ((Read-ReportFlag $registerPath "register_verification") -ne "OK") { throw "Register failed: $registerPath" }

$candidatePath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-live-candidate.txt"
if ($null -eq $candidatePath) { throw "Live candidate artifact missing after phase 1" }
Copy-Item $candidatePath (Join-Path $script:validationDir "sprint-7d-live-candidate.txt") -Force
$candidateId = Read-ReportFlag $candidatePath "candidate_id"

Write-Host "Phase 1b: issue authorization token..."
Assert-Mt5NotRunning
$authIni = Join-Path $script:configDir "sprint-7d-auth-startup.ini"
Write-StartupIni -Path $authIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\IssueSprint7dRecoveryAuthToken" -Parameters "IssueSprint7dRecoveryAuthToken.set"
Launch-Mt5 -IniPath $authIni -Label "issue-auth" -ExitTimeoutSeconds 60
$authPath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-auth-result.txt"
if ($null -eq $authPath) { throw "Auth result missing" }
$authToken = Read-ReportFlag $authPath "authorization_token"
if ([string]::IsNullOrEmpty($authToken)) { throw "authorization_token missing" }

Write-Host "Phase 2: primary manual recovery submission (trigger=$primaryTrigger)..."
Invoke-RecoverySubmitPhase -BasketId $script:basketId -CandidateId $candidateId -AuthToken $authToken `
    -TriggerToken $primaryTrigger -MinVolume $minVolume -Label "phase2-primary"

Write-Host "Phase 2b: duplicate trigger negative (same trigger)..."
Invoke-RecoverySubmitPhase -BasketId $script:basketId -CandidateId $candidateId -AuthToken $authToken `
    -TriggerToken $primaryTrigger -MinVolume $minVolume -Label "phase2-duplicate"

Write-Host "Phase 3: negative expired candidate..."
$negExpiryBasket = "sprint7d-neg-expiry-001"
$negSeedPreset = "SeedSprint7dNegExpiry.set"
@"
InpPreferredSymbol=$script:symbol
InpBasketId=$negExpiryBasket
InpAllowExistingSymbolPositions=true
InpManualRecoveryCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $negSeedPreset) -Encoding ASCII
Assert-Mt5NotRunning
$negSeedIni = Join-Path $script:configDir "sprint-7d-neg-expiry-seed.ini"
Write-StartupIni -Path $negSeedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\SeedSprint7dManualRecoveryCandidate" -Parameters $negSeedPreset
Launch-Mt5 -IniPath $negSeedIni -Label "neg-expiry-seed" -ExitTimeoutSeconds 120
Invoke-RegisterPhase -BasketId $negExpiryBasket -Label "neg-expiry-register"
$negPrepPreset = "PrepareSprint7dNegativeExpired.set"
"InpMode=EXPIRED`nInpBasketId=$negExpiryBasket" | Set-Content -Path (Join-Path $script:presetDir $negPrepPreset) -Encoding ASCII
$negPrepIni = Join-Path $script:configDir "sprint-7d-neg-expiry-prep.ini"
Write-StartupIni -Path $negPrepIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\PrepareSprint7dNegativeRecoveryBlockers" -Parameters $negPrepPreset
Launch-Mt5 -IniPath $negPrepIni -Label "neg-expiry-prep" -ExitTimeoutSeconds 60
$negCandidateId = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-7d-live-candidate.txt") "candidate_id"
Assert-Mt5NotRunning
Launch-Mt5 -IniPath (Join-Path $script:configDir "sprint-7d-auth-startup.ini") -Label "neg-expiry-auth" -ExitTimeoutSeconds 60
$negAuthToken = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-7d-auth-result.txt") "authorization_token"
Invoke-RecoverySubmitPhase -BasketId $negExpiryBasket -CandidateId $negCandidateId -AuthToken $negAuthToken `
    -TriggerToken $negExpiryTrigger -MinVolume $minVolume -Label "neg-expiry-submit"

Write-Host "Phase 4: negative pending execution blocker..."
$negPendingBasket = "sprint7d-neg-pending-001"
$negPendingSeedPreset = "SeedSprint7dNegPending.set"
@"
InpPreferredSymbol=$script:symbol
InpBasketId=$negPendingBasket
InpAllowExistingSymbolPositions=true
InpManualRecoveryCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $negPendingSeedPreset) -Encoding ASCII
Assert-Mt5NotRunning
$negPendingSeedIni = Join-Path $script:configDir "sprint-7d-neg-pending-seed.ini"
Write-StartupIni -Path $negPendingSeedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\SeedSprint7dManualRecoveryCandidate" -Parameters $negPendingSeedPreset
Launch-Mt5 -IniPath $negPendingSeedIni -Label "neg-pending-seed" -ExitTimeoutSeconds 120
Invoke-RegisterPhase -BasketId $negPendingBasket -Label "neg-pending-register"
$negPendingPrepPreset = "PrepareSprint7dNegativePending.set"
"InpMode=PENDING`nInpBasketId=$negPendingBasket" | Set-Content -Path (Join-Path $script:presetDir $negPendingPrepPreset) -Encoding ASCII
Assert-Mt5NotRunning
$negPendingPrepIni = Join-Path $script:configDir "sprint-7d-neg-pending-prep.ini"
Write-StartupIni -Path $negPendingPrepIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\PrepareSprint7dNegativeRecoveryBlockers" -Parameters $negPendingPrepPreset
Launch-Mt5 -IniPath $negPendingPrepIni -Label "neg-pending-prep" -ExitTimeoutSeconds 60
$negPendingCandidateId = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-7d-live-candidate.txt") "candidate_id"
Assert-Mt5NotRunning
Launch-Mt5 -IniPath (Join-Path $script:configDir "sprint-7d-auth-startup.ini") -Label "neg-pending-auth" -ExitTimeoutSeconds 60
$negPendingAuthToken = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-7d-auth-result.txt") "authorization_token"
Invoke-RecoverySubmitPhase -BasketId $negPendingBasket -CandidateId $negPendingCandidateId -AuthToken $negPendingAuthToken `
    -TriggerToken $negPendingTrigger -MinVolume $minVolume -Label "neg-pending-submit"

Write-Host "Phase 5: collect evidence..."
$journal = Get-LatestExpertsJournal
$journalPath = if ($journal) { $journal.FullName } else { "" }

$collectPreset = "CollectSprint7dManualRecoveryEvidence.set"
@"
InpBasketId=$script:basketId
InpPrimaryTriggerToken=$primaryTrigger
InpDuplicateTriggerToken=$primaryTrigger
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpExpertsJournalAbsolutePath=$journalPath
"@ | Set-Content -Path (Join-Path $script:presetDir $collectPreset) -Encoding ASCII
$collectIni = Join-Path $script:configDir "sprint-7d-collect-startup.ini"
Write-StartupIni -Path $collectIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\CollectSprint7dManualRecoveryEvidence" -Parameters $collectPreset
Launch-Mt5 -IniPath $collectIni -Label "collect" -ExitTimeoutSeconds 60

$resultPath = Find-ValidationFile "BasketRecovery\validation\sprint-7d-ea-chart-result.txt"
if ($null -eq $resultPath) { throw "Evidence file missing" }
Copy-Item $resultPath (Join-Path $script:validationDir "sprint-7d-ea-chart-result.txt") -Force
Write-Host "--- Sprint 7D Report ---"
Get-Content $resultPath

$passed = Read-ReportFlag $resultPath "chart_validation_passed"
if ($passed -ne "true") { throw "Sprint 7D chart validation FAILED" }
Write-Host "Sprint 7D chart validation PASSED"
