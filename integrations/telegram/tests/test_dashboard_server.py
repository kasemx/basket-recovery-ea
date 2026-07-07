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
import dashboard_vault  # noqa: E402
import fasttrack_file_bridge  # noqa: E402
import route_listener_service  # noqa: E402
import listener_worker_client  # noqa: E402
import telegram_adapter  # noqa: E402
import mt5_account_probe  # noqa: E402
import mt5_target_service  # noqa: E402
import mt5_terminal_discovery  # noqa: E402
import telegram_dashboard_server  # noqa: E402
from telegram_adapter import (  # noqa: E402
    CREDENTIAL_SOURCE_ENV,
    CREDENTIAL_SOURCE_NONE,
    CREDENTIAL_SOURCE_VAULT,
    SESSION_FILENAME,
    TELEGRAM_2FA_REQUIRED,
    TELEGRAM_AUTH_FAILED,
    TELEGRAM_CONNECTED,
    TELEGRAM_CONFIG_MISSING,
    TELETHON_NOT_INSTALLED,
    TelegramAdapter,
    TelegramChannelInfo,
    TelegramCodeResult,
    TelegramSignInResult,
    load_telegram_config,
    resolve_credential_source,
    resolve_session_path,
)

VALID_SEED = "Gold sell now"
VALID_DETAILS = (
    "Gold sell now 4014 - 4017\n"
    "SL: 4077\n"
    "TP: 4007\n"
    "TP: 4005\n"
    "TP: 4003\n"
    "TP: 4002\n"
    "TP: open"
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
    send_code_error: TelegramCodeResult | None = None

    async def connect(self):
        return telegram_adapter.TelegramConnectionResult(status=TELEGRAM_CONNECTED)

    async def send_code(self, phone: str) -> TelegramCodeResult:
        if self.send_code_error is not None:
            return self.send_code_error
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


def env_config_clear() -> dict[str, str]:
    return {
        "TELEGRAM_API_ID": "",
        "TELEGRAM_API_HASH": "",
        "TELEGRAM_SESSION_PATH": "",
    }


def save_test_vault_credentials(data_dir: Path) -> None:
    dashboard_vault.DashboardCredentialVault(data_dir).save_telegram_credentials(
        "12345",
        "abc123hashvalue",
    )


class DashboardCredentialVaultTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="dashboard_vault_")
        self.data_dir = Path(self.temp_dir)

    def tearDown(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_vault_roundtrip_and_no_plaintext_on_disk(self) -> None:
        vault = dashboard_vault.DashboardCredentialVault(self.data_dir)
        vault.save_telegram_credentials("12345", "abc123hashvalue")
        self.assertTrue(vault.has_telegram_credentials())
        loaded = vault.load_telegram_credentials()
        self.assertEqual(loaded, ("12345", "abc123hashvalue"))
        raw = vault.vault_path.read_text(encoding="utf-8")
        self.assertNotIn("abc123hashvalue", raw)
        self.assertNotIn('"api_hash":"abc123hashvalue"', raw)

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_clear_credentials_removes_vault_file(self) -> None:
        vault = dashboard_vault.DashboardCredentialVault(self.data_dir)
        vault.save_telegram_credentials("12345", "abc123hashvalue")
        vault.clear_telegram_credentials()
        self.assertFalse(vault.vault_path.exists())
        self.assertFalse(vault.has_telegram_credentials())

    def test_non_windows_fail_closed(self) -> None:
        with patch.object(dashboard_vault, "is_vault_platform_supported", return_value=False):
            vault = dashboard_vault.DashboardCredentialVault(self.data_dir)
            with self.assertRaises(dashboard_vault.CredentialVaultError) as ctx:
                vault.save_telegram_credentials("12345", "abc123hashvalue")
            self.assertEqual(
                ctx.exception.error_code,
                dashboard_vault.CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM,
            )


class DashboardServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="dashboard_test_")
        self.data_dir = Path(self.temp_dir)
        self.session_path = self.data_dir / SESSION_FILENAME
        self.env_patch = patch.dict(os.environ, env_config_clear(), clear=False)
        self.env_patch.start()
        if sys.platform == "win32":
            save_test_vault_credentials(self.data_dir)
        else:
            self.env_patch.stop()
            self.env_patch = patch.dict(
                os.environ,
                {
                    "TELEGRAM_API_ID": "12345",
                    "TELEGRAM_API_HASH": "abc123hashvalue",
                    "TELEGRAM_SESSION_PATH": str(self.session_path),
                },
                clear=False,
            )
            self.env_patch.start()
        self.fake_adapter = FakeTelegramAdapter()
        self.telethon_patch = patch(
            "telegram_adapter.is_telethon_available",
            return_value=True,
        )
        self.telethon_patch.start()
        self.worker_inline_patch = patch.dict(
            os.environ,
            {"DASHBOARD_LISTENER_WORKER_INLINE": "1"},
            clear=False,
        )
        self.worker_inline_patch.start()
        self.db = dashboard_store.DashboardDatabase(self.data_dir / "dashboard.sqlite3")
        self.telegram_service = dashboard_api.TelegramService(
            data_dir=self.data_dir,
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
        if getattr(self.context, "listener_worker_client", None) is not None:
            try:
                self.context.listener_worker_client.stop_worker()
            except Exception:
                pass
            self.context.listener_worker_client.shutdown_inline_worker()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.telethon_patch.stop()
        self.worker_inline_patch.stop()
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
        dashboard_vault.DashboardCredentialVault(self.data_dir).clear_telegram_credentials()
        self.env_patch.stop()
        with patch.dict(os.environ, env_config_clear(), clear=False):
            status, payload = self.request(
                "POST",
                "/api/telegram/configure",
                {"phone": "+905551234567"},
            )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error_code"], TELEGRAM_CONFIG_MISSING)
        self.env_patch.start()
        if sys.platform == "win32":
            save_test_vault_credentials(self.data_dir)

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
            status, payload = self.request(
                "POST",
                "/api/telegram/request-code",
                {"phone": "+905551234567"},
            )
        self.assertEqual(status, 500)
        self.assertEqual(payload["error_code"], TELETHON_NOT_INSTALLED)
        self.assertIn("user_message", payload)
        self.telethon_patch.start()

    def test_request_code_fake_adapter_stores_hash_not_response(self) -> None:
        self.configure_phone()
        status, payload = self.request(
            "POST",
            "/api/telegram/request-code",
            {"phone": "+905551234567"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "CODE_SENT")
        self.assertNotIn("phone_code_hash", payload)
        self.assertNotIn("fake_phone_code_hash_secret", json.dumps(payload))
        with self.db._connect() as conn:
            row = conn.execute(
                "SELECT phone_code_hash FROM telegram_connection WHERE id = 1"
            ).fetchone()
        self.assertEqual(row["phone_code_hash"], FakeTelegramAdapter.phone_code_hash)

    def test_request_code_with_phone_body_after_memory_loss(self) -> None:
        self.configure_phone()
        self.telegram_service._auth_phone = None
        status, payload = self.request(
            "POST",
            "/api/telegram/request-code",
            {"phone": "+905551234567"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "CODE_SENT")
        self.assertEqual(self.db.get_telegram_status()["status"], "CODE_SENT")

    def test_request_code_without_phone_returns_validation(self) -> None:
        self.configure_phone()
        self.telegram_service._auth_phone = None
        status, payload = self.request("POST", "/api/telegram/request-code", {})
        self.assertEqual(status, 400)
        self.assertIn("phone", payload["error"].lower())

    def test_request_code_maps_safe_error_without_secrets(self) -> None:
        self.configure_phone()
        self.fake_adapter.send_code_error = TelegramCodeResult(
            status="ERROR",
            phone_code_hash="",
            error_code="TELEGRAM_API_ID_INVALID",
        )
        status, payload = self.request(
            "POST",
            "/api/telegram/request-code",
            {"phone": "+905551234567"},
        )
        self.assertEqual(status, 400)
        self.assertEqual(payload["error_code"], "TELEGRAM_API_ID_INVALID")
        self.assertIn("user_message", payload)
        self.assertNotIn("fake", json.dumps(payload))

    def test_diagnostics_endpoint_safe_fields(self) -> None:
        self.configure_phone()
        status, payload = self.request("GET", "/api/telegram/diagnostics")
        self.assertEqual(status, 200)
        expected_keys = {
            "vault_supported",
            "vault_file_present",
            "vault_credentials_available",
            "credential_source",
            "session_path_resolved",
            "session_parent_exists",
            "session_file_exists",
            "data_dir_consistent",
            "last_safe_error_code",
        }
        self.assertEqual(set(payload.keys()), expected_keys)
        self.assertTrue(payload["session_path_resolved"])
        self.assertTrue(payload["data_dir_consistent"])
        if sys.platform == "win32":
            self.assertEqual(payload["credential_source"], CREDENTIAL_SOURCE_VAULT)
        else:
            self.assertEqual(payload["credential_source"], CREDENTIAL_SOURCE_ENV)
        blob = json.dumps(payload)
        self.assertNotIn("api_hash", blob.lower())
        self.assertNotIn("5551234567", blob)
        self.assertNotIn(str(self.data_dir), blob)
        self.assertNotIn(str(self.session_path), blob)

    def test_session_parent_created_before_request_code(self) -> None:
        nested_dir = self.data_dir / "nested" / "sessions"
        session_path = nested_dir / "custom.session"
        self.env_patch.stop()
        env = env_config_clear()
        env["TELEGRAM_SESSION_PATH"] = str(session_path)
        self.env_patch = patch.dict(os.environ, env, clear=False)
        self.env_patch.start()
        if sys.platform == "win32":
            save_test_vault_credentials(self.data_dir)
        self.configure_phone()
        self.assertFalse(nested_dir.exists())
        self.request(
            "POST",
            "/api/telegram/request-code",
            {"phone": "+905551234567"},
        )
        self.assertTrue(nested_dir.exists())

    def test_verify_code_success_connected(self) -> None:
        self.configure_phone()
        self.request(
            "POST",
            "/api/telegram/request-code",
            {"phone": "+905551234567"},
        )
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
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
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
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
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
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
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
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
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
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
        self.request("POST", "/api/telegram/verify-code", {"code": "12345"})
        status, payload = self.request("POST", "/api/telegram/disconnect", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "DISCONNECTED")
        self.assertIn("session_path_masked", payload)
        row = self.db.get_telegram_status()
        self.assertIsNotNone(row.get("session_path_masked"))

    def test_save_credentials_via_api(self) -> None:
        if sys.platform != "win32":
            self.skipTest("DPAPI credential API requires Windows")
        dashboard_vault.DashboardCredentialVault(self.data_dir).clear_telegram_credentials()
        status, payload = self.request(
            "POST",
            "/api/telegram/credentials",
            {"api_id": "54321", "api_hash": "vaulthashvalue"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "CREDENTIALS_SAVED")
        self.assertTrue(payload["credentials_saved"])
        self.assertTrue(payload["config_ready"])
        raw = (self.data_dir / "telegram_credentials.dpapi").read_text(encoding="utf-8")
        self.assertNotIn("vaulthashvalue", raw)

    def test_clear_credentials_via_api(self) -> None:
        if sys.platform != "win32":
            self.skipTest("DPAPI credential API requires Windows")
        status, payload = self.request("DELETE", "/api/telegram/credentials")
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "CREDENTIALS_CLEARED")
        self.assertFalse(payload["credentials_saved"])
        save_test_vault_credentials(self.data_dir)

    def test_credentials_not_written_to_sqlite_or_audit(self) -> None:
        if sys.platform != "win32":
            self.skipTest("DPAPI credential API requires Windows")
        dashboard_vault.DashboardCredentialVault(self.data_dir).clear_telegram_credentials()
        secret_hash = "supersecrethashvalue"
        self.request(
            "POST",
            "/api/telegram/credentials",
            {"api_id": "99999", "api_hash": secret_hash},
        )
        with self.db._connect() as conn:
            settings = conn.execute("SELECT key, value FROM settings").fetchall()
        self.assertEqual(len(settings), 0)
        audit = self.request("GET", "/api/audit?limit=20")[1]["events"]
        blob = json.dumps(audit)
        self.assertNotIn(secret_hash, blob)
        self.assertNotIn("99999", blob)
        save_test_vault_credentials(self.data_dir)

    def test_telegram_status_masks_phone_and_session(self) -> None:
        self.configure_phone()
        status, payload = self.request("GET", "/api/telegram/status")
        self.assertEqual(status, 200)
        self.assertTrue(payload["config_ready"])
        self.assertTrue(payload["telethon_available"])
        self.assertIn("vault_supported", payload)
        self.assertIn("credentials_saved", payload)
        self.assertNotIn("phone_code_hash", payload)
        self.assertNotIn("5551234567", json.dumps(payload))

    def test_login_audit_does_not_expose_secrets(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
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

    def test_mt5_accounts_page_ux_markup(self) -> None:
        status, body = self.request("GET", "/")
        self.assertEqual(status, 200)
        html = body.decode("utf-8") if isinstance(body, bytes) else str(body)
        self.assertIn("MT5 Terminallerini Bul", html)
        self.assertIn("Keşfedilen Hesaplar", html)
        self.assertIn("Eklenmiş Hesaplarım", html)
        self.assertIn("Manuel Hesap Ekle", html)
        self.assertIn("mt5-target-modal", html)
        self.assertIn("mt5-add-account-modal", html)
        self.assertIn("mt5-target-drawer", html)
        self.assertIn("mt5-real-account-modal", html)
        self.assertIn("mt5-row-menu-portal", html)
        self.assertIn("mt5-accounts-toolbar", html)
        self.assertIn("mt5-accounts-search", html)
        self.assertIn("mt5-quick-paths", html)
        self.assertNotIn("mt5-card-grid", html)
        self.assertNotIn(">Hesap Ekle<", html)
        self.assertNotIn('rows="4"', html)

    def test_health_includes_mt5_terminal_discovery_feature(self) -> None:
        status, payload = self.request("GET", "/api/health")
        self.assertEqual(status, 200)
        self.assertTrue(payload.get("features", {}).get("mt5_terminal_discovery"))

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_vault_saved_configure_returns_api_configured(self) -> None:
        dashboard_vault.DashboardCredentialVault(self.data_dir).clear_telegram_credentials()
        save_test_vault_credentials(self.data_dir)
        status, payload = self.request(
            "POST",
            "/api/telegram/configure",
            {"phone": "+905551234567"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "API_CONFIGURED")

    def test_vault_saved_no_session_file_config_ready(self) -> None:
        session_path = resolve_session_path(self.data_dir)
        if session_path.exists():
            session_path.unlink()
        self.assertFalse(session_path.exists())
        self.assertTrue(self.telegram_service.config_ready())

    def test_default_session_path_deterministic(self) -> None:
        first = resolve_session_path(self.data_dir)
        second = resolve_session_path(self.data_dir)
        self.assertEqual(first, second)
        self.assertEqual(first.name, SESSION_FILENAME)
        self.assertEqual(first.parent, self.data_dir.resolve())

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_restart_same_data_dir_finds_vault(self) -> None:
        save_test_vault_credentials(self.data_dir)
        restarted = dashboard_api.TelegramService(data_dir=self.data_dir)
        self.assertTrue(restarted.config_ready())
        self.assertTrue(restarted._vault().has_telegram_credentials())

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_different_data_dir_missing_config(self) -> None:
        other_dir = Path(tempfile.mkdtemp(prefix="dashboard_other_"))
        try:
            save_test_vault_credentials(self.data_dir)
            other_service = dashboard_api.TelegramService(data_dir=other_dir)
            self.assertFalse(other_service.config_ready())
            result = other_service.configure(self.db, "+905551234567")
            self.assertEqual(result["status"], "ERROR")
            self.assertEqual(result["error_code"], TELEGRAM_CONFIG_MISSING)
        finally:
            shutil.rmtree(other_dir, ignore_errors=True)

    @unittest.skipUnless(sys.platform == "win32", "DPAPI vault is Windows-only")
    def test_env_session_path_with_vault_credentials(self) -> None:
        custom_session = self.data_dir / "env_custom.session"
        self.env_patch.stop()
        env = env_config_clear()
        env["TELEGRAM_SESSION_PATH"] = str(custom_session)
        self.env_patch = patch.dict(os.environ, env, clear=False)
        self.env_patch.start()
        save_test_vault_credentials(self.data_dir)
        config = load_telegram_config(self.data_dir)
        self.assertIsNotNone(config)
        self.assertEqual(config.session_path, custom_session)

    def test_status_logic_session_missing_not_config_missing(self) -> None:
        session_path = resolve_session_path(self.data_dir)
        if session_path.exists():
            session_path.unlink()
        status, payload = self.request("GET", "/api/telegram/status")
        self.assertEqual(status, 200)
        self.assertTrue(payload["config_ready"])
        self.assertTrue(payload.get("session_pending"))


class RouteListenerDashboardTests(DashboardServerTests):
    def _connect_telegram(self) -> None:
        self.configure_phone()
        self.request("POST", "/api/telegram/request-code", {"phone": "+905551234567"})
        self.request("POST", "/api/telegram/verify-code", {"code": "12345"})

    def _create_tracked_channel(self, telegram_id: str = "9001") -> dict:
        self.fake_adapter.list_dialogs_result = [
            TelegramChannelInfo(telegram_id, "Listener Test Channel", "channel", "listener_test"),
        ]
        self._connect_telegram()
        self.request("POST", "/api/telegram/sync-channels", {})
        channels = self.request("GET", "/api/channels")[1]["channels"]
        channel = next(ch for ch in channels if ch["telegram_channel_id"] == telegram_id)
        self.request("PATCH", f"/api/channels/{channel['id']}", {"is_tracking": 1})
        refreshed = self.request("GET", "/api/channels")[1]["channels"]
        return next(ch for ch in refreshed if ch["id"] == channel["id"])

    def _create_target(
        self,
        *,
        name: str,
        seed_filename: str,
        details_filename: str,
        root_suffix: str = "common",
    ) -> dict:
        _status, payload = self.request(
            "POST",
            "/api/targets",
            {
                "name": name,
                "terminal_label": "D0E",
                "broker_label": "VantageMarkets-Demo",
                "account_mode": "DEMO",
                "file_common_root": str(self.data_dir / root_suffix),
                "seed_filename": seed_filename,
                "details_filename": details_filename,
            },
        )
        return payload["target"]

    def _create_route(self, channel_id: int, target_id: int, name: str) -> dict:
        _status, payload = self.request(
            "POST",
            "/api/routes",
            {
                "name": name,
                "channel_id": channel_id,
                "target_id": target_id,
                "parser_profile": "FASTTRACK_GOLD_NOW",
            },
        )
        return payload["route"]

    def _listener_manager(self) -> route_listener_service.RouteListenerManager:
        self.request("GET", "/api/listener/status")
        client = self.context.listener_worker_client
        self.assertIsNotNone(client)
        manager = client.get_inline_manager()
        self.assertIsNotNone(manager)
        return manager

    def _start_listener(self, route_id: int) -> tuple[int, dict]:
        return self.request(
            "POST",
            f"/api/routes/{route_id}/listener/start",
            {},
        )

    def test_listener_start_rejects_when_telegram_not_connected(self) -> None:
        self.request("POST", "/api/channels/import-demo", {})
        channel_id = self.request("GET", "/api/channels")[1]["channels"][0]["id"]
        self.request("PATCH", f"/api/channels/{channel_id}", {"is_tracking": 1})
        target = self._create_target(
            name="Reject Target",
            seed_filename="seed_reject.txt",
            details_filename="details_reject.txt",
        )
        route = self._create_route(channel_id, target["id"], "Reject Route")
        status, payload = self._start_listener(route["id"])
        self.assertEqual(status, 409)
        self.assertEqual(payload["error_code"], route_listener_service.START_ERROR_NOT_CONNECTED)
        self.assertEqual(payload["user_message"], "Telegram bağlantısı gerekli.")

    def test_listener_start_rejects_when_tracking_off(self) -> None:
        channel = self._create_tracked_channel("9010")
        self.request("PATCH", f"/api/channels/{channel['id']}", {"is_tracking": 0})
        target = self._create_target(
            name="Tracking Off Target",
            seed_filename="seed_track_off.txt",
            details_filename="details_track_off.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Tracking Off Route")
        status, payload = self._start_listener(route["id"])
        self.assertEqual(status, 409)
        self.assertEqual(payload["error_code"], route_listener_service.START_ERROR_TRACKING_OFF)
        self.assertIn("Kanal takibi kapalı", payload["user_message"])

    def test_listener_start_rejects_when_route_disabled(self) -> None:
        channel = self._create_tracked_channel("9011")
        target = self._create_target(
            name="Disabled Route Target",
            seed_filename="seed_disabled.txt",
            details_filename="details_disabled.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Disabled Route")
        self.request("PATCH", f"/api/routes/{route['id']}", {"is_enabled": 0})
        status, payload = self._start_listener(route["id"])
        self.assertEqual(status, 409)
        self.assertEqual(payload["error_code"], route_listener_service.START_ERROR_ROUTE_DISABLED)

    def test_listener_start_rejects_non_observer_target(self) -> None:
        channel = self._create_tracked_channel("9012")
        target = self._create_target(
            name="Non Observer Target",
            seed_filename="seed_non_obs.txt",
            details_filename="details_non_obs.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Non Observer Route")
        with self.db._connect() as conn:
            conn.execute(
                "UPDATE mt5_targets SET observer_only = 0 WHERE id = ?",
                (target["id"],),
            )
        status, payload = self._start_listener(route["id"])
        self.assertEqual(status, 409)
        self.assertEqual(payload["error_code"], route_listener_service.START_ERROR_NOT_OBSERVER)
        self.assertIn("yalnız izleme", payload["user_message"])

    def test_listener_start_stop_idempotent(self) -> None:
        channel = self._create_tracked_channel("9013")
        target = self._create_target(
            name="Idempotent Target",
            seed_filename="seed_idem.txt",
            details_filename="details_idem.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Idempotent Route")
        first_status, first_payload = self._start_listener(route["id"])
        second_status, second_payload = self._start_listener(route["id"])
        self.assertEqual(first_status, 200)
        self.assertEqual(second_status, 200)
        self.assertTrue(second_payload.get("already_running"))
        stop_status, stop_payload = self.request(
            "POST",
            f"/api/routes/{route['id']}/listener/stop",
            {},
        )
        again_status, again_payload = self.request(
            "POST",
            f"/api/routes/{route['id']}/listener/stop",
            {},
        )
        self.assertEqual(stop_status, 200)
        self.assertEqual(again_status, 200)
        self.assertTrue(again_payload.get("already_stopped"))

    def test_listener_publish_single_target_dry_run(self) -> None:
        channel = self._create_tracked_channel("9014")
        target = self._create_target(
            name="Single Publish Target",
            seed_filename="seed_single.txt",
            details_filename="details_single.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Single Publish Route")
        self._start_listener(route["id"])
        manager = self._listener_manager()
        telegram_id = int(channel["telegram_channel_id"])
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_SEED,
                message_id=101,
                channel_id=telegram_id,
            )
        )
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_DETAILS,
                message_id=102,
                channel_id=telegram_id,
            )
        )
        status, payload = self.request("GET", f"/api/routes/{route['id']}/listener-status")
        self.assertEqual(status, 200)
        self.assertEqual(payload["listener_status"], route_listener_service.LISTENER_PUBLISH_READY)
        self.assertTrue(payload["last_publish_at_utc"])

    def test_listener_publish_two_targets_same_channel(self) -> None:
        channel = self._create_tracked_channel("9015")
        target_a = self._create_target(
            name="Target A",
            seed_filename="seed_a.txt",
            details_filename="details_a.txt",
            root_suffix="common_a",
        )
        target_b = self._create_target(
            name="Target B",
            seed_filename="seed_b.txt",
            details_filename="details_b.txt",
            root_suffix="common_b",
        )
        route_a = self._create_route(channel["id"], target_a["id"], "Route A")
        route_b = self._create_route(channel["id"], target_b["id"], "Route B")
        self._start_listener(route_a["id"])
        self._start_listener(route_b["id"])
        manager = self._listener_manager()
        telegram_id = int(channel["telegram_channel_id"])
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_SEED,
                message_id=201,
                channel_id=telegram_id,
            )
        )
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_DETAILS,
                message_id=202,
                channel_id=telegram_id,
            )
        )
        status_a, payload_a = self.request("GET", f"/api/routes/{route_a['id']}/listener-status")
        status_b, payload_b = self.request("GET", f"/api/routes/{route_b['id']}/listener-status")
        self.assertEqual(status_a, 200)
        self.assertEqual(status_b, 200)
        self.assertEqual(payload_a["listener_status"], route_listener_service.LISTENER_PUBLISH_READY)
        self.assertEqual(payload_b["listener_status"], route_listener_service.LISTENER_PUBLISH_READY)
        events_a = self.request("GET", f"/api/routes/{route_a['id']}/events?limit=20")[1]["events"]
        events_b = self.request("GET", f"/api/routes/{route_b['id']}/events?limit=20")[1]["events"]
        self.assertTrue(any(e["target_id"] == target_a["id"] for e in events_a))
        self.assertTrue(any(e["target_id"] == target_b["id"] for e in events_b))

    def test_listener_one_target_fail_other_success(self) -> None:
        channel = self._create_tracked_channel("9016")
        target_ok = self._create_target(
            name="Target OK",
            seed_filename="seed_ok.txt",
            details_filename="details_ok.txt",
            root_suffix="common_ok",
        )
        target_fail = self._create_target(
            name="Target Fail",
            seed_filename="seed_fail.txt",
            details_filename="details_fail.txt",
            root_suffix="common_fail",
        )
        route_ok = self._create_route(channel["id"], target_ok["id"], "Route OK")
        route_fail = self._create_route(channel["id"], target_fail["id"], "Route Fail")
        self._start_listener(route_ok["id"])
        self._start_listener(route_fail["id"])
        manager = self._listener_manager()
        original_publish = fasttrack_file_bridge.AtomicPublisher.publish_pair

        def selective_publish(self, **kwargs):
            if kwargs.get("seed_filename") == "seed_fail.txt":
                raise fasttrack_file_bridge.BridgeValidationError("simulated publish failure")
            return original_publish(self, **kwargs)

        telegram_id = int(channel["telegram_channel_id"])
        with patch.object(
            fasttrack_file_bridge.AtomicPublisher,
            "publish_pair",
            selective_publish,
        ):
            manager.inject_message(
                fasttrack_file_bridge.TelegramInboundMessage(
                    text=VALID_SEED,
                    message_id=301,
                    channel_id=telegram_id,
                )
            )
            manager.inject_message(
                fasttrack_file_bridge.TelegramInboundMessage(
                    text=VALID_DETAILS,
                    message_id=302,
                    channel_id=telegram_id,
                )
            )
        ok_status, ok_payload = self.request("GET", f"/api/routes/{route_ok['id']}/listener-status")
        fail_status, fail_payload = self.request(
            "GET",
            f"/api/routes/{route_fail['id']}/listener-status",
        )
        self.assertEqual(ok_payload["listener_status"], route_listener_service.LISTENER_PUBLISH_READY)
        self.assertEqual(fail_payload["listener_status"], route_listener_service.LISTENER_PUBLISH_FAILED)

    def test_listener_duplicate_message_not_republished(self) -> None:
        channel = self._create_tracked_channel("9017")
        target = self._create_target(
            name="Dedup Target",
            seed_filename="seed_dedup.txt",
            details_filename="details_dedup.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Dedup Route")
        self._start_listener(route["id"])
        manager = self._listener_manager()
        telegram_id = int(channel["telegram_channel_id"])
        details_message = fasttrack_file_bridge.TelegramInboundMessage(
            text=VALID_DETAILS,
            message_id=401,
            channel_id=telegram_id,
        )
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_SEED,
                message_id=400,
                channel_id=telegram_id,
            )
        )
        manager.inject_message(details_message)
        manager.inject_message(details_message)
        events = self.request("GET", f"/api/routes/{route['id']}/events?limit=50")[1]["events"]
        publish_ready = [
            event for event in events if event["status"] == route_listener_service.LISTENER_PUBLISH_READY
        ]
        skipped = [
            event for event in events if event["status"] == route_listener_service.LISTENER_PUBLISH_SKIPPED
        ]
        self.assertEqual(len(publish_ready), 1)
        self.assertTrue(skipped)

    def test_route_events_exclude_raw_telegram_text(self) -> None:
        channel = self._create_tracked_channel("9018")
        target = self._create_target(
            name="Safe Events Target",
            seed_filename="seed_safe.txt",
            details_filename="details_safe.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Safe Events Route")
        self._start_listener(route["id"])
        manager = self._listener_manager()
        telegram_id = int(channel["telegram_channel_id"])
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_SEED,
                message_id=501,
                channel_id=telegram_id,
            )
        )
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_DETAILS,
                message_id=502,
                channel_id=telegram_id,
            )
        )
        status, payload = self.request("GET", f"/api/routes/{route['id']}/events?limit=20")
        self.assertEqual(status, 200)
        blob = json.dumps(payload)
        self.assertNotIn(VALID_SEED, blob)
        self.assertNotIn("4014 - 4017", blob)
        for event in payload["events"]:
            self.assertIn("safe_summary", event)
            self.assertNotIn("text", event)

    def test_listener_status_endpoints(self) -> None:
        status, payload = self.request("GET", "/api/listener/status")
        self.assertEqual(status, 200)
        self.assertIn("active_route_count", payload)
        self.assertTrue(payload["dry_run"])
        channel = self._create_tracked_channel("9019")
        target = self._create_target(
            name="Status Target",
            seed_filename="seed_status.txt",
            details_filename="details_status.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Status Route")
        self._start_listener(route["id"])
        routes_status, routes_payload = self.request("GET", "/api/routes")
        self.assertEqual(routes_status, 200)
        enriched = next(item for item in routes_payload["routes"] if item["id"] == route["id"])
        self.assertIn("listener", enriched)
        self.assertTrue(enriched["listener"]["running"])


