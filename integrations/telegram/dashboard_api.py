"""HTTP API routing for the local Telegram route dashboard."""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

from dashboard_security import (
    DashboardSecurityError,
    DashboardValidationError,
    json_response,
    mask_phone,
    mask_session_path,
    parse_json_body,
    reject_literal_credentials,
    resolve_static_file,
    security_headers,
)
from dashboard_store import DashboardDatabase
from route_listener_service import RouteListenerManager, build_default_listener_manager
from dashboard_vault import (
    CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM,
    CredentialVaultError,
    DashboardCredentialVault,
)
from telegram_adapter import (
    TELEGRAM_2FA_REQUIRED,
    TELEGRAM_AUTH_FAILED,
    TELEGRAM_CONFIG_MISSING,
    TELEGRAM_CONNECTED,
    TELEGRAM_FLOOD_WAIT,
    TELEGRAM_SYNC_FAILED,
    TELETHON_NOT_INSTALLED,
    TelegramAdapter,
    build_adapter_from_data_dir,
    ensure_session_path_ready,
    is_telethon_available,
    load_telegram_config,
    resolve_credential_source,
    run_telegram_async,
)

logger = logging.getLogger("telegram_dashboard")

USER_ERROR_MESSAGES = {
    TELEGRAM_CONFIG_MISSING: "Telegram API credentials are missing. Save credentials to the DPAPI vault or set environment fallback.",
    TELETHON_NOT_INSTALLED: "Telethon is not installed on this machine.",
    TELEGRAM_FLOOD_WAIT: "Telegram rate limit reached. Wait before trying again.",
    "TELEGRAM_API_ID_INVALID": "Telegram rejected the API ID. Check vault credentials.",
    "TELEGRAM_PHONE_INVALID": "Phone number format is invalid for Telegram.",
    "TELEGRAM_NETWORK_ERROR": "Network error while contacting Telegram.",
    "TELEGRAM_CODE_REQUEST_FAILED": "Telegram code request failed.",
    "TELEGRAM_SESSION_PATH_ERROR": "Session directory could not be prepared.",
    "TELEGRAM_INTERNAL_ERROR": "Unexpected dashboard error during Telegram login.",
    TELEGRAM_AUTH_FAILED: "Telegram authentication failed.",
}


def user_message_for_error(error_code: str | None, flood_wait_seconds: int | None = None) -> str:
    if error_code == TELEGRAM_FLOOD_WAIT and flood_wait_seconds:
        return f"Telegram rate limit reached. Wait {flood_wait_seconds} seconds."
    if error_code and error_code in USER_ERROR_MESSAGES:
        return USER_ERROR_MESSAGES[error_code]
    return "Telegram request failed."


@dataclass
class DashboardContext:
    host: str
    port: int
    data_dir: Path
    dashboard_dir: Path
    database: DashboardDatabase
    telegram_service: TelegramService | None = None
    route_listener_manager: RouteListenerManager | None = None


