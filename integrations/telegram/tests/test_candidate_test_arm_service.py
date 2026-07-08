"""Unit tests for controlled candidate-test arming."""

from __future__ import annotations

import sys
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import candidate_test_arm_service as ctas  # noqa: E402


def _d0e_route(**overrides: object) -> dict:
    base = {
        "id": 1,
        "target_id": 10,
        "is_enabled": 1,
        "mode": ctas.ROUTE_MODE_OBSERVER_ONLY,
        "channel_title": ctas.JUSTGOLD_CHANNEL_TITLE,
        "name": "JustGold → D0E Demo",
        "candidate_test_publish_count": 0,
        "candidate_test_expires_at_utc": None,
    }
    base.update(overrides)
    return base


def _d0e_target(**overrides: object) -> dict:
    base = {
        "id": 10,
        "is_enabled": 1,
        "account_mode": "DEMO",
        "execution_permission": "LOCKED",
        "magic_number": ctas.EXPECTED_MAGIC_NUMBER,
        "chart_symbol": ctas.EXPECTED_CHART_SYMBOL,
        "seed_filename": ctas.EXPECTED_SEED_FILENAME,
        "details_filename": ctas.EXPECTED_DETAILS_FILENAME,
        "broker_label": ctas.EXPECTED_BROKER_LABEL,
        "terminal_data_path": f"C:/Users/test/AppData/Roaming/MetaQuotes/Terminal/{ctas.D0E_TERMINAL_DATA_PATH_ID}",
    }
    base.update(overrides)
    return base


class CandidateTestArmServiceTests(unittest.TestCase):
    def test_d0e_demo_route_arm_eligible(self) -> None:
        ok, reason = ctas.validate_arm_eligibility(
            _d0e_route(),
            _d0e_target(),
            active_armed_route_count=0,
        )
        self.assertTrue(ok)
        self.assertIsNone(reason)

    def test_real_account_cannot_arm(self) -> None:
        ok, reason = ctas.validate_arm_eligibility(
            _d0e_route(),
            _d0e_target(account_mode="REAL"),
            active_armed_route_count=0,
        )
        self.assertFalse(ok)
        self.assertEqual(reason, "TARGET_NOT_DEMO")

    def test_observer_route_cannot_real_publish(self) -> None:
        allowed, reason = ctas.evaluate_real_publish_permission(
            _d0e_route(mode=ctas.ROUTE_MODE_OBSERVER_ONLY),
            listener_running=True,
            dry_run=False,
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "OBSERVER_ONLY_NO_REAL_PUBLISH")

    def test_dry_run_blocks_real_publish_even_when_armed(self) -> None:
        armed_at, expires_at = ctas.build_arm_schedule()
        allowed, reason = ctas.evaluate_real_publish_permission(
            _d0e_route(
                mode=ctas.ROUTE_MODE_CANDIDATE_TEST_ARMED,
                candidate_test_expires_at_utc=expires_at,
            ),
            listener_running=True,
            dry_run=True,
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "DRY_RUN_BLOCKS_REAL_PUBLISH")

    def test_armed_route_allows_single_real_publish_when_listener_running(self) -> None:
        armed_at, expires_at = ctas.build_arm_schedule()
        allowed, reason = ctas.evaluate_real_publish_permission(
            _d0e_route(
                mode=ctas.ROUTE_MODE_CANDIDATE_TEST_ARMED,
                candidate_test_expires_at_utc=expires_at,
            ),
            listener_running=True,
            dry_run=False,
        )
        self.assertTrue(allowed)
        self.assertIsNone(reason)

    def test_arm_ttl_expiry_blocks_publish(self) -> None:
        expired_at = (datetime.now(timezone.utc) - timedelta(minutes=1)).replace(microsecond=0)
        expires_at = expired_at.isoformat().replace("+00:00", "Z")
        allowed, reason = ctas.evaluate_real_publish_permission(
            _d0e_route(
                mode=ctas.ROUTE_MODE_CANDIDATE_TEST_ARMED,
                candidate_test_expires_at_utc=expires_at,
            ),
            listener_running=True,
            dry_run=False,
            now=datetime.now(timezone.utc),
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "CANDIDATE_TEST_EXPIRED")

    def test_second_publish_rejected_after_consumed(self) -> None:
        armed_at, expires_at = ctas.build_arm_schedule()
        route = _d0e_route(
            mode=ctas.ROUTE_MODE_CANDIDATE_TEST_CONSUMED,
            candidate_test_expires_at_utc=expires_at,
            candidate_test_publish_count=1,
        )
        allowed, reason = ctas.evaluate_real_publish_permission(
            route,
            listener_running=True,
            dry_run=False,
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "CANDIDATE_TEST_NOT_ARMED")

    def test_publish_limit_reached_while_still_armed(self) -> None:
        armed_at, expires_at = ctas.build_arm_schedule()
        allowed, reason = ctas.evaluate_real_publish_permission(
            _d0e_route(
                mode=ctas.ROUTE_MODE_CANDIDATE_TEST_ARMED,
                candidate_test_expires_at_utc=expires_at,
                candidate_test_publish_count=1,
            ),
            listener_running=True,
            dry_run=False,
        )
        self.assertFalse(allowed)
        self.assertEqual(reason, "CANDIDATE_TEST_PUBLISH_ALREADY_CONSUMED")

    def test_listener_start_supports_observer_and_armed(self) -> None:
        self.assertTrue(ctas.route_supports_listener_start(ctas.ROUTE_MODE_OBSERVER_ONLY))
        self.assertTrue(ctas.route_supports_listener_start(ctas.ROUTE_MODE_CANDIDATE_TEST_ARMED))
        self.assertFalse(ctas.route_supports_listener_start(ctas.ROUTE_MODE_CANDIDATE_TEST_CONSUMED))

    def test_build_arm_audit_keeps_execution_locked(self) -> None:
        audit = ctas.build_arm_audit(_d0e_route(), _d0e_target())
        self.assertEqual(audit.execution_permission, "LOCKED")
        self.assertEqual(audit.publish_remaining, 1)


if __name__ == "__main__":
    unittest.main()
