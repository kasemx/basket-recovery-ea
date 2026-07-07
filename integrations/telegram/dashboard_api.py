"""HTTP API routing for the local Telegram route dashboard."""

from __future__ import annotations

import json
import logging
import os
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
from dashboard_signal_history import (
    apply_history_filters,
    build_history_item,
    enrich_summary_with_execution,
    history_response,
    paginate_items,
)
from mt5_target_service import (
    build_targets_summary,
    compute_instance_fields,
    create_target_from_discovery,
    filter_mt5_targets,
    normalize_create_payload,
    paginate_mt5_targets,
    prepare_target_row_fields,
    project_mt5_target,
    validate_target_registration,
    verify_target,
)
from mt5_terminal_discovery import (
    discover_terminal_paths,
    discovery_record_target_source,
    get_discovery_store,
    list_discoveries,
    parse_terminal_path_lines,
    project_discovery,
    project_scan,
    refresh_discovery_record,
)
from dashboard_store import DashboardDatabase
from listener_worker_client import ListenerWorkerClient
from route_listener_service import (
    LISTENER_DETAILS_DETECTED,
    LISTENER_PUBLISH_FAILED,
    LISTENER_PUBLISH_READY,
    LISTENER_PUBLISH_SKIPPED,
    LISTENER_SEED_DETECTED,
    LISTENER_STOPPED,
    LISTENER_WAITING,
)
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