@dataclass
class TelegramService:
    data_dir: Path = field(default_factory=Path.cwd)
    adapter_factory: Callable[[], TelegramAdapter | None] | None = field(default=None)
    _auth_phone: str | None = field(default=None, init=False, repr=False)

    def __post_init__(self) -> None:
        object.__setattr__(self, "data_dir", self.data_dir.expanduser().resolve())
        if self.adapter_factory is None:
            data_dir = self.data_dir

            def _factory() -> TelegramAdapter | None:
                return build_adapter_from_data_dir(data_dir)

            self.adapter_factory = _factory

    def _vault(self) -> DashboardCredentialVault:
        return DashboardCredentialVault(self.data_dir)

    def telethon_available(self) -> bool:
        return is_telethon_available()

    def config_ready(self) -> bool:
        return load_telegram_config(self.data_dir) is not None

    def credentials_status(self) -> dict[str, Any]:
        status = self._vault().status_payload()
        status["config_ready"] = self.config_ready()
        return status

    def save_credentials(self, api_id: str, api_hash: str) -> dict[str, Any]:
        vault = self._vault()
        try:
            vault.save_telegram_credentials(api_id, api_hash)
        except CredentialVaultError as exc:
            return {"status": "ERROR", "error_code": exc.error_code}
        return {
            "status": "CREDENTIALS_SAVED",
            "vault_supported": True,
            "credentials_saved": True,
            "config_ready": self.config_ready(),
        }

    def clear_credentials(self) -> dict[str, Any]:
        self._vault().clear_telegram_credentials()
        return {
            "status": "CREDENTIALS_CLEARED",
            "credentials_saved": False,
            "config_ready": self.config_ready(),
        }

    def status_payload(self, db: DashboardDatabase) -> dict[str, Any]:
        config = load_telegram_config(self.data_dir)
        config_ready = config is not None
        payload = db.public_telegram_status(
            telethon_available=self.telethon_available(),
            config_ready=config_ready,
            session_pending=config is not None and not config.session_path.exists(),
        )
        payload.update(self._vault().status_payload())
        payload["credential_source"] = resolve_credential_source(self.data_dir)
        if config is not None:
            payload["session_file_exists"] = config.session_path.exists()
        else:
            payload["session_file_exists"] = False
        if not config_ready:
            stored_status = payload.get("status")
            if stored_status not in (None, "DISCONNECTED", "ERROR"):
                payload["status"] = "DISCONNECTED"
                payload["last_error_code"] = payload.get("last_error_code") or TELEGRAM_CONFIG_MISSING
        return payload

    def diagnostics_payload(self, db: DashboardDatabase) -> dict[str, Any]:
        vault = self._vault()
        config = load_telegram_config(self.data_dir)
        session_path_resolved = config is not None
        session_parent_exists = False
        session_file_exists = False
        if config is not None:
            session_parent_exists = config.session_path.parent.exists()
            session_file_exists = config.session_path.exists()
        row = db.get_telegram_status()
        return {
            "vault_supported": vault.status_payload()["vault_supported"],
            "vault_file_present": vault.vault_file_present(),
            "vault_credentials_available": vault.has_telegram_credentials(),
            "credential_source": resolve_credential_source(self.data_dir),
            "session_path_resolved": session_path_resolved,
            "session_parent_exists": session_parent_exists,
            "session_file_exists": session_file_exists,
            "data_dir_consistent": vault.data_dir == self.data_dir.expanduser().resolve(),
            "last_safe_error_code": row.get("last_error_code"),
        }

    def resolve_request_phone(self, phone_from_body: str) -> str:
        phone = str(phone_from_body or "").strip()
        if phone:
            if not phone.startswith("+") or len(re.sub(r"\D", "", phone)) < 8:
                raise DashboardValidationError(
                    "Phone must be in international format, e.g. +905xxxxxxxxx"
                )
            self._auth_phone = phone
            return phone
        if self._auth_phone:
            return self._auth_phone
        raise DashboardValidationError(
            "Enter your phone number in the field above, then click Request Code."
        )

    def configure(self, db: DashboardDatabase, phone: str) -> dict[str, Any]:
        if not self.config_ready():
            db.set_telegram_config_error(TELEGRAM_CONFIG_MISSING)
            return {
                "status": "ERROR",
                "error_code": TELEGRAM_CONFIG_MISSING,
                "user_message": user_message_for_error(TELEGRAM_CONFIG_MISSING),
            }
        if not phone.startswith("+") or len(re.sub(r"\D", "", phone)) < 8:
            raise DashboardValidationError(
                "Phone must be in international format, e.g. +905xxxxxxxxx"
            )
        telegram_config = load_telegram_config(self.data_dir)
        if telegram_config is None:
            db.set_telegram_config_error(TELEGRAM_CONFIG_MISSING)
            return {
                "status": "ERROR",
                "error_code": TELEGRAM_CONFIG_MISSING,
                "user_message": user_message_for_error(TELEGRAM_CONFIG_MISSING),
            }
        phone_masked = mask_phone(phone)
        session_path_masked = mask_session_path(str(telegram_config.session_path))
        self._auth_phone = phone
        db.configure_telegram(phone_masked, session_path_masked)
        return {
            "status": "API_CONFIGURED",
            "phone_masked": phone_masked,
            "session_path_masked": session_path_masked,
        }

    def request_code(self, db: DashboardDatabase, phone: str) -> dict[str, Any]:
        if not self.config_ready():
            raise DashboardValidationError("Telegram environment configuration is missing")
        if not self.telethon_available():
            return {
                "status": "ERROR",
                "error_code": TELETHON_NOT_INSTALLED,
                "user_message": user_message_for_error(TELETHON_NOT_INSTALLED),
            }
        config = load_telegram_config(self.data_dir)
        if config is None:
            return {
                "status": "ERROR",
                "error_code": TELEGRAM_CONFIG_MISSING,
                "user_message": user_message_for_error(TELEGRAM_CONFIG_MISSING),
            }
        try:
            ensure_session_path_ready(config.session_path)
        except OSError:
            db.set_telegram_auth_error("TELEGRAM_SESSION_PATH_ERROR")
            return {
                "status": "ERROR",
                "error_code": "TELEGRAM_SESSION_PATH_ERROR",
                "user_message": user_message_for_error("TELEGRAM_SESSION_PATH_ERROR"),
            }
        self._auth_phone = phone
        adapter = self._require_adapter()
        try:
            result = run_telegram_async(adapter.send_code(phone))
        except Exception:  # noqa: BLE001
            db.set_telegram_auth_error("TELEGRAM_INTERNAL_ERROR")
            return {
                "status": "ERROR",
                "error_code": "TELEGRAM_INTERNAL_ERROR",
                "user_message": user_message_for_error("TELEGRAM_INTERNAL_ERROR"),
            }
        if result.status != "CODE_SENT" or not result.phone_code_hash:
            error_code = result.error_code or "TELEGRAM_CODE_REQUEST_FAILED"
            db.set_telegram_auth_error(error_code)
            response: dict[str, Any] = {
                "status": "ERROR",
                "error_code": error_code,
                "user_message": user_message_for_error(error_code, result.flood_wait_seconds),
            }
            if result.flood_wait_seconds:
                response["flood_wait_seconds"] = result.flood_wait_seconds
            return response
        db.set_telegram_code_sent(result.phone_code_hash)
        row = db.get_telegram_status()
        return {
            "status": "CODE_SENT",
            "phone_masked": row.get("phone_masked"),
        }

    def verify_code(self, db: DashboardDatabase, code: str) -> dict[str, Any]:
        if not self.telethon_available():
            return {"status": "ERROR", "error_code": TELETHON_NOT_INSTALLED}
        phone_code_hash = db.get_phone_code_hash()
        if not phone_code_hash:
            raise DashboardValidationError("Request a login code before verification")
        phone = self._auth_phone
        if not phone:
            raise DashboardValidationError("Configure phone number before verification")
        adapter = self._require_adapter()
        result = run_telegram_async(
            adapter.sign_in_code(phone, code, phone_code_hash)
        )
        if result.status == TELEGRAM_CONNECTED:
            db.set_telegram_connected()
            self._auth_phone = None
            return {"status": TELEGRAM_CONNECTED}
        if result.status == "TWO_FACTOR_REQUIRED":
            db.set_telegram_two_factor_required()
            return {"status": "TWO_FACTOR_REQUIRED", "error_code": TELEGRAM_2FA_REQUIRED}
        error_code = result.error_code or TELEGRAM_AUTH_FAILED
        db.set_telegram_auth_error(error_code)
        return {"status": "ERROR", "error_code": error_code}

    def verify_password(self, db: DashboardDatabase, password: str) -> dict[str, Any]:
        if not self.telethon_available():
            return {"status": "ERROR", "error_code": TELETHON_NOT_INSTALLED}
        adapter = self._require_adapter()
        result = run_telegram_async(adapter.sign_in_password(password))
        if result.status == TELEGRAM_CONNECTED:
            db.set_telegram_connected()
            self._auth_phone = None
            return {"status": TELEGRAM_CONNECTED}
        error_code = result.error_code or TELEGRAM_AUTH_FAILED
        db.set_telegram_auth_error(error_code)
        return {"status": "ERROR", "error_code": error_code}

    def sync_channels(self, db: DashboardDatabase) -> dict[str, Any]:
        row = db.get_telegram_status()
        if row.get("status") != "CONNECTED":
            raise DashboardValidationError("Telegram must be connected before channel sync")
        if not self.telethon_available():
            return {"status": "ERROR", "error_code": TELETHON_NOT_INSTALLED}
        adapter = self._require_adapter()
        try:
            dialogs = run_telegram_async(adapter.list_dialogs(limit=200))
        except Exception as exc:  # noqa: BLE001
            db.set_telegram_auth_error(TELEGRAM_SYNC_FAILED)
            logger.error("dashboard_event=TELEGRAM_SYNC_FAILED reason=%s", exc)
            return {"status": "ERROR", "error_code": TELEGRAM_SYNC_FAILED}
        payload = [
            {
                "telegram_channel_id": item.telegram_channel_id,
                "title": item.title,
                "channel_type": item.channel_type,
                "username": item.username,
                "last_message_at_utc": item.last_message_at_utc,
            }
            for item in dialogs
        ]
        synced = db.sync_telegram_channels(payload)
        return {"synced": synced, "source": "TELEGRAM"}

    def disconnect(self, db: DashboardDatabase) -> dict[str, Any]:
        adapter = self.adapter_factory()
        if adapter is not None and self.telethon_available():
            run_telegram_async(adapter.disconnect())
        self._auth_phone = None
        db.set_telegram_disconnected()
        row = db.get_telegram_status()
        return {
            "status": "DISCONNECTED",
            "session_path_masked": row.get("session_path_masked"),
        }

    def _require_adapter(self) -> TelegramAdapter:
        adapter = self.adapter_factory()
        if adapter is None:
            raise DashboardValidationError("Telegram environment configuration is missing")
        return adapter


