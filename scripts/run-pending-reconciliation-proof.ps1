# Read-only pending execution reconciliation proof (no seed, no submit, no persistence writes).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run-pending-reconciliation-proof.ps1

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$terminalRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal"
$proofRelativePath = "BasketRecovery\validation\pending-reconciliation-proof.txt"
$proofCommonPath = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files\$proofRelativePath"
$validationDir = Join-Path $repo "build\validation"
$timeoutSeconds = 120
$pollIntervalSeconds = 2

function Get-ProofStatus {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $lines = Get-Content $Path -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^status=(.+)$') { return $Matches[1].Trim() }
    }
    return $null
}

function Get-ProofError {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    $line = Get-Content $Path -ErrorAction SilentlyContinue | Where-Object { $_ -like 'error=*' } | Select-Object -Last 1
    if ($null -eq $line) { return $null }
    return ($line -split '=', 2)[1]
}

function Find-MatchingProofFiles {
    $matches = @()
    $commonRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
    if (Test-Path $commonRoot) {
        $matches += Get-ChildItem $commonRoot -Recurse -Filter "pending-reconciliation-proof.txt" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    if (Test-Path $terminalRoot) {
        $matches += Get-ChildItem $terminalRoot -Recurse -Filter "pending-reconciliation-proof.txt" -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    }
    return @($matches | Sort-Object -Unique)
}

function Get-LatestTerminalLogLines {
    param([string]$TerminalData, [int]$Tail = 40)
    $logDirs = @(
        (Join-Path $TerminalData "logs"),
        (Join-Path $TerminalData "MQL5\Logs")
    )
    $latest = $null
    foreach ($dir in $logDirs) {
        if (-not (Test-Path $dir)) { continue }
        $file = Get-ChildItem $dir -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $file -and ($null -eq $latest -or $file.LastWriteTime -gt $latest.LastWriteTime)) {
            $latest = $file
        }
    }
    if ($null -eq $latest) { return @() }
    return Get-Content $latest.FullName -Tail $Tail -ErrorAction SilentlyContinue
}

function Find-EligibleDemoTerminals {
    $eligible = @()
    if (-not (Test-Path $terminalRoot)) { return $eligible }

    foreach ($dir in Get-ChildItem $terminalRoot -Directory) {
        $dataPath = $dir.FullName
        $pendingPath = Join-Path $dataPath "MQL5\Files\BasketRecovery\pending_executions.dat"
        if (-not (Test-Path $pendingPath)) { continue }

        $originPath = Join-Path $dataPath "origin.txt"
        if (-not (Test-Path $originPath)) { continue }
        $installRoot = (Get-Content $originPath -First 1).Trim()
        $terminalExe = Join-Path $installRoot "terminal64.exe"
        if (-not (Test-Path $terminalExe)) { continue }

        $classification = "UNKNOWN"
        $server = ""
        foreach ($iniName in @("common.ini", "terminal.ini")) {
            $iniPath = Join-Path $dataPath "config\$iniName"
            if (-not (Test-Path $iniPath)) { continue }
            $iniText = Get-Content $iniPath -Raw -ErrorAction SilentlyContinue
            if ($iniText -match '(?m)^Server=(.+)$') {
                $server = $Matches[1].Trim()
                break
            }
        }
        if ($server -match '(?i)demo') { $classification = "DEMO" }
        elseif ($server -ne "") { $classification = "NON_DEMO" }

        if ($classification -ne "DEMO") { continue }

        $eligible += [pscustomobject]@{
            DataId           = $dir.Name
            TerminalData     = $dataPath
            Mql5Path         = Join-Path $dataPath "MQL5"
            TerminalExe      = $terminalExe
            MetaEditor       = Join-Path $installRoot "metaeditor64.exe"
            PendingPath      = $pendingPath
            Server           = $server
            Classification   = $classification
        }
    }
    return $eligible
}

function Write-ProofFailureDiagnostics {
    param(
        [string]$Reason,
        [string]$ExpectedPath,
        [string]$LaunchCommand,
        [array]$EligibleTerminals,
        [string]$SelectedTerminalData,
        [double]$ElapsedSeconds,
        [string[]]$LogLines
    )
    Write-Host ""
    Write-Host "=== Reconciliation Proof Failure ==="
    Write-Host "reason=$Reason"
    Write-Host "expected_output_path=$ExpectedPath"
    Write-Host "terminal_launch_command=$LaunchCommand"
    Write-Host "elapsed_seconds=$([math]::Round($ElapsedSeconds, 1))"
    Write-Host "discovered_demo_terminals=$($EligibleTerminals.Count)"
    foreach ($term in $EligibleTerminals) {
        Write-Host "  terminal_data=$($term.TerminalData) | server=$($term.Server) | pending=$($term.PendingPath)"
    }
    if ($SelectedTerminalData -ne "") {
        Write-Host "selected_terminal_data=$SelectedTerminalData"
    }
    $matches = Find-MatchingProofFiles
    Write-Host "matching_proof_files=$($matches.Count)"
    foreach ($path in $matches) {
        Write-Host "  match=$path"
    }
    if ($LogLines.Count -gt 0) {
        Write-Host "latest_terminal_log_tail:"
        foreach ($line in $LogLines) { Write-Host "  $line" }
    }
}

New-Item -ItemType Directory -Force -Path $validationDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $proofCommonPath -Parent) | Out-Null

$running = @(Get-Process terminal64 -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
    throw "MT5 already running ($($running.Count) instance(s)). Close all terminal64 processes and retry."
}

