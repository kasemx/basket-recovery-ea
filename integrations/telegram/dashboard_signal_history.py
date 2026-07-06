"""Signal history projection from safe route_events (no raw Telegram text)."""

from __future__ import annotations

import json
from typing import Any

SIGNAL_META_MARKER = "|signal_meta="
SIGNAL_META_ALLOWLIST = frozenset(
    {
        "symbol",
        "side",
        "entry_low",
        "entry_high",
        "stop_loss",
        "take_profits",
    }
)

EXECUTION_NOT_EXECUTED = "NOT_EXECUTED"
EXECUTION_PENDING = "PENDING"
EXECUTION_OPEN = "OPEN"
EXECUTION_CLOSED = "CLOSED"

OUTCOME_NOT_APPLICABLE = "NOT_APPLICABLE"
OUTCOME_PENDING = "PENDING"
OUTCOME_PROFIT = "PROFIT"
OUTCOME_LOSS = "LOSS"
OUTCOME_BREAKEVEN = "BREAKEVEN"

PNL_STATE_UNKNOWN = "unknown"
PNL_STATE_PROFIT = "profit"
PNL_STATE_LOSS = "loss"
PNL_STATE_BREAKEVEN = "breakeven"


def extract_signal_meta(safe_summary: str | None) -> dict[str, Any] | None:
    if not safe_summary or SIGNAL_META_MARKER not in safe_summary:
        return None
    payload = safe_summary.split(SIGNAL_META_MARKER, 1)[1].strip()
    try:
        parsed = json.loads(payload)
    except json.JSONDecodeError:
        return None
    if not isinstance(parsed, dict):
        return None
    cleaned: dict[str, Any] = {}
    for key in SIGNAL_META_ALLOWLIST:
        if key not in parsed:
            continue
        value = parsed[key]
        if key == "take_profits":
            if isinstance(value, list):
                cleaned[key] = [str(item) for item in value]
            continue
        if key in ("entry_low", "entry_high", "stop_loss"):
            try:
                cleaned[key] = int(value)
            except (TypeError, ValueError):
                continue
            continue
        if value is not None:
            cleaned[key] = str(value)
    return cleaned or None


def normalize_symbol(symbol: str | None) -> str | None:
    if not symbol:
        return None
    lowered = symbol.strip().lower()
    if lowered in ("gold", "xauusd"):
        return "XAUUSD"
    return symbol.strip().upper()


def normalize_side(side: str | None) -> str | None:
    if not side:
        return None
    normalized = side.strip().upper()
    if normalized in ("BUY", "SELL"):
        return normalized
    return None


def resolve_pnl_state(realized_pnl: float | None) -> str:
    if realized_pnl is None:
        return PNL_STATE_UNKNOWN
    if realized_pnl > 0:
        return PNL_STATE_PROFIT
    if realized_pnl < 0:
        return PNL_STATE_LOSS
    return PNL_STATE_BREAKEVEN


def observer_execution_fields(*, dry_run: bool = True) -> dict[str, Any]:
    return {
        "execution_status": EXECUTION_NOT_EXECUTED,
        "trade_outcome": OUTCOME_NOT_APPLICABLE,
        "realized_pnl": None,
        "currency": None,
        "is_observer_only": True,
        "is_dry_run": dry_run,
    }


def build_history_item(row: dict[str, Any], *, dry_run: bool = True) -> dict[str, Any]:
    meta = extract_signal_meta(row.get("safe_summary")) or {}
    execution = observer_execution_fields(dry_run=dry_run)
    signal_status = str(row.get("status") or "PUBLISH_READY")
    take_profits = meta.get("take_profits")
    if take_profits is not None and not isinstance(take_profits, list):
        take_profits = None
    return {
        "id": int(row["id"]),
        "route_id": int(row["route_id"]),
        "channel_id": int(row["channel_id"]),
        "channel_name": row.get("channel_title") or row.get("channel_name"),
        "target_id": int(row["target_id"]),
        "target_name": row.get("target_name"),
        "received_at_utc": row.get("created_at_utc"),
        "symbol": normalize_symbol(meta.get("symbol")),
        "side": normalize_side(meta.get("side")),
        "entry_low": meta.get("entry_low"),
        "entry_high": meta.get("entry_high"),
        "stop_loss": meta.get("stop_loss"),
        "take_profits": take_profits,
        "signal_status": signal_status,
        "fingerprint_short": row.get("fingerprint_short"),
        **execution,
        "pnl_state": resolve_pnl_state(execution["realized_pnl"]),
    }


def apply_history_filters(
    items: list[dict[str, Any]],
    *,
    symbol: str | None,
    side: str | None,
    signal_status: str | None,
    execution_status: str | None,
    outcome: str | None,
    pnl_state: str | None,
) -> list[dict[str, Any]]:
    filtered: list[dict[str, Any]] = []
    symbol_needle = symbol.strip().upper() if symbol else None
    side_needle = side.strip().upper() if side else None
    for item in items:
        if symbol_needle and (item.get("symbol") or "").upper() != symbol_needle:
            continue
        if side_needle and (item.get("side") or "").upper() != side_needle:
            continue
        if signal_status and item.get("signal_status") != signal_status:
            continue
        if execution_status and item.get("execution_status") != execution_status:
            continue
        if outcome and item.get("trade_outcome") != outcome:
            continue
        if pnl_state and item.get("pnl_state") != pnl_state:
            continue
        filtered.append(item)
    return filtered


def paginate_items(items: list[dict[str, Any]], *, page: int, page_size: int) -> tuple[list[dict[str, Any]], int]:
    safe_page = max(page, 1)
    safe_size = max(min(page_size, 100), 1)
    total = len(items)
    start = (safe_page - 1) * safe_size
    end = start + safe_size
    return items[start:end], total


def history_response(items: list[dict[str, Any]], *, page: int, page_size: int, total: int) -> dict[str, Any]:
    return {
        "items": items,
        "page": page,
        "page_size": page_size,
        "total": total,
    }


def enrich_summary_with_execution(summary: dict[str, Any] | None, *, dry_run: bool) -> dict[str, Any] | None:
    if summary is None:
        return None
    enriched = dict(summary)
    enriched.update(observer_execution_fields(dry_run=dry_run))
    enriched["pnl_state"] = resolve_pnl_state(enriched["realized_pnl"])
    return enriched
