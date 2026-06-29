# Sprint 8C — EA chart manual profit-close candidate validation runner.
# Demo terminal only. Does NOT change MT5 login/account.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/validation/run-sprint8c-ea-chart-validation.ps1 [-Reseed]

param(
    [switch]$Reseed,
    [string]$TerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
)

$Script:AllowedDemoTerminalDataId = "81A933A9AFC5DE3C23B15CAB19C63850"
$Script:BlockedLiveTerminalDataIds = @("D0E8209F77C8CF37AD8BF550E51FF075")

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
        "InpManualProfitCloseCandidateExpirySeconds=60",
        "InpManualDemoValidationAutoShutdown=true",
        "InpManualDemoAuthorizationBasketId=$BasketId"
    )
    if ($EvaluateOnly) {
        $lines += "InpManualExecutionDryRunBasketId=$BasketId"
        $lines += "InpManualExecutionDryRunTriggerToken=0"
    }
    if ($CandidateId -ne "") { $lines += "InpManualProfitCloseCandidateId=$CandidateId" }
    if ($AuthToken -ne "") { $lines += "InpManualDemoAuthorizationToken=$AuthToken" }
    if ($TriggerToken -ne "") { $lines += "InpManualProfitCloseSubmissionTriggerToken=$TriggerToken" }
    $lines | Set-Content -Path (Join-Path $script:presetDir $PresetName) -Encoding ASCII
}

