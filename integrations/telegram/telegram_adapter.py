"""Thin Telethon adapter for dashboard login and channel listing."""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass, field
from pathlib import Path

from dashboard_security import resolve_default_data_dir
from typing import Any, Callable

TELETHON_NOT_INSTALLED = "TELETHON_NOT_INSTALLED"
TELEGRAM_CONFIG_MISSING = "TELEGRAM_CONFIG_MISSING"
TELEGRAM_CODE_REQUIRED = "TELEGRAM_CODE_REQUIRED"
TELEGRAM_2FA_REQUIRED = "TELEGRAM_2FA_REQUIRED"
TELEGRAM_AUTH_FAILED = "TELEGRAM_AUTH_FAILED"
TELEGRAM_CONNECTED = "TELEGRAM_CONNECTED"
TELEGRAM_SYNC_FAILED = "TELEGRAM_SYNC_FAILED"
TELEGRAM_NETWORK_ERROR = "TELEGRAM_NETWORK_ERROR"
TELEGRAM_API_ID_INVALID = "TELEGRAM_API_ID_INVALID"
TELEGRAM_PHONE_INVALID = "TELEGRAM_PHONE_INVALID"
TELEGRAM_FLOOD_WAIT = "TELEGRAM_FLOOD_WAIT"
TELEGRAM_CODE_REQUEST_FAILED = "TELEGRAM_CODE_REQUEST_FAILED"
TELEGRAM_SESSION_PATH_ERROR = "TELEGRAM_SESSION_PATH_ERROR"
TELEGRAM_INTERNAL_ERROR = "TELEGRAM_INTERNAL_ERROR"

SESSION_FILENAME = "telegram_dashboard.session"
CREDENTIAL_SOURCE_VAULT = "WINDOWS_DPAPI_VAULT"
CREDENTIAL_SOURCE_ENV = "ENVIRONMENT"
CREDENTIAL_SOURCE_NONE = "NONE"

# Telethon PeerChannel chat_id offset: -(10**12 + channel_id)
TELEGRAM_CHANNEL_PEER_OFFSET = 1_000_000_000_000


@dataclass(frozen=True)
class TelegramEnvConfig:
    api_id: int
    api_hash: str
    session_path: Path


@dataclass(frozen=True)
class TelegramConnectionResult:
    status: str
    error_code: str | None = None
    detail: str | None = None


@dataclass(frozen=True)
class TelegramCodeResult:
    status: str
    phone_code_hash: str
    error_code: str | None = None
    flood_wait_seconds: int | None = None


@dataclass(frozen=True)
class TelegramSignInResult:
    status: str
    error_code: str | None = None
    detail: str | None = None


@dataclass(frozen=True)
class TelegramChannelInfo:
    telegram_channel_id: str
    title: str
    channel_type: str
    username: str | None
    last_message_at_utc: str | None = None


