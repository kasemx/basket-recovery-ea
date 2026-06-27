# Run Sprint 6B live OrderCheck validation script via MT5 StartUp config.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-sprint6b-live-validation.ps1

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$terminalExe = "C:\Program Files\MetaTrader 5\terminal64.exe"
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$validationDir = Join-Path $repo "build\validation"
$triggerToken = "sprint6b-live-" + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

New-Item -ItemType Directory -Force -Path $validationDir | Out-Null

$sync = & (Join-Path $repo "scripts\sync-to-mt5.ps1")
$mql5 = $sync.Mql5Path
if (-not $mql5 -or -not (Test-Path $mql5)) {
    throw "Active MQL5 path unavailable from sync-to-mt5.ps1"
}
$terminalData = Split-Path $mql5 -Parent
$presetDir = Join-Path $mql5 "Presets"
New-Item -ItemType Directory -Force -Path $presetDir | Out-Null

$scriptRel = "Scripts\BasketRecovery\Validation\ValidateSprint6bLiveOrderCheck.mq5"
$scriptSource = Join-Path $mql5 $scriptRel
$compileLog = Join-Path $validationDir "ValidateSprint6bLiveOrderCheck.compile.log"
& $metaeditor /compile:"$scriptSource" /log:"$compileLog" | Out-Null
Start-Sleep -Seconds 3
if (-not (Test-Path $compileLog)) { throw "Compile log missing" }
$compileContent = Get-Content $compileLog -Raw
if ($compileContent -notmatch 'Result: 0 errors') {
    throw "Validation script compile failed. See $compileLog"
}

$symbol = "BTCUSD"
$presetName = "ValidateSprint6bLiveOrderCheck.set"
$presetPath = Join-Path $presetDir $presetName
@"
InpPreferredSymbol=$symbol
InpBasketId=sprint6b-demo-btc-001
InpManualTriggerToken=$triggerToken
InpManualLotSize=0.01
"@ | Set-Content -Path $presetPath -Encoding ASCII

$iniPath = Join-Path $terminalData "config\sprint-6b-live-startup.ini"
New-Item -ItemType Directory -Force -Path (Split-Path $iniPath -Parent) | Out-Null

$ini = @"
[StartUp]
Script=BasketRecovery\Validation\ValidateSprint6bLiveOrderCheck
ScriptParameters=$presetName
Symbol=$symbol
Period=M1
ShutdownTerminal=1

[Experts]
Enabled=1
AllowLiveTrading=1
AllowDllImport=0
"@

Set-Content -Path $iniPath -Value $ini -Encoding ASCII
Copy-Item $iniPath (Join-Path $validationDir "sprint-6b-live-startup.ini") -Force

Write-Host "Stopping existing MT5 instances so StartUp script can run..."
Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  stopping pid $($_.Id)"
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 3

Write-Host "Launching MT5 live validation | datadir=$terminalData | symbol=$symbol | trigger=$triggerToken"
$proc = Start-Process -FilePath $terminalExe -ArgumentList "/config:`"$iniPath`"" -PassThru -Wait
Write-Host "MT5 exit code: $($proc.ExitCode)"

Start-Sleep -Seconds 2

$resultPaths = @(
    Join-Path $mql5 "Files\BasketRecovery\validation\sprint-6b-live-result.txt"
    Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\BasketRecovery\validation\sprint-6b-live-result.txt"
)

$resultPath = $null
foreach ($path in $resultPaths) {
    if (Test-Path $path) {
        $resultPath = $path
        break
    }
}

if ($null -eq $resultPath) {
    $journal = Join-Path $terminalData "logs"
    Write-Host "Validation result file not found. Check Experts journal in $journal"
    $latestLog = Get-ChildItem $journal -Filter "*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -ne $latestLog) {
        Write-Host "--- tail $($latestLog.FullName) ---"
        Get-Content $latestLog.FullName -Tail 40
    }
    exit 2
}

Write-Host "--- Validation Report ($resultPath) ---"
Get-Content $resultPath
Copy-Item $resultPath (Join-Path $validationDir "sprint-6b-live-result.txt") -Force
Write-Host "Copied to build/validation/sprint-6b-live-result.txt"
