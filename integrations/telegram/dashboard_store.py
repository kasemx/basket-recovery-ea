"""SQLite persistence for the local Telegram route dashboard."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from dashboard_security import (
    ACCOUNT_MODES,
    DashboardValidationError,
    redact_metadata,
    redact_text,
    utc_now_iso,
    validate_basename_safe,
)

DEMO_CHANNEL_SPECS = (
    {
        "telegram_channel_id": "demo-gold-vip-001",
        "title": "Gold Signals VIP",
        "channel_type": "channel",
        "username": "gold_signals_vip_demo",
    },
    {
        "telegram_channel_id": "demo-xauusd-ideas-002",
        "title": "XAUUSD Ideas",
        "channel_type": "channel",
        "username": "xauusd_ideas_demo",
    },
    {
        "telegram_channel_id": "demo-forex-chat-003",
        "title": "General Forex Chat",
        "channel_type": "group",
        "username": None,
    },
)


class DashboardDatabase:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_schema()

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON")
        return conn

    def _init_schema(self) -> None:
        with self._connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS telegram_connection (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    status TEXT NOT NULL,
                    phone_masked TEXT NULL,
                    channel_count INTEGER NOT NULL DEFAULT 0,
                    last_error_code TEXT NULL,
                    updated_at_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS tracked_channels (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    telegram_channel_id TEXT NOT NULL UNIQUE,
                    title TEXT NOT NULL,
                    channel_type TEXT NOT NULL,
                    username TEXT NULL,
                    is_tracking INTEGER NOT NULL DEFAULT 0,
                    last_message_at_utc TEXT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS mt5_targets (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    terminal_label TEXT NOT NULL,
                    broker_label TEXT NOT NULL,
                    account_mode TEXT NOT NULL,
                    file_common_root TEXT NOT NULL,
                    seed_filename TEXT NOT NULL,
                    details_filename TEXT NOT NULL,
                    observer_only INTEGER NOT NULL DEFAULT 1,
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS routes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE,
                    channel_id INTEGER NOT NULL,
                    target_id INTEGER NOT NULL,
                    parser_profile TEXT NOT NULL DEFAULT 'FASTTRACK_GOLD_NOW',
                    mode TEXT NOT NULL DEFAULT 'OBSERVER_ONLY',
                    is_enabled INTEGER NOT NULL DEFAULT 1,
                    last_publish_status TEXT NULL,
                    last_publish_at_utc TEXT NULL,
                    created_at_utc TEXT NOT NULL,
                    updated_at_utc TEXT NOT NULL,
                    UNIQUE(channel_id, target_id),
                    FOREIGN KEY(channel_id) REFERENCES tracked_channels(id) ON DELETE RESTRICT,
                    FOREIGN KEY(target_id) REFERENCES mt5_targets(id) ON DELETE RESTRICT
                );

                CREATE TABLE IF NOT EXISTS audit_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type TEXT NOT NULL,
                    severity TEXT NOT NULL,
                    message TEXT NOT NULL,
                    metadata_json TEXT NULL,
                    created_at_utc TEXT NOT NULL
                );
                """
            )
            row = conn.execute("SELECT id FROM telegram_connection WHERE id = 1").fetchone()
            if row is None:
                now = utc_now_iso()
                conn.execute(
                    """
                    INSERT INTO telegram_connection
                    (id, status, phone_masked, channel_count, last_error_code, updated_at_utc)
                    VALUES (1, 'DISCONNECTED', NULL, 0, NULL, ?)
                    """,
                    (now,),
                )

    def add_audit(
        self,
        event_type: str,
        severity: str,
        message: str,
        metadata: dict[str, Any] | None = None,
    ) -> None:
        safe_message = redact_text(message)
        safe_metadata = redact_metadata(metadata)
        metadata_json = json.dumps(safe_metadata) if safe_metadata else None
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO audit_events
                (event_type, severity, message, metadata_json, created_at_utc)
                VALUES (?, ?, ?, ?, ?)
                """,
                (event_type, severity, safe_message, metadata_json, utc_now_iso()),
            )

    def get_telegram_status(self) -> dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM telegram_connection WHERE id = 1").fetchone()
        return dict(row) if row else {"status": "DISCONNECTED"}

    def configure_telegram(self, phone_masked: str) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'API_CONFIGURED',
                    phone_masked = ?,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (phone_masked, now),
            )

    def list_channels(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT c.*,
                       (SELECT COUNT(*) FROM routes r WHERE r.channel_id = c.id) AS route_count
                FROM tracked_channels c
                ORDER BY c.title
                """
            ).fetchall()
        return [dict(row) for row in rows]

    def import_demo_channels(self) -> tuple[int, str]:
        inserted = 0
        now = utc_now_iso()
        with self._connect() as conn:
            for spec in DEMO_CHANNEL_SPECS:
                cursor = conn.execute(
                    """
                    INSERT OR IGNORE INTO tracked_channels
                    (telegram_channel_id, title, channel_type, username, is_tracking,
                     last_message_at_utc, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?, 0, NULL, ?, ?)
                    """,
                    (
                        spec["telegram_channel_id"],
                        spec["title"],
                        spec["channel_type"],
                        spec["username"],
                        now,
                        now,
                    ),
                )
                inserted += cursor.rowcount
            conn.execute(
                """
                UPDATE telegram_connection
                SET channel_count = (SELECT COUNT(*) FROM tracked_channels),
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (now,),
            )
        return inserted, "LOCAL_DEMO_DATA"

    def update_channel(self, channel_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        allowed = {key: updates[key] for key in ("is_tracking", "title") if key in updates}
        if not allowed:
            raise DashboardValidationError("No updatable channel fields provided")
        now = utc_now_iso()
        sets = ", ".join(f"{key} = ?" for key in allowed)
        values = list(allowed.values()) + [now, channel_id]
        with self._connect() as conn:
            cursor = conn.execute(
                f"UPDATE tracked_channels SET {sets}, updated_at_utc = ? WHERE id = ?",
                values,
            )
            if cursor.rowcount == 0:
                raise DashboardValidationError("Channel not found")
            row = conn.execute(
                "SELECT * FROM tracked_channels WHERE id = ?", (channel_id,)
            ).fetchone()
        return dict(row)

    def delete_channel(self, channel_id: int) -> None:
        with self._connect() as conn:
            route_count = conn.execute(
                "SELECT COUNT(*) FROM routes WHERE channel_id = ?", (channel_id,)
            ).fetchone()[0]
            if route_count:
                raise DashboardValidationError("Channel has routes; remove routes first.")
            cursor = conn.execute("DELETE FROM tracked_channels WHERE id = ?", (channel_id,))
            if cursor.rowcount == 0:
                raise DashboardValidationError("Channel not found")
            conn.execute(
                """
                UPDATE telegram_connection
                SET channel_count = (SELECT COUNT(*) FROM tracked_channels),
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (utc_now_iso(),),
            )

    def list_targets(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute("SELECT * FROM mt5_targets ORDER BY name").fetchall()
        return [dict(row) for row in rows]

    def create_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        seed_filename = validate_basename_safe(str(payload["seed_filename"]))
        details_filename = validate_basename_safe(str(payload["details_filename"]))
        if seed_filename == details_filename:
            raise DashboardValidationError("Seed and details filenames must differ")
        account_mode = str(payload["account_mode"]).upper()
        if account_mode not in ACCOUNT_MODES:
            raise DashboardValidationError("account_mode must be DEMO or UNKNOWN")
        if payload.get("observer_only") in (False, 0, "0", "false"):
            raise DashboardValidationError("observer_only must remain enabled")
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO mt5_targets
                (name, terminal_label, broker_label, account_mode, file_common_root,
                 seed_filename, details_filename, observer_only, is_enabled,
                 created_at_utc, updated_at_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?)
                """,
                (
                    str(payload["name"]).strip(),
                    str(payload["terminal_label"]).strip(),
                    str(payload["broker_label"]).strip(),
                    account_mode,
                    str(payload["file_common_root"]).strip(),
                    seed_filename,
                    details_filename,
                    now,
                    now,
                ),
            )
            row = conn.execute(
                "SELECT * FROM mt5_targets WHERE name = ?", (payload["name"],)
            ).fetchone()
        return dict(row)

    def update_target(self, target_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        if updates.get("observer_only") in (False, 0, "0", "false"):
            raise DashboardValidationError("observer_only cannot be disabled")
        allowed_keys = (
            "name",
            "terminal_label",
            "broker_label",
            "seed_filename",
            "details_filename",
            "is_enabled",
        )
        allowed = {}
        for key in allowed_keys:
            if key not in updates:
                continue
            value = updates[key]
            if key in ("seed_filename", "details_filename"):
                value = validate_basename_safe(str(value))
            allowed[key] = value
        if not allowed:
            raise DashboardValidationError("No updatable target fields provided")
        now = utc_now_iso()
        sets = ", ".join(f"{key} = ?" for key in allowed)
        values = list(allowed.values()) + [now, target_id]
        with self._connect() as conn:
            cursor = conn.execute(
                f"UPDATE mt5_targets SET {sets}, updated_at_utc = ? WHERE id = ?",
                values,
            )
            if cursor.rowcount == 0:
                raise DashboardValidationError("Target not found")
            row = conn.execute("SELECT * FROM mt5_targets WHERE id = ?", (target_id,)).fetchone()
        return dict(row)

    def delete_target(self, target_id: int) -> None:
        with self._connect() as conn:
            route_count = conn.execute(
                "SELECT COUNT(*) FROM routes WHERE target_id = ?", (target_id,)
            ).fetchone()[0]
            if route_count:
                raise DashboardValidationError("Target has routes; remove routes first.")
            cursor = conn.execute("DELETE FROM mt5_targets WHERE id = ?", (target_id,))
            if cursor.rowcount == 0:
                raise DashboardValidationError("Target not found")

    def list_routes(self) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT r.*, c.title AS channel_title, t.name AS target_name
                FROM routes r
                JOIN tracked_channels c ON c.id = r.channel_id
                JOIN mt5_targets t ON t.id = r.target_id
                ORDER BY r.name
                """
            ).fetchall()
        return [dict(row) for row in rows]

    def create_route(self, payload: dict[str, Any]) -> dict[str, Any]:
        if payload.get("mode") and str(payload["mode"]).upper() != "OBSERVER_ONLY":
            raise DashboardValidationError("Route mode changes are not allowed")
        channel_id = int(payload["channel_id"])
        target_id = int(payload["target_id"])
        with self._connect() as conn:
            channel = conn.execute(
                "SELECT id FROM tracked_channels WHERE id = ?", (channel_id,)
            ).fetchone()
            target = conn.execute(
                "SELECT id, observer_only FROM mt5_targets WHERE id = ?", (target_id,)
            ).fetchone()
            if channel is None:
                raise DashboardValidationError("Channel not found")
            if target is None:
                raise DashboardValidationError("Target not found")
            if target["observer_only"] != 1:
                raise DashboardValidationError("Target must remain observer-only")
            now = utc_now_iso()
            try:
                conn.execute(
                    """
                    INSERT INTO routes
                    (name, channel_id, target_id, parser_profile, mode, is_enabled,
                     last_publish_status, last_publish_at_utc, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?, 'OBSERVER_ONLY', 1, NULL, NULL, ?, ?)
                    """,
                    (
                        str(payload["name"]).strip(),
                        channel_id,
                        target_id,
                        str(payload.get("parser_profile", "FASTTRACK_GOLD_NOW")),
                        now,
                        now,
                    ),
                )
            except sqlite3.IntegrityError as exc:
                raise DashboardValidationError(
                    "Route name or channel-target pair already exists"
                ) from exc
            row = conn.execute(
                "SELECT * FROM routes WHERE name = ?", (payload["name"],)
            ).fetchone()
        return dict(row)

    def update_route(self, route_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        if "mode" in updates or "execution" in updates:
            raise DashboardValidationError("Route mode changes are not allowed")
        allowed = {key: updates[key] for key in ("name", "is_enabled") if key in updates}
        if not allowed:
            raise DashboardValidationError("No updatable route fields provided")
        now = utc_now_iso()
        sets = ", ".join(f"{key} = ?" for key in allowed)
        values = list(allowed.values()) + [now, route_id]
        with self._connect() as conn:
            cursor = conn.execute(
                f"UPDATE routes SET {sets}, updated_at_utc = ? WHERE id = ?",
                values,
            )
            if cursor.rowcount == 0:
                raise DashboardValidationError("Route not found")
            row = conn.execute("SELECT * FROM routes WHERE id = ?", (route_id,)).fetchone()
        return dict(row)

    def delete_route(self, route_id: int) -> None:
        with self._connect() as conn:
            cursor = conn.execute("DELETE FROM routes WHERE id = ?", (route_id,))
            if cursor.rowcount == 0:
                raise DashboardValidationError("Route not found")

    def list_audit(self, limit: int) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, event_type, severity, message, metadata_json, created_at_utc
                FROM audit_events
                ORDER BY id DESC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
        events = []
        for row in rows:
            item = dict(row)
            if item["metadata_json"]:
                metadata = json.loads(item["metadata_json"])
                item["metadata"] = redact_metadata(metadata)
            else:
                item["metadata"] = None
            del item["metadata_json"]
            events.append(item)
        return events

    def add_demo_audit_event(self) -> dict[str, Any]:
        self.add_audit(
            "ROUTE_SIMULATION",
            "INFO",
            "route_event=SIMULATED_OBSERVER_BLOCKED",
            {"note": "UI demo only; no broker or EA action"},
        )
        return self.list_audit(1)[0]

    def overview(self) -> dict[str, Any]:
        telegram = self.get_telegram_status()
        with self._connect() as conn:
            tracked_channels = conn.execute("SELECT COUNT(*) FROM tracked_channels").fetchone()[0]
            mt5_targets = conn.execute("SELECT COUNT(*) FROM mt5_targets").fetchone()[0]
            routes = conn.execute("SELECT COUNT(*) FROM routes").fetchone()[0]
        return {
            "telegram": {
                "status": telegram["status"],
                "phone_masked": telegram.get("phone_masked"),
                "channel_count": telegram.get("channel_count", 0),
            },
            "counts": {
                "tracked_channels": tracked_channels,
                "mt5_targets": mt5_targets,
                "routes": routes,
            },
            "safety": {
                "broker_execution": "DISABLED_BY_DESIGN",
                "file_common_write": "NOT_IMPLEMENTED",
                "ea_control": "NOT_IMPLEMENTED",
            },
        }
