"""Tests for local Telegram Route Dashboard server."""

from __future__ import annotations

import importlib
import json
import shutil
import socket
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from urllib import error, request

ROOT = Path(__file__).resolve().parents[1]
DASHBOARD_DIR = ROOT / "dashboard"
sys.path.insert(0, str(ROOT))

import dashboard_api  # noqa: E402
import dashboard_security  # noqa: E402
import dashboard_server  # noqa: E402
import dashboard_store  # noqa: E402
import telegram_dashboard_server  # noqa: E402


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind((dashboard_security.ALLOWED_HOST, 0))
        return sock.getsockname()[1]


class DashboardServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.mkdtemp(prefix="dashboard_test_")
        self.data_dir = Path(self.temp_dir)
        self.db = dashboard_store.DashboardDatabase(self.data_dir / "dashboard.sqlite3")
        self.port = free_port()
        self.context = dashboard_api.DashboardContext(
            host=dashboard_security.ALLOWED_HOST,
            port=self.port,
            data_dir=self.data_dir,
            dashboard_dir=DASHBOARD_DIR.resolve(),
            database=self.db,
        )
        self.server = dashboard_server.create_server(self.context)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
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
        self.assertEqual(payload["safety"]["file_common_write"], "NOT_IMPLEMENTED")
        self.assertEqual(payload["counts"]["tracked_channels"], 0)

    def test_configure_rejects_literal_credentials(self) -> None:
        status, payload = self.request(
            "POST",
            "/api/telegram/configure",
            {
                "api_id_present": True,
                "api_hash_present": True,
                "phone": "+905551234567",
                "api_hash": "secret",
            },
        )
        self.assertEqual(status, 400)
        self.assertIn("credentials", payload["error"])

    def test_configure_accepts_masked_phone_only(self) -> None:
        status, payload = self.request(
            "POST",
            "/api/telegram/configure",
            {
                "api_id_present": True,
                "api_hash_present": True,
                "phone": "+905551234567",
            },
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["status"], "API_CONFIGURED")
        self.assertTrue(payload["phone_masked"].endswith("4567"))
        self.assertNotIn("5551234567", payload["phone_masked"])

        with self.db._connect() as conn:
            row = conn.execute(
                "SELECT phone_masked FROM telegram_connection WHERE id = 1"
            ).fetchone()
        self.assertIsNotNone(row)
        self.assertNotIn("5551234567", row["phone_masked"])

    def test_login_endpoints_not_implemented(self) -> None:
        status, payload = self.request("POST", "/api/telegram/request-code", {})
        self.assertEqual(status, 501)
        self.assertEqual(payload["status"], "NOT_IMPLEMENTED")

        status, payload = self.request(
            "POST",
            "/api/telegram/verify-code",
            {"code": "12345"},
        )
        self.assertEqual(status, 501)

        status, payload = self.request(
            "POST",
            "/api/telegram/verify-password",
            {"password": "secret"},
        )
        self.assertEqual(status, 501)

    def test_demo_channels_import_idempotent(self) -> None:
        first_status, first_payload = self.request("POST", "/api/channels/import-demo", {})
        second_status, second_payload = self.request("POST", "/api/channels/import-demo", {})
        self.assertEqual(first_status, 200)
        self.assertEqual(second_status, 200)
        self.assertEqual(first_payload["source"], "LOCAL_DEMO_DATA")
        self.assertGreaterEqual(first_payload["inserted"], 1)
        self.assertEqual(second_payload["inserted"], 0)

        status, payload = self.request("GET", "/api/channels")
        self.assertEqual(status, 200)
        self.assertEqual(len(payload["channels"]), 3)

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

        bad_traversal = dict(valid, name="Bad Traversal", seed_filename="../evil.txt")
        status, _payload = self.request("POST", "/api/targets", bad_traversal)
        self.assertEqual(status, 400)

        same_names = dict(valid, name="Same Names", seed_filename="same.txt", details_filename="same.txt")
        status, _payload = self.request("POST", "/api/targets", same_names)
        self.assertEqual(status, 400)

        observer_off = dict(valid, name="Observer Off", observer_only=False)
        status, _payload = self.request("POST", "/api/targets", observer_off)
        self.assertEqual(status, 400)

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

        duplicate = dict(route_payload, name="Gold Route Duplicate")
        status, _payload = self.request("POST", "/api/routes", duplicate)
        self.assertEqual(status, 400)

        mode_change = dict(route_payload, name="Mode Change", mode="LIVE")
        status, _payload = self.request("POST", "/api/routes", mode_change)
        self.assertEqual(status, 400)

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

        status, payload = self.request("DELETE", f"/api/targets/{target['id']}")
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
        for path in ("/", "/app.js", "/styles.css", "/api/health"):
            status, body = self.request("GET", path)
            self.assertEqual(status, 200)
            if path == "/api/health":
                self.assertIn("telegram-route-dashboard", body["server"])
            else:
                self.assertIsInstance(body, (bytes, str))
                self.assertGreater(len(body), 10)


class DashboardModularizationTests(unittest.TestCase):
    def test_legacy_wrapper_importable(self) -> None:
        self.assertTrue(hasattr(telegram_dashboard_server, "main"))
        self.assertEqual(
            telegram_dashboard_server.main.__module__,
            "dashboard_server",
        )

    def test_dashboard_server_host_guard(self) -> None:
        with self.assertRaises(dashboard_security.DashboardSecurityError):
            dashboard_security.validate_host("0.0.0.0")

    def test_no_circular_imports(self) -> None:
        for module_name in (
            "dashboard_security",
            "dashboard_store",
            "dashboard_api",
            "dashboard_server",
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
            self.assertIn("counts", overview)
            self.assertIn("safety", overview)
            self.assertEqual(overview["safety"]["broker_execution"], "DISABLED_BY_DESIGN")
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_static_asset_map_only_three_files(self) -> None:
        allowed = set(dashboard_security.STATIC_ASSET_MAP.values())
        self.assertEqual(allowed, {"index.html", "app.js", "styles.css"})
        with self.assertRaises(FileNotFoundError):
            dashboard_security.assert_static_path_allowed("/secret.txt")


if __name__ == "__main__":
    unittest.main()
