"""Dashboard route listener — observer-only Telegram to AtomicPublisher bridge."""

from __future__ import annotations

import asyncio
import os
import threading
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from dashboard_security import utc_now_iso
from dashboard_store import DashboardDatabase
from fasttrack_file_bridge import (
    AtomicPublisher,
    BridgeLogger,
    BridgeValidationError,
    TelegramInboundMessage,
    TelegramMessageHandler,
    TelegramPairMatcher,
    classify_telegram_text,
    format_safe_summary_with_signal_meta,
    normalize_telegram_event,
    raw_message_hash,
    resolve_root,
    short_fingerprint,
)
from telegram_adapter import (
    TELEGRAM_AUTH_FAILED,
    TELEGRAM_CONFIG_MISSING,
    TELEGRAM_SESSION_PATH_ERROR,
    TELETHON_NOT_INSTALLED,
    TelegramEnvConfig,
    canonical_channel_key_from_event,
    canonical_channel_key_from_value,
    is_telethon_available,
    load_telegram_config,
    validate_listener_session_config,
)

LISTENER_WAITING = "WAITING"
LISTENER_SEED_DETECTED = "SEED_DETECTED"
LISTENER_DETAILS_DETECTED = "DETAILS_DETECTED"
LISTENER_PUBLISH_READY = "PUBLISH_READY"
LISTENER_PUBLISH_SKIPPED = "PUBLISH_SKIPPED"
LISTENER_PUBLISH_FAILED = "PUBLISH_FAILED"
LISTENER_STOPPED = "LISTENER_STOPPED"

START_ERROR_NOT_CONNECTED = "LISTENER_TELEGRAM_NOT_CONNECTED"
START_ERROR_TRACKING_OFF = "LISTENER_CHANNEL_TRACKING_OFF"
START_ERROR_ROUTE_DISABLED = "LISTENER_ROUTE_DISABLED"
START_ERROR_TARGET_DISABLED = "LISTENER_TARGET_DISABLED"
START_ERROR_NOT_OBSERVER = "LISTENER_TARGET_NOT_OBSERVER"
START_ERROR_INVALID_MODE = "LISTENER_ROUTE_MODE_INVALID"
START_ERROR_NOT_FOUND = "LISTENER_ROUTE_NOT_FOUND"
START_ERROR_TELETHON_CONFIG = "LISTENER_TELETHON_CONFIG_MISSING"
START_ERROR_TELETHON_SESSION = "LISTENER_TELETHON_SESSION_UNAUTHORIZED"
START_ERROR_TELETHON_START = "LISTENER_TELETHON_START_FAILED"

START_ERROR_MESSAGES_TR = {
    START_ERROR_NOT_CONNECTED: "Telegram bağlantısı gerekli.",
    START_ERROR_TRACKING_OFF: "Kanal takibi kapalı.",
    START_ERROR_ROUTE_DISABLED: "Yönlendirme aktif değil.",
    START_ERROR_TARGET_DISABLED: "MT5 hedefi aktif değil.",
    START_ERROR_NOT_OBSERVER: "MT5 hedefi yalnız izleme modunda değil.",
    START_ERROR_INVALID_MODE: "Bu yönlendirme yalnız izleme modunda olmalı.",
    START_ERROR_NOT_FOUND: "Yönlendirme bulunamadı.",
    START_ERROR_TELETHON_CONFIG: "Telegram yapılandırması eksik.",
    START_ERROR_TELETHON_SESSION: "Telegram oturumu yetkili değil.",
    START_ERROR_TELETHON_START: "Telegram dinleyicisi başlatılamadı.",
}


@dataclass(frozen=True)
class RouteStartContext:
    route_id: int
    route_name: str
    channel_id: int
    telegram_channel_id: str
    telegram_channel_key: str
    channel_title: str
    target_id: int
    target_name: str
    file_common_root: str
    seed_filename: str
    details_filename: str
    observer_only: bool
    is_tracking: bool
    route_enabled: bool
    target_enabled: bool
    route_mode: str


@dataclass
class RouteRuntime:
    context: RouteStartContext
    handler: TelegramMessageHandler
    publisher: AtomicPublisher
    logger: BridgeLogger
    seen_raw_hashes: set[str] = field(default_factory=set)


TelethonClientFactory = Callable[[TelegramEnvConfig], Any]


