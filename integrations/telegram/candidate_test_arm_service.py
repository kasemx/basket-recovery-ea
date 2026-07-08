"""Controlled candidate-test arming for demo routes (no broker execution)."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

D0E_TERMINAL_DATA_PATH_ID = "D0E8209F77C8CF37AD8BF550E51FF075"
EXPECTED_SEED_FILENAME = "br_d0e_justgold_seed.txt"
EXPECTED_DETAILS_FILENAME = "br_d0e_justgold_details.txt"
EXPECTED_MAGIC_NUMBER = 91001
EXPECTED_CHART_SYMBOL = "XAUUSD"
EXPECTED_BROKER_LABEL = "VantageMarkets-Demo"
JUSTGOLD_CHANNEL_TITLE = "JustGold"
CANDIDATE_TEST_TTL_SECONDS = 15 * 60
CANDIDATE_TEST_PUBLISH_LIMIT = 1

ROUTE_MODE_OBSERVER_ONLY = "OBSERVER_ONLY"
ROUTE_MODE_CANDIDATE_TEST_ARMED = "CANDIDATE_TEST_ARMED"
ROUTE_MODE_CANDIDATE_TEST_CONSUMED = "CANDIDATE_TEST_CONSUMED"
ROUTE_MODE_CANDIDATE_TEST_EXPIRED = "CANDIDATE_TEST_EXPIRED"
ROUTE_MODE_CANDIDATE_TEST_BLOCKED = "CANDIDATE_TEST_BLOCKED"

CANDIDATE_TEST_ROUTE_MODES = frozenset(
    {
        ROUTE_MODE_CANDIDATE_TEST_ARMED,
        ROUTE_MODE_CANDIDATE_TEST_CONSUMED,
        ROUTE_MODE_CANDIDATE_TEST_EXPIRED,
        ROUTE_MODE_CANDIDATE_TEST_BLOCKED,
    }
)
LISTENER_COMPATIBLE_ROUTE_MODES = frozenset(
    {
        ROUTE_MODE_OBSERVER_ONLY,
        ROUTE_MODE_CANDIDATE_TEST_ARMED,
    }
)


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    return utc_now().replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_utc_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    text = str(value).strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def normalize_path_token(value: str | None) -> str:
    if not value:
        return ""
    return str(value).replace("\\", "/").strip().strip('"').upper()


def path_contains_d0e(value: str | None) -> bool:
    return D0E_TERMINAL_DATA_PATH_ID in normalize_path_token(value)


@dataclass(frozen=True)
class CandidateTestArmAudit:
    route_id: int
    target_id: int
    status: str
    armed_at_utc: str | None = None
    expires_at_utc: str | None = None
    armed_by_local_operator: str | None = None
    publish_count: int = 0
    publish_remaining: int = 0
    safe_block_reason: str | None = None
    execution_permission: str = "LOCKED"

    def to_dict(self) -> dict[str, Any]:
        return {
            "route_id": self.route_id,
            "target_id": self.target_id,
            "status": self.status,
            "armed_at_utc": self.armed_at_utc,
            "expires_at_utc": self.expires_at_utc,
            "armed_by_local_operator": self.armed_by_local_operator,
            "publish_count": self.publish_count,
            "publish_remaining": self.publish_remaining,
            "safe_block_reason": self.safe_block_reason,
            "execution_permission": self.execution_permission,
        }


def _target_account_mode(target: dict[str, Any]) -> str:
    mode = str(target.get("account_mode") or target.get("expected_account_type") or "").upper()
    return mode


def validate_arm_eligibility(
    route: dict[str, Any],
    target: dict[str, Any],
    *,
    active_armed_route_count: int,
) -> tuple[bool, str | None]:
    if not route.get("is_enabled"):
        return False, "ROUTE_DISABLED"
    if not target.get("is_enabled"):
        return False, "TARGET_DISABLED"
    if _target_account_mode(target) != "DEMO":
        return False, "TARGET_NOT_DEMO"
    if str(target.get("execution_permission", "LOCKED")).upper() != "LOCKED":
        return False, "EXECUTION_PERMISSION_NOT_LOCKED"
    if int(target.get("magic_number") or 0) != EXPECTED_MAGIC_NUMBER:
        return False, "MAGIC_MISMATCH"
    if str(target.get("chart_symbol") or "").upper() != EXPECTED_CHART_SYMBOL:
        return False, "SYMBOL_MISMATCH"
    if str(target.get("seed_filename") or "") != EXPECTED_SEED_FILENAME:
        return False, "SEED_FILENAME_MISMATCH"
    if str(target.get("details_filename") or "") != EXPECTED_DETAILS_FILENAME:
        return False, "DETAILS_FILENAME_MISMATCH"
    broker = str(target.get("broker_label") or "").strip()
    if broker and broker != EXPECTED_BROKER_LABEL:
        return False, "BROKER_MISMATCH"
    if not path_contains_d0e(str(target.get("terminal_data_path") or "")):
        return False, "TERMINAL_DATA_PATH_MISMATCH"
    channel_title = str(route.get("channel_title") or "").strip()
    route_name = str(route.get("name") or "").strip().lower()
    if channel_title != JUSTGOLD_CHANNEL_TITLE and route_name != "justgold":
        return False, "ROUTE_SOURCE_MISMATCH"
    if active_armed_route_count > 0:
        return False, "ANOTHER_ROUTE_ALREADY_ARMED"
    current_mode = str(route.get("mode") or ROUTE_MODE_OBSERVER_ONLY).upper()
    if current_mode == ROUTE_MODE_CANDIDATE_TEST_ARMED:
        return False, "ALREADY_ARMED"
    if current_mode in {
        ROUTE_MODE_CANDIDATE_TEST_CONSUMED,
        ROUTE_MODE_CANDIDATE_TEST_EXPIRED,
        ROUTE_MODE_CANDIDATE_TEST_BLOCKED,
    }:
        return False, "CANDIDATE_TEST_NOT_REARMABLE"
    return True, None


def is_armed_mode(mode: str | None) -> bool:
    return str(mode or "").upper() == ROUTE_MODE_CANDIDATE_TEST_ARMED


def is_arm_expired(route: dict[str, Any], *, now: datetime | None = None) -> bool:
    if not is_armed_mode(route.get("mode")):
        return False
    expires = parse_utc_iso(route.get("candidate_test_expires_at_utc"))
    if expires is None:
        return True
    current = now or utc_now()
    return current >= expires


def build_arm_schedule(*, now: datetime | None = None) -> tuple[str, str]:
    current = now or utc_now()
    armed_at = current.replace(microsecond=0).isoformat().replace("+00:00", "Z")
    expires = (current + timedelta(seconds=CANDIDATE_TEST_TTL_SECONDS)).replace(microsecond=0)
    expires_at = expires.isoformat().replace("+00:00", "Z")
    return armed_at, expires_at


def build_arm_audit(route: dict[str, Any], target: dict[str, Any]) -> CandidateTestArmAudit:
    mode = str(route.get("mode") or ROUTE_MODE_OBSERVER_ONLY).upper()
    publish_count = int(route.get("candidate_test_publish_count") or 0)
    remaining = max(0, CANDIDATE_TEST_PUBLISH_LIMIT - publish_count)
    return CandidateTestArmAudit(
        route_id=int(route["id"]),
        target_id=int(route["target_id"]),
        status=mode,
        armed_at_utc=route.get("candidate_test_armed_at_utc"),
        expires_at_utc=route.get("candidate_test_expires_at_utc"),
        armed_by_local_operator=route.get("candidate_test_armed_by"),
        publish_count=publish_count,
        publish_remaining=remaining,
        safe_block_reason=route.get("candidate_test_block_reason"),
        execution_permission=str(target.get("execution_permission", "LOCKED")).upper(),
    )


def evaluate_real_publish_permission(
    route: dict[str, Any],
    *,
    listener_running: bool,
    dry_run: bool,
    now: datetime | None = None,
) -> tuple[bool, str | None]:
    mode = str(route.get("mode") or ROUTE_MODE_OBSERVER_ONLY).upper()
    if mode == ROUTE_MODE_OBSERVER_ONLY:
        return False, "OBSERVER_ONLY_NO_REAL_PUBLISH"
    if mode != ROUTE_MODE_CANDIDATE_TEST_ARMED:
        return False, "CANDIDATE_TEST_NOT_ARMED"
    if dry_run:
        return False, "DRY_RUN_BLOCKS_REAL_PUBLISH"
    if not listener_running:
        return False, "LISTENER_NOT_RUNNING"
    if is_arm_expired(route, now=now):
        return False, "CANDIDATE_TEST_EXPIRED"
    publish_count = int(route.get("candidate_test_publish_count") or 0)
    if publish_count >= CANDIDATE_TEST_PUBLISH_LIMIT:
        return False, "CANDIDATE_TEST_PUBLISH_ALREADY_CONSUMED"
    return True, None


def route_supports_listener_start(mode: str | None) -> bool:
    return str(mode or "").upper() in LISTENER_COMPATIBLE_ROUTE_MODES