@dataclass
class TelegramAdapter:
    api_id: str
    api_hash: str
    session_path: str
    _client_factory: Callable[..., Any] | None = field(default=None, repr=False)

    async def connect(self) -> TelegramConnectionResult:
        if not is_telethon_available():
            return TelegramConnectionResult(
                status="ERROR",
                error_code=TELETHON_NOT_INSTALLED,
                detail="Install telethon locally: pip install telethon",
            )
        client = self._create_client()
        try:
            await client.connect()
            authorized = await client.is_user_authorized()
            if authorized:
                return TelegramConnectionResult(status=TELEGRAM_CONNECTED)
            return TelegramConnectionResult(status="DISCONNECTED")
        except Exception as exc:  # noqa: BLE001 - adapter boundary
            return TelegramConnectionResult(
                status="ERROR",
                error_code=TELEGRAM_AUTH_FAILED,
                detail=str(exc),
            )
        finally:
            await client.disconnect()

    async def send_code(self, phone: str) -> TelegramCodeResult:
        if not is_telethon_available():
            return TelegramCodeResult(
                status="ERROR",
                phone_code_hash="",
                error_code=TELETHON_NOT_INSTALLED,
            )
        try:
            ensure_session_path_ready(Path(self.session_path))
        except OSError as exc:
            logger_safe_event("TELEGRAM_SESSION_PATH_ERROR")
            return TelegramCodeResult(
                status="ERROR",
                phone_code_hash="",
                error_code=TELEGRAM_SESSION_PATH_ERROR,
            )
        client = self._create_client()
        try:
            await client.connect()
            sent = await client.send_code_request(phone)
            return TelegramCodeResult(
                status="CODE_SENT",
                phone_code_hash=sent.phone_code_hash,
            )
        except Exception as exc:  # noqa: BLE001
            error_code, flood_wait = map_telethon_error(exc)
            return TelegramCodeResult(
                status="ERROR",
                phone_code_hash="",
                error_code=error_code,
                flood_wait_seconds=flood_wait,
            )
        finally:
            await client.disconnect()

    async def sign_in_code(
        self,
        phone: str,
        code: str,
        phone_code_hash: str,
    ) -> TelegramSignInResult:
        if not is_telethon_available():
            return TelegramSignInResult(status="ERROR", error_code=TELETHON_NOT_INSTALLED)
        client = self._create_client()
        try:
            await client.connect()
            try:
                await client.sign_in(phone=phone, code=code, phone_code_hash=phone_code_hash)
            except Exception as exc:  # noqa: BLE001
                if _is_two_factor_required(exc):
                    return TelegramSignInResult(
                        status="TWO_FACTOR_REQUIRED",
                        error_code=TELEGRAM_2FA_REQUIRED,
                    )
                return TelegramSignInResult(
                    status="ERROR",
                    error_code=TELEGRAM_AUTH_FAILED,
                    detail=str(exc),
                )
            return TelegramSignInResult(status=TELEGRAM_CONNECTED)
        finally:
            await client.disconnect()

    async def sign_in_password(self, password: str) -> TelegramSignInResult:
        if not is_telethon_available():
            return TelegramSignInResult(status="ERROR", error_code=TELETHON_NOT_INSTALLED)
        client = self._create_client()
        try:
            await client.connect()
            try:
                await client.sign_in(password=password)
            except Exception as exc:  # noqa: BLE001
                return TelegramSignInResult(
                    status="ERROR",
                    error_code=TELEGRAM_AUTH_FAILED,
                    detail=str(exc),
                )
            return TelegramSignInResult(status=TELEGRAM_CONNECTED)
        finally:
            await client.disconnect()

    async def list_dialogs(self, limit: int = 200) -> list[TelegramChannelInfo]:
        if not is_telethon_available():
            raise RuntimeError(TELETHON_NOT_INSTALLED)
        client = self._create_client()
        channels: list[TelegramChannelInfo] = []
        try:
            await client.connect()
            if not await client.is_user_authorized():
                raise RuntimeError(TELEGRAM_AUTH_FAILED)
            async for dialog in client.iter_dialogs(limit=limit):
                entity = dialog.entity
                channel_type = _classify_entity(entity)
                if channel_type is None:
                    continue
                username = getattr(entity, "username", None)
                last_at = None
                if dialog.message and getattr(dialog.message, "date", None):
                    last_at = dialog.message.date.strftime("%Y-%m-%dT%H:%M:%SZ")
                canonical_id = canonical_channel_key_from_entity(entity)
                raw_id = getattr(entity, "id", dialog.id)
                channels.append(
                    TelegramChannelInfo(
                        telegram_channel_id=canonical_id or str(raw_id),
                        title=str(getattr(entity, "title", dialog.name or "Unknown")),
                        channel_type=channel_type,
                        username=str(username) if username else None,
                        last_message_at_utc=last_at,
                    )
                )
        finally:
            await client.disconnect()
        return channels

    async def disconnect(self) -> None:
        held = getattr(self, "_held_client", None)
        if held is None:
            return None
        try:
            if getattr(held, "is_connected", lambda: False)():
                await held.disconnect()
        except Exception:  # noqa: BLE001 - best-effort disconnect
            return None
        finally:
            self._held_client = None
        return None

    def _create_client(self) -> Any:
        if self._client_factory is not None:
            return self._client_factory(self.session_path, int(self.api_id), self.api_hash)
        from telethon import TelegramClient

        return TelegramClient(self.session_path, int(self.api_id), self.api_hash)


def is_telethon_available() -> bool:
    try:
        import telethon  # noqa: F401
    except ImportError:
        return False
    return True


def resolve_session_path(data_dir: Path) -> Path:
    session_path_raw = os.environ.get("TELEGRAM_SESSION_PATH", "").strip()
    if session_path_raw:
        return Path(session_path_raw).expanduser()
    return data_dir.expanduser().resolve() / SESSION_FILENAME


def resolve_credential_source(data_dir: Path) -> str:
    from dashboard_vault import DashboardCredentialVault

    vault = DashboardCredentialVault(data_dir)
    if vault.has_telegram_credentials():
        return CREDENTIAL_SOURCE_VAULT
    api_id_raw = os.environ.get("TELEGRAM_API_ID", "").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
    if api_id_raw and api_hash:
        return CREDENTIAL_SOURCE_ENV
    return CREDENTIAL_SOURCE_NONE


def load_telegram_config(data_dir: Path) -> TelegramEnvConfig | None:
    from dashboard_vault import DashboardCredentialVault

    api_id_raw = ""
    api_hash = ""

    vault = DashboardCredentialVault(data_dir)
    if vault.has_telegram_credentials():
        loaded = vault.load_telegram_credentials()
        if loaded is not None:
            api_id_raw, api_hash = loaded

    if not api_id_raw or not api_hash:
        api_id_raw = os.environ.get("TELEGRAM_API_ID", "").strip()
        api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()

    session_path = resolve_session_path(data_dir)

    if not api_id_raw or not api_hash:
        return None
    try:
        api_id = int(api_id_raw)
    except ValueError:
        return None
    if api_id <= 0 or not api_hash:
        return None
    return TelegramEnvConfig(
        api_id=api_id,
        api_hash=api_hash,
        session_path=session_path,
    )