class TelethonRouteListenerBridge:
    """Dedicated asyncio thread + single Telethon client for dashboard route listener."""

    def __init__(
        self,
        *,
        manager: RouteListenerManager,
        data_dir: Path,
        client_factory: TelethonClientFactory | None = None,
        startup_timeout_seconds: float = 10.0,
    ) -> None:
        self._manager = manager
        self._data_dir = data_dir
        self._client_factory = client_factory
        self._startup_timeout_seconds = startup_timeout_seconds
        self._lock = threading.RLock()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._client: Any | None = None
        self._handler: Callable[..., Any] | None = None
        self._connected = False
        self._start_error_code: str | None = None
        self._startup_event = threading.Event()
        self._shutdown_async_event: asyncio.Event | None = None

    def is_connected(self) -> bool:
        with self._lock:
            return self._connected

    def start_error_code(self) -> str | None:
        with self._lock:
            return self._start_error_code

    def ensure_started(self) -> str | None:
        with self._lock:
            if self._connected and self._client is not None:
                return None
            if self._thread is not None and self._thread.is_alive():
                self._startup_event.wait(timeout=self._startup_timeout_seconds)
                return self._start_error_code

            config = load_telegram_config(self._data_dir)
            if config is None:
                self._start_error_code = START_ERROR_TELETHON_CONFIG
                return self._start_error_code

            ok, error_code = validate_listener_session_config(config)
            if not ok:
                mapped = {
                    TELETHON_NOT_INSTALLED: START_ERROR_TELETHON_START,
                    TELEGRAM_SESSION_PATH_ERROR: START_ERROR_TELETHON_SESSION,
                    TELEGRAM_AUTH_FAILED: START_ERROR_TELETHON_SESSION,
                }.get(error_code or "", START_ERROR_TELETHON_START)
                self._start_error_code = mapped
                return self._start_error_code

            self._startup_event.clear()
            self._start_error_code = None
            self._thread = threading.Thread(
                target=self._thread_main,
                args=(config,),
                name="dashboard-telethon-listener",
                daemon=True,
            )
            self._thread.start()

        if not self._startup_event.wait(timeout=self._startup_timeout_seconds):
            with self._lock:
                self._start_error_code = START_ERROR_TELETHON_START
            self.shutdown()
            return START_ERROR_TELETHON_START
        return self.start_error_code()

    def shutdown(self) -> None:
        loop: asyncio.AbstractEventLoop | None
        thread: threading.Thread | None
        with self._lock:
            loop = self._loop
            shutdown_event = self._shutdown_async_event
            thread = self._thread
        if loop is not None and shutdown_event is not None:
            loop.call_soon_threadsafe(shutdown_event.set)
        if thread is not None:
            thread.join(timeout=self._startup_timeout_seconds)
        with self._lock:
            self._thread = None
            self._loop = None
            self._client = None
            self._handler = None
            self._connected = False
            self._shutdown_async_event = None

    def _thread_main(self, config: TelegramEnvConfig) -> None:
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        with self._lock:
            self._loop = loop
        try:
            loop.run_until_complete(self._async_main(config))
        finally:
            with self._lock:
                self._connected = False
                self._client = None
                self._handler = None
                self._loop = None
            loop.close()

    async def _async_main(self, config: TelegramEnvConfig) -> None:
        client = self._create_client(config)
        try:
            await client.connect()
            if not await client.is_user_authorized():
                with self._lock:
                    self._start_error_code = START_ERROR_TELETHON_SESSION
                await client.disconnect()
                self._startup_event.set()
                return

            from telethon import events

            @client.on(events.NewMessage())
            async def on_new_message(event: object) -> None:
                channel_key = canonical_channel_key_from_event(event)
                if channel_key is None:
                    return
                if not self._manager.has_active_channel(channel_key):
                    return
                try:
                    inbound = normalize_telegram_event(event)
                    self._manager.deliver_inbound_message(channel_key, inbound)
                except Exception:  # noqa: BLE001 - handler boundary
                    self._manager.record_telethon_handler_error(channel_key)

            with self._lock:
                self._client = client
                self._handler = on_new_message
                self._connected = True
                self._shutdown_async_event = asyncio.Event()

            self._startup_event.set()
            await self._shutdown_async_event.wait()

            if self._handler is not None:
                client.remove_event_handler(self._handler)
            await client.disconnect()
        except Exception:  # noqa: BLE001 - startup boundary
            with self._lock:
                self._start_error_code = START_ERROR_TELETHON_START
            try:
                await client.disconnect()
            except Exception:  # noqa: BLE001
                pass
            self._startup_event.set()

    def _create_client(self, config: TelegramEnvConfig) -> Any:
        if self._client_factory is not None:
            return self._client_factory(config)
        from telethon import TelegramClient

        return TelegramClient(
            str(config.session_path),
            config.api_id,
            config.api_hash,
        )


