# GitHub'a yukleme scripti (bir kez gh auth login yaptiktan sonra)
# Kullanim: powershell -ExecutionPolicy Bypass -File scripts/publish-to-github.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) bulunamadi. winget install GitHub.cli"
}

gh auth status
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Once GitHub'a giris yapin:" -ForegroundColor Yellow
    Write-Host "  gh auth login" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Secenekler: GitHub.com -> HTTPS -> Login with a web browser" -ForegroundColor Gray
    exit 1
}

$repoName = "basket-recovery-ea"
$visibility = "public"

Write-Host "Repo olusturuluyor ve push ediliyor: $repoName ($visibility)" -ForegroundColor Green
gh repo create $repoName --$visibility --source=. --remote=origin --push --description "Basket Recovery Trading Engine - MT5 EA with clean architecture"

if ($LASTEXITCODE -eq 0) {
    gh repo view --web
}
