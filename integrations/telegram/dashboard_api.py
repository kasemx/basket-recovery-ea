"""HTTP API routing for the local Telegram route dashboard."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from dashboard_security import (
    DashboardSecurityError,
    DashboardValidationError,
    json_response,
    mask_phone,
    parse_json_body,
    reject_literal_credentials,
    resolve_static_file,
    security_headers,
)
from dashboard_store import DashboardDatabase

logger = logging.getLogger("telegram_dashboard")


@dataclass
class DashboardContext:
    host: str
    port: int
    data_dir: Path
    dashboard_dir: Path
    database: DashboardDatabase


class DashboardRequestHandler(BaseHTTPRequestHandler):
    server_version = "TelegramRouteDashboard/0.1"
    context: DashboardContext

    def log_message(self, format: str, *args: object) -> None:
        logger.info("%s - %s", self.address_string(), format % args)

    def _send(self, status: int, headers: dict[str, str], body: bytes) -> None:
        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, data: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        code, headers, body = json_response(data, status)
        self._send(code, headers, body)

    def _send_error_json(self, status: HTTPStatus, message: str) -> None:
        self._send_json({"error": message}, status)

    def _read_body(self) -> bytes:
        length = int(self.headers.get("Content-Length", "0"))
        return self.rfile.read(length) if length else b""

    def _route_id(self, prefix: str) -> int | None:
        path = urlparse(self.path).path
        if not path.startswith(prefix):
            return None
        suffix = path[len(prefix) :].strip("/")
        if not suffix.isdigit():
            return None
        return int(suffix)

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        try:
            if path == "/api/health":
                telegram = self.context.database.get_telegram_status()
                self._send_json(
                    {
                        "ok": True,
                        "server": "telegram-route-dashboard",
                        "host": self.context.host,
                        "telegram_status": telegram["status"],
                    }
                )
                return
            if path == "/api/overview":
                self._send_json(self.context.database.overview())
                return
            if path == "/api/telegram/status":
                row = self.context.database.get_telegram_status()
                self._send_json(
                    {
                        "status": row["status"],
                        "phone_masked": row.get("phone_masked"),
                        "channel_count": row.get("channel_count", 0),
                        "last_error_code": row.get("last_error_code"),
                        "updated_at_utc": row.get("updated_at_utc"),
                    }
                )
                return
            if path == "/api/channels":
                self._send_json({"channels": self.context.database.list_channels()})
                return
            if path == "/api/targets":
                self._send_json({"targets": self.context.database.list_targets()})
                return
            if path == "/api/routes":
                self._send_json({"routes": self.context.database.list_routes()})
                return
            if path.startswith("/api/audit"):
                query = parse_qs(urlparse(self.path).query)
                limit = min(int(query.get("limit", ["100"])[0]), 200)
                self._send_json({"events": self.context.database.list_audit(limit)})
                return
            self._serve_static(path)
        except DashboardValidationError as exc:
            self._send_error_json(HTTPStatus.BAD_REQUEST, str(exc))
        except FileNotFoundError:
            self._send_error_json(HTTPStatus.NOT_FOUND, "Not found")
        except DashboardSecurityError as exc:
            self._send_error_json(HTTPStatus.FORBIDDEN, str(exc))

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            body = self._read_body()
            payload = parse_json_body(body)
            db = self.context.database

            if path == "/api/telegram/configure":
                reject_literal_credentials(payload)
                if not payload.get("api_id_present") or not payload.get("api_hash_present"):
                    raise DashboardValidationError("api_id_present and api_hash_present must be true")
                phone = str(payload.get("phone", "")).strip()
                if not phone.startswith("+") or len(re.sub(r"\D", "", phone)) < 8:
                    raise DashboardValidationError("Phone must be in international format, e.g. +905xxxxxxxxx")
                phone_masked = mask_phone(phone)
                db.configure_telegram(phone_masked)
                db.add_audit(
                    "TELEGRAM_CONFIGURE",
                    "INFO",
                    "Telegram local configuration saved (masked phone only)",
                    {"phone_masked": phone_masked},
                )
                self._send_json({"status": "API_CONFIGURED", "phone_masked": phone_masked})
                return

            if path == "/api/telegram/request-code":
                self._send_json(
                    {"status": "NOT_IMPLEMENTED", "next_phase": "Telethon adapter"},
                    HTTPStatus.NOT_IMPLEMENTED,
                )
                return

            if path == "/api/telegram/verify-code":
                self._send_error_json(
                    HTTPStatus.NOT_IMPLEMENTED,
                    "Telegram login is not enabled in dashboard foundation.",
                )
                return

            if path == "/api/telegram/verify-password":
                self._send_error_json(
                    HTTPStatus.NOT_IMPLEMENTED,
                    "Telegram login is not enabled in dashboard foundation.",
                )
                return

            if path == "/api/channels/import-demo":
                inserted, source = db.import_demo_channels()
                db.add_audit(
                    "CHANNELS_IMPORT_DEMO",
                    "INFO",
                    "Imported local demo channels",
                    {"inserted": inserted, "source": source},
                )
                self._send_json({"inserted": inserted, "source": source})
                return

            if path == "/api/targets":
                reject_literal_credentials(payload)
                target = db.create_target(payload)
                db.add_audit(
                    "TARGET_CREATE",
                    "INFO",
                    f"Created MT5 target {target['name']}",
                    {"target_id": target["id"], "observer_only": 1},
                )
                self._send_json({"target": target}, HTTPStatus.CREATED)
                return

            if path == "/api/routes":
                if payload.get("mode") and str(payload["mode"]).upper() != "OBSERVER_ONLY":
                    raise DashboardValidationError("Route mode changes are not allowed")
                route = db.create_route(payload)
                db.add_audit(
                    "ROUTE_CREATE",
                    "INFO",
                    f"Created observer-only route {route['name']}",
                    {"route_id": route["id"], "mode": route["mode"]},
                )
                self._send_json({"route": route}, HTTPStatus.CREATED)
                return

            if path == "/api/audit/demo-event":
                event = db.add_demo_audit_event()
                self._send_json({"event": event}, HTTPStatus.CREATED)
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "Not found")
        except DashboardValidationError as exc:
            status = HTTPStatus.CONFLICT if "routes" in str(exc) else HTTPStatus.BAD_REQUEST
            self._send_error_json(status, str(exc))

    def do_PATCH(self) -> None:
        path = urlparse(self.path).path
        try:
            payload = parse_json_body(self._read_body())
            reject_literal_credentials(payload)
            db = self.context.database

            channel_id = self._route_id("/api/channels/")
            if channel_id is not None:
                channel = db.update_channel(channel_id, payload)
                db.add_audit(
                    "CHANNEL_UPDATE",
                    "INFO",
                    f"Updated channel {channel_id}",
                    {"channel_id": channel_id, "fields": sorted(payload.keys())},
                )
                self._send_json({"channel": channel})
                return

            target_id = self._route_id("/api/targets/")
            if target_id is not None:
                target = db.update_target(target_id, payload)
                db.add_audit(
                    "TARGET_UPDATE",
                    "INFO",
                    f"Updated target {target_id}",
                    {"target_id": target_id, "fields": sorted(payload.keys())},
                )
                self._send_json({"target": target})
                return

            route_id = self._route_id("/api/routes/")
            if route_id is not None:
                route = db.update_route(route_id, payload)
                db.add_audit(
                    "ROUTE_UPDATE",
                    "INFO",
                    f"Updated route {route_id}",
                    {"route_id": route_id, "fields": sorted(payload.keys())},
                )
                self._send_json({"route": route})
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "Not found")
        except DashboardValidationError as exc:
            self._send_error_json(HTTPStatus.BAD_REQUEST, str(exc))

    def do_DELETE(self) -> None:
        path = urlparse(self.path).path
        try:
            db = self.context.database
            channel_id = self._route_id("/api/channels/")
            if channel_id is not None:
                db.delete_channel(channel_id)
                db.add_audit(
                    "CHANNEL_DELETE",
                    "INFO",
                    f"Deleted channel {channel_id}",
                    {"channel_id": channel_id},
                )
                self._send_json({"deleted": True})
                return

            target_id = self._route_id("/api/targets/")
            if target_id is not None:
                db.delete_target(target_id)
                db.add_audit(
                    "TARGET_DELETE",
                    "INFO",
                    f"Deleted target {target_id}",
                    {"target_id": target_id},
                )
                self._send_json({"deleted": True})
                return

            route_id = self._route_id("/api/routes/")
            if route_id is not None:
                db.delete_route(route_id)
                db.add_audit(
                    "ROUTE_DELETE",
                    "INFO",
                    f"Deleted route {route_id}",
                    {"route_id": route_id},
                )
                self._send_json({"deleted": True})
                return

            self._send_error_json(HTTPStatus.NOT_FOUND, "Not found")
        except DashboardValidationError as exc:
            status = HTTPStatus.CONFLICT if "routes" in str(exc) else HTTPStatus.BAD_REQUEST
            self._send_error_json(status, str(exc))

    def _serve_static(self, path: str) -> None:
        file_path, content_type = resolve_static_file(self.context.dashboard_dir, path)
        content = file_path.read_bytes()
        headers = {
            "Content-Type": content_type,
            "Content-Length": str(len(content)),
            **security_headers(),
        }
        self._send(HTTPStatus.OK.value, headers, content)
