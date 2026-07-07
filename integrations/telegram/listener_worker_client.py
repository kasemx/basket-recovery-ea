"""Dashboard-side client for the persistent Telegram listener worker."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from dashboard_security import utc_now_iso
from dashboard_store import DashboardDatabase
from route_listener_service import (
    LISTENER_STOPPED,
    RouteListenerManager,
    build_worker_listener_manager,
)

WORKER_STOPPED = "STOPPED"
WORKER_STARTING = "STARTING"
WORKER_CONNECTING = "CONNECTING"
WORKER_CONNECTED = "CONNECTED"
WORKER_RECONNECTING = "RECONNECTING"
WORKER_DEGRADED = "DEGRADED"
WORKER_STOPPING = "STOPPING"
WORKER_ERROR = "ERROR"

WORKER_COMMAND_START_ROUTE = "START_ROUTE"
WORKER_COMMAND_STOP_ROUTE = "STOP_ROUTE"
WORKER_COMMAND_WORKER_STOP = "WORKER_STOP"

HEARTBEAT_DEGRADED_SECONDS = 30
COMMAND_WAIT_TIMEOUT_SECONDS = 8.0
COMMAND_POLL_INTERVAL_SECONDS = 0.05

WORKER_STATE_LABELS_TR = {
    WORKER_STOPPED: "Kapalı",
    WORKER_STARTING: "Başlatılıyor",
    WORKER_CONNECTING: "Bağlanıyor",
    WORKER_CONNECTED: "Bağlı",
    WORKER_RECONNECTING: "Yeniden Bağlanıyor",
    WORKER_DEGRADED: "Sorun Var",
    WORKER_STOPPING: "Durduruluyor",
    WORKER_ERROR: "Hata",
}


def worker_lock_path(data_dir: Path) -> Path:
    return data_dir.expanduser().resolve() / ".listener_worker.lock"


def inline_worker_enabled() -> bool:
    return os.environ.get("DASHBOARD_LISTENER_WORKER_INLINE", "0") == "1"


def _parse_iso_utc(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _heartbeat_age_seconds(last_heartbeat_at_utc: str | None) -> float | None:
    parsed = _parse_iso_utc(last_heartbeat_at_utc)
    if parsed is None:
        return None
    now = datetime.now(timezone.utc)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return max(0.0, (now - parsed).total_seconds())


def is_process_running(pid: int | None) -> bool:
    if pid is None or pid <= 0:
        return False
    if sys.platform == "win32":
        import ctypes

        kernel32 = ctypes.windll.kernel32
        PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        STILL_ACTIVE = 259
        handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
        if not handle:
            return False
        try:
            exit_code = ctypes.c_ulong()
            if kernel32.GetExitCodeProcess(handle, ctypes.byref(exit_code)) == 0:
                return False
            return int(exit_code.value) == STILL_ACTIVE
        finally:
            kernel32.CloseHandle(handle)
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def effective_worker_state(row: dict[str, Any]) -> str:
    state = str(row.get("state") or WORKER_STOPPED)
    pid = row.get("pid")
    if state not in (WORKER_STOPPED, WORKER_STOPPING) and pid and not is_process_running(int(pid)):
        return WORKER_ERROR
    if state in (WORKER_CONNECTED, WORKER_RECONNECTING, WORKER_CONNECTING, WORKER_STARTING):
        age = _heartbeat_age_seconds(row.get("last_heartbeat_at_utc"))
        if age is not None and age > HEARTBEAT_DEGRADED_SECONDS:
            return WORKER_DEGRADED
    return state


def clear_stale_worker_lock(data_dir: Path) -> None:
    lock = worker_lock_path(data_dir)
    if not lock.exists():
        return
    try:
        pid = int(lock.read_text(encoding="utf-8").strip())
    except (OSError, ValueError):
        lock.unlink(missing_ok=True)
        return
    if not is_process_running(pid):
        lock.unlink(missing_ok=True)


@dataclass
class ListenerWorkerClient:
    database: DashboardDatabase
    data_dir: Path
    _inline_runtime: Any | None = field(default=None, init=False, repr=False)
    _inline_thread: threading.Thread | None = field(default=None, init=False, repr=False)
    _lock: threading.RLock = field(default_factory=threading.RLock, init=False, repr=False)

    def worker_status_payload(self) -> dict[str, Any]:
        row = self.database.get_listener_worker_state()
        state = effective_worker_state(row)
        return {
            "state": state,
            "state_label": WORKER_STATE_LABELS_TR.get(state, state),
            "pid": row.get("pid"),
            "started_at_utc": row.get("started_at_utc"),
            "last_heartbeat_at_utc": row.get("last_heartbeat_at_utc"),
            "reconnect_count": int(row.get("reconnect_count") or 0),
            "active_route_count": int(row.get("active_route_count") or 0),
            "active_route_ids": list(row.get("active_route_ids") or []),
            "safe_last_error": row.get("safe_last_error"),
            "dry_run": bool(row.get("dry_run", True)),
            "process_alive": is_process_running(row.get("pid")),
            "inline_mode": inline_worker_enabled(),
        }

    def status_payload(self) -> dict[str, Any]:
        worker = self.worker_status_payload()
        active_ids = worker["active_route_ids"]
        worker_state = worker["state"]
        telethon_connected = worker_state == WORKER_CONNECTED and bool(worker.get("process_alive"))
        return {
            "worker": worker,
            "active_route_count": len(active_ids),
            "active_route_ids": active_ids,
            "dry_run": worker["dry_run"],
            "telethon_hook_enabled": True,
            "telethon_connected": telethon_connected,
        }

    def route_listener_status(self, route_id: int) -> dict[str, Any] | None:
        if self.database.get_route_start_context(route_id) is None:
            return None
        row = self.database.get_route_listener_state(route_id)
        worker = self.worker_status_payload()
        active_ids = set(worker.get("active_route_ids") or [])
        running = route_id in active_ids
        worker_state = worker["state"]
        telegram_connected = worker_state == WORKER_CONNECTED and bool(worker.get("process_alive"))
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
                "worker_state": worker_state,
                "worker_state_label": worker["state_label"],
                "worker_connected": worker_state in (WORKER_CONNECTED, WORKER_RECONNECTING),
                "telegram_connected": telegram_connected,
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
            "worker_state": worker_state,
            "worker_state_label": worker["state_label"],
            "worker_connected": worker_state in (WORKER_CONNECTED, WORKER_RECONNECTING),
            "telegram_connected": telegram_connected,
        }

    def start_worker(self) -> dict[str, Any]:
        clear_stale_worker_lock(self.data_dir)
        with self._lock:
            if (
                inline_worker_enabled()
                and self._inline_runtime is not None
                and self._inline_thread is not None
                and self._inline_thread.is_alive()
            ):
                return {
                    "status": "WORKER_ALREADY_RUNNING",
                    "worker": self.worker_status_payload(),
                }
        row = self.database.get_listener_worker_state()
        pid = row.get("pid")
        if pid and is_process_running(int(pid)):
            return {
                "status": "WORKER_ALREADY_RUNNING",
                "worker": self.worker_status_payload(),
            }
        lock = worker_lock_path(self.data_dir)
        if lock.exists():
            try:
                lock_pid = int(lock.read_text(encoding="utf-8").strip())
            except ValueError:
                lock_pid = None
            if lock_pid and is_process_running(lock_pid):
                return {
                    "status": "WORKER_ALREADY_RUNNING",
                    "worker": self.worker_status_payload(),
                }
            lock.unlink(missing_ok=True)

        now = utc_now_iso()
        self.database.upsert_listener_worker_state(
            state=WORKER_STARTING,
            pid=None,
            started_at_utc=now,
            last_heartbeat_at_utc=now,
            safe_last_error=None,
        )

        if inline_worker_enabled():
            self._start_inline_worker()
        else:
            self._spawn_subprocess_worker()

        deadline = time.time() + COMMAND_WAIT_TIMEOUT_SECONDS
        while time.time() < deadline:
            worker = self.worker_status_payload()
            if worker["state"] not in (WORKER_STOPPED, WORKER_STARTING):
                return {"status": "WORKER_STARTED", "worker": worker}
            if worker["state"] == WORKER_ERROR:
                return {"status": "WORKER_ERROR", "worker": worker}
            time.sleep(COMMAND_POLL_INTERVAL_SECONDS)
        return {"status": "WORKER_START_PENDING", "worker": self.worker_status_payload()}

    def stop_worker(self) -> dict[str, Any]:
        row = self.database.get_listener_worker_state()
        pid = row.get("pid")
        if not pid or not is_process_running(int(pid)):
            self.database.upsert_listener_worker_state(
                state=WORKER_STOPPED,
                pid=None,
                active_route_count=0,
                active_route_ids=[],
            )
            worker_lock_path(self.data_dir).unlink(missing_ok=True)
            return {"status": "WORKER_ALREADY_STOPPED", "worker": self.worker_status_payload()}

        cmd_id = self.database.enqueue_listener_worker_command(WORKER_COMMAND_WORKER_STOP)
        try:
            result = self._wait_for_command(cmd_id)
        except TimeoutError:
            result = {"status": "WORKER_STOPPING"}
        if inline_worker_enabled():
            self.shutdown_inline_worker()
        worker_lock_path(self.data_dir).unlink(missing_ok=True)
        return {"status": result.get("status", "WORKER_STOPPED"), "worker": self.worker_status_payload()}

    def start_route(self, route_id: int) -> dict[str, Any]:
        self._ensure_worker_running()
        cmd_id = self.database.enqueue_listener_worker_command(
            WORKER_COMMAND_START_ROUTE,
            route_id=route_id,
        )
        return self._wait_for_command(cmd_id)

    def stop_route(self, route_id: int) -> dict[str, Any]:
        self._ensure_worker_running(required=False)
        row = self.database.get_listener_worker_state()
        if not row.get("pid") or not is_process_running(int(row["pid"])):
            return {"status": "LISTENER_STOPPED", "route_id": route_id, "already_stopped": True}
        cmd_id = self.database.enqueue_listener_worker_command(
            WORKER_COMMAND_STOP_ROUTE,
            route_id=route_id,
        )
        return self._wait_for_command(cmd_id)

    def get_inline_manager(self) -> RouteListenerManager | None:
        runtime = self._inline_runtime
        if runtime is None:
            return None
        return runtime.manager

    def shutdown_inline_worker(self) -> None:
        with self._lock:
            runtime = self._inline_runtime
            thread = self._inline_thread
        if runtime is not None:
            runtime.request_stop()
        if thread is not None:
            thread.join(timeout=5)
        with self._lock:
            self._inline_runtime = None
            self._inline_thread = None

    def _ensure_worker_running(self, *, required: bool = True) -> None:
        worker = self.worker_status_payload()
        if worker["state"] not in (WORKER_STOPPED, WORKER_ERROR) and worker.get("process_alive"):
            return
        if not required and worker["state"] == WORKER_STOPPED:
            return
        self.start_worker()

    def _wait_for_command(self, command_id: int) -> dict[str, Any]:
        deadline = time.time() + COMMAND_WAIT_TIMEOUT_SECONDS
        while time.time() < deadline:
            row = self.database.get_worker_command(command_id)
            if row is None:
                raise RuntimeError("Worker command missing")
            status = row["status"]
            if status == "DONE":
                return row.get("result") or {}
            if status == "FAILED":
                result = row.get("result") or {}
                return result if result else {"status": "ERROR", "error_code": "WORKER_COMMAND_FAILED"}
            time.sleep(COMMAND_POLL_INTERVAL_SECONDS)
        raise TimeoutError(f"Worker command {command_id} timed out")

    def _spawn_subprocess_worker(self) -> None:
        script = Path(__file__).resolve().parent / "telegram_listener_worker.py"
        env = os.environ.copy()
        env.setdefault("DASHBOARD_ROUTE_LISTENER_DRY_RUN", "1")
        env.setdefault("DASHBOARD_ROUTE_LISTENER_TELETHON", "1")
        creationflags = 0
        if sys.platform == "win32":
            creationflags = subprocess.CREATE_NO_WINDOW  # type: ignore[attr-defined]
        subprocess.Popen(
            [sys.executable, str(script), str(self.data_dir.resolve())],
            cwd=str(script.parent),
            env=env,
            creationflags=creationflags,
        )

    def _start_inline_worker(self) -> None:
        with self._lock:
            if self._inline_runtime is not None:
                return
            from listener_worker_runtime import ListenerWorkerRuntime

            runtime = ListenerWorkerRuntime(self.data_dir)
            thread = threading.Thread(
                target=runtime.run_forever,
                name="inline-telegram-listener-worker",
                daemon=True,
            )
            self._inline_runtime = runtime
            self._inline_thread = thread
            thread.start()
