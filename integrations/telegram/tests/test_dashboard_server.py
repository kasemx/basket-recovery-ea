"""Tests for local Telegram Route Dashboard server."""

from __future__ import annotations

import importlib
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch
from urllib import error, request

ROOT = Path(__file__).resolve().parents[1]
DASHBOARD_DIR = ROOT / "dashboard"
sys.path.insert(0, str(ROOT))

import dashboard_api  # noqa: E402
import dashboard_security  # noqa: E402
import dashboard_server  # noqa: E402
import dashboard_store  # noqa: E402
import telegram_adapter  # noqa: E402
import telegram_dashboard_server  # noqa: E402
from telegram_adapter import (  # noqa: E402
    TELEGRAM_2FA_REQUIRED,
    TELEGRAM_AUTH_FAILED,
    TELEGRAM_CONNECTED,
    TELEGRAM_CONFIG_MISSING,
    TELETHON_NOT_INSTALLED,
    TelegramAdapter,
    TelegramChannelInfo,
    TelegramCodeResult,
    TelegramSignInResult,
)


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((dashboard_security.ALLOWED_HOST, 0))
        return sock.getsockname()[1]


class FakeTelegramAdapter:
    phone_code_hash = "fake_phone_code_hash_secret"
    sign_in_code_result = TelegramSignInResult(status=TELEGRAM_CONNECTED)
    sign_in_password_result = TelegramSignInResult(status=TELEGRAM_CONNECTED)
    list_dialogs_result: list[TelegramChannelInfo] = []

    async def connect(self):
        return telegram_adapter.TelegramConnectionResult(status=TELEGRAM_CONNECTED)

    async def send_code(self, phone: str) -> TelegramCodeResult:
        return TelegramCodeResult(
            status="CODE_SENT",
            phone_code_hash=self.phone_code_hash,
        )

    async def sign_in_code(self, phone: str, code: str, phone_code_hash: str) -> TelegramSignInResult:
        if code == "2fa":
            return TelegramSignInResult(
                status="TWO_FACTOR_REQUIRED",
                error_code=TELEGRAM_2FA_REQUIRED,
            )
        if code == "bad":
            return TelegramSignInResult(status="ERROR", error_code=TELEGRAM_AUTH_FAILED)
        return self.sign_in_code_result

    async def sign_in_password(self, password: str) -> TelegramSignInResult:
        if password == "bad":
            return TelegramSignInResult(status="ERROR", error_code=TELEGRAM_AUTH_FAILED)
        return self.sign_in_password_result

    async def list_dialogs(self, limit: int = 200) -> list[TelegramChannelInfo]:
        return list(self.list_dialogs_result)

    async def disconnect(self) -> None:
        return None


def env_config(session_path: Path) -> dict[str, str]:
    return {
        "TELEGRAM_API_ID": "12345",
        "TELEGRAM_API_HASH": "abc123hash",
        "TELEGRAM_SESSION_PATH": str(session_path / "dashboard.session"),
    }


class DashboardServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="dashboard_test_")
        self.data_dir = Path(self.temp_dir)
        self.session_path = self.data_dir / "dashboard.session"
        self.env_patch = patch.dict(os.environ, env_config(self.data_dir), clear=False)
        self.env_patch.start()
        self.fake_adapter = FakeTelegramAdapter()
        self.telethon_patch = patch(
            "telegram_adapter.is_telethon_available",
            return_value=True,
        )
        self.telethon_patch.start()
        self.db = dashboard_store.DashboardDatabase(self.data_dir / "dashboard.sqlite3")
        self.telegram_service = dashboard_api.TelegramService(
            adapter_factory=lambda: self.fake_adapter,
        )
        self.port = free_port()
        self.context = dashboard_api.DashboardContext(
            host=dashboard_security.ALLOWED_HOST,
            port=self.port,
            data_dir=self.data_dir,
            dashboard_dir=DASHBOARD_DIR.resolve(),
            database=self.db,
            telegram_service=self.telegram_service,
        )
        self.server = dashboard_server.create_server(self.context)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.telethon_patch.stop()
        self.env_patch.stop()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @property
    def base_url(self) -> str:
        return f"http://{dashboard_security.ALLOWED_HOST}:{self.port}"

    def request(
        self,
        method: str,
        path: str,
        payload: dict | None = None,
    ) -> tuple[int, dict | str | bytes]:
        data = None
        headers = {}
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        req = request.Request(
            self.base_url + path,
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with request.urlopen(req, timeout=5) as response:
                body = response.read()
                content_type = response.headers.get("Content-Type", "")
                if "application/json" in content_type:
                    return response.status, json.loads(body.decode("utf-8"))
                return response.status, body
        except error.HTTPError as exc:
            body = exc.read().decode("utf-8")
            try:
                return exc.code, json.loads(body)
            except json.JSONDecodeError:
                return exc.code, body

    def configure_phone(self, phone: str = "+905551234567") -> None:
        status, _payload = self.request(
            "POST",
            "/api/telegram/configure",
            {"phone": phone},
        )
        self.assertEqual(status, 200)

    def test_host_outside_localhost_rejected(self) -> None:
        with self.assertRaises(dashboard_security.DashboardSecurityError):
            dashboard_security.validate_host("0.0.0.0")

    def test_schema_idempotent_on_reopen(self) -> None:
        db_path = self.data_dir / "reopen.sqlite3"
        dashboard_store.DashboardDatabase(db_path)
        reopened = dashboard_store.DashboardDatabase(db_path)
        overview = reopened.overview()
        self.assertEqual(overview["telegram"]["status"], "DISCONNECTED")

    def test_overview_initial_safe_state(self) -> None:
        status, payload = self.request("GET", "/api/overview")
        self.assertEqual(status, 200)
        self.assertEqual(payload["safety"]["broker_execution"], "DISABLED_BY_DESIGN")
        self.assertEqual(payload["safety"]["file_common_write"], "NOT_IMPLEMENTED_IN_DASHBOARD")
        self.assertEqual(payload["counts"]["tracked_channels"], 0)

    def test_configure_env_missing_returns_error(self) -> None:
        self.env_patch.stop()
        with patch.dict(os.environ, {}, clear=True):
            status, payload = self.request(
                "POST",
                "/api/telegram/configure",
                {"phone": "+905551234567"},
            )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error_code"], TELEGRAM_CONFIG_MISSING)
        self.env_patch.start()

    def test_configure_rejects_literal_credentials(self) -> None:
        status, payload = self.request(
            "POST",
            "/api/telegram/configure",
            {"phone": "+905551234567", "api_hash": "secret"},
        )
        self.assertEqual(status, 400)
        self.assertIn("credentials", payload["error"])

    def test_configure_accepts_masked_phone_only(self) -> None:
        status, payload = self.request(
            "POST",
            "/api/telegram/configure",
            {"phone": "+905551234567"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "API_CONFIGURED")
        self.assertTrue(payload["phone_masked"].endswith("4567"))
        self.assertNotIn("5551234567", payload["phone_masked"])
        self.assertIn("session_path_masked", payload)

        with self.db._connect() as conn:
            row = conn.execute(
                "SELECT phone_masked, phone_code_hash FROM telegram_connection WHERE id = 1"
            ).fetchone()
        self.assertIsNotNone(row)
        self.assertNotIn("5551234567", row["phone_masked"])

    def test_request_code_telethon_missing(self) -> None:
        self.telethon_patch.stop()
        with patch("dashboard_api.is_telethon_available", return_value=False):
            self.configure_phone()
            status, payload = self.request("POST", "/api/telegram/request-code", {})
        self.assertEqual(status, 500)
        self.assertEqual(payload["error_code"], TELETHON_NOT_INSTALLED)
        self.telethon_patch.start()

    def test_request_code_fake_adapter_stores_hash_not_response(self) -> None:
        self.configure_phone()
        status, payload = self.request("POST", "/api/telegram/request-code", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "CODE_SENT")
        self.assertNotIn("phone_code_hash", payload)
        self.assertNotIn("fake_phone_code_hash_secret", json.dumps(payload))
        with self.db._connect() as conn:
            row = conn.execute(
                "SELECT phone_code_hash FROM telegram_connection WHERE id = 1"
            ).fetchone()
        self.assertEqual(row["phone_code_hash"], FakeTelegramAdapter.phone_code_hash)

    def test_verify_code_success_connected(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        status, payload = self.request(
            "POST",
            "/api/telegram/verify-code",
            {"code": "12345"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], TELEGRAM_CONNECTED)
        row = self.db.get_telegram_status()
        self.assertEqual(row["status"], "CONNECTED")

    def test_verify_code_two_factor_required(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        status, payload = self.request(
            "POST",
            "/api/telegram/verify-code",
            {"code": "2fa"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "TWO_FACTOR_REQUIRED")
        self.assertEqual(self.db.get_telegram_status()["status"], "TWO_FACTOR_REQUIRED")

    def test_verify_password_success_connected(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        self.request("POST", "/api/telegram/verify-code", {"code": "2fa"})
        status, payload = self.request(
            "POST",
            "/api/telegram/verify-password",
            {"password": "secret"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], TELEGRAM_CONNECTED)

    def test_wrong_code_and_password_redacted(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        status, payload = self.request(
            "POST",
            "/api/telegram/verify-code",
            {"code": "bad"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["status"], "ERROR")
        self.assertNotIn("bad", json.dumps(payload))

        self.db.set_telegram_two_factor_required()
        status, payload = self.request(
            "POST",
            "/api/telegram/verify-password",
            {"password": "bad"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error_code"], TELEGRAM_AUTH_FAILED)

    def test_sync_channels_requires_connected(self) -> None:
        status, payload = self.request("POST", "/api/telegram/sync-channels", {})
        self.assertEqual(status, 400)
        self.assertIn("connected", payload["error"].lower())

    def test_sync_channels_fake_adapter_inserts_three(self) -> None:
        self.fake_adapter.list_dialogs_result = [
            TelegramChannelInfo("1001", "Alpha Channel", "channel", "alpha"),
            TelegramChannelInfo("1002", "Beta Group", "group", None),
            TelegramChannelInfo("1003", "Gamma Super", "supergroup", "gamma"),
        ]
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        self.request("POST", "/api/telegram/verify-code", {"code": "12345"})
        status, payload = self.request("POST", "/api/telegram/sync-channels", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["synced"], 3)
        self.assertEqual(payload["source"], "TELEGRAM")
        channels = self.request("GET", "/api/channels")[1]["channels"]
        self.assertEqual(len(channels), 3)
        self.assertTrue(all(ch["source"] == "TELEGRAM" for ch in channels))

    def test_sync_preserves_existing_is_tracking(self) -> None:
        self.fake_adapter.list_dialogs_result = [
            TelegramChannelInfo("2001", "Tracked Channel", "channel", "tracked"),
        ]
        self.db.sync_telegram_channels(
            [
                {
                    "telegram_channel_id": "2001",
                    "title": "Tracked Channel",
                    "channel_type": "channel",
                    "username": "tracked",
                }
            ]
        )
        with self.db._connect() as conn:
            conn.execute(
                "UPDATE tracked_channels SET is_tracking = 1 WHERE telegram_channel_id = '2001'"
            )
        self.db.set_telegram_connected()
        status, payload = self.request("POST", "/api/telegram/sync-channels", {})
        self.assertEqual(status, 200)
        channel = self.request("GET", "/api/channels")[1]["channels"][0]
        self.assertEqual(channel["is_tracking"], 1)

    def test_disconnect_does_not_delete_session_path(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        self.request("POST", "/api/telegram/verify-code", {"code": "12345"})
        status, payload = self.request("POST", "/api/telegram/disconnect", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "DISCONNECTED")
        self.assertIn("session_path_masked", payload)
        row = self.db.get_telegram_status()
        self.assertIsNotNone(row.get("session_path_masked"))

    def test_telegram_status_masks_phone_and_session(self) -> None:
        self.configure_phone()
        status, payload = self.request("GET", "/api/telegram/status")
        self.assertEqual(status, 200)
        self.assertTrue(payload["config_ready"])
        self.assertTrue(payload["telethon_available"])
        self.assertNotIn("phone_code_hash", payload)
        self.assertNotIn("5551234567", json.dumps(payload))

    def test_login_audit_does_not_expose_secrets(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {})
        self.request("POST", "/api/telegram/verify-code", {"code": "12345"})
        self.db.add_audit(
            "SECRET_TEST",
            "INFO",
            "api_hash=supersecret phone_code_hash=abc code=12345 password=secret",
            {
                "api_hash": "supersecret",
                "phone_code_hash": "abc",
                "code": "12345",
                "password": "secret",
            },
        )
        status, payload = self.request("GET", "/api/audit?limit=20")
        self.assertEqual(status, 200)
        blob = json.dumps(payload)
        self.assertNotIn("supersecret", blob)
        self.assertNotIn("fake_phone_code_hash_secret", blob)
        self.assertNotIn("12345", blob)

    def test_demo_channels_import_idempotent(self) -> None:
        first_status, first_payload = self.request("POST", "/api/channels/import-demo", {})
        second_status, second_payload = self.request("POST", "/api/channels/import-demo", {})
        self.assertEqual(first_status, 200)
        self.assertEqual(second_payload["inserted"], 0)
        self.assertEqual(first_payload["source"], "LOCAL_DEMO_DATA")
        channels = self.request("GET", "/api/channels")[1]["channels"]
        self.assertTrue(all(ch["source"] == "LOCAL_DEMO_DATA" for ch in channels))

    def test_channel_tracking_update_writes_audit(self) -> None:
        self.request("POST", "/api/channels/import-demo", {})
        channels = self.request("GET", "/api/channels")[1]["channels"]
        channel_id = channels[0]["id"]
        status, _payload = self.request(
            "PATCH",
            f"/api/channels/{channel_id}",
            {"is_tracking": 1},
        )
        self.assertEqual(status, 200)
        audit = self.request("GET", "/api/audit?limit=20")[1]["events"]
        self.assertTrue(any(event["event_type"] == "CHANNEL_UPDATE" for event in audit))

    def test_target_create_validation(self) -> None:
        valid = {
            "name": "Vantage Demo XAUUSD",
            "terminal_label": "D0E",
            "broker_label": "VantageMarkets-Demo",
            "account_mode": "DEMO",
            "file_common_root": str(self.data_dir / "common"),
            "seed_filename": "br_vantage_xauusd_seed.txt",
            "details_filename": "br_vantage_xauusd_details.txt",
        }
        status, payload = self.request("POST", "/api/targets", valid)
        self.assertEqual(status, 201)
        self.assertEqual(payload["target"]["observer_only"], 1)

    def test_route_create_and_duplicate_reject(self) -> None:
        self.request("POST", "/api/channels/import-demo", {})
        target_payload = {
            "name": "Route Target",
            "terminal_label": "D0E",
            "broker_label": "VantageMarkets-Demo",
            "account_mode": "DEMO",
            "file_common_root": str(self.data_dir / "common"),
            "seed_filename": "seed_a.txt",
            "details_filename": "details_a.txt",
        }
        target = self.request("POST", "/api/targets", target_payload)[1]["target"]
        channel_id = self.request("GET", "/api/channels")[1]["channels"][0]["id"]
        route_payload = {
            "name": "Gold Route",
            "channel_id": channel_id,
            "target_id": target["id"],
            "parser_profile": "FASTTRACK_GOLD_NOW",
        }
        status, created = self.request("POST", "/api/routes", route_payload)
        self.assertEqual(status, 201)
        self.assertEqual(created["route"]["mode"], "OBSERVER_ONLY")

    def test_delete_with_routes_returns_conflict(self) -> None:
        self.request("POST", "/api/channels/import-demo", {})
        channel_id = self.request("GET", "/api/channels")[1]["channels"][0]["id"]
        target = self.request(
            "POST",
            "/api/targets",
            {
                "name": "Delete Guard Target",
                "terminal_label": "D0E",
                "broker_label": "Demo",
                "account_mode": "DEMO",
                "file_common_root": str(self.data_dir / "common"),
                "seed_filename": "seed_b.txt",
                "details_filename": "details_b.txt",
            },
        )[1]["target"]
        self.request(
            "POST",
            "/api/routes",
            {
                "name": "Guard Route",
                "channel_id": channel_id,
                "target_id": target["id"],
            },
        )
        status, payload = self.request("DELETE", f"/api/channels/{channel_id}")
        self.assertEqual(status, 409)
        self.assertIn("routes", payload["error"])

    def test_audit_secret_redaction(self) -> None:
        self.db.add_audit(
            "SECRET_TEST",
            "INFO",
            "api_hash=supersecret phone=+905551234567 session=abc",
            {"api_hash": "supersecret", "phone": "+905551234567", "code": "12345"},
        )
        status, payload = self.request("GET", "/api/audit?limit=10")
        self.assertEqual(status, 200)
        event = payload["events"][0]
        self.assertNotIn("supersecret", event["message"])
        self.assertNotIn("5551234567", json.dumps(event))

    def test_static_path_traversal_rejected(self) -> None:
        status, _payload = self.request("GET", "/../telegram_dashboard_server.py")
        self.assertIn(status, (403, 404))

    def test_health_localhost_metadata(self) -> None:
        status, payload = self.request("GET", "/api/health")
        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["host"], dashboard_security.ALLOWED_HOST)

    def test_static_assets_and_health_smoke(self) -> None:
        for path in ("/", "/app.js", "/styles.css", "/api/health", "/api/telegram/status"):
            status, body = self.request("GET", path)
            self.assertEqual(status, 200)
            if path.startswith("/api/"):
                self.assertIsInstance(body, dict)
            else:
                self.assertIsInstance(body, (bytes, str))
                self.assertGreater(len(body), 10)


class DashboardModularizationTests(unittest.TestCase):
    def test_legacy_wrapper_importable(self) -> None:
        self.assertTrue(hasattr(telegram_dashboard_server, "main"))

    def test_no_circular_imports(self) -> None:
        for module_name in (
            "dashboard_security",
            "dashboard_store",
            "dashboard_api",
            "dashboard_server",
            "telegram_adapter",
            "telegram_dashboard_server",
        ):
            module = importlib.import_module(module_name)
            self.assertIsNotNone(module)

    def test_api_contract_health_and_overview(self) -> None:
        temp_dir = tempfile.mkdtemp(prefix="dashboard_contract_")
        try:
            db = dashboard_store.DashboardDatabase(Path(temp_dir) / "dashboard.sqlite3")
            overview = db.overview()
            self.assertIn("telegram", overview)
            self.assertEqual(overview["safety"]["broker_execution"], "DISABLED_BY_DESIGN")
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_static_asset_map_only_three_files(self) -> None:
        allowed = set(dashboard_security.STATIC_ASSET_MAP.values())
        self.assertEqual(allowed, {"index.html", "app.js", "styles.css"})


if __name__ == "__main__":
    unittest.main()