def load_telegram_env_config() -> TelegramEnvConfig | None:
    return load_telegram_config(resolve_default_data_dir())


def build_adapter_from_data_dir(data_dir: Path) -> TelegramAdapter | None:
    config = load_telegram_config(data_dir)
    if config is None:
        return None
    return TelegramAdapter(
        api_id=str(config.api_id),
        api_hash=config.api_hash,
        session_path=str(config.session_path),
    )


def build_adapter_from_env() -> TelegramAdapter | None:
    return build_adapter_from_data_dir(resolve_default_data_dir())


def ensure_session_path_ready(session_path: Path) -> Path:
    resolved = session_path.expanduser().resolve()
    resolved.parent.mkdir(parents=True, exist_ok=True)
    return resolved


def canonical_channel_key_from_value(value: int | str | None) -> str | None:
    """Normalize Telethon entity.id or event.chat_id to a shared channel key."""
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    try:
        numeric = int(text)
    except ValueError:
        return None
    if numeric == 0:
        return None
    if numeric < 0:
        abs_value = -numeric
        if abs_value >= TELEGRAM_CHANNEL_PEER_OFFSET:
            channel_id = abs_value - TELEGRAM_CHANNEL_PEER_OFFSET
            if channel_id > 0:
                return str(channel_id)
        return str(abs_value)
    return str(numeric)


def canonical_channel_key_from_entity(entity: object) -> str | None:
    """Canonical key for Telethon Channel / megagroup entities."""
    class_name = entity.__class__.__name__
    entity_id = getattr(entity, "id", None)
    if entity_id is None:
        return None
    if class_name == "Channel":
        return canonical_channel_key_from_value(entity_id)
    if class_name == "Chat":
        numeric = int(entity_id)
        return canonical_channel_key_from_value(-numeric if numeric > 0 else numeric)
    return None


def canonical_channel_key_from_event(event: object) -> str | None:
    """Canonical key from a Telethon NewMessage event."""
    chat_id = getattr(event, "chat_id", None)
    if chat_id is None:
        return None
    return canonical_channel_key_from_value(chat_id)


def validate_listener_session_config(config: TelegramEnvConfig) -> tuple[bool, str | None]:
    """Fail-closed validation for observer listener startup (no login flow)."""
    if not is_telethon_available():
        return False, TELETHON_NOT_INSTALLED
    session_path = config.session_path.expanduser()
    if not session_path.parent.exists():
        return False, TELEGRAM_SESSION_PATH_ERROR
    if not session_path.exists():
        return False, TELEGRAM_AUTH_FAILED
    return True, None


def map_telethon_error(exc: Exception) -> tuple[str, int | None]:
    name = exc.__class__.__name__
    if name in {"ApiIdInvalidError", "ApiIdPublishedFloodError"}:
        return TELEGRAM_API_ID_INVALID, None
    if name in {
        "PhoneNumberInvalidError",
        "PhoneNumberBannedError",
        "PhoneNumberFloodError",
        "PhoneNumberOccupiedError",
    }:
        return TELEGRAM_PHONE_INVALID, None
    if name == "FloodWaitError":
        seconds = int(getattr(exc, "seconds", 0) or 0)
        return TELEGRAM_FLOOD_WAIT, seconds if seconds > 0 else None
    if name in {
        "NetworkMigrateError",
        "PhoneMigrateError",
        "UserMigrateError",
        "TimeoutError",
        "ConnectionError",
        "OSError",
    }:
        return TELEGRAM_NETWORK_ERROR, None
    if name == "PhoneCodeHashEmptyError":
        return TELEGRAM_CODE_REQUEST_FAILED, None
    return TELEGRAM_CODE_REQUEST_FAILED, None


def logger_safe_event(event: str) -> None:
    """Placeholder for secret-free diagnostic logging."""
    _ = event


def run_telegram_async(coro: Any) -> Any:
    try:
        return asyncio.run(coro)
    except RuntimeError as exc:
        if "asyncio.run() cannot be called from a running event loop" not in str(exc):
            raise
        loop = asyncio.new_event_loop()
        try:
            return loop.run_until_complete(coro)
        finally:
            loop.close()


def _is_two_factor_required(exc: Exception) -> bool:
    name = exc.__class__.__name__
    if name == "SessionPasswordNeededError":
        return True
    try:
        from telethon.errors import SessionPasswordNeededError

        return isinstance(exc, SessionPasswordNeededError)
    except ImportError:
        return False


def _classify_entity(entity: object) -> str | None:
    class_name = entity.__class__.__name__
    if class_name == "Channel":
        if getattr(entity, "megagroup", False):
            return "supergroup"
        if getattr(entity, "broadcast", False):
            return "channel"
        return "channel"
    if class_name == "Chat":
        return "group"
    return None
