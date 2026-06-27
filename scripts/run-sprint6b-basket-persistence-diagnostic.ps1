# Sprint 6B.3: inspect stale basket persistence, then re-seed with verification.
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-sprint6b-basket-persistence-diagnostic.ps1

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$terminalExe = "C:\Program Files\MetaTrader 5\terminal64.exe"
$metaeditor = "C:\Program Files\MetaTrader 5\metaeditor64.exe"
$validationDir = Join-Path $repo "build\validation"

New-Item -ItemType Directory -Force -Path $validationDir | Out-Null

$sync = & (Join-Path $repo "scripts\sync-to-mt5.ps1")
$mql5 = $sync.Mql5Path
if (-not $mql5 -or -not (Test-Path $mql5)) {
    throw "Active MQL5 path unavailable from sync-to-mt5.ps1"
}
$terminalData = Split-Path $mql5 -Parent
$presetDir = Join-Path $mql5 "Presets"
New-Item -ItemType Directory -Force -Path $presetDir | Out-Null

function Invoke-Mq5Compile {
    param([string]$RelativePath, [string]$LogPath)
    $source = Join-Path $mql5 $RelativePath
    & $metaeditor /compile:"$source" /log:"$LogPath" | Out-Null
    Start-Sleep -Seconds 3
    if (-not (Test-Path $LogPath)) { throw "Compile log missing: $LogPath" }
    $content = Get-Content $LogPath -Raw
    if ($content -notmatch 'Result: 0 errors') {
        throw "Compile failed for $RelativePath. See $LogPath"
    }
}

function Stop-Mt5 {
    Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "  stopping pid $($_.Id)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

function Invoke-Mt5StartupScript {
    param(
        [string]$ScriptRel,
        [string]$PresetName,
        [string]$PresetContent,
        [string]$IniName,
        [string]$Symbol = "BTCUSD"
    )
    $presetPath = Join-Path $presetDir $PresetName
    Set-Content -Path $presetPath -Value $PresetContent -Encoding ASCII
    $iniPath = Join-Path $terminalData "config\$IniName"
    New-Item -ItemType Directory -Force -Path (Split-Path $iniPath -Parent) | Out-Null
    $ini = @"
[StartUp]
Script=BasketRecovery\Validation\$ScriptRel
ScriptParameters=$PresetName
Symbol=$Symbol
Period=M1
ShutdownTerminal=1

[Experts]
Enabled=1
AllowLiveTrading=1
AllowDllImport=0
"@
    Set-Content -Path $iniPath -Value $ini -Encoding ASCII
    Write-Host "Launching MT5 | script=$ScriptRel | ini=$iniPath"
    $proc = Start-Process -FilePath $terminalExe -ArgumentList "/config:`"$iniPath`"" -PassThru -Wait
    Write-Host "MT5 exit code: $($proc.ExitCode)"
    return $proc.ExitCode
}

function Find-CommonResultFile {
    param([string]$FileName)
    $paths = @(
        Join-Path $mql5 "Files\BasketRecovery\validation\$FileName"
        Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\BasketRecovery\validation\$FileName"
    )
    foreach ($path in $paths) {
        if (Test-Path $path) { return $path }
    }
    return $null
}

$scripts = @(
    @{
        Rel = "Scripts\BasketRecovery\Validation\InspectSprint6bBasketPersistence.mq5"
        Log = Join-Path $validationDir "InspectSprint6bBasketPersistence.compile.log"
    },
    @{
        Rel = "Scripts\BasketRecovery\Validation\SeedSprint6bOrderCheckBasket.mq5"
        Log = Join-Path $validationDir "SeedSprint6bOrderCheckBasket.compile.log"
    },
    @{
        Rel = "Scripts\BasketRecovery\Tests\TestBasketPersistenceCrcDiagnostic.mq5"
        Log = Join-Path $validationDir "TestBasketPersistenceCrcDiagnostic.compile.log"
    }
)

foreach ($item in $scripts) {
    Write-Host "Compiling $($item.Rel)..."
    Invoke-Mq5Compile -RelativePath $item.Rel -LogPath $item.Log
}

Stop-Mt5

Write-Host "`n=== Phase 1: Inspect existing persistence (pre-seed) ==="
Invoke-Mt5StartupScript `
    -ScriptRel "InspectSprint6bBasketPersistence" `
    -PresetName "InspectSprint6bBasketPersistence.set" `
    -PresetContent "InpBasketId=sprint6b-demo-btc-001" `
    -IniName "sprint-6b-inspect-startup.ini" | Out-Null

Start-Sleep -Seconds 2
$inspectPath = Find-CommonResultFile "sprint-6b-basket-inspect-result.txt"
if ($null -eq $inspectPath) {
    Write-Warning "Inspect result file not found"
} else {
    Write-Host "--- Inspect Report ($inspectPath) ---"
    Get-Content $inspectPath
    Copy-Item $inspectPath (Join-Path $validationDir "sprint-6b-basket-inspect-result.txt") -Force
}

Write-Host "`n=== Phase 2: Production seed + reopen verification ==="
Stop-Mt5
Invoke-Mt5StartupScript `
    -ScriptRel "SeedSprint6bOrderCheckBasket" `
    -PresetName "SeedSprint6bOrderCheckBasket.set" `
    -PresetContent @"
InpPreferredSymbol=BTCUSD
InpBasketId=sprint6b-demo-btc-001
"@ `
    -IniName "sprint-6b-seed-startup.ini" | Out-Null

Start-Sleep -Seconds 2
$seedPath = Find-CommonResultFile "sprint-6b-seed-result.txt"
if ($null -eq $seedPath) {
    Write-Warning "Seed result file not found"
} else {
    Write-Host "--- Seed Report ($seedPath) ---"
    Get-Content $seedPath
    Copy-Item $seedPath (Join-Path $validationDir "sprint-6b-seed-result.txt") -Force
}

Write-Host "`n=== Phase 3: Post-seed inspect ==="
Stop-Mt5
Invoke-Mt5StartupScript `
    -ScriptRel "InspectSprint6bBasketPersistence" `
    -PresetName "InspectSprint6bBasketPersistence.set" `
    -PresetContent "InpBasketId=sprint6b-demo-btc-001" `
    -IniName "sprint-6b-inspect-post-seed-startup.ini" | Out-Null

Start-Sleep -Seconds 2
$postInspectPath = Find-CommonResultFile "sprint-6b-basket-inspect-result.txt"
if ($null -ne $postInspectPath) {
    Write-Host "--- Post-Seed Inspect ($postInspectPath) ---"
    Get-Content $postInspectPath
    Copy-Item $postInspectPath (Join-Path $validationDir "sprint-6b-basket-inspect-post-seed-result.txt") -Force
}

Write-Host "`nDone. Reports in build/validation/"
