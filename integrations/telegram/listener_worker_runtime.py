"""Persistent Telegram listener worker runtime loop."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path
from typing import Any

from dashboard_security import utc_now_iso
from dashboard_store import DashboardDatabase
from listener_worker_client import (
    WORKER_COMMAND_START_ROUTE,
    WORKER_COMMAND_STOP_ROUTE,
    WORKER_COMMAND_WORKER_STOP,
    WORKER_CONNECTED,
    WORKER_CONNECTING,
    WORKER_ERROR,
    WORKER_RECONNECTING,
    WORKER_STARTING,
    WORKER_STOPPED,
    WORKER_STOPPING,
    clear_stale_worker_lock,
    is_process_running,
    worker_lock_path,
)
from route_listener_service import RouteListenerManager, build_worker_listener_manager

HEARTBEAT_INTERVAL_SECONDS = 10
RECONNECT_BASE_DELAY_SECONDS = 2.0
RECONNECT_MAX_DELAY_SECONDS = 60.0
LOOP_SLEEP_SECONDS = 0.5


class ListenerWorkerRuntime:
    def __init__(self, data_dir: Path) -> None:
        self._data_dir = data_dir.expanduser().resolve()
        db_path = self._data_dir / "dashboard.sqlite3"
        self._database = DashboardDatabase(db_path)
        self._manager: RouteListenerManager | None = None
        self._stop_requested = False
        self._reconnect_delay = RECONNECT_BASE_DELAY_SECONDS
        self._last_heartbeat_at = 0.0
        self._lock_acquired = False

    @property
    def manager(self) -> RouteListenerManager:
        if self._manager is None:
            raise RuntimeError("Worker manager not initialized")
        return self._manager

    def request_stop(self) -> None:
        self._stop_requested = True

    def run_forever(self) -> None:
        if not self._acquire_lock():
            return
        try:
            self._run_loop()
        finally:
            self._release_lock()

    def _acquire_lock(self) -> bool:
        clear_stale_worker_lock(self._data_dir)
        lock = worker_lock_path(self._data_dir)
        pid = os.getpid()
        if lock.exists():
            try:
                existing_pid = int(lock.read_text(encoding="utf-8").strip())
            except ValueError:
                existing_pid = None
            if existing_pid and is_process_running(existing_pid) and existing_pid != pid:
                return False
            lock.unlink(missing_ok=True)
        lock.write_text(str(pid), encoding="utf-8")
        self._lock_acquired = True
        return True

    def _release_lock(self) -> None:
        if not self._lock_acquired:
            return
        lock = worker_lock_path(self._data_dir)
        try:
            if lock.exists() and lock.read_text(encoding="utf-8").strip() == str(os.getpid()):
                lock.unlink(missing_ok=True)
        except OSError:
            pass
        self._lock_acquired = False

    def _run_loop(self) -> None:
        now = utc_now_iso()
        dry_run = os.environ.get("DASHBOARD_ROUTE_LISTENER_DRY_RUN", "1") == "1"
        self._database.upsert_listener_worker_state(
            state=WORKER_STARTING,
            pid=os.getpid(),
            started_at_utc=now,
            last_heartbeat_at_utc=now,
            reconnect_count=0,
            active_route_count=0,
            active_route_ids=[],
            safe_last_error=None,
            dry_run=dry_run,
        )
        self._manager = build_worker_listener_manager(self._database, self._data_dir)
        self._publish_state(WORKER_CONNECTING)
        if self._manager._telethon_enabled:  # noqa: SLF001
            telethon_error = self._manager._ensure_telethon_hook()  # noqa: SLF001
            if telethon_error is not None:
                self._publish_state(
                    WORKER_ERROR,
                    safe_last_error="Telegram oturumu kullanılamıyor.",
                )
            else:
                self._publish_state(WORKER_CONNECTED)
                self._reconnect_delay = RECONNECT_BASE_DELAY_SECONDS
        else:
            self._publish_state(WORKER_CONNECTED)
            self._reconnect_delay = RECONNECT_BASE_DELAY_SECONDS

        while not self._stop_requested:
            self._process_commands()
            if self._stop_requested:
                break
            self._maybe_heartbeat()
            self._monitor_telethon_connection()
            time.sleep(LOOP_SLEEP_SECONDS)

        self._shutdown()

    def _shutdown(self) -> None:
        self._publish_state(WORKER_STOPPING)
        if self._manager is not None:
            with self._manager._lock:  # noqa: SLF001
                active_ids = list(self._manager._active.keys())
            for route_id in active_ids:
                self._manager.stop_route(route_id)
            self._manager._shutdown_telethon_hook()  # noqa: SLF001
        self._database.upsert_listener_worker_state(
            state=WORKER_STOPPED,
            pid=None,
            active_route_count=0,
            active_route_ids=[],
        )

    def _process_commands(self) -> None:
        commands = self._database.claim_pending_worker_commands()
        for command in commands:
            cmd_id = int(command["id"])
            cmd_type = command["command_type"]
            route_id = command.get("route_id")
            try:
                result = self._dispatch_command(cmd_type, route_id)
                self._database.complete_worker_command(cmd_id, status="DONE", result=result)
            except Exception:  # noqa: BLE001 - command boundary
                self._database.complete_worker_command(
                    cmd_id,
                    status="FAILED",
                    result={"status": "ERROR", "error_code": "WORKER_COMMAND_FAILED"},
                )
            if cmd_type == WORKER_COMMAND_WORKER_STOP:
                self._stop_requested = True
                return

    def _dispatch_command(self, command_type: str, route_id: int | None) -> dict[str, Any]:
        if self._manager is None:
            raise RuntimeError("Worker manager unavailable")
        if command_type == WORKER_COMMAND_START_ROUTE:
            if route_id is None:
                raise ValueError("route_id required")
            result = self._manager.start_route(int(route_id))
            self._sync_active_routes()
            return result
        if command_type == WORKER_COMMAND_STOP_ROUTE:
            if route_id is None:
                raise ValueError("route_id required")
            result = self._manager.stop_route(int(route_id))
            self._sync_active_routes()
            return result
        if command_type == WORKER_COMMAND_WORKER_STOP:
            return {"status": "WORKER_STOPPED"}
        raise ValueError(f"Unknown worker command: {command_type}")

    def _sync_active_routes(self) -> None:
        if self._manager is None:
            return
        payload = self._manager.status_payload()
        self._database.upsert_listener_worker_state(
            active_route_count=len(payload["active_route_ids"]),
            active_route_ids=payload["active_route_ids"],
        )

    def _maybe_heartbeat(self) -> None:
        now_mono = time.monotonic()
        if now_mono - self._last_heartbeat_at < HEARTBEAT_INTERVAL_SECONDS:
            return
        self._last_heartbeat_at = now_mono
        row = self._database.get_listener_worker_state()
        state = row.get("state") or WORKER_STOPPED
        if state in (WORKER_STOPPING, WORKER_STOPPED, WORKER_ERROR):
            return
        self._sync_active_routes()
        self._database.upsert_listener_worker_state(last_heartbeat_at_utc=utc_now_iso())

    def _monitor_telethon_connection(self) -> None:
        if self._manager is None or not self._manager._telethon_enabled:  # noqa: SLF001
            return
        bridge = self._manager._telethon_bridge  # noqa: SLF001
        active_count = len(self._manager.status_payload()["active_route_ids"])
        if active_count == 0:
            return
        if bridge is not None and bridge.is_connected():
            row = self._database.get_listener_worker_state()
            if row.get("state") == WORKER_RECONNECTING:
                self._publish_state(WORKER_CONNECTED)
                self._reconnect_delay = RECONNECT_BASE_DELAY_SECONDS
            return

        row = self._database.get_listener_worker_state()
        reconnect_count = int(row.get("reconnect_count") or 0) + 1
        self._publish_state(
            WORKER_RECONNECTING,
            reconnect_count=reconnect_count,
            safe_last_error="Telegram bağlantısı yeniden kuruluyor.",
        )
        if bridge is not None:
            self._manager._shutdown_telethon_hook()  # noqa: SLF001
        time.sleep(self._reconnect_delay)
        error = self._manager._ensure_telethon_hook()  # noqa: SLF001
        self._reconnect_delay = min(self._reconnect_delay * 2, RECONNECT_MAX_DELAY_SECONDS)
        if error is None:
            self._publish_state(WORKER_CONNECTED, safe_last_error=None)
            self._reconnect_delay = RECONNECT_BASE_DELAY_SECONDS
        else:
            self._publish_state(
                WORKER_RECONNECTING,
                safe_last_error="Telegram bağlantısı kurulamadı; yeniden denenecek.",
            )

    def _publish_state(self, state: str, **fields: Any) -> None:
        updates: dict[str, Any] = {"state": state}
        updates.update(fields)
        if state == WORKER_CONNECTED:
            updates.setdefault("safe_last_error", None)
        self._database.upsert_listener_worker_state(**updates)


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if not args:
        print("Usage: telegram_listener_worker.py <data_dir>", file=sys.stderr)
        return 2
    data_dir = Path(args[0]).expanduser().resolve()
    runtime = ListenerWorkerRuntime(data_dir)
    runtime.run_forever()
    return 0
