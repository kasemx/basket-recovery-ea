"""Thin Telethon adapter for dashboard login and channel listing."""

from __future__ import annotations

import asyncio
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Protocol

TELETHON_NOT_INSTALLED = "TELETHON_NOT_INSTALLED"
TELEGRAM_CONFIG_MISSING = "TELEGRAM_CONFIG_MISSING"
TELEGRAM_CODE_REQUIRED = "TELEGRAM_CODE_REQUIRED"
TELEGRAM_2FA_REQUIRED = "TELEGRAM_2FA_REQUIRED"
TELEGRAM_AUTH_FAILED = "TELEGRAM_AUTH_FAILED"
TELEGRAM_CONNECTED = "TELEGRAM_CONNECTED"
TELEGRAM_SYNC_FAILED = "TELEGRAM_SYNC_FAILED"


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
    detail: str | None = None


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
        client = self._create_client()
        try:
            await client.connect()
            sent = await client.send_code_request(phone)
            return TelegramCodeResult(
                status="CODE_SENT",
                phone_code_hash=sent.phone_code_hash,
            )
        except Exception as exc:  # noqa: BLE001
            return TelegramCodeResult(
                status="ERROR",
                phone_code_hash="",
                error_code=TELEGRAM_AUTH_FAILED,
                detail=str(exc),
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
                channels.append(
                    TelegramChannelInfo(
                        telegram_channel_id=str(getattr(entity, "id", dialog.id)),
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


def load_telegram_env_config() -> TelegramEnvConfig | None:
    api_id_raw = os.environ.get("TELEGRAM_API_ID", "").strip()
    api_hash = os.environ.get("TELEGRAM_API_HASH", "").strip()
    session_path_raw = os.environ.get("TELEGRAM_SESSION_PATH", "").strip()
    if not api_id_raw or not api_hash or not session_path_raw:
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
        session_path=Path(session_path_raw).expanduser(),
    )


def build_adapter_from_env() -> TelegramAdapter | None:
    config = load_telegram_env_config()
    if config is None:
        return None
    return TelegramAdapter(
        api_id=str(config.api_id),
        api_hash=config.api_hash,
        session_path=str(config.session_path),
    )


def run_telegram_async(coro: Any) -> Any:
    return asyncio.run(coro)


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