class TelegramCanonicalChannelKeyTests(unittest.TestCase):
    def test_entity_id_and_event_chat_id_same_key(self) -> None:
        entity = type("Channel", (), {"id": 1234567890})()
        event = type("Event", (), {"chat_id": -1001234567890})()
        self.assertEqual(
            telegram_adapter.canonical_channel_key_from_entity(entity),
            "1234567890",
        )
        self.assertEqual(
            telegram_adapter.canonical_channel_key_from_event(event),
            "1234567890",
        )
        self.assertEqual(
            telegram_adapter.canonical_channel_key_from_value("1234567890"),
            "1234567890",
        )
        self.assertEqual(
            telegram_adapter.canonical_channel_key_from_value(-1001234567890),
            "1234567890",
        )

    def test_positive_negative_string_inputs(self) -> None:
        self.assertEqual(telegram_adapter.canonical_channel_key_from_value("9001"), "9001")
        self.assertEqual(telegram_adapter.canonical_channel_key_from_value(9001), "9001")
        self.assertEqual(
            telegram_adapter.canonical_channel_key_from_value("-1000000009001"),
            "9001",
        )

    def test_legacy_positive_db_id_matches_event_format(self) -> None:
        legacy = telegram_adapter.canonical_channel_key_from_value("1234567890")
        live = telegram_adapter.canonical_channel_key_from_value(-1001234567890)
        self.assertEqual(legacy, live)


