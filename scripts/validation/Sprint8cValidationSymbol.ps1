# Shared Sprint 8C validation symbol configuration (tooling only).

function Resolve-Sprint8cValidationSymbol {
    param([string]$Symbol)
    $normalized = $Symbol.Trim().ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "Validation symbol must not be empty."
    }
    if ($normalized -notmatch '^[A-Z0-9._+]+$') {
        throw "Invalid validation symbol '$Symbol'."
    }
    return $normalized
}

function Get-Sprint8cValidationBasketId {
    param(
        [string]$Symbol,
        [string]$AttemptSuffix = "002"
    )
    $slug = ($Symbol.ToLowerInvariant() -replace '[^a-z0-9]', '')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        throw "Cannot derive basket id from symbol '$Symbol'."
    }
    return "sprint8c-demo-$slug-$AttemptSuffix"
}
