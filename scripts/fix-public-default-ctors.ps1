$files = @(
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\BreakEvenTrigger.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\BreakEvenAction.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\StrategyMetadata.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\ExecutionZone.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\RiskPlan.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\BreakEvenRule.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\ProfitDistributionPlan.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\BreakEvenPlan.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\ValueObjects\RecoveryPlan.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Aggregates\StrategyProfile.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Aggregates\StrategyProfileSnapshot.mqh",
    "mt5\Include\BasketRecovery\Domain\Configuration\ProfileSnapshot.mqh",
    "mt5\Include\BasketRecovery\Domain\Basket\BasketProfitLevelProgress.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\MarketContext.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\RiskRuntimeContext.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\ProfitLevelRuntimeState.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\PositionRuntimeView.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\BasketStrategyState.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Context\StrategyEvaluationContext.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Services\ExecutionZoneResolver.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Services\RecoveryPlanResolver.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\OpenRecoveryPositionDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\ClosePositionsDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\MoveBreakEvenDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\DisableRecoveryDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\ReduceRiskDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\NoActionDecision.mqh",
    "mt5\Include\BasketRecovery\Domain\Strategy\Decisions\StrategyDecision.mqh"
)

$repo = Split-Path -Parent $PSScriptRoot
foreach ($rel in $files) {
    $path = Join-Path $repo $rel
    if (-not (Test-Path $path)) { continue }
    $content = [IO.File]::ReadAllText($path)
    $updated = [regex]::Replace(
        $content,
        '(\r?\n)\s+(C[A-Za-z0-9_]+)\(void\) \{\}(\r?\n)(\r?\npublic:\r?\n\s+\2\(const)',
        '$1public:$1                     $2(void) {}$3$1                     $2(const',
        1)
    if ($updated -ne $content) {
        [IO.File]::WriteAllText($path, $updated)
        Write-Host "Updated $rel"
    }
}
