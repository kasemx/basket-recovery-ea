function Read-ProofFileState {
    param([string]$Path)

    $state = [ordered]@{
        Exists          = $false
        Status          = $null
        Error           = $null
        LastWriteTime   = $null
        LineCount       = 0
        TerminalStatus  = $null
    }

    if (-not (Test-Path $Path)) {
        return $state
    }

    $item = Get-Item $Path
    $state.Exists = $true
    $state.LastWriteTime = $item.LastWriteTimeUtc
    $lines = @(Get-Content $Path -ErrorAction SilentlyContinue)
    $state.LineCount = $lines.Count

    $lastStatus = $null
    foreach ($line in $lines) {
        if ($line -match '^status=(.+)$') {
            $lastStatus = $Matches[1].Trim()
        }
        if ($line -match '^error=(.+)$') {
            $state.Error = $Matches[1].Trim()
        }
    }

    $state.Status = $lastStatus
    if ($lastStatus -in @('COMPLETED', 'FAILED')) {
        $state.TerminalStatus = $lastStatus
    }
    return $state
}

function Test-ProofStatusParser {
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("bre-proof-parser-" + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    try {
        $startedOnly = Join-Path $tempRoot "started-only.txt"
        @(
            'status=STARTED'
            'timestamp_utc=1'
        ) | Set-Content -Path $startedOnly -Encoding ASCII

        $startedState = Read-ProofFileState -Path $startedOnly
        if ($startedState.Status -ne 'STARTED') {
            throw "expected STARTED from single status line, got '$($startedState.Status)'"
        }
        if ($null -ne $startedState.TerminalStatus) {
            throw 'terminal status should be null before COMPLETED/FAILED'
        }

        $completed = Join-Path $tempRoot "completed.txt"
        @(
            'status=STARTED'
            'timestamp_utc=1'
            'record[1]=example'
            'status=COMPLETED'
        ) | Set-Content -Path $completed -Encoding ASCII

        $completedState = Read-ProofFileState -Path $completed
        if ($completedState.Status -ne 'COMPLETED') {
            throw "expected last status COMPLETED, got '$($completedState.Status)'"
        }
        if ($completedState.TerminalStatus -ne 'COMPLETED') {
            throw "expected terminal status COMPLETED, got '$($completedState.TerminalStatus)'"
        }

        $failed = Join-Path $tempRoot "failed.txt"
        @(
            'status=STARTED'
            'status=FAILED'
            'error=proof_report_open_failed'
        ) | Set-Content -Path $failed -Encoding ASCII

        $failedState = Read-ProofFileState -Path $failed
        if ($failedState.Status -ne 'FAILED') {
            throw "expected last status FAILED, got '$($failedState.Status)'"
        }
        if ($failedState.Error -ne 'proof_report_open_failed') {
            throw "expected parsed error line, got '$($failedState.Error)'"
        }

        return $true
    }
    finally {
        if (Test-Path $tempRoot) {
            Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
