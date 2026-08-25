"""SQLite persistence for the local Telegram route dashboard."""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path
from typing import Any

from dashboard_security import (
    ACCOUNT_MODES,
    DashboardValidationError,
    mask_session_path,
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

                CREATE TABLE IF NOT EXISTS route_listener_state (
                    route_id INTEGER PRIMARY KEY,
                    listener_status TEXT NOT NULL DEFAULT 'LISTENER_STOPPED',
                    last_signal_status TEXT NULL,
                    last_error_code TEXT NULL,
                    last_publish_at_utc TEXT NULL,
                    started_at_utc TEXT NULL,
                    updated_at_utc TEXT NOT NULL,
                    FOREIGN KEY(route_id) REFERENCES routes(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS route_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    route_id INTEGER NOT NULL,
                    event_type TEXT NOT NULL,
                    status TEXT NOT NULL,
                    target_id INTEGER NULL,
                    fingerprint_short TEXT NULL,
                    seed_bytes INTEGER NULL,
                    details_bytes INTEGER NULL,
                    safe_summary TEXT NOT NULL,
                    created_at_utc TEXT NOT NULL,
                    FOREIGN KEY(route_id) REFERENCES routes(id) ON DELETE CASCADE
                );

                CREATE TABLE IF NOT EXISTS listener_worker_state (
                    id INTEGER PRIMARY KEY CHECK (id = 1),
                    state TEXT NOT NULL DEFAULT 'STOPPED',
                    pid INTEGER NULL,
                    started_at_utc TEXT NULL,
                    last_heartbeat_at_utc TEXT NULL,
                    reconnect_count INTEGER NOT NULL DEFAULT 0,
                    active_route_count INTEGER NOT NULL DEFAULT 0,
                    active_route_ids_json TEXT NULL,
                    safe_last_error TEXT NULL,
                    dry_run INTEGER NOT NULL DEFAULT 1,
                    updated_at_utc TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS listener_worker_commands (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    command_type TEXT NOT NULL,
                    route_id INTEGER NULL,
                    status TEXT NOT NULL DEFAULT 'PENDING',
                    result_json TEXT NULL,
                    created_at_utc TEXT NOT NULL,
                    processed_at_utc TEXT NULL
                );
                """
            )
            self._ensure_column(conn, "telegram_connection", "phone_code_hash", "TEXT NULL")
            self._ensure_column(conn, "telegram_connection", "session_path_masked", "TEXT NULL")
            self._ensure_column(conn, "tracked_channels", "source", "TEXT NULL")
            for column, definition in (
                ("terminal_exe_path", "TEXT NULL"),
                ("expected_account_login", "TEXT NULL"),
                ("expected_server", "TEXT NULL"),
                ("expected_account_type", "TEXT NULL"),
                ("ea_name", "TEXT NULL"),
                ("chart_symbol", "TEXT NULL"),
                ("chart_timeframe", "TEXT NULL"),
                ("magic_number", "INTEGER NULL"),
                ("execution_permission", "TEXT NOT NULL DEFAULT 'LOCKED'"),
                ("detected_account_login", "TEXT NULL"),
                ("detected_server", "TEXT NULL"),
                ("detected_company", "TEXT NULL"),
                ("detected_trade_mode", "TEXT NULL"),
                ("detected_currency", "TEXT NULL"),
                ("detected_equity", "REAL NULL"),
                ("terminal_connected", "INTEGER NULL"),
                ("terminal_trade_allowed", "INTEGER NULL"),
                ("xauusd_available", "INTEGER NULL"),
                ("xauusd_trade_mode", "TEXT NULL"),
                ("last_verified_at_utc", "TEXT NULL"),
                ("verification_status", "TEXT NULL"),
                ("verification_message_safe", "TEXT NULL"),
                ("last_verify_attempt_at_utc", "TEXT NULL"),
                ("terminal_data_path", "TEXT NULL"),
                ("terminal_instance_key", "TEXT NULL"),
                ("terminal_process_id", "INTEGER NULL"),
                ("detected_terminal_data_path", "TEXT NULL"),
                ("detected_terminal_path", "TEXT NULL"),
            ):
                self._ensure_column(conn, "mt5_targets", column, definition)
            for column, definition in (
                ("candidate_test_armed_at_utc", "TEXT NULL"),
                ("candidate_test_expires_at_utc", "TEXT NULL"),
                ("candidate_test_armed_by", "TEXT NULL"),
                ("candidate_test_publish_count", "INTEGER NOT NULL DEFAULT 0"),
                ("candidate_test_block_reason", "TEXT NULL"),
            ):
                self._ensure_column(conn, "routes", column, definition)
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
            worker_row = conn.execute("SELECT id FROM listener_worker_state WHERE id = 1").fetchone()
            if worker_row is None:
                now = utc_now_iso()
                conn.execute(
                    """
                    INSERT INTO listener_worker_state
                    (id, state, reconnect_count, active_route_count, dry_run, updated_at_utc)
                    VALUES (1, 'STOPPED', 0, 0, 1, ?)
                    """,
                    (now,),
                )

    def _ensure_column(
        self,
        conn: sqlite3.Connection,
        table: str,
        column: str,
        definition: str,
    ) -> None:
        columns = {
            row[1] for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
        }
        if column not in columns:
            conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")

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

    def public_telegram_status(
        self,
        *,
        telethon_available: bool,
        config_ready: bool,
        session_pending: bool = False,
    ) -> dict[str, Any]:
        row = self.get_telegram_status()
        return {
            "status": row.get("status", "DISCONNECTED"),
            "phone_masked": row.get("phone_masked"),
            "channel_count": row.get("channel_count", 0),
            "last_error_code": row.get("last_error_code"),
            "updated_at_utc": row.get("updated_at_utc"),
            "telethon_available": telethon_available,
            "config_ready": config_ready,
            "session_path_masked": row.get("session_path_masked"),
            "session_pending": session_pending,
        }

    def configure_telegram(self, phone_masked: str, session_path_masked: str) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'API_CONFIGURED',
                    phone_masked = ?,
                    session_path_masked = ?,
                    last_error_code = NULL,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (phone_masked, session_path_masked, now),
            )

    def set_telegram_config_error(self, error_code: str) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'ERROR',
                    last_error_code = ?,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (error_code, now),
            )

    def set_telegram_code_sent(self, phone_code_hash: str) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'CODE_SENT',
                    phone_code_hash = ?,
                    last_error_code = NULL,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (phone_code_hash, now),
            )

    def get_phone_code_hash(self) -> str | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT phone_code_hash FROM telegram_connection WHERE id = 1"
            ).fetchone()
        if row is None:
            return None
        return row["phone_code_hash"]

    def set_telegram_connected(self) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'CONNECTED',
                    phone_code_hash = NULL,
                    last_error_code = NULL,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (now,),
            )

    def set_telegram_two_factor_required(self) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'TWO_FACTOR_REQUIRED',
                    last_error_code = NULL,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (now,),
            )

    def set_telegram_auth_error(self, error_code: str) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'ERROR',
                    last_error_code = ?,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (error_code, now),
            )

    def set_telegram_disconnected(self) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE telegram_connection
                SET status = 'DISCONNECTED',
                    phone_code_hash = NULL,
                    last_error_code = NULL,
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (now,),
            )

    def sync_telegram_channels(self, channels: list[dict[str, Any]]) -> int:
        now = utc_now_iso()
        synced = 0
        with self._connect() as conn:
            for channel in channels:
                existing = conn.execute(
                    """
                    SELECT id, is_tracking FROM tracked_channels
                    WHERE telegram_channel_id = ?
                    """,
                    (channel["telegram_channel_id"],),
                ).fetchone()
                if existing:
                    conn.execute(
                        """
                        UPDATE tracked_channels
                        SET title = ?,
                            channel_type = ?,
                            username = ?,
                            last_message_at_utc = ?,
                            source = ?,
                            updated_at_utc = ?
                        WHERE telegram_channel_id = ?
                        """,
                        (
                            channel["title"],
                            channel["channel_type"],
                            channel.get("username"),
                            channel.get("last_message_at_utc"),
                            "TELEGRAM",
                            now,
                            channel["telegram_channel_id"],
                        ),
                    )
                else:
                    conn.execute(
                        """
                        INSERT INTO tracked_channels
                        (telegram_channel_id, title, channel_type, username, is_tracking,
                         last_message_at_utc, source, created_at_utc, updated_at_utc)
                        VALUES (?, ?, ?, ?, 0, ?, ?, ?, ?)
                        """,
                        (
                            channel["telegram_channel_id"],
                            channel["title"],
                            channel["channel_type"],
                            channel.get("username"),
                            channel.get("last_message_at_utc"),
                            "TELEGRAM",
                            now,
                            now,
                        ),
                    )
                synced += 1
            conn.execute(
                """
                UPDATE telegram_connection
                SET channel_count = (SELECT COUNT(*) FROM tracked_channels),
                    updated_at_utc = ?
                WHERE id = 1
                """,
                (now,),
            )
        return synced

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
                     last_message_at_utc, source, created_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?, 0, NULL, 'LOCAL_DEMO_DATA', ?, ?)
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

    def get_target(self, target_id: int) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM mt5_targets WHERE id = ?", (target_id,)).fetchone()
        return dict(row) if row else None

    def _validate_target_core(self, payload: dict[str, Any]) -> tuple[str, str, str, str, str]:
        seed_filename = validate_basename_safe(str(payload["seed_filename"]))
        details_filename = validate_basename_safe(str(payload["details_filename"]))
        if seed_filename == details_filename:
            raise DashboardValidationError("Seed and details filenames must differ")
        expected_type = str(
            payload.get("expected_account_type") or payload.get("account_mode") or "UNKNOWN"
        ).upper()
        if expected_type not in {"DEMO", "REAL", "UNKNOWN"}:
            raise DashboardValidationError("expected_account_type must be DEMO, REAL, or UNKNOWN")
        account_mode = expected_type if expected_type in ACCOUNT_MODES else "UNKNOWN"
        if payload.get("observer_only") in (False, 0, "0", "false"):
            raise DashboardValidationError("observer_only must remain enabled")
        if str(payload.get("execution_permission", "LOCKED")).upper() != "LOCKED":
            raise DashboardValidationError("execution_permission must remain LOCKED")
        return seed_filename, details_filename, account_mode, expected_type, str(payload["name"]).strip()

    def create_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        seed_filename, details_filename, account_mode, expected_type, name = self._validate_target_core(payload)
        now = utc_now_iso()
        terminal_data_path = str(payload.get("terminal_data_path") or "").strip() or None
        terminal_instance_key = str(payload.get("terminal_instance_key") or "").strip() or None
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO mt5_targets
                (name, terminal_label, broker_label, account_mode, file_common_root,
                 seed_filename, details_filename, observer_only, is_enabled,
                 terminal_exe_path, expected_account_login, expected_server, expected_account_type,
                 ea_name, chart_symbol, chart_timeframe, magic_number, execution_permission,
                 terminal_data_path, terminal_instance_key,
                 created_at_utc, updated_at_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?, ?, ?, ?, ?, ?, ?, ?, 'LOCKED', ?, ?, ?, ?)
                """,
                (
                    name,
                    str(payload["terminal_label"]).strip(),
                    str(payload["broker_label"]).strip(),
                    account_mode,
                    str(payload["file_common_root"]).strip(),
                    seed_filename,
                    details_filename,
                    str(payload.get("terminal_exe_path") or "").strip() or None,
                    str(payload.get("expected_account_login") or "").strip() or None,
                    str(payload.get("expected_server") or "").strip() or None,
                    expected_type,
                    str(payload.get("ea_name") or "Basket Recovery EA").strip(),
                    str(payload.get("chart_symbol") or "XAUUSD").strip(),
                    str(payload.get("chart_timeframe") or "M1").strip(),
                    int(payload["magic_number"]) if payload.get("magic_number") not in (None, "") else None,
                    terminal_data_path,
                    terminal_instance_key,
                    now,
                    now,
                ),
            )
            row = conn.execute("SELECT * FROM mt5_targets WHERE name = ?", (name,)).fetchone()
        return dict(row)

    def create_mt5_target(self, payload: dict[str, Any]) -> dict[str, Any]:
        return self.create_target(payload)

    def update_target(self, target_id: int, updates: dict[str, Any]) -> dict[str, Any]:
        if updates.get("observer_only") in (False, 0, "0", "false"):
            raise DashboardValidationError("observer_only cannot be disabled")
        if "execution_permission" in updates:
            raise DashboardValidationError("execution_permission cannot be changed")
        allowed_keys = (
            "name",
            "terminal_label",
            "broker_label",
            "seed_filename",
            "details_filename",
            "is_enabled",
            "terminal_exe_path",
            "expected_account_login",
            "expected_server",
            "expected_account_type",
            "file_common_root",
            "ea_name",
            "chart_symbol",
            "chart_timeframe",
            "magic_number",
            "terminal_data_path",
            "terminal_instance_key",
        )
        allowed = {}
        for key in allowed_keys:
            if key not in updates:
                continue
            value = updates[key]
            if key in ("seed_filename", "details_filename"):
                value = validate_basename_safe(str(value))
            if key == "expected_account_type":
                value = str(value).upper()
                if value not in {"DEMO", "REAL", "UNKNOWN"}:
                    raise DashboardValidationError("expected_account_type must be DEMO, REAL, or UNKNOWN")
                allowed["account_mode"] = value if value in ACCOUNT_MODES else "UNKNOWN"
            if key == "magic_number":
                value = int(value) if value not in (None, "") else None
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

    def disable_target(self, target_id: int) -> dict[str, Any]:
        return self.update_target(target_id, {"is_enabled": 0})

    def verify_rate_limit_ok(self, target_id: int, min_seconds: int) -> tuple[bool, int]:
        row = self.get_target(target_id)
        if row is None:
            raise DashboardValidationError("Target not found")
        last_attempt = row.get("last_verify_attempt_at_utc")
        now = utc_now_iso()
        if not last_attempt:
            with self._connect() as conn:
                conn.execute(
                    "UPDATE mt5_targets SET last_verify_attempt_at_utc = ? WHERE id = ?",
                    (now, target_id),
                )
            return True, 0
        from datetime import datetime, timezone

        previous = datetime.strptime(last_attempt, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        current = datetime.strptime(now, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        elapsed = int((current - previous).total_seconds())
        if elapsed < min_seconds:
            return False, min_seconds - elapsed
        with self._connect() as conn:
            conn.execute(
                "UPDATE mt5_targets SET last_verify_attempt_at_utc = ? WHERE id = ?",
                (now, target_id),
            )
        return True, 0

    def save_target_verification(self, target_id: int, fields: dict[str, Any]) -> None:
        allowed_keys = (
            "detected_account_login",
            "detected_server",
            "detected_company",
            "detected_trade_mode",
            "detected_currency",
            "detected_equity",
            "terminal_connected",
            "terminal_trade_allowed",
            "xauusd_available",
            "xauusd_trade_mode",
            "last_verified_at_utc",
            "verification_status",
            "verification_message_safe",
            "detected_terminal_data_path",
            "detected_terminal_path",
            "terminal_process_id",
        )
        updates = {key: fields[key] for key in allowed_keys if key in fields}
        if not updates:
            return
        now = utc_now_iso()
        sets = ", ".join(f"{key} = ?" for key in updates)
        values = list(updates.values()) + [now, target_id]
        with self._connect() as conn:
            conn.execute(
                f"UPDATE mt5_targets SET {sets}, updated_at_utc = ? WHERE id = ?",
                values,
            )

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
        self.expire_candidate_test_arms()
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT r.*,
                       c.title AS channel_title,
                       c.username AS channel_username,
                       c.telegram_channel_id,
                       c.is_tracking AS channel_is_tracking,
                       t.name AS target_name,
                       t.observer_only AS target_observer_only,
                       t.is_enabled AS target_is_enabled,
                       ls.listener_status,
                       ls.last_signal_status,
                       ls.last_error_code AS listener_last_error_code,
                       ls.last_publish_at_utc AS listener_last_publish_at_utc,
                       ls.started_at_utc AS listener_started_at_utc
                FROM routes r
                JOIN tracked_channels c ON c.id = r.channel_id
                JOIN mt5_targets t ON t.id = r.target_id
                LEFT JOIN route_listener_state ls ON ls.route_id = r.id
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

    def get_route_detail(self, route_id: int) -> dict[str, Any] | None:
        self.expire_candidate_test_arms()
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT r.*,
                       c.title AS channel_title,
                       c.username AS channel_username,
                       c.telegram_channel_id,
                       c.is_tracking AS channel_is_tracking,
                       t.name AS target_name,
                       t.observer_only AS target_observer_only,
                       t.is_enabled AS target_is_enabled,
                       t.account_mode,
                       t.expected_account_type,
                       t.execution_permission,
                       t.magic_number,
                       t.chart_symbol,
                       t.seed_filename,
                       t.details_filename,
                       t.broker_label,
                       t.terminal_data_path,
                       t.file_common_root
                FROM routes r
                JOIN tracked_channels c ON c.id = r.channel_id
                JOIN mt5_targets t ON t.id = r.target_id
                WHERE r.id = ?
                """,
                (route_id,),
            ).fetchone()
        return dict(row) if row else None

    def count_active_candidate_test_arms(self, *, exclude_route_id: int | None = None) -> int:
        with self._connect() as conn:
            if exclude_route_id is None:
                row = conn.execute(
                    "SELECT COUNT(*) AS count FROM routes WHERE mode = 'CANDIDATE_TEST_ARMED'"
                ).fetchone()
            else:
                row = conn.execute(
                    """
                    SELECT COUNT(*) AS count
                    FROM routes
                    WHERE mode = 'CANDIDATE_TEST_ARMED' AND id != ?
                    """,
                    (exclude_route_id,),
                ).fetchone()
        return int(row["count"]) if row else 0

    def expire_candidate_test_arms(self) -> list[int]:
        now = utc_now_iso()
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id
                FROM routes
                WHERE mode = 'CANDIDATE_TEST_ARMED'
                  AND candidate_test_expires_at_utc IS NOT NULL
                  AND candidate_test_expires_at_utc <= ?
                """,
                (now,),
            ).fetchall()
            expired_ids = [int(row["id"]) for row in rows]
            if not expired_ids:
                return []
            conn.executemany(
                """
                UPDATE routes
                SET mode = 'CANDIDATE_TEST_EXPIRED',
                    candidate_test_block_reason = 'CANDIDATE_TEST_TTL_EXPIRED',
                    updated_at_utc = ?
                WHERE id = ?
                """,
                [(now, route_id) for route_id in expired_ids],
            )
        return expired_ids

    def arm_candidate_test_route(
        self,
        route_id: int,
        *,
        armed_at_utc: str,
        expires_at_utc: str,
        armed_by: str,
    ) -> dict[str, Any]:
        now = utc_now_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE routes
                SET mode = 'CANDIDATE_TEST_ARMED',
                    candidate_test_armed_at_utc = ?,
                    candidate_test_expires_at_utc = ?,
                    candidate_test_armed_by = ?,
                    candidate_test_publish_count = 0,
                    candidate_test_block_reason = NULL,
                    updated_at_utc = ?
                WHERE id = ?
                """,
                (armed_at_utc, expires_at_utc, armed_by, now, route_id),
            )
            if cursor.rowcount == 0:
                raise DashboardValidationError("Route not found")
            row = conn.execute("SELECT * FROM routes WHERE id = ?", (route_id,)).fetchone()
        return dict(row)

    def disarm_candidate_test_route(self, route_id: int) -> dict[str, Any]:
        now = utc_now_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE routes
                SET mode = 'OBSERVER_ONLY',
                    candidate_test_armed_at_utc = NULL,
                    candidate_test_expires_at_utc = NULL,
                    candidate_test_armed_by = NULL,
                    candidate_test_publish_count = 0,
                    candidate_test_block_reason = NULL,
                    updated_at_utc = ?
                WHERE id = ?
                """,
                (now, route_id),
            )
            if cursor.rowcount == 0:
                raise DashboardValidationError("Route not found")
            row = conn.execute("SELECT * FROM routes WHERE id = ?", (route_id,)).fetchone()
        return dict(row)

    def consume_candidate_test_publish(self, route_id: int) -> dict[str, Any]:
        now = utc_now_iso()
        with self._connect() as conn:
            row = conn.execute("SELECT * FROM routes WHERE id = ?", (route_id,)).fetchone()
            if row is None:
                raise DashboardValidationError("Route not found")
            route = dict(row)
            publish_count = int(route.get("candidate_test_publish_count") or 0) + 1
            mode = "CANDIDATE_TEST_CONSUMED" if publish_count >= 1 else route["mode"]
            conn.execute(
                """
                UPDATE routes
                SET candidate_test_publish_count = ?,
                    mode = ?,
                    candidate_test_block_reason = NULL,
                    updated_at_utc = ?
                WHERE id = ?
                """,
                (publish_count, mode, now, route_id),
            )
            updated = conn.execute("SELECT * FROM routes WHERE id = ?", (route_id,)).fetchone()
        return dict(updated)

    def block_candidate_test_route(self, route_id: int, *, reason: str) -> dict[str, Any]:
        now = utc_now_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                UPDATE routes
                SET mode = 'CANDIDATE_TEST_BLOCKED',
                    candidate_test_block_reason = ?,
                    updated_at_utc = ?
                WHERE id = ?
                """,
                (reason, now, route_id),
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

    def get_route_start_context(self, route_id: int) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT r.id AS route_id,
                       r.name AS route_name,
                       r.channel_id,
                       r.target_id,
                       r.mode AS route_mode,
                       r.is_enabled AS route_enabled,
                       c.telegram_channel_id,
                       c.title AS channel_title,
                       c.is_tracking,
                       t.name AS target_name,
                       t.file_common_root,
                       t.seed_filename,
                       t.details_filename,
                       t.observer_only,
                       t.is_enabled AS target_enabled
                FROM routes r
                JOIN tracked_channels c ON c.id = r.channel_id
                JOIN mt5_targets t ON t.id = r.target_id
                WHERE r.id = ?
                """,
                (route_id,),
            ).fetchone()
        return dict(row) if row else None

    def get_route_listener_state(self, route_id: int) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM route_listener_state WHERE route_id = ?",
                (route_id,),
            ).fetchone()
        return dict(row) if row else None

    def upsert_route_listener_state(
        self,
        route_id: int,
        *,
        listener_status: str,
        last_signal_status: str | None = None,
        last_error_code: str | None = None,
        last_publish_at_utc: str | None = None,
        started_at_utc: str | None = None,
    ) -> None:
        now = utc_now_iso()
        existing = self.get_route_listener_state(route_id)
        with self._connect() as conn:
            if existing is None:
                conn.execute(
                    """
                    INSERT INTO route_listener_state
                    (route_id, listener_status, last_signal_status, last_error_code,
                     last_publish_at_utc, started_at_utc, updated_at_utc)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        route_id,
                        listener_status,
                        last_signal_status,
                        last_error_code,
                        last_publish_at_utc,
                        started_at_utc,
                        now,
                    ),
                )
                return
            conn.execute(
                """
                UPDATE route_listener_state
                SET listener_status = ?,
                    last_signal_status = COALESCE(?, last_signal_status),
                    last_error_code = ?,
                    last_publish_at_utc = COALESCE(?, last_publish_at_utc),
                    started_at_utc = COALESCE(?, started_at_utc),
                    updated_at_utc = ?
                WHERE route_id = ?
                """,
                (
                    listener_status,
                    last_signal_status,
                    last_error_code,
                    last_publish_at_utc,
                    started_at_utc,
                    now,
                    route_id,
                ),
            )

    def update_route_publish_status(
        self,
        route_id: int,
        publish_status: str,
        publish_at_utc: str,
    ) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE routes
                SET last_publish_status = ?,
                    last_publish_at_utc = ?,
                    updated_at_utc = ?
                WHERE id = ?
                """,
                (publish_status, publish_at_utc, now, route_id),
            )

    def add_route_event(
        self,
        route_id: int,
        *,
        event_type: str,
        status: str,
        target_id: int | None,
        safe_summary: str,
        fingerprint_short: str | None = None,
        seed_bytes: int | None = None,
        details_bytes: int | None = None,
    ) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                INSERT INTO route_events
                (route_id, event_type, status, target_id, fingerprint_short,
                 seed_bytes, details_bytes, safe_summary, created_at_utc)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    route_id,
                    event_type,
                    status,
                    target_id,
                    fingerprint_short,
                    seed_bytes,
                    details_bytes,
                    safe_summary,
                    now,
                ),
            )

    def list_route_events(self, route_id: int, limit: int = 50) -> list[dict[str, Any]]:
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, route_id, event_type, status, target_id, fingerprint_short,
                       seed_bytes, details_bytes, safe_summary, created_at_utc
                FROM route_events
                WHERE route_id = ?
                ORDER BY id DESC
                LIMIT ?
                """,
                (route_id, limit),
            ).fetchall()
        return [dict(row) for row in rows]

    def list_signal_history_candidates(
        self,
        *,
        date_from: str | None = None,
        date_to: str | None = None,
        channel_id: int | None = None,
        target_id: int | None = None,
        limit: int = 500,
    ) -> list[dict[str, Any]]:
        clauses = ["e.status IN ('PUBLISH_READY', 'PUBLISH_FAILED')"]
        params: list[Any] = []
        if date_from:
            clauses.append("e.created_at_utc >= ?")
            params.append(date_from)
        if date_to:
            clauses.append("e.created_at_utc <= ?")
            params.append(date_to)
        if channel_id is not None:
            clauses.append("r.channel_id = ?")
            params.append(channel_id)
        if target_id is not None:
            clauses.append("r.target_id = ?")
            params.append(target_id)
        where_sql = " AND ".join(clauses)
        params.append(min(max(limit, 1), 2000))
        with self._connect() as conn:
            rows = conn.execute(
                f"""
                SELECT
                    e.id,
                    e.route_id,
                    e.status,
                    e.fingerprint_short,
                    e.safe_summary,
                    e.created_at_utc,
                    r.channel_id,
                    r.target_id,
                    c.title AS channel_title,
                    t.name AS target_name
                FROM route_events e
                JOIN routes r ON r.id = e.route_id
                JOIN tracked_channels c ON c.id = r.channel_id
                JOIN mt5_targets t ON t.id = r.target_id
                WHERE {where_sql}
                ORDER BY e.created_at_utc DESC, e.id DESC
                LIMIT ?
                """,
                params,
            ).fetchall()
        return [dict(row) for row in rows]

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
                "file_common_write": "NOT_IMPLEMENTED_IN_DASHBOARD",
                "ea_control": "NOT_IMPLEMENTED",
                "telegram_login": "IMPLEMENTED_LOCAL_ONLY",
                "channel_live_sync": "IMPLEMENTED_ON_DEMAND",
            },
        }

    def get_listener_worker_state(self) -> dict[str, Any]:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, state, pid, started_at_utc, last_heartbeat_at_utc,
                       reconnect_count, active_route_count, active_route_ids_json,
                       safe_last_error, dry_run, updated_at_utc
                FROM listener_worker_state
                WHERE id = 1
                """
            ).fetchone()
        if row is None:
            return {
                "state": "STOPPED",
                "pid": None,
                "started_at_utc": None,
                "last_heartbeat_at_utc": None,
                "reconnect_count": 0,
                "active_route_count": 0,
                "active_route_ids": [],
                "safe_last_error": None,
                "dry_run": True,
                "updated_at_utc": utc_now_iso(),
            }
        item = dict(row)
        raw_ids = item.pop("active_route_ids_json", None)
        item["active_route_ids"] = json.loads(raw_ids) if raw_ids else []
        item["dry_run"] = bool(item.get("dry_run", 1))
        return item

    def upsert_listener_worker_state(self, **fields: Any) -> None:
        allowed = {
            "state",
            "pid",
            "started_at_utc",
            "last_heartbeat_at_utc",
            "reconnect_count",
            "active_route_count",
            "active_route_ids_json",
            "safe_last_error",
            "dry_run",
        }
        updates = {key: value for key, value in fields.items() if key in allowed}
        if not updates:
            return
        if "active_route_ids_json" not in updates and "active_route_ids" in fields:
            ids = fields["active_route_ids"]
            normalized = sorted(set(ids))
            updates["active_route_ids_json"] = json.dumps(normalized)
            updates["active_route_count"] = len(normalized)
        updates.pop("active_route_ids", None)
        updates["updated_at_utc"] = utc_now_iso()
        columns = ", ".join(f"{key} = ?" for key in updates)
        values = list(updates.values())
        with self._connect() as conn:
            conn.execute(
                f"UPDATE listener_worker_state SET {columns} WHERE id = 1",
                values,
            )

    def enqueue_listener_worker_command(
        self,
        command_type: str,
        *,
        route_id: int | None = None,
    ) -> int:
        now = utc_now_iso()
        with self._connect() as conn:
            cursor = conn.execute(
                """
                INSERT INTO listener_worker_commands
                (command_type, route_id, status, created_at_utc)
                VALUES (?, ?, 'PENDING', ?)
                """,
                (command_type, route_id, now),
            )
            return int(cursor.lastrowid)

    def claim_pending_worker_commands(self, limit: int = 20) -> list[dict[str, Any]]:
        now = utc_now_iso()
        with self._connect() as conn:
            rows = conn.execute(
                """
                SELECT id, command_type, route_id, status, created_at_utc
                FROM listener_worker_commands
                WHERE status = 'PENDING'
                ORDER BY id ASC
                LIMIT ?
                """,
                (limit,),
            ).fetchall()
            ids = [int(row["id"]) for row in rows]
            if ids:
                placeholders = ",".join("?" for _ in ids)
                conn.execute(
                    f"""
                    UPDATE listener_worker_commands
                    SET status = 'PROCESSING', processed_at_utc = ?
                    WHERE id IN ({placeholders})
                    """,
                    [now, *ids],
                )
        return [dict(row) for row in rows]

    def complete_worker_command(
        self,
        command_id: int,
        *,
        status: str,
        result: dict[str, Any] | None = None,
    ) -> None:
        now = utc_now_iso()
        with self._connect() as conn:
            conn.execute(
                """
                UPDATE listener_worker_commands
                SET status = ?, result_json = ?, processed_at_utc = ?
                WHERE id = ?
                """,
                (status, json.dumps(result) if result is not None else None, now, command_id),
            )

    def get_worker_command(self, command_id: int) -> dict[str, Any] | None:
        with self._connect() as conn:
            row = conn.execute(
                """
                SELECT id, command_type, route_id, status, result_json,
                       created_at_utc, processed_at_utc
                FROM listener_worker_commands
                WHERE id = ?
                """,
                (command_id,),
            ).fetchone()
        if row is None:
            return None
        item = dict(row)
        if item.get("result_json"):
            item["result"] = json.loads(item["result_json"])
        else:
            item["result"] = None
        del item["result_json"]
        return item