class RouteListenerManager:
    """In-process route listener registry with optional Telethon hook."""

    def __init__(
        self,
        *,
        database: DashboardDatabase,
        data_dir: Path,
        dry_run: bool = True,
        telethon_enabled: bool = False,
        pair_timeout_seconds: int = 900,
        telethon_client_factory: TelethonClientFactory | None = None,
        normalize_stale_states: bool = True,
        stale_state_reason: str = "Dashboard yeniden başlatıldı; dinleme durduruldu.",
    ) -> None:
        self._database = database
        self._data_dir = data_dir
        self._dry_run = dry_run
        self._telethon_enabled = telethon_enabled
        self._pair_timeout_seconds = pair_timeout_seconds
        self._telethon_client_factory = telethon_client_factory
        self._lock = threading.RLock()
        self._active: dict[int, RouteRuntime] = {}
        self._telethon_bridge: TelethonRouteListenerBridge | None = None
        if normalize_stale_states:
            self._normalize_stale_listener_states(reason_message=stale_state_reason)

    def status_payload(self) -> dict[str, Any]:
        with self._lock:
            active_ids = sorted(self._active.keys())
            telethon_connected = (
                self._telethon_bridge.is_connected() if self._telethon_bridge is not None else False
            )
        return {
            "active_route_count": len(active_ids),
            "active_route_ids": active_ids,
            "dry_run": self._dry_run,
            "telethon_hook_enabled": self._telethon_enabled,
            "telethon_connected": telethon_connected,
        }

    def route_listener_status(self, route_id: int) -> dict[str, Any] | None:
        if self._database.get_route_start_context(route_id) is None:
            return None
        row = self._database.get_route_listener_state(route_id)
        with self._lock:
            running = route_id in self._active
        if row is None:
            return {
                "route_id": route_id,
                "running": running,
                "listener_status": LISTENER_STOPPED,
                "last_signal_status": None,
                "last_error_code": None,
                "last_publish_at_utc": None,
                "started_at_utc": None,
                "updated_at_utc": None,
            }
        return {
            "route_id": route_id,
            "running": running,
            "listener_status": row.get("listener_status", LISTENER_STOPPED),
            "last_signal_status": row.get("last_signal_status"),
            "last_error_code": row.get("last_error_code"),
            "last_publish_at_utc": row.get("last_publish_at_utc"),
            "started_at_utc": row.get("started_at_utc"),
            "updated_at_utc": row.get("updated_at_utc"),
        }

    def has_active_channel(self, channel_key: str) -> bool:
        with self._lock:
            return any(
                runtime.context.telegram_channel_key == channel_key
                for runtime in self._active.values()
            )

    def validate_start(self, route_id: int) -> tuple[RouteStartContext | None, str | None]:
        ctx_row = self._database.get_route_start_context(route_id)
        if ctx_row is None:
            return None, START_ERROR_NOT_FOUND
        telegram = self._database.get_telegram_status()
        if telegram.get("status") not in ("CONNECTED", "TELEGRAM_CONNECTED"):
            return None, START_ERROR_NOT_CONNECTED
        if str(ctx_row.get("route_mode", "")).upper() != "OBSERVER_ONLY":
            return None, START_ERROR_INVALID_MODE
        if not ctx_row.get("is_tracking"):
            return None, START_ERROR_TRACKING_OFF
        if not ctx_row.get("route_enabled"):
            return None, START_ERROR_ROUTE_DISABLED
        if not ctx_row.get("target_enabled"):
            return None, START_ERROR_TARGET_DISABLED
        if not ctx_row.get("observer_only"):
            return None, START_ERROR_NOT_OBSERVER
        raw_channel_id = str(ctx_row["telegram_channel_id"])
        channel_key = canonical_channel_key_from_value(raw_channel_id) or raw_channel_id
        context = RouteStartContext(
            route_id=route_id,
            route_name=str(ctx_row["route_name"]),
            channel_id=int(ctx_row["channel_id"]),
            telegram_channel_id=raw_channel_id,
            telegram_channel_key=channel_key,
            channel_title=str(ctx_row["channel_title"]),
            target_id=int(ctx_row["target_id"]),
            target_name=str(ctx_row["target_name"]),
            file_common_root=str(ctx_row["file_common_root"]),
            seed_filename=str(ctx_row["seed_filename"]),
            details_filename=str(ctx_row["details_filename"]),
            observer_only=bool(ctx_row["observer_only"]),
            is_tracking=bool(ctx_row["is_tracking"]),
            route_enabled=bool(ctx_row["route_enabled"]),
            target_enabled=bool(ctx_row["target_enabled"]),
            route_mode=str(ctx_row["route_mode"]),
        )
        return context, None

    def start_route(self, route_id: int) -> dict[str, Any]:
        with self._lock:
            if route_id in self._active:
                return self._start_response(route_id, already_running=True)

            context, error_code = self.validate_start(route_id)
            if error_code is not None:
                return {
                    "status": "ERROR",
                    "error_code": error_code,
                    "user_message": START_ERROR_MESSAGES_TR[error_code],
                }

            try:
                runtime = self._build_runtime(context)
            except BridgeValidationError:
                return {
                    "status": "ERROR",
                    "error_code": "LISTENER_TARGET_ROOT_INVALID",
                    "user_message": "MT5 hedef dizini kullanılamıyor.",
                }

            self._active[route_id] = runtime
            now = utc_now_iso()
            self._database.upsert_route_listener_state(
                route_id,
                listener_status=LISTENER_WAITING,
                last_signal_status="Kanal dinlenmeye hazır.",
                started_at_utc=now,
            )
            self._database.add_route_event(
                route_id,
                event_type="LISTENER_START",
                status=LISTENER_WAITING,
                target_id=context.target_id,
                safe_summary="Route listener started (observer-only).",
            )

            if self._telethon_enabled:
                hook_error = self._ensure_telethon_hook()
                if hook_error is not None:
                    self._active.pop(route_id, None)
                    self._database.upsert_route_listener_state(
                        route_id,
                        listener_status=LISTENER_STOPPED,
                        last_signal_status="Telegram dinleyicisi başlatılamadı.",
                        last_error_code=hook_error,
                    )
                    return {
                        "status": "ERROR",
                        "error_code": hook_error,
                        "user_message": START_ERROR_MESSAGES_TR.get(
                            hook_error,
                            START_ERROR_MESSAGES_TR[START_ERROR_TELETHON_START],
                        ),
                    }

            return self._start_response(route_id, already_running=False)

    def stop_route(self, route_id: int) -> dict[str, Any]:
        with self._lock:
            removed = self._active.pop(route_id, None)
            if removed is None:
                row = self._database.get_route_listener_state(route_id)
                if row and row.get("listener_status") == LISTENER_STOPPED:
                    return {"status": "LISTENER_STOPPED", "route_id": route_id, "already_stopped": True}
            self._database.upsert_route_listener_state(
                route_id,
                listener_status=LISTENER_STOPPED,
                last_signal_status="Dinleme durduruldu.",
            )
            self._database.add_route_event(
                route_id,
                event_type="LISTENER_STOP",
                status=LISTENER_STOPPED,
                target_id=removed.context.target_id if removed else None,
                safe_summary="Route listener stopped.",
            )
            if not self._active:
                self._shutdown_telethon_hook()
            return {"status": "LISTENER_STOPPED", "route_id": route_id}

    def inject_message(self, message: TelegramInboundMessage) -> None:
        """Process a new Telegram message for all active routes on the channel (tests/simulation)."""
        message_key = canonical_channel_key_from_value(message.channel_id)
        if message_key is None:
            return
        self.deliver_inbound_message(message_key, message)

    def deliver_inbound_message(self, channel_key: str, message: TelegramInboundMessage) -> None:
        with self._lock:
            runtimes = [
                runtime
                for runtime in self._active.values()
                if runtime.context.telegram_channel_key == channel_key
            ]
        for runtime in runtimes:
            self._process_message(runtime, message)

    def record_telethon_handler_error(self, channel_key: str) -> None:
        with self._lock:
            runtimes = [
                runtime
                for runtime in self._active.values()
                if runtime.context.telegram_channel_key == channel_key
            ]
        for runtime in runtimes:
            self._record_event(
                runtime.context.route_id,
                runtime.context.target_id,
                LISTENER_PUBLISH_FAILED,
                "TELETHON_HANDLER_ERROR",
                "Telegram mesaj işleyicisi hata verdi.",
            )

    def _start_response(self, route_id: int, *, already_running: bool) -> dict[str, Any]:
        status = self.route_listener_status(route_id) or {}
        payload = {
            "status": "LISTENER_STARTED",
            "route_id": route_id,
            "listener_status": status.get("listener_status", LISTENER_WAITING),
            "already_running": already_running,
            "dry_run": self._dry_run,
        }
        return payload

    def _build_runtime(self, context: RouteStartContext) -> RouteRuntime:
        root_path = Path(context.file_common_root).expanduser()
        if self._dry_run:
            root_path.mkdir(parents=True, exist_ok=True)
        root = resolve_root(context.file_common_root)
        logger = BridgeLogger()
        publisher = AtomicPublisher(logger)
        matcher = TelegramPairMatcher(
            publisher=publisher,
            root=root,
            seed_filename=context.seed_filename,
            details_filename=context.details_filename,
            pair_timeout_seconds=self._pair_timeout_seconds,
            logger=logger,
            mode="dashboard-route-listener",
            dry_run=self._dry_run,
        )
        handler = TelegramMessageHandler(matcher, logger)
        return RouteRuntime(context=context, handler=handler, publisher=publisher, logger=logger)

    def _process_message(self, runtime: RouteRuntime, message: TelegramInboundMessage) -> None:
        route_id = runtime.context.route_id
        target_id = runtime.context.target_id
        content_hash = raw_message_hash(message.text)
        if content_hash in runtime.seen_raw_hashes:
            self._record_event(
                route_id,
                target_id,
                LISTENER_PUBLISH_SKIPPED,
                "LISTENER_DEDUP",
                "Yinelenen mesaj atlandı.",
            )
            return

        classification = classify_telegram_text(message.text)
        if classification == "seed":
            runtime.seen_raw_hashes.add(content_hash)
            self._database.upsert_route_listener_state(
                route_id,
                listener_status=LISTENER_SEED_DETECTED,
                last_signal_status="Sinyal algılandı, yalnız izleme modunda değerlendirilecek.",
            )
            self._database.add_route_event(
                route_id,
                event_type="SEED_DETECTED",
                status=LISTENER_SEED_DETECTED,
                target_id=target_id,
                fingerprint_short=short_fingerprint(content_hash),
                safe_summary="Seed signal detected for observer-only route.",
            )
            runtime.handler.handle(message)
            return

        if classification == "details":
            runtime.seen_raw_hashes.add(content_hash)
            self._database.upsert_route_listener_state(
                route_id,
                listener_status=LISTENER_DETAILS_DETECTED,
                last_signal_status="Detay sinyali algılandı.",
            )
            self._database.add_route_event(
                route_id,
                event_type="DETAILS_DETECTED",
                status=LISTENER_DETAILS_DETECTED,
                target_id=target_id,
                fingerprint_short=short_fingerprint(content_hash),
                safe_summary="Details signal detected for observer-only route.",
            )
            before_count = len(runtime.publisher._published_fingerprints)
            try:
                runtime.handler.handle(message)
            except Exception:
                self._record_publish_failure(route_id, target_id)
                return
            after_count = len(runtime.publisher._published_fingerprints)
            if after_count > before_count:
                self._record_publish_success(route_id, target_id, runtime)
            else:
                self._record_event(
                    route_id,
                    target_id,
                    LISTENER_PUBLISH_SKIPPED,
                    "PUBLISH_SKIPPED",
                    "Yayın atlandı (eşleşme veya tekrar).",
                )
            return

        if classification in ("empty", "non_ascii", "unrecognized"):
            self._record_event(
                route_id,
                target_id,
                LISTENER_PUBLISH_SKIPPED,
                f"SKIP_{classification.upper()}",
                "Mesaj sinyal formatına uymuyor.",
            )

    def _record_publish_success(self, route_id: int, target_id: int, runtime: RouteRuntime) -> None:
        now = utc_now_iso()
        self._database.upsert_route_listener_state(
            route_id,
            listener_status=LISTENER_PUBLISH_READY,
            last_signal_status="Sinyal yalnız izleme modunda hazırlandı.",
            last_publish_at_utc=now,
            last_error_code=None,
        )
        self._database.update_route_publish_status(route_id, LISTENER_PUBLISH_READY, now)
        fingerprint = next(iter(runtime.publisher._published_fingerprints), "")
        signal_meta = runtime.publisher.last_signal_meta
        safe_summary = format_safe_summary_with_signal_meta(
            "Observer-only publish plan completed.",
            signal_meta,
        )
        self._database.add_route_event(
            route_id,
            event_type="PUBLISH_READY",
            status=LISTENER_PUBLISH_READY,
            target_id=target_id,
            fingerprint_short=short_fingerprint(fingerprint) if fingerprint else None,
            seed_bytes=runtime.publisher.last_seed_bytes,
            details_bytes=runtime.publisher.last_details_bytes,
            safe_summary=safe_summary,
        )

    def _record_publish_failure(self, route_id: int, target_id: int) -> None:
        self._database.upsert_route_listener_state(
            route_id,
            listener_status=LISTENER_PUBLISH_FAILED,
            last_signal_status="Yayın başarısız oldu.",
            last_error_code="PUBLISH_FAILED",
        )
        self._database.update_route_publish_status(route_id, LISTENER_PUBLISH_FAILED, utc_now_iso())
        self._database.add_route_event(
            route_id,
            event_type="PUBLISH_FAILED",
            status=LISTENER_PUBLISH_FAILED,
            target_id=target_id,
            safe_summary="Observer-only publish failed.",
        )

    def _record_event(
        self,
        route_id: int,
        target_id: int,
        status: str,
        error_code: str,
        summary: str,
    ) -> None:
        self._database.upsert_route_listener_state(
            route_id,
            listener_status=status,
            last_signal_status=summary,
            last_error_code=error_code if status == LISTENER_PUBLISH_FAILED else None,
        )
        self._database.add_route_event(
            route_id,
            event_type=error_code,
            status=status,
            target_id=target_id,
            safe_summary=summary,
        )

    def _ensure_telethon_hook(self) -> str | None:
        if self._telethon_bridge is None:
            self._telethon_bridge = TelethonRouteListenerBridge(
                manager=self,
                data_dir=self._data_dir,
                client_factory=self._telethon_client_factory,
            )
        return self._telethon_bridge.ensure_started()

    def _shutdown_telethon_hook(self) -> None:
        if self._telethon_bridge is not None:
            self._telethon_bridge.shutdown()
            self._telethon_bridge = None

    def _normalize_stale_listener_states(
        self,
        *,
        reason_message: str = "Dashboard yeniden başlatıldı; dinleme durduruldu.",
    ) -> None:
        now = utc_now_iso()
        with self._database._connect() as conn:
            conn.execute(
                """
                UPDATE route_listener_state
                SET listener_status = ?,
                    last_signal_status = ?,
                    updated_at_utc = ?
                WHERE listener_status != ?
                """,
                (
                    LISTENER_STOPPED,
                    reason_message,
                    now,
                    LISTENER_STOPPED,
                ),
            )