class FakeTelethonMessage:
    def __init__(self, text: str, message_id: int) -> None:
        self.message = text
        self.id = message_id
        self.grouped_id = None
        self.reply_to = None


class FakeTelethonEvent:
    def __init__(self, chat_id: int, text: str, message_id: int = 1) -> None:
        self.chat_id = chat_id
        self.message = FakeTelethonMessage(text, message_id)


class FakeTelethonClient:
    instances: list[FakeTelethonClient] = []

    def __init__(self, *_args: object, **_kwargs: object) -> None:
        self.connected = False
        self.disconnected = False
        self.authorized = True
        self.handlers: list = []
        self.removed_handlers: list = []
        FakeTelethonClient.instances.append(self)

    async def connect(self) -> None:
        self.connected = True

    async def disconnect(self) -> None:
        self.disconnected = True
        self.connected = False

    async def is_user_authorized(self) -> bool:
        return self.authorized

    def on(self, _event: object):
        def decorator(fn):
            self.handlers.append(fn)
            return fn

        return decorator

    def remove_event_handler(self, handler: object) -> None:
        self.removed_handlers.append(handler)
        if handler in self.handlers:
            self.handlers.remove(handler)

    async def dispatch(self, event: FakeTelethonEvent) -> None:
        for handler in list(self.handlers):
            await handler(event)