function Invoke-ProfitCloseSubmitPhase {
    param(
        [string]$BasketId,
        [string]$CandidateId,
        [string]$AuthToken,
        [string]$TriggerToken,
        [string]$Label
    )
    Assert-Mt5NotRunning
    Write-EaPreset -PresetName "BasketRecoveryEA.sprint8c-submit.set" -BasketId $BasketId `
        -CandidateId $CandidateId -AuthToken $AuthToken -TriggerToken $TriggerToken
    $ini = Join-Path $script:configDir "sprint-8c-submit-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters "BasketRecoveryEA.sprint8c-submit.set"
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 180
    Stop-Mt5Instances
}

function Invoke-RegisterPhase {
    param([string]$BasketId, [string]$Label)
    Assert-Mt5NotRunning
    $preset = "RegisterSprint8cLiveProfitCloseCandidate.$Label.set"
    @"
InpBasketId=$BasketId
InpManualProfitCloseCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $preset) -Encoding ASCII
    $ini = Join-Path $script:configDir "sprint-8c-register-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\RegisterSprint8cLiveProfitCloseCandidate" -Parameters $preset
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 120
    $registerPath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-register-result.txt"
    if ($null -eq $registerPath) { throw "Register result missing for $Label" }
    if ((Read-ReportFlag $registerPath "register_verification") -ne "OK") { throw "Register failed for ${Label}: $registerPath" }
}

function Invoke-EvaluatePhase {
    param([string]$BasketId, [string]$Label)
    Assert-Mt5NotRunning
    Write-EaPreset -PresetName "BasketRecoveryEA.sprint8c-evaluate.set" -BasketId $BasketId -EvaluateOnly
    $ini = Join-Path $script:configDir "sprint-8c-eval-$Label.ini"
    Write-StartupIni -Path $ini -Mode "Expert" -ExpertOrScript "BasketRecovery\BasketRecoveryEA" -Parameters "BasketRecoveryEA.sprint8c-evaluate.set"
    Launch-Mt5 -IniPath $ini -Label $Label -ExitTimeoutSeconds 90 -AllowTimeout
    Stop-Mt5Instances
}

Assert-DemoTerminalConfigured -DataId $TerminalDataId
$terminalPaths = Resolve-TerminalPaths -DataId $TerminalDataId
$script:terminalExe = $terminalPaths.TerminalExe
$script:metaeditor = $terminalPaths.MetaEditor
$script:mql5 = $terminalPaths.Mql5Path
$script:terminalData = $terminalPaths.TerminalData
$script:validationDir = Join-Path $repo "build\validation"
$script:basketId = "sprint8c-demo-btc-001"
$script:symbol = "BTCUSD"
$script:presetDir = Join-Path $script:mql5 "Presets"
$script:configDir = Join-Path $script:terminalData "config"
$primaryTrigger = "sprint8c-profit-close-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$negExpiryTrigger = "sprint8c-exp-" + ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 2)
$negStaleTrigger = "sprint8c-stale-" + ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 3)

New-Item -ItemType Directory -Force -Path $script:validationDir, $script:presetDir, $script:configDir | Out-Null
& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null

Write-Host "=== Sprint 8C Manual Profit-Close Chart Validation ==="
Write-Host "Target: $($script:terminalData)"
Assert-Mt5NotRunning

Compile-Mq5 "Scripts\BasketRecovery\Validation\Sprint8C\SeedSprint8cManualProfitCloseCandidate.mq5" "SeedSprint8c"
Compile-Mq5 "Scripts\BasketRecovery\Validation\Sprint8C\RegisterSprint8cLiveProfitCloseCandidate.mq5" "RegisterSprint8c"
Compile-Mq5 "Scripts\BasketRecovery\Validation\Sprint8C\IssueSprint8cProfitCloseAuthToken.mq5" "IssueSprint8cAuth"
Compile-Mq5 "Scripts\BasketRecovery\Validation\Sprint8C\PrepareSprint8cNegativeProfitCloseBlockers.mq5" "PrepareSprint8cNegative"
Compile-Mq5 "Scripts\BasketRecovery\Validation\Sprint8C\CollectSprint8cManualProfitCloseEvidence.mq5" "CollectSprint8c"
Compile-Mq5 "Experts\BasketRecovery\BasketRecoveryEA.mq5" "BasketRecoveryEA"

if ($Reseed -or -not (Find-ValidationFile "BasketRecovery\validation\sprint-8c-seed-result.txt")) {
    Write-Host "Phase 0: seed profit-close basket and linked position..."
    $seedPreset = "SeedSprint8cManualProfitCloseCandidate.set"
    @"
InpPreferredSymbol=$script:symbol
InpBasketId=$script:basketId
InpManualProfitCloseCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $seedPreset) -Encoding ASCII
    $seedIni = Join-Path $script:configDir "sprint-8c-seed-startup.ini"
    Write-StartupIni -Path $seedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\SeedSprint8cManualProfitCloseCandidate" -Parameters $seedPreset
    Launch-Mt5 -IniPath $seedIni -Label "seed" -ExitTimeoutSeconds 180
}

$seedPath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-seed-result.txt"
if ($null -eq $seedPath) { throw "Seed result missing" }
Copy-Item $seedPath (Join-Path $script:validationDir "sprint-8c-seed-result.txt") -Force
if ((Read-ReportFlag $seedPath "seed_verification") -ne "OK") { throw "Seed failed: $seedPath" }

Write-Host "Phase 1: register live profit-close candidate..."
Invoke-RegisterPhase -BasketId $script:basketId -Label "phase1-register"

$candidatePath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-live-candidate.txt"
if ($null -eq $candidatePath) { throw "Live candidate artifact missing after phase 1" }
Copy-Item $candidatePath (Join-Path $script:validationDir "sprint-8c-live-candidate.txt") -Force
$candidateId = Read-ReportFlag $candidatePath "candidate_id"

Write-Host "Phase 1b: issue authorization token..."
Assert-Mt5NotRunning
$authIni = Join-Path $script:configDir "sprint-8c-auth-startup.ini"
Write-StartupIni -Path $authIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\IssueSprint8cProfitCloseAuthToken" -Parameters "IssueSprint8cProfitCloseAuthToken.set"
Launch-Mt5 -IniPath $authIni -Label "issue-auth" -ExitTimeoutSeconds 60
$authPath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-auth-result.txt"
if ($null -eq $authPath) { throw "Auth result missing" }
$authToken = Read-ReportFlag $authPath "authorization_token"
if ([string]::IsNullOrEmpty($authToken)) { throw "authorization_token missing" }

Write-Host "Phase 2: primary manual profit-close submission (trigger=$primaryTrigger)..."
Invoke-ProfitCloseSubmitPhase -BasketId $script:basketId -CandidateId $candidateId -AuthToken $authToken `
    -TriggerToken $primaryTrigger -Label "phase2-primary"

Write-Host "Phase 2b: duplicate trigger negative (same trigger)..."
Invoke-ProfitCloseSubmitPhase -BasketId $script:basketId -CandidateId $candidateId -AuthToken $authToken `
    -TriggerToken $primaryTrigger -Label "phase2-duplicate"

Write-Host "Phase 3: negative expired candidate..."
$negExpiryBasket = "sprint8c-neg-expiry-001"
$negSeedPreset = "SeedSprint8cNegExpiry.set"
@"
InpPreferredSymbol=$script:symbol
InpBasketId=$negExpiryBasket
InpAllowExistingSymbolPositions=true
InpManualProfitCloseCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $negSeedPreset) -Encoding ASCII
Assert-Mt5NotRunning
$negSeedIni = Join-Path $script:configDir "sprint-8c-neg-expiry-seed.ini"
Write-StartupIni -Path $negSeedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\SeedSprint8cManualProfitCloseCandidate" -Parameters $negSeedPreset
Launch-Mt5 -IniPath $negSeedIni -Label "neg-expiry-seed" -ExitTimeoutSeconds 180
Invoke-RegisterPhase -BasketId $negExpiryBasket -Label "neg-expiry-register"
$negPrepPreset = "PrepareSprint8cNegativeExpired.set"
"InpMode=EXPIRED`nInpBasketId=$negExpiryBasket" | Set-Content -Path (Join-Path $script:presetDir $negPrepPreset) -Encoding ASCII
$negPrepIni = Join-Path $script:configDir "sprint-8c-neg-expiry-prep.ini"
Write-StartupIni -Path $negPrepIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\PrepareSprint8cNegativeProfitCloseBlockers" -Parameters $negPrepPreset
Launch-Mt5 -IniPath $negPrepIni -Label "neg-expiry-prep" -ExitTimeoutSeconds 60
$negCandidateId = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-8c-live-candidate.txt") "candidate_id"
Assert-Mt5NotRunning
Launch-Mt5 -IniPath (Join-Path $script:configDir "sprint-8c-auth-startup.ini") -Label "neg-expiry-auth" -ExitTimeoutSeconds 60
$negAuthToken = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-8c-auth-result.txt") "authorization_token"
Invoke-ProfitCloseSubmitPhase -BasketId $negExpiryBasket -CandidateId $negCandidateId -AuthToken $negAuthToken `
    -TriggerToken $negExpiryTrigger -Label "neg-expiry-submit"

Write-Host "Phase 4: negative stale volume candidate..."
$negStaleBasket = "sprint8c-neg-stale-001"
$negStaleSeedPreset = "SeedSprint8cNegStale.set"
@"
InpPreferredSymbol=$script:symbol
InpBasketId=$negStaleBasket
InpAllowExistingSymbolPositions=true
InpManualProfitCloseCandidateExpirySeconds=60
"@ | Set-Content -Path (Join-Path $script:presetDir $negStaleSeedPreset) -Encoding ASCII
Assert-Mt5NotRunning
$negStaleSeedIni = Join-Path $script:configDir "sprint-8c-neg-stale-seed.ini"
Write-StartupIni -Path $negStaleSeedIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\SeedSprint8cManualProfitCloseCandidate" -Parameters $negStaleSeedPreset
Launch-Mt5 -IniPath $negStaleSeedIni -Label "neg-stale-seed" -ExitTimeoutSeconds 180
Invoke-RegisterPhase -BasketId $negStaleBasket -Label "neg-stale-register"
$negStalePrepPreset = "PrepareSprint8cNegativeStale.set"
"InpMode=STALE_VOLUME`nInpBasketId=$negStaleBasket" | Set-Content -Path (Join-Path $script:presetDir $negStalePrepPreset) -Encoding ASCII
$negStalePrepIni = Join-Path $script:configDir "sprint-8c-neg-stale-prep.ini"
Write-StartupIni -Path $negStalePrepIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\PrepareSprint8cNegativeProfitCloseBlockers" -Parameters $negStalePrepPreset
Launch-Mt5 -IniPath $negStalePrepIni -Label "neg-stale-prep" -ExitTimeoutSeconds 60
$negStaleCandidateId = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-8c-live-candidate.txt") "candidate_id"
Assert-Mt5NotRunning
Launch-Mt5 -IniPath (Join-Path $script:configDir "sprint-8c-auth-startup.ini") -Label "neg-stale-auth" -ExitTimeoutSeconds 60
$negStaleAuthToken = Read-ReportFlag (Find-ValidationFile "BasketRecovery\validation\sprint-8c-auth-result.txt") "authorization_token"
Invoke-ProfitCloseSubmitPhase -BasketId $negStaleBasket -CandidateId $negStaleCandidateId -AuthToken $negStaleAuthToken `
    -TriggerToken $negStaleTrigger -Label "neg-stale-submit"

Write-Host "Phase 5: read-only evaluation after terminal pending lifecycle..."
Invoke-EvaluatePhase -BasketId $script:basketId -Label "phase5-evaluate"

Write-Host "Phase 6: collect evidence..."
$journal = Get-LatestExpertsJournal
$journalPath = if ($journal) { $journal.FullName } else { "" }

$collectPreset = "CollectSprint8cManualProfitCloseEvidence.set"
@"
InpBasketId=$script:basketId
InpPrimaryTriggerToken=$primaryTrigger
InpDuplicateTriggerToken=$primaryTrigger
InpLogFilePath=BasketRecovery/logs/basket_recovery.log
InpExpertsJournalAbsolutePath=$journalPath
"@ | Set-Content -Path (Join-Path $script:presetDir $collectPreset) -Encoding ASCII
$collectIni = Join-Path $script:configDir "sprint-8c-collect-startup.ini"
Write-StartupIni -Path $collectIni -Mode "Script" -ExpertOrScript "BasketRecovery\Validation\Sprint8C\CollectSprint8cManualProfitCloseEvidence" -Parameters $collectPreset
Launch-Mt5 -IniPath $collectIni -Label "collect" -ExitTimeoutSeconds 60

$resultPath = Find-ValidationFile "BasketRecovery\validation\sprint-8c-ea-chart-result.txt"
if ($null -eq $resultPath) { throw "Evidence file missing" }
Copy-Item $resultPath (Join-Path $script:validationDir "sprint-8c-ea-chart-result.txt") -Force
Write-Host "--- Sprint 8C Report ---"
Get-Content $resultPath

$passed = Read-ReportFlag $resultPath "chart_validation_passed"
if ($passed -ne "true") { throw "Sprint 8C chart validation FAILED" }
Write-Host "Sprint 8C chart validation PASSED"