$eligibleTerminals = @(Find-EligibleDemoTerminals)
if ($eligibleTerminals.Count -eq 0) {
    throw "No eligible DEMO terminal with BasketRecovery/pending_executions.dat found under $terminalRoot"
}
if ($eligibleTerminals.Count -gt 1) {
    Write-ProofFailureDiagnostics -Reason "ambiguous_demo_terminal_selection" `
        -ExpectedPath $proofCommonPath -LaunchCommand "" `
        -EligibleTerminals $eligibleTerminals -SelectedTerminalData "" `
        -ElapsedSeconds 0 -LogLines @()
    throw "Multiple eligible DEMO terminals found ($($eligibleTerminals.Count)). Resolve ambiguity before running proof."
}

$selected = $eligibleTerminals[0]
$mql5 = $selected.Mql5Path
$terminalExe = $selected.TerminalExe
$metaeditor = $selected.MetaEditor
$terminalData = $selected.TerminalData
$configDir = Join-Path $terminalData "config"
$pendingPath = $selected.PendingPath

Write-Host "=== Read-Only Pending Reconciliation Proof ==="
Write-Host "selected_terminal_data=$terminalData"
Write-Host "selected_terminal_classification=$($selected.Classification)"
Write-Host "selected_terminal_server=$($selected.Server)"
Write-Host "selected_terminal_exe=$terminalExe"
Write-Host "expected_output_path=$proofCommonPath"
Write-Host "pending_executions_path=$pendingPath"

if (-not (Test-Path $pendingPath)) {
    throw "Pending executions file missing at $pendingPath"
}
$pendingHashBefore = (Get-FileHash $pendingPath -Algorithm SHA256).Hash
$pendingSizeBefore = (Get-Item $pendingPath).Length
Write-Host "pending_sha256_before=$pendingHashBefore"
Write-Host "pending_bytes_before=$pendingSizeBefore"

if (Test-Path $proofCommonPath) {
    Remove-Item $proofCommonPath -Force
}

& (Join-Path $repo "scripts\sync-to-mt5.ps1") | Out-Null

$source = Join-Path $mql5 "Scripts\BasketRecovery\Validation\InspectPendingExecutionReconciliation.mq5"
if (-not (Test-Path $source)) {
    $source = Join-Path $repo "mt5\Scripts\BasketRecovery\Validation\InspectPendingExecutionReconciliation.mq5"
}
$compileLog = Join-Path $validationDir "InspectPendingExecutionReconciliation.compile.log"
& $metaeditor /compile:"$source" /log:"$compileLog" | Out-Null
Start-Sleep -Seconds 2
if (-not (Test-Path $compileLog) -or ((Get-Content $compileLog -Raw) -notmatch 'Result: 0 errors')) {
    throw "Reconciliation proof compile failed: $compileLog"
}

$ini = Join-Path $configDir "inspect-pending-reconciliation.ini"
@"
[StartUp]
Script=BasketRecovery\Validation\InspectPendingExecutionReconciliation
Symbol=BTCUSD
Period=M1
ShutdownTerminal=1

[Experts]
Enabled=1
AllowLiveTrading=0
AllowDllImport=0
AllowAlgoTrading=1
"@ | Set-Content -Path $ini -Encoding ASCII

$launchCommand = "`"$terminalExe`" /config:`"$ini`""
Write-Host "terminal_launch_command=$launchCommand"

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath $terminalExe -ArgumentList @("/config:$ini") -PassThru
$completed = $false
$finalStatus = $null

while ($sw.Elapsed.TotalSeconds -lt $timeoutSeconds) {
    Start-Sleep -Seconds $pollIntervalSeconds
    $finalStatus = Get-ProofStatus -Path $proofCommonPath
    if ($finalStatus -eq "COMPLETED") {
        $completed = $true
        break
    }
    if ($finalStatus -eq "FAILED") {
        break
    }
    if ($proc.HasExited -and $null -eq $finalStatus) {
        Start-Sleep -Seconds 2
        $finalStatus = Get-ProofStatus -Path $proofCommonPath
        if ($finalStatus -eq "COMPLETED") { $completed = $true }
        break
    }
}

if (-not $proc.HasExited) {
    if (-not $completed) {
        try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
    } else {
        $proc.WaitForExit(15000) | Out-Null
    }
}

$sw.Stop()
Get-Process terminal64 -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
}

$pendingHashAfter = (Get-FileHash $pendingPath -Algorithm SHA256).Hash
$pendingSizeAfter = (Get-Item $pendingPath).Length
Write-Host "pending_sha256_after=$pendingHashAfter"
Write-Host "pending_bytes_after=$pendingSizeAfter"
Write-Host "pending_file_unchanged=$($pendingHashBefore -eq $pendingHashAfter)"

if (-not $completed) {
    $reason = if ($finalStatus -eq "FAILED") { "proof_status_failed" } else { "proof_status_not_completed" }
    $logLines = Get-LatestTerminalLogLines -TerminalData $terminalData
    Write-ProofFailureDiagnostics -Reason $reason `
        -ExpectedPath $proofCommonPath -LaunchCommand $launchCommand `
        -EligibleTerminals $eligibleTerminals -SelectedTerminalData $terminalData `
        -ElapsedSeconds $sw.Elapsed.TotalSeconds -LogLines $logLines
    if ($finalStatus -eq "FAILED") {
        throw "Reconciliation proof failed: $(Get-ProofError -Path $proofCommonPath)"
    }
    throw "Reconciliation proof result missing or incomplete at $proofCommonPath"
}

Copy-Item $proofCommonPath (Join-Path $validationDir "pending-reconciliation-proof.txt") -Force
Write-Host ""
Write-Host "=== Proof File Contents ==="
Get-Content $proofCommonPath
exit 0