class TelethonRouteListenerWiringTests(unittest.TestCase):
    def setUp(self) -> None:
        FakeTelethonClient.instances = []
        self.temp_dir = tempfile.mkdtemp(prefix="telethon_wiring_")
        self.data_dir = Path(self.temp_dir)
        self.db = dashboard_store.DashboardDatabase(self.data_dir / "dashboard.sqlite3")
        self.db.set_telegram_connected()
        self.session_path = self.data_dir / "telegram_dashboard.session"
        self.session_path.write_text("fake-session", encoding="ascii")
        self.env_patch = patch.dict(
            os.environ,
            {
                "TELEGRAM_API_ID": "12345",
                "TELEGRAM_API_HASH": "abc123hashvalue",
                "TELEGRAM_SESSION_PATH": str(self.session_path),
            },
            clear=False,
        )
        self.env_patch.start()

    def tearDown(self) -> None:
        self.env_patch.stop()
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _manager(self, *, telethon_enabled: bool = True) -> route_listener_service.RouteListenerManager:
        return route_listener_service.RouteListenerManager(
            database=self.db,
            data_dir=self.data_dir,
            dry_run=True,
            telethon_enabled=telethon_enabled,
            telethon_client_factory=lambda _config: FakeTelethonClient(),
            normalize_stale_states=True,
        )

    def _seed_channel_route(
        self,
        *,
        telegram_channel_id: str = "1234567890",
        channel_key: str = "1234567890",
    ) -> tuple[dict, dict]:
        now = dashboard_security.utc_now_iso()
        with self.db._connect() as conn:
            conn.execute(
                """
                INSERT INTO tracked_channels
                (telegram_channel_id, title, channel_type, username, is_tracking,
                 last_message_at_utc, source, created_at_utc, updated_at_utc)
                VALUES (?, 'Wiring Channel', 'channel', 'wire', 1, NULL, 'TEST', ?, ?)
                """,
                (telegram_channel_id, now, now),
            )
            channel_row = conn.execute(
                "SELECT * FROM tracked_channels WHERE telegram_channel_id = ?",
                (telegram_channel_id,),
            ).fetchone()
            conn.execute(
                """
                INSERT INTO mt5_targets
                (name, terminal_label, broker_label, account_mode, file_common_root,
                 seed_filename, details_filename, observer_only, is_enabled, created_at_utc, updated_at_utc)
                VALUES ('Wire Target', 'D0E', 'Demo', 'DEMO', ?, 'seed_wire.txt', 'details_wire.txt', 1, 1, ?, ?)
                """,
                (str(self.data_dir / "common"), now, now),
            )
            target_row = conn.execute("SELECT * FROM mt5_targets WHERE name = 'Wire Target'").fetchone()
            conn.execute(
                """
                INSERT INTO routes
                (name, channel_id, target_id, parser_profile, mode, is_enabled,
                 last_publish_status, last_publish_at_utc, created_at_utc, updated_at_utc)
                VALUES ('Wire Route', ?, ?, 'FASTTRACK_GOLD_NOW', 'OBSERVER_ONLY', 1, NULL, NULL, ?, ?)
                """,
                (channel_row["id"], target_row["id"], now, now),
            )
            route_row = conn.execute("SELECT * FROM routes WHERE name = 'Wire Route'").fetchone()
        return dict(channel_row), dict(route_row)

    def test_telethon_disabled_does_not_create_client(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager(telethon_enabled=False)
        result = manager.start_route(route["id"])
        self.assertEqual(result["status"], "LISTENER_STARTED")
        self.assertIsNone(manager._telethon_bridge)
        self.assertEqual(FakeTelethonClient.instances, [])

    def test_telethon_enabled_missing_config_returns_controlled_error(self) -> None:
        empty_dir = Path(tempfile.mkdtemp(prefix="telethon_no_config_"))
        try:
            db = dashboard_store.DashboardDatabase(empty_dir / "dashboard.sqlite3")
            db.set_telegram_connected()
            now = dashboard_security.utc_now_iso()
            with db._connect() as conn:
                conn.execute(
                    """
                    INSERT INTO tracked_channels
                    (telegram_channel_id, title, channel_type, username, is_tracking,
                     last_message_at_utc, source, created_at_utc, updated_at_utc)
                    VALUES ('1234567890', 'Wiring Channel', 'channel', 'wire', 1, NULL, 'TEST', ?, ?)
                    """,
                    (now, now),
                )
                ch = conn.execute("SELECT id FROM tracked_channels LIMIT 1").fetchone()
                conn.execute(
                    """
                    INSERT INTO mt5_targets
                    (name, terminal_label, broker_label, account_mode, file_common_root,
                     seed_filename, details_filename, observer_only, is_enabled, created_at_utc, updated_at_utc)
                    VALUES ('Wire Target', 'D0E', 'Demo', 'DEMO', ?, 'seed_wire.txt', 'details_wire.txt', 1, 1, ?, ?)
                    """,
                    (str(empty_dir / "common"), now, now),
                )
                tg = conn.execute("SELECT id FROM mt5_targets LIMIT 1").fetchone()
                conn.execute(
                    """
                    INSERT INTO routes
                    (name, channel_id, target_id, parser_profile, mode, is_enabled,
                     last_publish_status, last_publish_at_utc, created_at_utc, updated_at_utc)
                    VALUES ('Wire Route', ?, ?, 'FASTTRACK_GOLD_NOW', 'OBSERVER_ONLY', 1, NULL, NULL, ?, ?)
                    """,
                    (ch["id"], tg["id"], now, now),
                )
                rt = conn.execute("SELECT id FROM routes LIMIT 1").fetchone()
            with patch.dict(
                os.environ,
                {
                    "TELEGRAM_API_ID": "",
                    "TELEGRAM_API_HASH": "",
                    "TELEGRAM_SESSION_PATH": "",
                },
                clear=False,
            ):
                manager = route_listener_service.RouteListenerManager(
                    database=db,
                    data_dir=empty_dir,
                    dry_run=True,
                    telethon_enabled=True,
                    telethon_client_factory=lambda _config: FakeTelethonClient(),
                    normalize_stale_states=False,
                )
                result = manager.start_route(rt["id"])
            self.assertEqual(result["status"], "ERROR")
            self.assertEqual(result["error_code"], route_listener_service.START_ERROR_TELETHON_CONFIG)
        finally:
            shutil.rmtree(empty_dir, ignore_errors=True)

    def test_fake_client_registers_single_handler(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager()
        manager.start_route(route["id"])
        manager.start_route(route["id"])
        client = FakeTelethonClient.instances[0]
        self.assertEqual(len(client.handlers), 1)

    def test_fake_new_message_reaches_matching_route(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager()
        manager.start_route(route["id"])
        client = FakeTelethonClient.instances[0]
        import asyncio

        asyncio.run(
            client.dispatch(
                FakeTelethonEvent(-1001234567890, VALID_SEED, message_id=501),
            )
        )
        asyncio.run(
            client.dispatch(
                FakeTelethonEvent(-1001234567890, VALID_DETAILS, message_id=502),
            )
        )
        status = manager.route_listener_status(route["id"])
        assert status is not None
        self.assertEqual(status["listener_status"], route_listener_service.LISTENER_PUBLISH_READY)

    def test_fake_new_message_other_channel_is_ignored(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager()
        manager.start_route(route["id"])
        client = FakeTelethonClient.instances[0]
        import asyncio

        asyncio.run(
            client.dispatch(
                FakeTelethonEvent(-1009999999999, VALID_SEED, message_id=601),
            )
        )
        status = manager.route_listener_status(route["id"])
        assert status is not None
        self.assertEqual(status["listener_status"], route_listener_service.LISTENER_WAITING)

    def test_route_events_exclude_raw_message_text(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager()
        manager.start_route(route["id"])
        client = FakeTelethonClient.instances[0]
        import asyncio

        asyncio.run(
            client.dispatch(
                FakeTelethonEvent(-1001234567890, VALID_SEED, message_id=701),
            )
        )
        asyncio.run(
            client.dispatch(
                FakeTelethonEvent(-1001234567890, VALID_DETAILS, message_id=702),
            )
        )
        events = self.db.list_route_events(route["id"], 20)
        blob = json.dumps(events)
        self.assertNotIn(VALID_SEED, blob)
        self.assertNotIn("4014 - 4017", blob)

    def test_last_route_stop_disconnects_client(self) -> None:
        _channel, route = self._seed_channel_route()
        manager = self._manager()
        manager.start_route(route["id"])
        client = FakeTelethonClient.instances[0]
        manager.stop_route(route["id"])
        self.assertTrue(client.disconnected)
        self.assertEqual(len(client.removed_handlers), 1)
        self.assertFalse(manager.status_payload()["telethon_connected"])

    def test_telethon_connected_reflects_real_client_state(self) -> None:
        manager = self._manager()
        self.assertFalse(manager.status_payload()["telethon_connected"])
        _channel, route = self._seed_channel_route()
        manager.start_route(route["id"])
        self.assertTrue(manager.status_payload()["telethon_connected"])

    def test_stale_listener_db_state_normalized_on_manager_init(self) -> None:
        _channel, route = self._seed_channel_route()
        self.db.upsert_route_listener_state(
            route["id"],
            listener_status=route_listener_service.LISTENER_WAITING,
            last_signal_status="Sinyal bekleniyor.",
        )
        manager = self._manager()
        _ = manager
        row = self.db.get_route_listener_state(route["id"])
        assert row is not None
        self.assertEqual(row["listener_status"], route_listener_service.LISTENER_STOPPED)
        self.assertIn("yeniden başlatıldı", row["last_signal_status"])


class SignalSummaryApiTests(DashboardServerTests):
    SIGNAL_META = {
        "symbol": "XAUUSD",
        "side": "SELL",
        "entry_low": 4014,
        "entry_high": 4017,
        "stop_loss": 4077,
        "take_profits": ["4007", "4005", "4003", "4002", "OPEN"],
    }

    def _seed_route(self) -> dict:
        self.request("POST", "/api/channels/import-demo", {})
        channel_id = self.request("GET", "/api/channels")[1]["channels"][0]["id"]
        self.request("PATCH", f"/api/channels/{channel_id}", {"is_tracking": 1})
        target = self.request(
            "POST",
            "/api/targets",
            {
                "name": "Vantage Demo Altın",
                "terminal_label": "D0E",
                "broker_label": "VantageMarkets-Demo",
                "account_mode": "DEMO",
                "file_common_root": str(self.data_dir / "common"),
                "seed_filename": "br_d0e_justgold_seed.txt",
                "details_filename": "br_d0e_justgold_details.txt",
            },
        )[1]["target"]
        route = self.request(
            "POST",
            "/api/routes",
            {
                "name": "justgold",
                "channel_id": channel_id,
                "target_id": target["id"],
            },
        )[1]["route"]
        return route

    def _publish_ready_event(self, route_id: int, target_id: int) -> None:
        meta_json = json.dumps(self.SIGNAL_META, separators=(",", ":"))
        self.db.add_route_event(
            route_id,
            event_type="PUBLISH_READY",
            status=route_listener_service.LISTENER_PUBLISH_READY,
            target_id=target_id,
            safe_summary=f"Observer-only publish plan completed.{dashboard_api.SIGNAL_META_MARKER}{meta_json}",
            fingerprint_short="98e0205b6e16",
        )
        self.db.upsert_route_listener_state(
            route_id,
            listener_status=route_listener_service.LISTENER_PUBLISH_READY,
            last_signal_status="Sinyal yalnız izleme modunda hazırlandı.",
        )

    def test_publish_ready_builds_last_signal_summary(self) -> None:
        route = self._seed_route()
        self._publish_ready_event(route["id"], route["target_id"])
        _status, payload = self.request("GET", "/api/routes")
        enriched = payload["routes"][0]
        summary = enriched["last_signal_summary"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["status"], route_listener_service.LISTENER_PUBLISH_READY)
        self.assertEqual(summary["symbol"], "XAUUSD")
        self.assertEqual(summary["side"], "SELL")
        self.assertEqual(summary["entry_low"], 4014)
        self.assertEqual(summary["entry_high"], 4017)
        self.assertEqual(summary["stop_loss"], 4077)
        self.assertEqual(summary["take_profits"], ["4007", "4005", "4003", "4002", "OPEN"])
        self.assertTrue(summary["is_dry_run"])
        self.assertIn("simülasyon", summary["user_message"].lower())

    def test_last_signal_summary_excludes_raw_message_fields(self) -> None:
        route = self._seed_route()
        self._publish_ready_event(route["id"], route["target_id"])
        _status, payload = self.request("GET", "/api/routes")
        blob = json.dumps(payload)
        self.assertNotIn("Gold sell", blob)
        self.assertNotIn("4014 - 4017", blob)
        summary = payload["routes"][0]["last_signal_summary"]
        self.assertNotIn("raw_message", summary)
        self.assertNotIn("text", summary)

    def test_no_signal_events_returns_null_summary(self) -> None:
        self._seed_route()
        _status, payload = self.request("GET", "/api/routes")
        self.assertIsNone(payload["routes"][0]["last_signal_summary"])

    def test_publish_skipped_user_message(self) -> None:
        route = self._seed_route()
        self.db.add_route_event(
            route["id"],
            event_type="LISTENER_DEDUP",
            status=route_listener_service.LISTENER_PUBLISH_SKIPPED,
            target_id=route["target_id"],
            safe_summary="Yinelenen mesaj atlandı.",
        )
        _status, payload = self.request("GET", "/api/routes")
        summary = payload["routes"][0]["last_signal_summary"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["status"], route_listener_service.LISTENER_PUBLISH_SKIPPED)
        self.assertIn("tekrar", summary["user_message"].lower())

    def test_status_user_messages_turkish(self) -> None:
        route = {
            "channel_title": "JustGold",
            "target_name": "Vantage Demo Altın",
        }
        cases = [
            (route_listener_service.LISTENER_SEED_DETECTED, "detay bekleniyor"),
            (route_listener_service.LISTENER_DETAILS_DETECTED, "ayrıntıları alındı"),
            (route_listener_service.LISTENER_PUBLISH_FAILED, "başarısız"),
        ]
        for status, needle in cases:
            with self.subTest(status=status):
                events = [
                    {
                        "event_type": status,
                        "status": status,
                        "safe_summary": "Safe summary only.",
                        "created_at_utc": "2026-07-05T23:19:16Z",
                    }
                ]
                summary = dashboard_api.build_last_signal_summary(
                    route,
                    events,
                    listener_status=status,
                    dry_run=True,
                )
                self.assertIsNotNone(summary)
                self.assertIn(needle, summary["user_message"].lower())
        waiting_message = dashboard_api._signal_user_message(
            route_listener_service.LISTENER_WAITING,
            dry_run=True,
        )
        self.assertIn("bekleniyor", waiting_message.lower())

    def test_routes_response_backward_compatible(self) -> None:
        route = self._seed_route()
        _status, payload = self.request("GET", "/api/routes")
        item = payload["routes"][0]
        for key in ("id", "name", "mode", "channel_title", "target_name", "listener"):
            self.assertIn(key, item)
        self.assertIn("last_signal_summary", item)
        self.assertIn("signal_timeline", item)

    def test_build_last_signal_summary_unit(self) -> None:
        route = {
            "channel_title": "JustGold",
            "target_name": "Vantage Demo Altın",
        }
        events = [
            {
                "event_type": "PUBLISH_READY",
                "status": route_listener_service.LISTENER_PUBLISH_READY,
                "safe_summary": f"Done.{dashboard_api.SIGNAL_META_MARKER}{json.dumps(self.SIGNAL_META)}",
                "created_at_utc": "2026-07-05T23:19:16Z",
            }
        ]
        summary = dashboard_api.build_last_signal_summary(
            route,
            events,
            listener_status=route_listener_service.LISTENER_PUBLISH_READY,
            dry_run=True,
        )
        self.assertIsNotNone(summary)
        self.assertEqual(summary["symbol"], "XAUUSD")


class ListenerWorkerPersistenceTests(RouteListenerDashboardTests):
    def _start_worker(self) -> dict:
        _status, payload = self.request("POST", "/api/listener/worker/start", {})
        return payload

    def _worker_status(self) -> dict:
        _status, payload = self.request("GET", "/api/listener/worker/status")
        return payload["worker"]

    def _ready_route(self) -> dict:
        channel = self._create_tracked_channel("9099")
        target = self._create_target(
            name="Worker Route Target",
            seed_filename="seed_worker.txt",
            details_filename="details_worker.txt",
        )
        return self._create_route(channel["id"], target["id"], "Worker Route")

    def test_dashboard_restart_does_not_stop_worker(self) -> None:
        route = self._ready_route()
        self._start_worker()
        self._start_listener(route["id"])
        worker_client = self.context.listener_worker_client
        self.assertIsNotNone(worker_client)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        new_context = dashboard_api.DashboardContext(
            host=dashboard_security.ALLOWED_HOST,
            port=self.port,
            data_dir=self.data_dir,
            dashboard_dir=DASHBOARD_DIR.resolve(),
            database=self.db,
            telegram_service=self.telegram_service,
        )
        self.server = dashboard_server.create_server(new_context)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.context = new_context
        status, payload = self.request("GET", "/api/listener/status")
        self.assertEqual(status, 200)
        self.assertGreaterEqual(payload["active_route_count"], 1)
        worker_client.shutdown_inline_worker()

    def test_second_worker_start_is_rejected(self) -> None:
        self._start_worker()
        second = self._start_worker()
        self.assertEqual(second["status"], "WORKER_ALREADY_RUNNING")

    def test_worker_heartbeat_visible_via_api(self) -> None:
        self._start_worker()
        worker = self._worker_status()
        self.assertIsNotNone(worker.get("last_heartbeat_at_utc"))
        self.assertIn(worker["state"], ("CONNECTED", "CONNECTING", "STARTING"))

    def test_stale_heartbeat_shows_degraded(self) -> None:
        self._start_worker()
        stale = dashboard_security.utc_now_iso()
        with self.db._connect() as conn:
            conn.execute(
                """
                UPDATE listener_worker_state
                SET last_heartbeat_at_utc = '2000-01-01T00:00:00+00:00',
                    state = 'CONNECTED'
                WHERE id = 1
                """
            )
        worker = self._worker_status()
        self.assertEqual(worker["state"], listener_worker_client.WORKER_DEGRADED)

    def test_worker_restart_does_not_auto_resume_routes(self) -> None:
        route = self._ready_route()
        self._start_worker()
        self._start_listener(route["id"])
        client = self.context.listener_worker_client
        self.assertIsNotNone(client)
        client.stop_worker()
        self._start_worker()
        status, payload = self.request("GET", f"/api/routes/{route['id']}/listener-status")
        self.assertEqual(status, 200)
        self.assertEqual(payload["listener_status"], route_listener_service.LISTENER_STOPPED)
        self.assertFalse(payload["running"])

    def test_route_start_starts_worker_and_waiting(self) -> None:
        route = self._ready_route()
        status, payload = self._start_listener(route["id"])
        self.assertEqual(status, 200)
        worker = self._worker_status()
        self.assertIn(worker["state"], ("CONNECTED", "CONNECTING", "STARTING"))
        route_status = self.request("GET", f"/api/routes/{route['id']}/listener-status")[1]
        self.assertEqual(route_status["listener_status"], route_listener_service.LISTENER_WAITING)

    def test_route_stop_only_stops_target_route(self) -> None:
        channel = self._create_tracked_channel("9098")
        self._connect_telegram()
        target_a = self._create_target(
            name="Worker A",
            seed_filename="seed_wa.txt",
            details_filename="details_wa.txt",
            root_suffix="wa",
        )
        target_b = self._create_target(
            name="Worker B",
            seed_filename="seed_wb.txt",
            details_filename="details_wb.txt",
            root_suffix="wb",
        )
        route_a = self._create_route(channel["id"], target_a["id"], "Worker A Route")
        route_b = self._create_route(channel["id"], target_b["id"], "Worker B Route")
        self._start_worker()
        self._start_listener(route_a["id"])
        self._start_listener(route_b["id"])
        self.request("POST", f"/api/routes/{route_a['id']}/listener/stop", {})
        status_a = self.request("GET", f"/api/routes/{route_a['id']}/listener-status")[1]
        status_b = self.request("GET", f"/api/routes/{route_b['id']}/listener-status")[1]
        self.assertFalse(status_a["running"])
        self.assertTrue(status_b["running"])

    def test_worker_stop_runs_telethon_cleanup(self) -> None:
        route = self._ready_route()
        self._start_worker()
        self._start_listener(route["id"])
        manager = self._listener_manager()
        bridge = manager._telethon_bridge
        if bridge is not None:
            with patch.object(bridge, "shutdown", wraps=bridge.shutdown) as shutdown_mock:
                self.request("POST", "/api/listener/worker/stop", {})
                if manager._telethon_enabled:
                    shutdown_mock.assert_called()
        else:
            self.request("POST", "/api/listener/worker/stop", {})
        worker = self._worker_status()
        self.assertEqual(worker["state"], listener_worker_client.WORKER_STOPPED)

    def test_reconnect_state_is_safe(self) -> None:
        self.db.upsert_listener_worker_state(
            state=listener_worker_client.WORKER_RECONNECTING,
            reconnect_count=2,
            safe_last_error="Telegram bağlantısı yeniden kuruluyor.",
            last_heartbeat_at_utc=dashboard_security.utc_now_iso(),
            pid=os.getpid(),
        )
        worker = self._worker_status()
        self.assertEqual(worker["state"], listener_worker_client.WORKER_RECONNECTING)
        self.assertEqual(worker["reconnect_count"], 2)
        self.assertNotIn("Traceback", worker.get("safe_last_error") or "")

    def test_raw_telegram_message_not_in_worker_state(self) -> None:
        route = self._ready_route()
        self._start_worker()
        self._start_listener(route["id"])
        channels = self.request("GET", "/api/channels")[1]["channels"]
        channel = next(item for item in channels if item["id"] == route["channel_id"])
        manager = self._listener_manager()
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=VALID_SEED,
                message_id=501,
                channel_id=int(channel["telegram_channel_id"]),
            )
        )
        worker = self._worker_status()
        blob = json.dumps(worker)
        self.assertNotIn(VALID_SEED, blob)
        status, payload = self.request("GET", "/api/listener/status")
        self.assertNotIn(VALID_SEED, json.dumps(payload))
        self.assertEqual(status, 200)

    def test_listener_status_includes_worker_fields(self) -> None:
        route = self._ready_route()
        self._start_worker()
        self._start_listener(route["id"])
        payload = self.request("GET", f"/api/routes/{route['id']}/listener-status")[1]
        self.assertIn("worker_state", payload)
        self.assertIn("telegram_connected", payload)
        self.assertIn("worker_connected", payload)


class LiveSignalMetaTests(RouteListenerDashboardTests):
    VALID_BUY_SEED = "Gold buy now"
    VALID_BUY_MARKET_DETAILS = "Gold buy now\nSL: 4010\nTP: open"
    VALID_SELL_MINIMAL_DETAILS = "Gold sell now 4014 - 4017\nSL: 4077"
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

    def _publish_pair(self, route: dict, channel: dict, seed: str, details: str, msg_base: int) -> None:
        self._start_listener(route["id"])
        manager = self._listener_manager()
        telegram_id = int(channel["telegram_channel_id"])
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=seed,
                message_id=msg_base,
                channel_id=telegram_id,
            )
        )
        manager.inject_message(
            fasttrack_file_bridge.TelegramInboundMessage(
                text=details,
                message_id=msg_base + 1,
                channel_id=telegram_id,
            )
        )

    def _latest_publish_ready_event(self, route_id: int) -> dict:
        events = self.request("GET", f"/api/routes/{route_id}/events?limit=20")[1]["events"]
        ready = [
            event
            for event in events
            if event["status"] == route_listener_service.LISTENER_PUBLISH_READY
        ]
        self.assertTrue(ready, "Expected PUBLISH_READY event")
        return ready[-1]

    def _extract_event_signal_meta(self, event: dict) -> dict:
        summary = event["safe_summary"]
        marker = fasttrack_file_bridge.SIGNAL_META_MARKER
        self.assertIn(marker, summary)
        return json.loads(summary.split(marker, 1)[1])

    def test_build_signal_meta_sell_full(self) -> None:
        meta = fasttrack_file_bridge.build_signal_meta(VALID_SEED, VALID_DETAILS)
        self.assertEqual(meta["symbol"], "XAUUSD")
        self.assertEqual(meta["side"], "SELL")
        self.assertEqual(meta["entry_low"], 4014)
        self.assertEqual(meta["entry_high"], 4017)
        self.assertEqual(meta["stop_loss"], 4077)
        self.assertEqual(meta["take_profits"], ["4007", "4005", "4003", "4002", "OPEN"])

    def test_build_signal_meta_buy_market_entry(self) -> None:
        meta = fasttrack_file_bridge.build_signal_meta(
            self.VALID_BUY_SEED,
            self.VALID_BUY_MARKET_DETAILS,
        )
        self.assertEqual(meta["symbol"], "XAUUSD")
        self.assertEqual(meta["side"], "BUY")
        self.assertIsNone(meta["entry_low"])
        self.assertIsNone(meta["entry_high"])
        self.assertEqual(meta["stop_loss"], 4010)
        self.assertEqual(meta["take_profits"], ["OPEN"])

    def test_build_signal_meta_missing_take_profits(self) -> None:
        meta = fasttrack_file_bridge.build_signal_meta(VALID_SEED, self.VALID_SELL_MINIMAL_DETAILS)
        self.assertEqual(meta["stop_loss"], 4077)
        self.assertEqual(meta["take_profits"], [])

    def test_signal_meta_allowlist_only(self) -> None:
        meta = fasttrack_file_bridge.build_signal_meta(VALID_SEED, VALID_DETAILS)
        self.assertSetEqual(set(meta.keys()), self.SIGNAL_META_ALLOWLIST)

    def test_listener_publish_ready_includes_signal_meta(self) -> None:
        channel = self._create_tracked_channel("9020")
        target = self._create_target(
            name="Signal Meta Target",
            seed_filename="seed_meta.txt",
            details_filename="details_meta.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Signal Meta Route")
        self._publish_pair(route, channel, VALID_SEED, VALID_DETAILS, 601)
        event = self._latest_publish_ready_event(route["id"])
        meta = self._extract_event_signal_meta(event)
        self.assertEqual(meta["symbol"], "XAUUSD")
        self.assertEqual(meta["side"], "SELL")
        self.assertEqual(meta["entry_low"], 4014)
        self.assertEqual(meta["entry_high"], 4017)
        self.assertEqual(meta["stop_loss"], 4077)
        self.assertEqual(meta["take_profits"], ["4007", "4005", "4003", "4002", "OPEN"])
        self.assertSetEqual(set(meta.keys()), self.SIGNAL_META_ALLOWLIST)

    def test_live_publish_ready_populates_last_signal_summary(self) -> None:
        channel = self._create_tracked_channel("9021")
        target = self._create_target(
            name="Summary Meta Target",
            seed_filename="seed_summary_meta.txt",
            details_filename="details_summary_meta.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Summary Meta Route")
        self._publish_pair(route, channel, VALID_SEED, VALID_DETAILS, 701)
        _status, payload = self.request("GET", "/api/routes")
        enriched = next(item for item in payload["routes"] if item["id"] == route["id"])
        summary = enriched["last_signal_summary"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["symbol"], "XAUUSD")
        self.assertEqual(summary["side"], "SELL")
        self.assertEqual(summary["entry_low"], 4014)
        self.assertEqual(summary["entry_high"], 4017)
        self.assertEqual(summary["stop_loss"], 4077)
        self.assertEqual(summary["take_profits"], ["4007", "4005", "4003", "4002", "OPEN"])

    def test_live_signal_meta_excludes_raw_telegram_text(self) -> None:
        channel = self._create_tracked_channel("9022")
        target = self._create_target(
            name="Safe Meta Target",
            seed_filename="seed_safe_meta.txt",
            details_filename="details_safe_meta.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Safe Meta Route")
        self._publish_pair(route, channel, VALID_SEED, VALID_DETAILS, 801)
        events_payload = self.request("GET", f"/api/routes/{route['id']}/events?limit=20")[1]
        routes_payload = self.request("GET", "/api/routes")[1]
        for blob in (json.dumps(events_payload), json.dumps(routes_payload)):
            self.assertNotIn(VALID_SEED, blob)
            self.assertNotIn("4014 - 4017", blob)
            self.assertNotIn("SL: 4077", blob)
        event = self._latest_publish_ready_event(route["id"])
        meta = self._extract_event_signal_meta(event)
        self.assertNotIn("raw_message", meta)
        self.assertNotIn("text", meta)

    def test_publish_skipped_preserves_previous_signal_summary(self) -> None:
        channel = self._create_tracked_channel("9023")
        target = self._create_target(
            name="Skip Preserve Target",
            seed_filename="seed_skip_meta.txt",
            details_filename="details_skip_meta.txt",
        )
        route = self._create_route(channel["id"], target["id"], "Skip Preserve Route")
        self._publish_pair(route, channel, VALID_SEED, VALID_DETAILS, 901)
        details_message = fasttrack_file_bridge.TelegramInboundMessage(
            text=VALID_DETAILS,
            message_id=903,
            channel_id=int(channel["telegram_channel_id"]),
        )
        manager = self._listener_manager()
        manager.inject_message(details_message)
        _status, payload = self.request("GET", "/api/routes")
        enriched = next(item for item in payload["routes"] if item["id"] == route["id"])
        summary = enriched["last_signal_summary"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["status"], route_listener_service.LISTENER_PUBLISH_SKIPPED)
        self.assertEqual(summary["symbol"], "XAUUSD")
        self.assertEqual(summary["side"], "SELL")
        self.assertEqual(summary["entry_low"], 4014)
        self.assertEqual(summary["stop_loss"], 4077)
        self.assertIn("tekrar", summary["user_message"].lower())
        events = self.request("GET", f"/api/routes/{route['id']}/events?limit=20")[1]["events"]
        skipped = [
            event
            for event in events
            if event["status"] == route_listener_service.LISTENER_PUBLISH_SKIPPED
        ]
        self.assertTrue(skipped)
        self.assertNotIn(fasttrack_file_bridge.SIGNAL_META_MARKER, skipped[-1]["safe_summary"])


class SignalHistoryApiTests(RouteListenerDashboardTests):
    META = {
        "symbol": "XAUUSD",
        "side": "SELL",
        "entry_low": 4014,
        "entry_high": 4017,
        "stop_loss": 4077,
        "take_profits": ["4007", "4005", "OPEN"],
    }

    def _seed_history_event(
        self,
        *,
        route_id: int,
        target_id: int,
        channel_id: int,
        received_at: str = "2026-07-06T02:19:00Z",
        side: str = "SELL",
    ) -> None:
        meta = dict(self.META)
        meta["side"] = side
        meta_json = json.dumps(meta, separators=(",", ":"))
        self.db.add_route_event(
            route_id,
            event_type="PUBLISH_READY",
            status=route_listener_service.LISTENER_PUBLISH_READY,
            target_id=target_id,
            safe_summary=f"Observer-only publish plan completed.{fasttrack_file_bridge.SIGNAL_META_MARKER}{meta_json}",
            fingerprint_short="98e0205b6e16",
            seed_bytes=13,
            details_bytes=79,
        )
        with self.db._connect() as conn:
            conn.execute(
                "UPDATE route_events SET created_at_utc = ? WHERE route_id = ? AND status = ?",
                (received_at, route_id, route_listener_service.LISTENER_PUBLISH_READY),
            )

    def _setup_route(self, telegram_id: str = "9030") -> tuple[dict, dict, dict]:
        channel = self._create_tracked_channel(telegram_id)
        target = self._create_target(
            name=f"History Target {telegram_id}",
            seed_filename=f"seed_hist_{telegram_id}.txt",
            details_filename=f"details_hist_{telegram_id}.txt",
        )
        route = self._create_route(channel["id"], target["id"], f"History Route {telegram_id}")
        return channel, target, route

    def test_publish_ready_appears_in_signal_history(self) -> None:
        _channel, target, route = self._setup_route("9030")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        status, payload = self.request("GET", "/api/signal-history")
        self.assertEqual(status, 200)
        self.assertEqual(payload["total"], 1)
        item = payload["items"][0]
        self.assertEqual(item["symbol"], "XAUUSD")
        self.assertEqual(item["side"], "SELL")
        self.assertEqual(item["entry_low"], 4014)
        self.assertEqual(item["stop_loss"], 4077)

    def test_signal_history_excludes_raw_telegram(self) -> None:
        _channel, target, route = self._setup_route("9031")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        _status, payload = self.request("GET", "/api/signal-history")
        blob = json.dumps(payload)
        self.assertNotIn(VALID_SEED, blob)
        self.assertNotIn("4014 - 4017", blob)
        self.assertNotIn("raw_message", blob)

    def test_observer_only_execution_fields(self) -> None:
        _channel, target, route = self._setup_route("9032")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        _status, payload = self.request("GET", "/api/signal-history")
        item = payload["items"][0]
        self.assertEqual(item["execution_status"], "NOT_EXECUTED")
        self.assertEqual(item["trade_outcome"], "NOT_APPLICABLE")
        self.assertIsNone(item["realized_pnl"])
        self.assertEqual(item["pnl_state"], "unknown")

    def test_channel_filter(self) -> None:
        self.fake_adapter.list_dialogs_result = [
            TelegramChannelInfo("9033", "Channel A", "channel", "channel_a"),
            TelegramChannelInfo("9034", "Channel B", "channel", "channel_b"),
        ]
        self._connect_telegram()
        self.request("POST", "/api/telegram/sync-channels", {})
        channels = self.request("GET", "/api/channels")[1]["channels"]
        channel_a = next(ch for ch in channels if ch["telegram_channel_id"] == "9033")
        channel_b = next(ch for ch in channels if ch["telegram_channel_id"] == "9034")
        self.request("PATCH", f"/api/channels/{channel_a['id']}", {"is_tracking": 1})
        self.request("PATCH", f"/api/channels/{channel_b['id']}", {"is_tracking": 1})
        target_a = self._create_target(
            name="History Target A",
            seed_filename="seed_hist_a.txt",
            details_filename="details_hist_a.txt",
        )
        target_b = self._create_target(
            name="History Target B",
            seed_filename="seed_hist_b.txt",
            details_filename="details_hist_b.txt",
        )
        route_a = self._create_route(channel_a["id"], target_a["id"], "History Route A")
        route_b = self._create_route(channel_b["id"], target_b["id"], "History Route B")
        self._seed_history_event(route_id=route_a["id"], target_id=target_a["id"], channel_id=channel_a["id"])
        self._seed_history_event(route_id=route_b["id"], target_id=target_b["id"], channel_id=channel_b["id"])
        status, payload = self.request("GET", f"/api/signal-history?channel_id={channel_a['id']}")
        self.assertEqual(status, 200)
        self.assertEqual(payload["total"], 1)
        self.assertEqual(payload["items"][0]["channel_id"], channel_a["id"])

    def test_date_filter(self) -> None:
        _channel, target, route = self._setup_route("9035")
        self._seed_history_event(
            route_id=route["id"],
            target_id=target["id"],
            channel_id=route["channel_id"],
            received_at="2026-06-01T10:00:00Z",
        )
        status, payload = self.request("GET", "/api/signal-history?from=2026-07-01")
        self.assertEqual(status, 200)
        self.assertEqual(payload["total"], 0)
        status_in, payload_in = self.request("GET", "/api/signal-history?from=2026-05-01&to=2026-06-30")
        self.assertEqual(status_in, 200)
        self.assertEqual(payload_in["total"], 1)

    def test_side_filter(self) -> None:
        _channel, target, route = self._setup_route("9036")
        self._seed_history_event(
            route_id=route["id"],
            target_id=target["id"],
            channel_id=route["channel_id"],
            side="BUY",
        )
        status, payload = self.request("GET", "/api/signal-history?side=BUY")
        self.assertEqual(status, 200)
        self.assertEqual(payload["total"], 1)
        self.assertEqual(payload["items"][0]["side"], "BUY")
        status_sell, payload_sell = self.request("GET", "/api/signal-history?side=SELL")
        self.assertEqual(status_sell, 200)
        self.assertEqual(payload_sell["total"], 0)

    def test_pnl_state_unknown_includes_observer(self) -> None:
        _channel, target, route = self._setup_route("9037")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        _status, payload = self.request("GET", "/api/signal-history?pnl_state=unknown")
        self.assertEqual(payload["total"], 1)

    def test_pnl_state_profit_excludes_observer(self) -> None:
        _channel, target, route = self._setup_route("9038")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        _status, payload = self.request("GET", "/api/signal-history?pnl_state=profit")
        self.assertEqual(payload["total"], 0)

    def test_signal_history_pagination(self) -> None:
        for idx in range(3):
            _channel, target, route = self._setup_route(str(9040 + idx))
            self._seed_history_event(
                route_id=route["id"],
                target_id=target["id"],
                channel_id=route["channel_id"],
                received_at=f"2026-07-06T0{idx}:00:00Z",
            )
        status, payload = self.request("GET", "/api/signal-history?page=1&page_size=2")
        self.assertEqual(status, 200)
        self.assertEqual(payload["total"], 3)
        self.assertEqual(len(payload["items"]), 2)
        self.assertEqual(payload["page"], 1)
        self.assertEqual(payload["page_size"], 2)

    def test_routes_include_execution_fields(self) -> None:
        _channel, target, route = self._setup_route("9043")
        self._seed_history_event(route_id=route["id"], target_id=target["id"], channel_id=route["channel_id"])
        _status, payload = self.request("GET", "/api/routes")
        item = next(r for r in payload["routes"] if r["id"] == route["id"])
        summary = item["last_signal_summary"]
        self.assertIsNotNone(summary)
        self.assertEqual(summary["execution_status"], "NOT_EXECUTED")
        self.assertIsNone(summary["realized_pnl"])
        self.assertEqual(summary["pnl_state"], "unknown")


class Mt5TargetVerificationTests(DashboardServerTests):
    def setUp(self) -> None:
        super().setUp()
        self._probe_backup = mt5_account_probe._PROBE_OVERRIDE
        mt5_account_probe.set_probe_override(None)
        self._instance_counter = 0

    def tearDown(self) -> None:
        mt5_account_probe.set_probe_override(self._probe_backup)
        super().tearDown()

    def _write_terminal_exe(self) -> Path:
        exe = self.data_dir / "terminal64.exe"
        exe.write_text("fake", encoding="utf-8")
        return exe

    def _instance_path(self, suffix: str) -> str:
        path = self.data_dir / f"terminal_instance_{suffix}"
        path.mkdir(parents=True, exist_ok=True)
        return str(path)

    def _target_payload(self, **overrides) -> dict:
        instance_suffix = overrides.pop("instance_suffix", None)
        if instance_suffix is None:
            self._instance_counter += 1
            instance_suffix = str(self._instance_counter)
        payload = {
            "display_name": overrides.pop("display_name", "Probe Target"),
            "terminal_label": "D0E",
            "terminal_exe_path": str(self._write_terminal_exe()),
            "terminal_data_path": overrides.pop(
                "terminal_data_path",
                self._instance_path(instance_suffix),
            ),
            "broker_label": "VantageMarkets-Demo",
            "expected_server": "VantageMarkets-Demo",
            "expected_account_login": overrides.pop(
                "expected_account_login",
                f"1000{instance_suffix}",
            ),
            "expected_account_type": "DEMO",
            "file_common_root": str(self.data_dir / "common"),
            "seed_filename": "seed_probe_a.txt",
            "details_filename": "details_probe_a.txt",
            "ea_name": "Basket Recovery EA",
            "chart_symbol": "XAUUSD",
            "chart_timeframe": "M1",
            "magic_number": 91001,
        }
        payload.update(overrides)
        return payload

    def _create_target(self, **overrides) -> dict:
        payload = self._target_payload(**overrides)
        status, response = self.request("POST", "/api/mt5-targets", payload)
        self.assertEqual(status, 201)
        target = response["target"]
        target["_expected_login"] = payload.get("expected_account_login", "")
        target["_expected_server"] = payload.get("expected_server", "")
        target["_terminal_data_path"] = payload.get("terminal_data_path", "")
        return target

    def _demo_probe(self, **overrides) -> mt5_account_probe.ProbeResult:
        values = {
            "status": mt5_account_probe.PROBE_STATUS_VERIFIED,
            "user_message": "Hesap bilgileri okundu.",
            "terminal_connected": True,
            "account_login": "12345678",
            "server": "VantageMarkets-Demo",
            "company": "Vantage",
            "trade_mode": mt5_account_probe.ACCOUNT_TYPE_DEMO,
            "trade_mode_label": "Demo Hesap",
            "currency": "USD",
            "equity": 10000.0,
            "terminal_trade_allowed": True,
            "xauusd_available": True,
        }
        values.update(overrides)
        return mt5_account_probe.ProbeResult(**values)

    def _probe_for_target(self, target: dict, **overrides):
        account_login = overrides.pop("account_login", target.get("_expected_login") or "12345678")
        server = overrides.pop("server", target.get("_expected_server") or "VantageMarkets-Demo")
        data_path = overrides.pop(
            "detected_terminal_data_path",
            target.get("_terminal_data_path") or target.get("terminal_data_path"),
        )
        return lambda _req: self._demo_probe(
            account_login=account_login,
            server=server,
            detected_terminal_data_path=data_path,
            **overrides,
        )

    def test_terminal_offline_safe_status(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(
            lambda _req: mt5_account_probe.ProbeResult(
                status=mt5_account_probe.PROBE_STATUS_TERMINAL_OFFLINE,
                user_message="Terminal çevrimdışı. MT5 terminalini açıp tekrar doğrulayın.",
            )
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_account_probe.PROBE_STATUS_TERMINAL_OFFLINE)
        self.assertEqual(payload["target"]["card_status"], mt5_target_service.CARD_STATUS_TERMINAL_OFFLINE)

    def test_connector_unavailable_user_message(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(
            lambda _req: mt5_account_probe.ProbeResult(
                status=mt5_account_probe.PROBE_STATUS_CONNECTOR_UNAVAILABLE,
                user_message="MT5 doğrulama bileşeni bu bilgisayarda hazır değil.",
            )
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(
            payload["verification"]["status"],
            mt5_account_probe.PROBE_STATUS_CONNECTOR_UNAVAILABLE,
        )
        self.assertIn("hazır değil", payload["verification"]["message"])

    def test_demo_account_detection(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(self._probe_for_target(target))
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_VERIFIED_OK)
        self.assertEqual(payload["target"]["detected_trade_mode"], "DEMO")

    def test_real_account_warning_execution_locked(self) -> None:
        target = self._create_target(expected_account_type="DEMO")
        mt5_account_probe.set_probe_override(
            self._probe_for_target(
                target,
                trade_mode=mt5_account_probe.ACCOUNT_TYPE_REAL,
                trade_mode_label="Gerçek Hesap",
            )
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_REAL_ACCOUNT_WARNING)
        self.assertTrue(payload["target"]["warnings"])
        self.assertEqual(payload["target"]["execution_permission"], "LOCKED")

    def test_expected_account_mismatch(self) -> None:
        target = self._create_target(expected_account_login="12345678")
        mt5_account_probe.set_probe_override(
            self._probe_for_target(target, account_login="99999999")
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_ACCOUNT_MISMATCH)

    def test_expected_server_mismatch(self) -> None:
        target = self._create_target(expected_server="VantageMarkets-Demo")
        mt5_account_probe.set_probe_override(
            self._probe_for_target(target, server="OtherServer-Demo")
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_SERVER_MISMATCH)

    def test_xauusd_not_found(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(self._probe_for_target(target, xauusd_available=False))
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_XAUUSD_NOT_FOUND)
        self.assertEqual(payload["target"]["xauusd_status"], "Bulunamadı")

    def test_duplicate_seed_filename_conflict(self) -> None:
        shared_root = str(self.data_dir / "common_pair")
        self._create_target(
            display_name="Target A",
            file_common_root=shared_root,
            seed_filename="dup_pair_seed.txt",
            details_filename="dup_pair_details.txt",
        )
        second = self._create_target(
            display_name="Target B",
            file_common_root=shared_root,
            seed_filename="dup_pair_seed.txt",
            details_filename="dup_pair_details.txt",
            magic_number=91002,
        )
        issues = second["ea_config_match"]["issues"]
        self.assertTrue(any("seed/details" in issue.lower() or "file_common" in issue.lower() for issue in issues))

    def test_instance_path_user_supplied_when_probe_cannot_verify(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(
            self._probe_for_target(target, detected_terminal_data_path=None)
        )
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(
            payload["verification"]["status"],
            mt5_target_service.VERIFICATION_INSTANCE_PATH_USER_SUPPLIED,
        )
        self.assertEqual(
            payload["target"]["terminal_instance_status"],
            mt5_target_service.INSTANCE_STATUS_USER_SUPPLIED,
        )

    def test_duplicate_magic_number_conflict(self) -> None:
        self._create_target(display_name="Magic A", magic_number=424242, seed_filename="seed_m1.txt", details_filename="details_m1.txt")
        second = self._create_target(
            display_name="Magic B",
            magic_number=424242,
            seed_filename="seed_m2.txt",
            details_filename="details_m2.txt",
        )
        issues = second["ea_config_match"]["issues"]
        self.assertTrue(any("Magic numarası" in issue for issue in issues))

    def test_account_login_masked_in_api(self) -> None:
        target = self._create_target(expected_account_login="12345678")
        mt5_account_probe.set_probe_override(self._probe_for_target(target, account_login="12345678"))
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(payload["target"]["detected_account_login_masked"], "***5678")
        get_status, listed = self.request("GET", "/api/mt5-targets")
        self.assertEqual(get_status, 200)
        item = next(row for row in listed["targets"] if row["id"] == target["id"])
        self.assertEqual(item["detected_account_login_masked"], "***5678")
        self.assertNotIn("12345678", json.dumps(listed))

    def test_password_field_rejected(self) -> None:
        payload = self._target_payload()
        payload["password"] = "secret"
        status, body = self.request("POST", "/api/mt5-targets", payload)
        self.assertEqual(status, 400)
        self.assertIn("credentials", str(body).lower())

    def test_verify_rate_limit(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(self._probe_for_target(target))
        first_status, _ = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(first_status, 200)
        second_status, body = self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        self.assertEqual(second_status, 400)
        self.assertIn("bekleyin", str(body).lower())

    def test_get_verification_endpoint(self) -> None:
        target = self._create_target()
        mt5_account_probe.set_probe_override(self._probe_for_target(target))
        self.request("POST", f"/api/mt5-targets/{target['id']}/verify", {})
        status, payload = self.request("GET", f"/api/mt5-targets/{target['id']}/verification")
        self.assertEqual(status, 200)
        self.assertEqual(payload["verification"]["status"], mt5_target_service.VERIFICATION_VERIFIED_OK)

    def test_disable_target(self) -> None:
        target = self._create_target()
        status, payload = self.request("POST", f"/api/mt5-targets/{target['id']}/disable", {})
        self.assertEqual(status, 200)
        self.assertFalse(payload["target"]["is_enabled"])

    def test_execution_permission_cannot_be_changed(self) -> None:
        target = self._create_target()
        status, _body = self.request(
            "PATCH",
            f"/api/mt5-targets/{target['id']}",
            {"execution_permission": "OPEN"},
        )
        self.assertEqual(status, 400)

    def test_same_exe_different_data_path_allowed(self) -> None:
        exe = str(self._write_terminal_exe())
        first = self._create_target(
            terminal_exe_path=exe,
            terminal_data_path=self._instance_path("instance_a"),
            display_name="Instance A",
            magic_number=93001,
            seed_filename="seed_inst_a.txt",
            details_filename="details_inst_a.txt",
        )
        status, payload = self.request(
            "POST",
            "/api/mt5-targets",
            self._target_payload(
                terminal_exe_path=exe,
                terminal_data_path=self._instance_path("instance_b"),
                display_name="Instance B",
                magic_number=93002,
                seed_filename="seed_inst_b.txt",
                details_filename="details_inst_b.txt",
            ),
        )
        self.assertEqual(status, 201)
        self.assertNotEqual(first["terminal_data_path"], payload["target"]["terminal_data_path"])

    def test_same_terminal_data_path_conflict(self) -> None:
        shared = str(self.data_dir / "shared_terminal_instance")
        Path(shared).mkdir(parents=True, exist_ok=True)
        self._create_target(
            terminal_data_path=shared,
            display_name="Shared A",
            magic_number=94001,
            seed_filename="seed_shared_a.txt",
            details_filename="details_shared_a.txt",
        )
        status, body = self.request(
            "POST",
            "/api/mt5-targets",
            self._target_payload(
                terminal_data_path=shared,
                display_name="Shared B",
                magic_number=94002,
                seed_filename="seed_shared_b.txt",
                details_filename="details_shared_b.txt",
            ),
        )
        self.assertEqual(status, 400)
        self.assertIn("terminal instance", str(body).lower())

    def test_duplicate_account_server_rejected(self) -> None:
        self._create_target(
            expected_account_login="555001",
            expected_server="Broker-Demo",
            display_name="Account A",
            magic_number=95001,
            seed_filename="seed_acc_a.txt",
            details_filename="details_acc_a.txt",
            instance_suffix="acc_a",
        )
        status, body = self.request(
            "POST",
            "/api/mt5-targets",
            self._target_payload(
                expected_account_login="555001",
                expected_server="Broker-Demo",
                display_name="Account B",
                magic_number=95002,
                seed_filename="seed_acc_b.txt",
                details_filename="details_acc_b.txt",
                instance_suffix="acc_b",
            ),
        )
        self.assertEqual(status, 400)
        self.assertIn("hesap numarası", str(body).lower())

    def test_instance_ambiguous_without_data_path(self) -> None:
        exe = str(self._write_terminal_exe())
        common_root = str(self.data_dir / "common")
        legacy_payload = {
            "name": "Legacy A",
            "terminal_label": "D0E",
            "broker_label": "VantageMarkets-Demo",
            "account_mode": "DEMO",
            "file_common_root": common_root,
            "seed_filename": "seed_legacy_a.txt",
            "details_filename": "details_legacy_a.txt",
            "terminal_exe_path": exe,
        }
        self.request("POST", "/api/targets", legacy_payload)
        self.request(
            "POST",
            "/api/targets",
            {
                **legacy_payload,
                "name": "Legacy B",
                "seed_filename": "seed_legacy_b.txt",
                "details_filename": "details_legacy_b.txt",
            },
        )
        listed = self.request("GET", "/api/mt5-targets")[1]["targets"]
        target_row = next(item for item in listed if item["display_name"] == "Legacy A")
        mt5_account_probe.set_probe_override(self._probe_for_target(target_row))
        status, payload = self.request("POST", f"/api/mt5-targets/{target_row['id']}/verify", {})
        self.assertEqual(status, 200)
        self.assertEqual(
            payload["verification"]["status"],
            mt5_target_service.VERIFICATION_INSTANCE_AMBIGUOUS,
        )
        self.assertEqual(payload["target"]["terminal_instance_status"], mt5_target_service.INSTANCE_STATUS_AMBIGUOUS)

    def test_dynamic_summary_counts(self) -> None:
        for count, expected_total in ((1, 1), (5, 6), (10, 16)):
            for index in range(count):
                suffix = f"{count}_{index}"
                self._create_target(
                    display_name=f"Summary {count}-{index}",
                    expected_account_type="DEMO" if index % 2 == 0 else "REAL",
                    magic_number=96000 + count * 100 + index,
                    seed_filename=f"seed_summary_{suffix}.txt",
                    details_filename=f"details_summary_{suffix}.txt",
                    instance_suffix=suffix,
                )
            status, payload = self.request("GET", "/api/mt5-targets")
            self.assertEqual(status, 200)
            self.assertEqual(payload["summary"]["total"], expected_total)
        self.assertGreaterEqual(payload["summary"]["demo_accounts"], 1)
        self.assertGreaterEqual(payload["summary"]["real_accounts"], 1)
        self.assertEqual(payload["summary"]["pending_verification"], payload["summary"]["total"])
        self.assertIn("terminal_instance_conflicts", payload["summary"])

    def test_mt5_targets_pagination(self) -> None:
        for index in range(3):
            self._create_target(
                display_name=f"Paged Target {index}",
                magic_number=97000 + index,
                seed_filename=f"seed_page_{index}.txt",
                details_filename=f"details_page_{index}.txt",
                instance_suffix=f"page_{index}",
            )
        status, payload = self.request("GET", "/api/mt5-targets?page=1&page_size=2")
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["targets"]), 2)
        self.assertGreaterEqual(payload["total"], 3)
        self.assertEqual(payload["page"], 1)
        self.assertEqual(payload["page_size"], 2)


class Mt5TerminalDiscoveryTests(DashboardServerTests):
    def setUp(self) -> None:
        super().setUp()
        self._probe_backup = mt5_account_probe._PROBE_OVERRIDE
        self._discovery_backup = mt5_terminal_discovery._DISCOVERY_INSTANCES_OVERRIDE
        mt5_account_probe.set_probe_override(None)
        mt5_terminal_discovery.set_discovery_instances_override(None)
        mt5_terminal_discovery.reset_discovery_store()

    def tearDown(self) -> None:
        mt5_account_probe.set_probe_override(self._probe_backup)
        mt5_terminal_discovery.set_discovery_instances_override(self._discovery_backup)
        mt5_terminal_discovery.reset_discovery_store()
        super().tearDown()

    def _write_terminal_exe(self, folder: Path | None = None) -> Path:
        base = folder or self.data_dir
        exe = base / "terminal64.exe"
        exe.write_text("fake", encoding="utf-8")
        return exe

    def _instance_path(self, suffix: str) -> str:
        path = self.data_dir / f"terminal_instance_{suffix}"
        path.mkdir(parents=True, exist_ok=True)
        return str(path)

    def _verified_probe(
        self,
        *,
        exe: str,
        data_path: str,
        login: str = "12345678",
        server: str = "VantageMarkets-Demo",
        trade_mode: str = mt5_account_probe.ACCOUNT_TYPE_DEMO,
        company: str = "Vantage",
        equity: float = 10000.0,
    ) -> mt5_account_probe.ProbeResult:
        return mt5_account_probe.ProbeResult(
            status=mt5_account_probe.PROBE_STATUS_VERIFIED,
            user_message="Hesap bilgileri okundu.",
            terminal_connected=True,
            terminal_exe_path=exe,
            detected_terminal_path=exe,
            detected_terminal_data_path=data_path,
            account_login=login,
            server=server,
            company=company,
            trade_mode=trade_mode,
            trade_mode_label="Demo Hesap" if trade_mode == mt5_account_probe.ACCOUNT_TYPE_DEMO else "Gerçek Hesap",
            currency="USD",
            equity=equity,
            terminal_trade_allowed=True,
            xauusd_available=True,
        )

    def _scan_paths(self, paths: list[str]) -> dict:
        status, payload = self.request(
            "POST",
            "/api/mt5-terminals/discover",
            {"terminal_paths": paths},
        )
        self.assertEqual(status, 200)
        return payload

    def test_exe_path_normalizes(self) -> None:
        exe = self._write_terminal_exe()
        result = mt5_terminal_discovery.normalize_terminal_path(str(exe))
        self.assertEqual(result.status, "OK")
        self.assertEqual(result.terminal_exe_path, str(exe.resolve()))

    def test_folder_path_finds_terminal64(self) -> None:
        folder = self.data_dir / "BrokerTerminal"
        folder.mkdir()
        exe = self._write_terminal_exe(folder)
        result = mt5_terminal_discovery.normalize_terminal_path(str(folder))
        self.assertEqual(result.status, "OK")
        self.assertEqual(result.terminal_exe_path, str(exe.resolve()))

    def test_folder_without_executable_reports_error(self) -> None:
        folder = self.data_dir / "empty_terminal_folder"
        folder.mkdir()
        result = mt5_terminal_discovery.normalize_terminal_path(str(folder))
        self.assertEqual(result.status, mt5_terminal_discovery.TERMINAL_EXECUTABLE_NOT_FOUND)

    def test_missing_path_reports_error(self) -> None:
        result = mt5_terminal_discovery.normalize_terminal_path(str(self.data_dir / "missing-path"))
        self.assertEqual(result.status, mt5_terminal_discovery.TERMINAL_PATH_NOT_FOUND)

    def test_terminal_offline_discovery(self) -> None:
        exe = self._write_terminal_exe()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [
                mt5_account_probe.ProbeResult(
                    status=mt5_account_probe.PROBE_STATUS_TERMINAL_OFFLINE,
                    user_message="Terminal çevrimdışı. MT5 terminalini açıp tekrar tarayın.",
                    terminal_exe_path=str(exe),
                )
            ]
        )
        payload = self._scan_paths([str(exe)])
        self.assertEqual(payload["discoveries"][0]["verification_status"], mt5_account_probe.PROBE_STATUS_TERMINAL_OFFLINE)

    def test_demo_account_discovery(self) -> None:
        exe = self._write_terminal_exe()
        data_path = self._instance_path("demo_a")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=data_path)]
        )
        payload = self._scan_paths([str(exe)])
        self.assertEqual(payload["discoveries"][0]["detected_trade_mode"], "DEMO")

    def test_real_account_discovery_execution_locked(self) -> None:
        exe = self._write_terminal_exe()
        data_path = self._instance_path("real_a")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [
                self._verified_probe(
                    exe=str(exe),
                    data_path=data_path,
                    trade_mode=mt5_account_probe.ACCOUNT_TYPE_REAL,
                    login="87654321",
                )
            ]
        )
        payload = self._scan_paths([str(exe)])
        discovery = payload["discoveries"][0]
        self.assertEqual(discovery["detected_trade_mode"], "REAL")
        self.assertEqual(discovery["execution_permission"], "LOCKED")

    def test_same_exe_different_data_paths_create_two_discoveries(self) -> None:
        exe = self._write_terminal_exe()
        path_a = self._instance_path("inst_a")
        path_b = self._instance_path("inst_b")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [
                self._verified_probe(exe=str(exe), data_path=path_a, login="111001"),
                self._verified_probe(exe=str(exe), data_path=path_b, login="111002"),
            ]
        )
        payload = self._scan_paths([str(exe)])
        self.assertEqual(len(payload["discoveries"]), 2)

    def test_duplicate_account_server_blocks_second_target(self) -> None:
        exe = self._write_terminal_exe()
        data_path_a = self._instance_path("dup_account_a")
        data_path_b = self._instance_path("dup_account_b")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=data_path_a, login="555001")]
        )
        payload = self._scan_paths([str(exe)])
        discovery_id = payload["discoveries"][0]["id"]
        first_status, _ = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{discovery_id}/add-target",
            {},
        )
        self.assertEqual(first_status, 200)
        mt5_terminal_discovery.reset_discovery_store()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=data_path_b, login="555001")]
        )
        payload = self._scan_paths([str(exe)])
        second_id = payload["discoveries"][0]["id"]
        second_status, body = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{second_id}/add-target",
            {},
        )
        self.assertEqual(second_status, 400)
        self.assertIn("hesap", str(body).lower())

    def test_duplicate_terminal_data_path_blocks_second_target(self) -> None:
        exe = self._write_terminal_exe()
        shared = self._instance_path("shared_data")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=shared, login="777001")]
        )
        payload = self._scan_paths([str(exe)])
        discovery_id = payload["discoveries"][0]["id"]
        self.request("POST", f"/api/mt5-terminals/discoveries/{discovery_id}/add-target", {})
        mt5_terminal_discovery.reset_discovery_store()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=shared, login="777002")]
        )
        payload = self._scan_paths([str(exe)])
        second_id = payload["discoveries"][0]["id"]
        status, body = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{second_id}/add-target",
            {},
        )
        self.assertEqual(status, 400)
        self.assertIn("instance", str(body).lower())

    def test_ambiguous_instance_cannot_add_target(self) -> None:
        exe = self._write_terminal_exe()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [
                mt5_account_probe.ProbeResult(
                    status=mt5_account_probe.PROBE_STATUS_VERIFIED,
                    user_message="Hesap bilgileri okundu.",
                    terminal_exe_path=str(exe),
                    account_login="12345678",
                    server="VantageMarkets-Demo",
                    trade_mode=mt5_account_probe.ACCOUNT_TYPE_DEMO,
                )
            ]
        )
        payload = self._scan_paths([str(exe)])
        discovery = payload["discoveries"][0]
        self.assertEqual(discovery["verification_status"], mt5_target_service.VERIFICATION_INSTANCE_AMBIGUOUS)
        self.assertFalse(discovery["can_add_as_target"])
        status, _body = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{discovery['id']}/add-target",
            {},
        )
        self.assertEqual(status, 400)

    def test_added_target_masks_login(self) -> None:
        exe = self._write_terminal_exe()
        data_path = self._instance_path("mask_login")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=data_path, login="12345678")]
        )
        payload = self._scan_paths([str(exe)])
        discovery_id = payload["discoveries"][0]["id"]
        status, body = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{discovery_id}/add-target",
            {"display_name": "Adem Demo"},
        )
        self.assertEqual(status, 200)
        self.assertEqual(body["target"]["detected_account_login_masked"], "***5678")
        self.assertNotIn("12345678", json.dumps(body))

    def test_password_field_rejected_on_discover(self) -> None:
        exe = self._write_terminal_exe()
        status, body = self.request(
            "POST",
            "/api/mt5-terminals/discover",
            {"terminal_paths": [str(exe)], "password": "secret"},
        )
        self.assertEqual(status, 400)
        self.assertIn("credentials", str(body).lower())

    def test_discovery_scan_supports_multiple_paths(self) -> None:
        for count in (1, 5, 10):
            mt5_terminal_discovery.reset_discovery_store()
            paths: list[str] = []
            probe_by_exe: dict[str, mt5_account_probe.ProbeResult] = {}
            for index in range(count):
                folder = self.data_dir / f"scan_terminal_{count}_{index}"
                folder.mkdir(parents=True, exist_ok=True)
                exe = self._write_terminal_exe(folder)
                paths.append(str(exe))
                probe_by_exe[str(exe.resolve())] = self._verified_probe(
                    exe=str(exe),
                    data_path=self._instance_path(f"scan_{count}_{index}"),
                    login=f"900{count}{index}",
                )

            def handler(path: str, mapping: dict[str, mt5_account_probe.ProbeResult] = probe_by_exe):
                return [mapping[path]]

            mt5_terminal_discovery.set_discovery_instances_override(handler)
            payload = self._scan_paths(paths)
            self.assertEqual(len(payload["discoveries"]), count)

    def test_duplicate_input_path_reported(self) -> None:
        exe = self._write_terminal_exe()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=self._instance_path("dup_path"))]
        )
        payload = self._scan_paths([str(exe), str(exe)])
        self.assertEqual(payload["duplicate_paths"], [str(exe)])

    def test_list_discoveries_endpoint(self) -> None:
        exe = self._write_terminal_exe()
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=self._instance_path("listed"))]
        )
        scan = self._scan_paths([str(exe)])
        status, payload = self.request("GET", f"/api/mt5-terminals/discoveries?scan_id={scan['scan_id']}")
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["discoveries"]), 1)

    def test_refresh_discovery_endpoint(self) -> None:
        exe = self._write_terminal_exe()
        data_path = self._instance_path("refresh_me")
        mt5_terminal_discovery.set_discovery_instances_override(
            lambda _path: [self._verified_probe(exe=str(exe), data_path=data_path, equity=1000.0)]
        )
        scan = self._scan_paths([str(exe)])
        discovery_id = scan["discoveries"][0]["id"]

        def refreshed_probe(_path: str) -> list[mt5_account_probe.ProbeResult]:
            return [self._verified_probe(exe=str(exe), data_path=data_path, equity=2000.0)]

        mt5_terminal_discovery.set_discovery_instances_override(refreshed_probe)
        mt5_account_probe.set_probe_override(
            lambda _req: self._verified_probe(exe=str(exe), data_path=data_path, equity=2000.0)
        )
        status, payload = self.request(
            "POST",
            f"/api/mt5-terminals/discoveries/{discovery_id}/refresh",
            {},
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["discovery"]["detected_equity"], 2000.0)