USER_ERROR_MESSAGES: dict[str, str] = {
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


SIGNAL_META_MARKER = "|signal_meta="
SIGNAL_SUMMARY_ALLOWED_KEYS = frozenset(
    {
        "symbol",
        "side",
        "entry_low",
        "entry_high",
        "stop_loss",
        "take_profits",
    }
)
SIGNAL_EVENT_STATUSES = (
    LISTENER_PUBLISH_READY,
    LISTENER_PUBLISH_SKIPPED,
    LISTENER_PUBLISH_FAILED,
    LISTENER_DETAILS_DETECTED,
    LISTENER_SEED_DETECTED,
)


def _listener_dry_run_enabled() -> bool:
    return os.environ.get("DASHBOARD_ROUTE_LISTENER_DRY_RUN", "1") == "1"


def _extract_signal_meta(safe_summary: str | None) -> dict[str, Any] | None:
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
    for key in SIGNAL_SUMMARY_ALLOWED_KEYS:
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


def _normalize_symbol(symbol: str | None) -> str | None:
    if not symbol:
        return None
    lowered = symbol.strip().lower()
    if lowered in ("gold", "xauusd"):
        return "XAUUSD"
    return symbol.strip().upper()


def _normalize_side(side: str | None) -> str | None:
    if not side:
        return None
    normalized = side.strip().upper()
    if normalized in ("BUY", "SELL"):
        return normalized
    return None


def _signal_user_message(status: str, *, dry_run: bool) -> str:
    if status == LISTENER_WAITING:
        return "Sinyal bekleniyor."
    if status == LISTENER_SEED_DETECTED:
        return "Sinyal eksik, detay bekleniyor."
    if status == LISTENER_DETAILS_DETECTED:
        return "Sinyal ayrıntıları alındı."
    if status == LISTENER_PUBLISH_READY:
        if dry_run:
            return "Sinyal başarıyla algılandı. MT5 için simülasyon hazırlandı."
        return "Sinyal başarıyla algılandı."
    if status == LISTENER_PUBLISH_SKIPPED:
        return "Aynı sinyal tekrar geldi, tekrar işlenmedi."
    if status == LISTENER_PUBLISH_FAILED:
        return "Gönderim başarısız."
    if status == LISTENER_STOPPED:
        return "Takip kapalı. Yeni sinyaller dinlenmiyor."
    return "Sinyal durumu güncellendi."


def _signal_headline(status: str, *, dry_run: bool) -> str:
    if status == LISTENER_WAITING:
        return "Sinyal Bekleniyor"
    if status in (LISTENER_SEED_DETECTED, LISTENER_DETAILS_DETECTED):
        return "Sinyal Algılandı"
    if status == LISTENER_PUBLISH_READY:
        return "Simülasyon Başarılı" if dry_run else "Sinyal Hazır"
    if status == LISTENER_PUBLISH_SKIPPED:
        return "Tekrar Sinyal — İşlenmedi"
    if status == LISTENER_PUBLISH_FAILED:
        return "Gönderim Sorunu"
    if status == LISTENER_STOPPED:
        return "Takip Kapalı"
    return "Sinyal Durumu"


def _resolve_signal_status(events: list[dict[str, Any]], listener_status: str | None) -> str | None:
    for event in events:
        status = str(event.get("status", ""))
        if status in SIGNAL_EVENT_STATUSES:
            return status
    if listener_status in SIGNAL_EVENT_STATUSES:
        return listener_status
    return None


def build_safe_signal_timeline(events: list[dict[str, Any]], *, limit: int = 10) -> list[dict[str, Any]]:
    timeline: list[dict[str, Any]] = []
    for event in events[:limit]:
        timeline.append(
            {
                "event_type": event.get("event_type"),
                "status": event.get("status"),
                "fingerprint_short": event.get("fingerprint_short"),
                "seed_bytes": event.get("seed_bytes"),
                "details_bytes": event.get("details_bytes"),
                "created_at_utc": event.get("created_at_utc"),
            }
        )
    return timeline


def build_last_signal_summary(
    route: dict[str, Any],
    events: list[dict[str, Any]],
    *,
    listener_status: str | None,
    dry_run: bool,
) -> dict[str, Any] | None:
    signal_status = _resolve_signal_status(events, listener_status)
    if signal_status is None:
        return None

    meta: dict[str, Any] | None = None
    received_at: str | None = None
    for event in events:
        if meta is None:
            meta = _extract_signal_meta(event.get("safe_summary"))
        event_status = str(event.get("status", ""))
        if event_status in SIGNAL_EVENT_STATUSES:
            received_at = str(event.get("created_at_utc") or "") or None
            if meta is not None:
                break
    if received_at is None and events:
        received_at = str(events[0].get("created_at_utc") or "") or None

    summary: dict[str, Any] = {
        "status": signal_status,
        "headline": _signal_headline(signal_status, dry_run=dry_run),
        "symbol": _normalize_symbol(meta.get("symbol") if meta else None),
        "side": _normalize_side(meta.get("side") if meta else None),
        "entry_low": meta.get("entry_low") if meta else None,
        "entry_high": meta.get("entry_high") if meta else None,
        "stop_loss": meta.get("stop_loss") if meta else None,
        "take_profits": meta.get("take_profits") if meta else None,
        "received_at_utc": received_at,
        "channel_title": route.get("channel_title"),
        "target_name": route.get("target_name"),
        "is_dry_run": dry_run,
        "user_message": _signal_user_message(signal_status, dry_run=dry_run),
    }
    return enrich_summary_with_execution(summary, dry_run=dry_run)


def query_signal_history(
    database: DashboardDatabase,
    query: dict[str, list[str]],
    *,
    dry_run: bool,
) -> dict[str, Any]:
    def first(key: str, default: str | None = None) -> str | None:
        values = query.get(key)
        if not values or values[0] == "":
            return default
        return values[0]

    page = int(first("page", "1") or "1")
    page_size = int(first("page_size", "20") or "20")
    channel_raw = first("channel_id")
    target_raw = first("target_id")
    channel_id = int(channel_raw) if channel_raw and channel_raw.isdigit() else None
    target_id = int(target_raw) if target_raw and target_raw.isdigit() else None
    rows = database.list_signal_history_candidates(
        date_from=first("from"),
        date_to=first("to"),
        channel_id=channel_id,
        target_id=target_id,
    )
    items = [build_history_item(row, dry_run=dry_run) for row in rows]
    items = apply_history_filters(
        items,
        symbol=first("symbol"),
        side=first("side"),
        signal_status=first("signal_status"),
        execution_status=first("execution_status"),
        outcome=first("outcome"),
        pnl_state=first("pnl_state"),
    )
    page_items, total = paginate_items(items, page=page, page_size=page_size)
    return history_response(page_items, page=max(page, 1), page_size=min(max(page_size, 1), 100), total=total)


@dataclass
class DashboardContext:
    host: str
    port: int
    data_dir: Path
    dashboard_dir: Path
    database: DashboardDatabase
    telegram_service: TelegramService | None = None
    listener_worker_client: ListenerWorkerClient | None = None


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

    def verify_code(self, db: DashboardDatabase, code: str, phone: str = "") -> dict[str, Any]:
        if not self.telethon_available():
            return {"status": "ERROR", "error_code": TELETHON_NOT_INSTALLED}
        phone_code_hash = db.get_phone_code_hash()
        if not phone_code_hash:
            raise DashboardValidationError("Request a login code before verification")
        resolved_phone = self.resolve_request_phone(phone)
        adapter = self._require_adapter()
        result = run_telegram_async(
            adapter.sign_in_code(resolved_phone, code, phone_code_hash)
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

    def _listener_client(self) -> ListenerWorkerClient:
        if self.context.listener_worker_client is None:
            self.context.listener_worker_client = ListenerWorkerClient(
                database=self.context.database,
                data_dir=self.context.data_dir,
            )
        return self.context.listener_worker_client

    def _parse_listener_worker_path(self, path: str) -> str | None:
        if path == "/api/listener/worker/status":
            return "status"
        if path == "/api/listener/worker/start":
            return "start"
        if path == "/api/listener/worker/stop":
            return "stop"
        return None

    def _parse_route_listener_path(self, path: str) -> tuple[int | None, str | None]:
        match = re.match(
            r"^/api/routes/(\d+)(?:/(listener/start|listener/stop|listener-status|events))?$",
            path,
        )
        if not match:
            return None, None
        return int(match.group(1)), match.group(2)

    def _enrich_routes(self, routes: list[dict[str, Any]]) -> list[dict[str, Any]]:
        client = self._listener_client()
        dry_run = client.status_payload().get("dry_run", _listener_dry_run_enabled())
        enriched: list[dict[str, Any]] = []
        for route in routes:
            item = dict(route)
            status = client.route_listener_status(int(route["id"]))
            item["listener"] = status or {
                "route_id": route["id"],
                "running": False,
                "listener_status": LISTENER_STOPPED,
            }
            events = self.context.database.list_route_events(int(route["id"]), 50)
            listener_status = item["listener"].get("listener_status")
            item["last_signal_summary"] = build_last_signal_summary(
                item,
                events,
                listener_status=listener_status,
                dry_run=bool(dry_run),
            )
            item["signal_timeline"] = build_safe_signal_timeline(events)
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

    def _parse_mt5_target_path(self, path: str) -> tuple[int | None, str | None]:
        if path == "/api/mt5-targets":
            return None, None
        match = re.match(r"^/api/mt5-targets/(\d+)(?:/(verify|verification|disable))?$", path)
        if not match:
            return None, None
        return int(match.group(1)), match.group(2)

    def _parse_mt5_discovery_path(self, path: str) -> tuple[int | None, str | None]:
        if path == "/api/mt5-terminals/discover":
            return None, None
        if path == "/api/mt5-terminals/discoveries":
            return None, None
        match = re.match(
            r"^/api/mt5-terminals/discoveries/(\d+)(?:/(add-target|refresh))?$",
            path,
        )
        if not match:
            return None, None
        return int(match.group(1)), match.group(2)

    def _mt5_targets_response(self, query: dict[str, list[str]] | None = None) -> dict[str, Any]:
        rows = self.context.database.list_targets()
        summary = build_targets_summary(rows)
        projected = [project_mt5_target(row, rows) for row in rows]
        params = query or {}

        def first(key: str, default: str | None = None) -> str | None:
            values = params.get(key)
            if not values or values[0] == "":
                return default
            return values[0]

        enabled_raw = first("is_enabled")
        is_enabled = None
        if enabled_raw in ("0", "1"):
            is_enabled = enabled_raw == "1"
        account_type = first("account_type")
        search = first("search")
        page = int(first("page", "1") or "1")
        page_size = int(first("page_size", "20") or "20")

        filtered = filter_mt5_targets(
            projected,
            is_enabled=is_enabled,
            account_type=account_type,
            search=search,
        )
        page_items, total = paginate_mt5_targets(filtered, page=page, page_size=page_size)
        return {
            "targets": page_items,
            "summary": summary,
            "page": max(page, 1),
            "page_size": min(max(page_size, 1), 100),
            "total": total,
        }

    def _mt5_target_verification_response(self, target_id: int) -> dict[str, Any]:
        row = self.context.database.get_target(target_id)
        if row is None:
            raise DashboardValidationError("Target not found")
        projected = project_mt5_target(row, self.context.database.list_targets())
        return {
            "target_id": target_id,
            "verification": {
                "status": projected.get("verification_status"),
                "message": projected.get("verification_message_safe"),
                "last_verified_at_utc": projected.get("last_verified_at_utc"),
                "warnings": projected.get("warnings", []),
                "detected_account_login_masked": projected.get("detected_account_login_masked"),
                "detected_trade_mode_label": projected.get("detected_trade_mode_label"),
                "xauusd_status": projected.get("xauusd_status"),
            },
        }

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        try:
            if path == "/api/health":
                telegram = self.context.database.get_telegram_status()
                self._send_json(
                    {
                        "ok": True,
                        "server": "telegram-route-dashboard",
                        "api_version": "9e.0.2",
                        "host": self.context.host,
                        "telegram_status": telegram["status"],
                        "features": {
                            "mt5_targets": True,
                            "mt5_terminal_discovery": True,
                            "listener_worker": True,
                            "signal_history": True,
                        },
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
            if path == "/api/mt5-targets":
                query = parse_qs(urlparse(self.path).query)
                self._send_json(self._mt5_targets_response(query))
                return
            if path == "/api/mt5-terminals/discoveries":
                query = parse_qs(urlparse(self.path).query)
                scan_id = query.get("scan_id", [None])[0]
                self._send_json(list_discoveries(scan_id))
                return
            mt5_target_id, mt5_subpath = self._parse_mt5_target_path(path)
            if mt5_target_id is not None and mt5_subpath == "verification":
                self._send_json(self._mt5_target_verification_response(mt5_target_id))
                return
            if path == "/api/listener/status":
                self._send_json(self._listener_client().status_payload())
                return
            worker_subpath = self._parse_listener_worker_path(path)
            if worker_subpath == "status":
                self._send_json({"worker": self._listener_client().worker_status_payload()})
                return
            route_id, subpath = self._parse_route_listener_path(path)
            if route_id is not None and subpath == "listener-status":
                status = self._listener_client().route_listener_status(route_id)
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
            if path == "/api/signal-history":
                query = parse_qs(urlparse(self.path).query)
                payload = query_signal_history(
                    self.context.database,
                    query,
                    dry_run=bool(self._listener_client().status_payload().get("dry_run", _listener_dry_run_enabled())),
                )
                self._send_json(payload)
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
                reject_literal_credentials(payload, allowed=frozenset({"code", "phone"}))
                code = str(payload.get("code", "")).strip()
                if not code:
                    raise DashboardValidationError("Verification code is required")
                phone = str(payload.get("phone", "")).strip()
                result = telegram.verify_code(db, code, phone)
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

            if path == "/api/mt5-targets":
                reject_literal_credentials(payload)
                normalized = normalize_create_payload(payload)
                rows = db.list_targets()
                validate_target_registration(rows, normalized)
                normalized.update(prepare_target_row_fields(normalized))
                target = db.create_mt5_target(normalized)
                rows = db.list_targets()
                projected = project_mt5_target(target, rows)
                db.add_audit(
                    "MT5_TARGET_CREATE",
                    "INFO",
                    f"Created MT5 target {target['name']}",
                    {"target_id": target["id"], "observer_only": 1},
                )
                self._send_json({"target": projected}, HTTPStatus.CREATED)
                return

            if path == "/api/mt5-terminals/discover":
                reject_literal_credentials(payload)
                paths = payload.get("terminal_paths")
                if not isinstance(paths, list):
                    text = str(payload.get("paths_text") or "").strip()
                    paths = parse_terminal_path_lines(text)
                else:
                    paths = [str(item).strip() for item in paths if str(item).strip()]
                if not paths:
                    raise DashboardValidationError("En az bir terminal yolu gerekli.")
                scan = discover_terminal_paths(paths, existing_targets=db.list_targets())
                db.add_audit(
                    "MT5_TERMINAL_DISCOVER",
                    "INFO",
                    "MT5 terminal discovery scan completed",
                    {
                        "scan_id": scan.scan_id,
                        "path_count": len(paths),
                        "discovery_count": len(scan.discoveries),
                    },
                )
                self._send_json(project_scan(scan))
                return

            discovery_id, discovery_subpath = self._parse_mt5_discovery_path(path)
            if discovery_id is not None and discovery_subpath == "add-target":
                reject_literal_credentials(payload)
                record = get_discovery_store().get_record(discovery_id)
                if record is None:
                    raise DashboardValidationError("Discovery not found")
                display_name = str(payload.get("display_name") or "").strip() or None
                source = discovery_record_target_source(record)
                target = create_target_from_discovery(
                    db,
                    source,
                    display_name=display_name,
                )
                db.add_audit(
                    "MT5_TARGET_CREATE_FROM_DISCOVERY",
                    "INFO",
                    f"Created MT5 target from discovery {discovery_id}",
                    {"target_id": target["id"], "discovery_id": discovery_id},
                )
                self._send_json({"target": target, "discovery": project_discovery(record)})
                return
            if discovery_id is not None and discovery_subpath == "refresh":
                reject_literal_credentials(payload)
                record = refresh_discovery_record(
                    discovery_id,
                    existing_targets=db.list_targets(),
                )
                db.add_audit(
                    "MT5_TERMINAL_DISCOVERY_REFRESH",
                    "INFO",
                    f"Refreshed MT5 discovery {discovery_id}",
                    {"discovery_id": discovery_id},
                )
                self._send_json({"discovery": project_discovery(record)})
                return

            mt5_target_id, mt5_subpath = self._parse_mt5_target_path(path)
            if mt5_target_id is not None and mt5_subpath == "verify":
                reject_literal_credentials(payload)
                result = verify_target(db, mt5_target_id)
                db.add_audit(
                    "MT5_TARGET_VERIFY",
                    "INFO",
                    "MT5 target read-only verification completed",
                    {
                        "target_id": mt5_target_id,
                        "verification_status": result["verification"]["status"],
                    },
                )
                self._send_json(result)
                return
            if mt5_target_id is not None and mt5_subpath == "disable":
                reject_literal_credentials(payload)
                target = db.disable_target(mt5_target_id)
                rows = db.list_targets()
                projected = project_mt5_target(target, rows)
                db.add_audit(
                    "MT5_TARGET_DISABLE",
                    "INFO",
                    f"Disabled MT5 target {mt5_target_id}",
                    {"target_id": mt5_target_id},
                )
                self._send_json({"target": projected})
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

            worker_subpath = self._parse_listener_worker_path(path)
            if worker_subpath == "start":
                result = self._listener_client().start_worker()
                db.add_audit(
                    "LISTENER_WORKER_START",
                    "INFO",
                    "Telegram listener worker start requested",
                    {"worker_state": result.get("worker", {}).get("state")},
                )
                self._send_json(result)
                return
            if worker_subpath == "stop":
                result = self._listener_client().stop_worker()
                db.add_audit(
                    "LISTENER_WORKER_STOP",
                    "INFO",
                    "Telegram listener worker stop requested",
                    {"worker_state": result.get("worker", {}).get("state")},
                )
                self._send_json(result)
                return

            route_id, subpath = self._parse_route_listener_path(path)
            if route_id is not None and subpath == "listener/start":
                result = self._listener_client().start_route(route_id)
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
                result = self._listener_client().stop_route(route_id)
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

            mt5_target_id, mt5_subpath = self._parse_mt5_target_path(path)
            if mt5_target_id is not None and mt5_subpath is None:
                existing = db.get_target(mt5_target_id)
                if existing is None:
                    raise DashboardValidationError("Target not found")
                rows = db.list_targets()
                validate_target_registration(rows, payload, target_id=mt5_target_id)
                target = db.update_target(mt5_target_id, payload)
                instance_fields = compute_instance_fields(target)
                if instance_fields.get("terminal_instance_key") != target.get("terminal_instance_key"):
                    target = db.update_target(mt5_target_id, instance_fields)
                rows = db.list_targets()
                projected = project_mt5_target(target, rows)
                db.add_audit(
                    "MT5_TARGET_UPDATE",
                    "INFO",
                    f"Updated MT5 target {mt5_target_id}",
                    {"target_id": mt5_target_id, "fields": sorted(payload.keys())},
                )
                self._send_json({"target": projected})
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