class DashboardRequestHandler(BaseHTTPRequestHandler):
    server_version = "TelegramRouteDashboard/0.2"
    context: DashboardContext

    def _telegram_service(self) -> TelegramService:
        if self.context.telegram_service is None:
            self.context.telegram_service = TelegramService(data_dir=self.context.data_dir)
        return self.context.telegram_service

    def _listener_manager(self) -> RouteListenerManager:
        if self.context.route_listener_manager is None:
            self.context.route_listener_manager = build_default_listener_manager(
                self.context.database,
                self.context.data_dir,
            )
        return self.context.route_listener_manager

    def _parse_route_listener_path(self, path: str) -> tuple[int | None, str | None]:
        match = re.match(
            r"^/api/routes/(\d+)(?:/(listener/start|listener/stop|listener-status|events))?$",
            path,
        )
        if not match:
            return None, None
        return int(match.group(1)), match.group(2)

    def _enrich_routes(self, routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
        manager = self._listener_manager()
        enriched: list[dict[str, Any]] = []
        for route in routes:
            item = dict(route)
            status = manager.route_listener_status(int(route["id"]))
            item["listener"] = status or {
                "route_id": route["id"],
                "running": False,
                "listener_status": "LISTENER_STOPPED",
            }
            enriched.append(item)
        return enriched

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
                self._send_json(
                    self._telegram_service().status_payload(self.context.database)
                )
                return
            if path == "/api/telegram/credentials/status":
                self._send_json(self._telegram_service().credentials_status())
                return
            if path == "/api/telegram/diagnostics":
                self._send_json(
                    self._telegram_service().diagnostics_payload(self.context.database)
                )
                return
            if path == "/api/channels":
                self._send_json({"channels": self.context.database.list_channels()})
                return
            if path == "/api/targets":
                self._send_json({"targets": self.context.database.list_targets()})
                return
            if path == "/api/listener/status":
                self._send_json(self._listener_manager().status_payload())
                return
            route_id, subpath = self._parse_route_listener_path(path)
            if route_id is not None and subpath == "listener-status":
                status = self._listener_manager().route_listener_status(route_id)
                if status is None:
                    self._send_error_json(HTTPStatus.NOT_FOUND, "Route not found")
                    return
                self._send_json(status)
                return
            if route_id is not None and subpath == "events":
                query = parse_qs(urlparse(self.path).query)
                limit = min(int(query.get("limit", ["50"])[0]), 200)
                events = self.context.database.list_route_events(route_id, limit)
                self._send_json({"route_id": route_id, "events": events})
                return
            if path == "/api/routes":
                routes = self._enrich_routes(self.context.database.list_routes())
                self._send_json({"routes": routes})
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
            telegram = self._telegram_service()

            if path == "/api/telegram/configure":
                reject_literal_credentials(payload)
                phone = str(payload.get("phone", "")).strip()
                result = telegram.configure(db, phone)
                if result.get("status") == "ERROR":
                    db.add_audit(
                        "TELEGRAM_CONFIGURE",
                        "ERROR",
                        "Telegram configuration failed",
                        {"error_code": result.get("error_code")},
                    )
                    self._send_json(result, HTTPStatus.BAD_REQUEST)
                    return
                db.add_audit(
                    "TELEGRAM_CONFIGURE",
                    "INFO",
                    "Telegram local configuration saved (masked phone only)",
                    {
                        "phone_masked": result["phone_masked"],
                        "session_path_masked": result.get("session_path_masked"),
                    },
                )
                self._send_json(result)
                return

            if path == "/api/telegram/credentials":
                reject_literal_credentials(
                    payload,
                    allowed=frozenset({"api_id", "api_hash"}),
                )
                api_id = str(payload.get("api_id", "")).strip()
                api_hash = str(payload.get("api_hash", "")).strip()
                if not api_id or not api_hash:
                    raise DashboardValidationError("api_id and api_hash are required")
                result = telegram.save_credentials(api_id, api_hash)
                if result.get("status") == "ERROR":
                    db.add_audit(
                        "TELEGRAM_CREDENTIALS_SAVE",
                        "ERROR",
                        "Telegram credential vault save failed",
                        {"error_code": result.get("error_code")},
                    )
                    status = HTTPStatus.BAD_REQUEST
                    if result.get("error_code") == CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM:
                        status = HTTPStatus.NOT_IMPLEMENTED
                    self._send_json(result, status)
                    return
                db.add_audit(
                    "TELEGRAM_CREDENTIALS_SAVE",
                    "INFO",
                    "Telegram API credentials saved to DPAPI vault",
                    {"credentials_saved": True},
                )
                self._send_json(result)
                return

            if path == "/api/telegram/request-code":
                reject_literal_credentials(payload)
                phone = telegram.resolve_request_phone(str(payload.get("phone", "")))
                result = telegram.request_code(db, phone)
                if result.get("status") == "ERROR":
                    status = (
                        HTTPStatus.INTERNAL_SERVER_ERROR
                        if result.get("error_code") == TELETHON_NOT_INSTALLED
                        else HTTPStatus.BAD_REQUEST
                    )
                    db.add_audit(
                        "TELEGRAM_REQUEST_CODE",
                        "ERROR",
                        "Telegram code request failed",
                        {"error_code": result.get("error_code")},
                    )
                    self._send_json(result, status)
                    return
                db.add_audit(
                    "TELEGRAM_REQUEST_CODE",
                    "INFO",
                    "Telegram login code requested",
                    {"phone_masked": result.get("phone_masked")},
                )
                self._send_json(result)
                return

            if path == "/api/telegram/verify-code":
                reject_literal_credentials(payload, allowed=frozenset({"code"}))
                code = str(payload.get("code", "")).strip()
                if not code:
                    raise DashboardValidationError("Verification code is required")
                result = telegram.verify_code(db, code)
                db.add_audit(
                    "TELEGRAM_VERIFY_CODE",
                    "INFO" if result.get("status") == TELEGRAM_CONNECTED else "ERROR",
                    "Telegram code verification processed",
                    {"status": result.get("status"), "error_code": result.get("error_code")},
                )
                status = HTTPStatus.OK
                if result.get("status") == "ERROR":
                    status = HTTPStatus.BAD_REQUEST
                self._send_json(result, status)
                return

            if path == "/api/telegram/verify-password":
                reject_literal_credentials(payload, allowed=frozenset({"password"}))
                password = str(payload.get("password", "")).strip()
                if not password:
                    raise DashboardValidationError("2FA password is required")
                result = telegram.verify_password(db, password)
                db.add_audit(
                    "TELEGRAM_VERIFY_PASSWORD",
                    "INFO" if result.get("status") == TELEGRAM_CONNECTED else "ERROR",
                    "Telegram 2FA verification processed",
                    {"status": result.get("status"), "error_code": result.get("error_code")},
                )
                status = HTTPStatus.OK
                if result.get("status") == "ERROR":
                    status = HTTPStatus.BAD_REQUEST
                self._send_json(result, status)
                return

            if path == "/api/telegram/sync-channels":
                result = telegram.sync_channels(db)
                if result.get("status") == "ERROR":
                    db.add_audit(
                        "TELEGRAM_SYNC_CHANNELS",
                        "ERROR",
                        "Telegram channel sync failed",
                        {"error_code": result.get("error_code")},
                    )
                    self._send_json(result, HTTPStatus.BAD_REQUEST)
                    return
                db.add_audit(
                    "TELEGRAM_SYNC_CHANNELS",
                    "INFO",
                    "Telegram channels synced",
                    {"synced": result.get("synced"), "source": result.get("source")},
                )
                self._send_json(result)
                return

            if path == "/api/telegram/disconnect":
                result = telegram.disconnect(db)
                db.add_audit(
                    "TELEGRAM_DISCONNECT",
                    "INFO",
                    "Telegram client disconnected (session file retained)",
                    {"status": result.get("status")},
                )
                self._send_json(result)
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

            route_id, subpath = self._parse_route_listener_path(path)
            if route_id is not None and subpath == "listener/start":
                result = self._listener_manager().start_route(route_id)
                if result.get("status") == "ERROR":
                    db.add_audit(
                        "ROUTE_LISTENER_START",
                        "ERROR",
                        "Route listener start rejected",
                        {"route_id": route_id, "error_code": result.get("error_code")},
                    )
                    self._send_json(result, HTTPStatus.CONFLICT)
                    return
                db.add_audit(
                    "ROUTE_LISTENER_START",
                    "INFO",
                    "Route listener started",
                    {"route_id": route_id},
                )
                self._send_json(result)
                return
            if route_id is not None and subpath == "listener/stop":
                result = self._listener_manager().stop_route(route_id)
                db.add_audit(
                    "ROUTE_LISTENER_STOP",
                    "INFO",
                    "Route listener stopped",
                    {"route_id": route_id},
                )
                self._send_json(result)
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
            telegram = self._telegram_service()

            if path == "/api/telegram/credentials":
                result = telegram.clear_credentials()
                db.add_audit(
                    "TELEGRAM_CREDENTIALS_CLEAR",
                    "INFO",
                    "Telegram API credentials cleared from DPAPI vault",
                    {"credentials_saved": False},
                )
                self._send_json(result)
                return

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