class DashboardDataDirTests(unittest.TestCase):
    def test_resolve_default_data_dir_absolute(self) -> None:
        fixed = Path(tempfile.mkdtemp(prefix="dashboard_default_dir_"))
        other = Path(tempfile.mkdtemp(prefix="dashboard_cwd_"))
        try:
            with patch.dict(
                os.environ,
                {"DASHBOARD_DATA_DIR": str(fixed), "LOCALAPPDATA": ""},
                clear=False,
            ):
                first = dashboard_security.resolve_default_data_dir()
            original_cwd = Path.cwd()
            try:
                os.chdir(other)
                with patch.dict(
                    os.environ,
                    {"DASHBOARD_DATA_DIR": str(fixed), "LOCALAPPDATA": ""},
                    clear=False,
                ):
                    second = dashboard_security.resolve_default_data_dir()
            finally:
                os.chdir(original_cwd)
            self.assertEqual(first, fixed.resolve())
            self.assertEqual(second, fixed.resolve())
            self.assertTrue(first.is_absolute())
        finally:
            shutil.rmtree(fixed, ignore_errors=True)
            shutil.rmtree(other, ignore_errors=True)


class DashboardModularizationTests(unittest.TestCase):
    def test_legacy_wrapper_importable(self) -> None:
        self.assertTrue(hasattr(telegram_dashboard_server, "main"))

    def test_no_circular_imports(self) -> None:
        for module_name in (
            "dashboard_security",
            "dashboard_store",
            "dashboard_api",
            "dashboard_server",
            "dashboard_vault",
            "route_listener_service",
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
        self.assertEqual(allowed, {"index.html", "app.js", "styles.css", "favicon.svg"})


if __name__ == "__main__":
    unittest.main()