def build_worker_listener_manager(
    database: DashboardDatabase,
    data_dir: Path,
    *,
    telethon_client_factory: TelethonClientFactory | None = None,
) -> RouteListenerManager:
    dry_run = os.environ.get("DASHBOARD_ROUTE_LISTENER_DRY_RUN", "1") == "1"
    telethon_enabled = os.environ.get("DASHBOARD_ROUTE_LISTENER_TELETHON", "0") == "1"
    return RouteListenerManager(
        database=database,
        data_dir=data_dir,
        dry_run=dry_run,
        telethon_enabled=telethon_enabled,
        telethon_client_factory=telethon_client_factory,
        normalize_stale_states=True,
        stale_state_reason="Dinleme servisi yeniden başlatıldı; takibi yeniden başlatın.",
    )


def build_default_listener_manager(
    database: DashboardDatabase,
    data_dir: Path,
) -> RouteListenerManager:
    dry_run = os.environ.get("DASHBOARD_ROUTE_LISTENER_DRY_RUN", "1") == "1"
    telethon_enabled = os.environ.get("DASHBOARD_ROUTE_LISTENER_TELETHON", "0") == "1"
    return RouteListenerManager(
        database=database,
        data_dir=data_dir,
        dry_run=dry_run,
        telethon_enabled=telethon_enabled,
        normalize_stale_states=False,
    )
