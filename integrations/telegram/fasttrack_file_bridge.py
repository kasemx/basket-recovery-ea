#!/usr/bin/env python3
"""FastTrack FILE_COMMON bridge — stdin simulator, atomic publish, Telethon listener."""

from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import re
import sys
import time
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import IO, Any, Literal

MAX_BYTES = 8192
SIGNAL_META_MARKER = "|signal_meta="
SIGNAL_META_ALLOWLIST_KEYS = frozenset(
    {
        "symbol",
        "side",
        "entry_low",
        "entry_high",
        "stop_loss",
        "take_profits",
    }
)
SYMBOL_ALIASES = {
    "gold": "XAUUSD",
    "xauusd": "XAUUSD",
    "xau/usd": "XAUUSD",
    "xau": "XAUUSD",
}
DETAILS_ENTRY_RANGE_PATTERN = re.compile(
    r"now\s+(?P<low>\d+(?:\.\d+)?)\s*-\s*(?P<high>\d+(?:\.\d+)?)",
    re.IGNORECASE,
)
SL_LINE_PATTERN = re.compile(r"^SL:\s*(?P<value>.+)\s*$", re.IGNORECASE)
TP_LINE_PATTERN = re.compile(r"^TP:\s*(?P<value>.+)\s*$", re.IGNORECASE)
SEED_PATTERN = re.compile(
    r"^(?P<symbol>\S+)\s+(?P<direction>buy|sell)\s+now(?:\s*[.!?]*\s*)?$",
    re.IGNORECASE,
)
DETAILS_HEADER_PATTERN = re.compile(
    r"^(?P<symbol>\S+)\s+(?P<direction>buy|sell)\s+now\b",
    re.IGNORECASE,
)
DETAILS_RANGE_HINT = re.compile(r"now\s+\d", re.IGNORECASE)
SUPPORTED_SYMBOLS = frozenset(SYMBOL_ALIASES)
_UNICODE_DASH_AND_SPACE = str.maketrans(
    {
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\u00a0": " ",
        "\u202f": " ",
        "\u2007": " ",
        "\u2009": " ",
        "\u200a": " ",
        "\u2028": "\n",
    }
)


class BridgeValidationError(ValueError):
    """Raised when payload or path validation fails."""


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def utc_date() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def validate_basename(name: str) -> str:
    trimmed = name.strip()
    if not trimmed:
        raise BridgeValidationError("Filename must not be empty")
    for forbidden in ("/", "\\", "..", ":"):
        if forbidden in trimmed:
            raise BridgeValidationError(f"Invalid filename: contains '{forbidden}'")
    return trimmed


def resolve_root(root: str) -> Path:
    resolved = Path(root).expanduser().resolve()
    if not resolved.is_dir():
        raise BridgeValidationError(f"FILE_COMMON root is not a directory: {resolved}")
    return resolved


def assert_within_root(root: Path, target: Path) -> None:
    try:
        target.resolve().relative_to(root.resolve())
    except ValueError as exc:
        raise BridgeValidationError(f"Path escapes FILE_COMMON root: {target}") from exc


def validate_ascii(text: str, label: str) -> None:
    try:
        text.encode("ascii")
    except UnicodeEncodeError as exc:
        raise BridgeValidationError(f"{label} must be ASCII-safe") from exc


def validate_non_empty(text: str, label: str) -> str:
    trimmed = text.strip()
    if not trimmed:
        raise BridgeValidationError(f"{label} must not be empty")
    return trimmed


def normalize_line_endings(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


def sanitize_signal_text(text: str) -> str:
    """Strip emoji/decoration and map unicode dashes so FastTrack ASCII parse can run."""
    translated = normalize_line_endings(text).translate(_UNICODE_DASH_AND_SPACE)
    kept: list[str] = []
    for character in translated:
        code = ord(character)
        if character == "\n" or (code < 128 and (character.isprintable() or character in "\t")):
            kept.append(" " if character == "\t" else character)
    lines = [" ".join(line.split()) for line in "".join(kept).split("\n")]
    while lines and lines[0] == "":
        lines.pop(0)
    while lines and lines[-1] == "":
        lines.pop()
    return "\n".join(lines)


def validate_seed_format(text: str) -> tuple[str, str]:
    normalized = validate_non_empty(text, "Seed").strip()
    validate_ascii(normalized, "Seed")
    match = SEED_PATTERN.match(normalized)
    if not match:
        raise BridgeValidationError(
            "Seed format must be '<symbol> <buy|sell> now'"
        )
    symbol = match.group("symbol").lower()
    direction = match.group("direction").lower()
    if symbol not in SUPPORTED_SYMBOLS:
        raise BridgeValidationError(f"Unsupported symbol alias: {symbol}")
    return symbol, direction


def validate_details_text(text: str) -> str:
    normalized = normalize_line_endings(text)
    validate_non_empty(normalized, "Details")
    validate_ascii(normalized, "Details")
    return normalized


def validate_payload_size(text: str, label: str) -> None:
    encoded = text.encode("utf-8")
    if len(encoded) > MAX_BYTES:
        raise BridgeValidationError(f"{label} exceeds {MAX_BYTES} bytes")


def validate_pair_payload(seed_text: str, details_text: str) -> tuple[str, str, str, str]:
    symbol, direction = validate_seed_format(seed_text)
    details = validate_details_text(details_text)
    seed = validate_non_empty(seed_text, "Seed").strip()
    validate_payload_size(seed, "Seed")
    validate_payload_size(details, "Details")
    return seed, details, symbol, direction


def pair_fingerprint(seed_text: str, details_text: str) -> str:
    seed = validate_non_empty(seed_text, "Seed").strip()
    details = validate_details_text(details_text)
    payload = f"{seed}\n---\n{details}".encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def raw_message_hash(text: str) -> str:
    normalized = normalize_line_endings(text).strip()
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def short_fingerprint(full_hash: str) -> str:
    return full_hash[:12]


def build_correlation_key(
    symbol: str,
    direction: str,
    seed_message_id: str,
    channel_id: str = "",
) -> str:
    if channel_id:
        return f"{symbol}|{direction}|{utc_date()}|{channel_id}|{seed_message_id}"
    return f"{symbol}|{direction}|{utc_date()}|{seed_message_id}"


def parse_details_header_symbol_direction(text: str) -> tuple[str, str] | None:
    normalized = normalize_line_endings(text).strip()
    if not normalized:
        return None
    first_line = normalized.split("\n", 1)[0].strip()
    match = DETAILS_HEADER_PATTERN.match(first_line)
    if not match:
        return None
    symbol = match.group("symbol").lower()
    direction = match.group("direction").lower()
    if symbol not in SUPPORTED_SYMBOLS:
        return None
    return symbol, direction


def _normalize_price_number(token: str) -> int | None:
    trimmed = token.strip()
    if not trimmed:
        return None
    try:
        value = float(trimmed)
    except ValueError:
        return None
    if value <= 0:
        return None
    if value.is_integer():
        return int(value)
    return int(value)


def _canonical_symbol(symbol_alias: str) -> str | None:
    return SYMBOL_ALIASES.get(symbol_alias.strip().lower())


def _canonical_side(direction: str) -> str | None:
    normalized = direction.strip().upper()
    if normalized in ("BUY", "SELL"):
        return normalized
    return None


def build_signal_meta(seed_text: str, details_text: str) -> dict[str, Any]:
    """Build dashboard-safe signal metadata from validated parser output only."""
    meta: dict[str, Any] = {
        "symbol": None,
        "side": None,
        "entry_low": None,
        "entry_high": None,
        "stop_loss": None,
        "take_profits": [],
    }
    try:
        _seed, details, symbol_alias, direction = validate_pair_payload(seed_text, details_text)
    except BridgeValidationError:
        return _finalize_signal_meta(meta)

    meta["symbol"] = _canonical_symbol(symbol_alias)
    meta["side"] = _canonical_side(direction)

    lines = [line.strip() for line in details.split("\n") if line.strip()]
    if lines:
        range_match = DETAILS_ENTRY_RANGE_PATTERN.search(lines[0])
        if range_match:
            meta["entry_low"] = _normalize_price_number(range_match.group("low"))
            meta["entry_high"] = _normalize_price_number(range_match.group("high"))

        take_profits: list[str] = []
        for line in lines[1:]:
            sl_match = SL_LINE_PATTERN.match(line)
            if sl_match:
                meta["stop_loss"] = _normalize_price_number(sl_match.group("value"))
                continue
            tp_match = TP_LINE_PATTERN.match(line)
            if tp_match:
                tp_value = tp_match.group("value").strip()
                if tp_value.lower() == "open":
                    take_profits.append("OPEN")
                else:
                    parsed_tp = _normalize_price_number(tp_value)
                    if parsed_tp is not None:
                        take_profits.append(str(parsed_tp))
        meta["take_profits"] = take_profits

    return _finalize_signal_meta(meta)


def _finalize_signal_meta(meta: dict[str, Any]) -> dict[str, Any]:
    cleaned: dict[str, Any] = {}
    for key in SIGNAL_META_ALLOWLIST_KEYS:
        if key not in meta:
            continue
        value = meta[key]
        if key == "take_profits":
            cleaned[key] = [str(item) for item in value] if isinstance(value, list) else []
            continue
        if key in ("entry_low", "entry_high", "stop_loss"):
            cleaned[key] = value if isinstance(value, int) else None
            continue
        if value is not None:
            cleaned[key] = str(value)
    return cleaned


def append_signal_meta_to_safe_summary(base_summary: str, seed_text: str, details_text: str) -> str:
    return format_safe_summary_with_signal_meta(base_summary, build_signal_meta(seed_text, details_text))


def format_safe_summary_with_signal_meta(base_summary: str, meta: dict[str, Any] | None) -> str:
    if not meta or not meta.get("symbol") or not meta.get("side"):
        return base_summary
    cleaned = _finalize_signal_meta(meta)
    payload = json.dumps(cleaned, separators=(",", ":"))
    return f"{base_summary}{SIGNAL_META_MARKER}{payload}"


def classify_telegram_text(text: str) -> Literal["empty", "non_ascii", "seed", "details", "unrecognized"]:
    original = normalize_line_endings(text).strip()
    if not original:
        return "empty"
    normalized = sanitize_signal_text(original)
    if not normalized:
        try:
            validate_ascii(original, "Message")
        except BridgeValidationError:
            return "non_ascii"
        return "empty"

    lines = [line.strip() for line in normalized.split("\n") if line.strip()]
    if not lines:
        return "empty"
    first_line = lines[0]
    if len(lines) == 1 and SEED_PATTERN.match(first_line):
        return "seed"
    if DETAILS_HEADER_PATTERN.match(first_line) and (
        DETAILS_RANGE_HINT.search(first_line) or "SL:" in normalized.upper()
    ):
        return "details"
    if "SL:" in normalized.upper() and DETAILS_HEADER_PATTERN.match(first_line):
        return "details"
    return "unrecognized"


class BridgeLogger:
    def __init__(self, log_file: str | None = None) -> None:
        self._log_path = Path(log_file).expanduser() if log_file else None
        if self._log_path:
            self._log_path.parent.mkdir(parents=True, exist_ok=True)

    def log(self, bridge_event: str, **fields: object) -> None:
        parts = [f"bridge_event={bridge_event}"]
        for key in sorted(fields):
            value = fields[key]
            if value is None:
                continue
            text = str(value).replace("\n", "\\n")
            parts.append(f"{key}={text}")
        line = " ".join(parts)
        print(line, flush=True)
        if self._log_path:
            with self._log_path.open("a", encoding="ascii", newline="\n") as handle:
                handle.write(line + "\n")


def write_full_file(path: Path, content: str) -> None:
    data = content.encode("utf-8")
    with path.open("wb") as handle:
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())


def safe_unlink(path: Path) -> None:
    if path.exists():
        path.unlink()


def move_to_hold(path: Path) -> Path | None:
    if not path.exists():
        return None
    hold_path = path.with_name(f"{path.name}.hold.{uuid.uuid4().hex}")
    os.replace(path, hold_path)
    return hold_path


@dataclass
class PublishResult:
    correlation_key: str
    fingerprint: str
    seed_bytes: int
    details_bytes: int
    signal_meta: dict[str, Any] | None = None


class AtomicPublisher:
    def __init__(self, logger: BridgeLogger) -> None:
        self._logger = logger
        self._published_fingerprints: set[str] = set()
        self._last_signal_meta: dict[str, Any] | None = None
        self._last_seed_bytes: int | None = None
        self._last_details_bytes: int | None = None

    @property
    def last_signal_meta(self) -> dict[str, Any] | None:
        return self._last_signal_meta

    @property
    def last_seed_bytes(self) -> int | None:
        return self._last_seed_bytes

    @property
    def last_details_bytes(self) -> int | None:
        return self._last_details_bytes

    def publish_pair(
        self,
        *,
        root: Path,
        seed_filename: str,
        details_filename: str,
        seed_text: str,
        details_text: str,
        correlation_key: str,
        mode: str,
        dry_run: bool = False,
    ) -> PublishResult:
        seed_name = validate_basename(seed_filename)
        details_name = validate_basename(details_filename)
        seed, details, _symbol, _direction = validate_pair_payload(seed_text, details_text)
        fingerprint = pair_fingerprint(seed, details)
        signal_meta = build_signal_meta(seed, details)

        if fingerprint in self._published_fingerprints:
            self._logger.log(
                "SKIPPED",
                reason="dedup",
                correlation_key=correlation_key,
                pair_fingerprint=short_fingerprint(fingerprint),
                mode=mode,
                timestamp_utc=utc_now_iso(),
            )
            return PublishResult(
                correlation_key=correlation_key,
                fingerprint=fingerprint,
                seed_bytes=len(seed.encode("utf-8")),
                details_bytes=len(details.encode("utf-8")),
            )

        seed_final = root / seed_name
        details_final = root / details_name
        assert_within_root(root, seed_final)
        assert_within_root(root, details_final)

        seed_bytes = len(seed.encode("utf-8"))
        details_bytes = len(details.encode("utf-8"))
        self._last_signal_meta = signal_meta
        self._last_seed_bytes = seed_bytes
        self._last_details_bytes = details_bytes

        if dry_run:
            self._logger.log(
                "PUBLISH_READY",
                correlation_key=correlation_key,
                pair_fingerprint=short_fingerprint(fingerprint),
                seed_file=seed_name,
                details_file=details_name,
                seed_bytes=seed_bytes,
                details_bytes=details_bytes,
                mode=mode,
                timestamp_utc=utc_now_iso(),
                dry_run="true",
            )
            self._published_fingerprints.add(fingerprint)
            return PublishResult(
                correlation_key=correlation_key,
                fingerprint=fingerprint,
                seed_bytes=seed_bytes,
                details_bytes=details_bytes,
                signal_meta=signal_meta,
            )

        seed_hold: Path | None = None
        details_hold: Path | None = None
        details_staging: Path | None = None
        seed_staging: Path | None = None
        seed_final_created = False

        try:
            seed_hold = move_to_hold(seed_final)
            details_hold = move_to_hold(details_final)

            details_staging = details_final.with_name(
                f"{details_name}.part.{uuid.uuid4().hex}"
            )
            assert_within_root(root, details_staging)
            write_full_file(details_staging, details)
            os.replace(details_staging, details_final)
            details_staging = None

            seed_staging = seed_final.with_name(
                f"{seed_name}.part.{uuid.uuid4().hex}"
            )
            assert_within_root(root, seed_staging)
            write_full_file(seed_staging, seed)
            os.replace(seed_staging, seed_final)
            seed_staging = None
            seed_final_created = True

            if seed_hold is not None:
                safe_unlink(seed_hold)
                seed_hold = None
            if details_hold is not None:
                safe_unlink(details_hold)
                details_hold = None

            self._published_fingerprints.add(fingerprint)
            self._logger.log(
                "PUBLISH_READY",
                correlation_key=correlation_key,
                pair_fingerprint=short_fingerprint(fingerprint),
                seed_file=seed_name,
                details_file=details_name,
                seed_bytes=seed_bytes,
                details_bytes=details_bytes,
                mode=mode,
                timestamp_utc=utc_now_iso(),
            )
            return PublishResult(
                correlation_key=correlation_key,
                fingerprint=fingerprint,
                seed_bytes=seed_bytes,
                details_bytes=details_bytes,
                signal_meta=signal_meta,
            )
        except Exception as exc:
            if details_staging is not None:
                safe_unlink(details_staging)
            if seed_staging is not None:
                safe_unlink(seed_staging)

            if not seed_final_created:
                if seed_final.exists():
                    safe_unlink(seed_final)
                if seed_hold is not None and seed_hold.exists():
                    os.replace(seed_hold, seed_final)
                    seed_hold = None

            if details_hold is not None and details_hold.exists():
                if details_final.exists():
                    safe_unlink(details_final)
                os.replace(details_hold, details_final)
                details_hold = None
            elif details_final.exists() and not seed_final_created:
                safe_unlink(details_final)

            if seed_hold is not None:
                safe_unlink(seed_hold)
            if details_hold is not None:
                safe_unlink(details_hold)

            self._logger.log(
                "ERROR",
                reason="publish_failed",
                detail=str(exc),
                correlation_key=correlation_key,
                pair_fingerprint=short_fingerprint(fingerprint),
                seed_file=seed_name,
                details_file=details_name,
                mode=mode,
                timestamp_utc=utc_now_iso(),
            )
            raise


@dataclass
class PendingSeed:
    text: str
    message_id: str
    symbol: str
    direction: str
    received_at: float
    channel_id: str = ""
    grouped_id: str | None = None
    telegram_message_id: int | None = None


@dataclass
class PairMatcher:
    publisher: AtomicPublisher
    root: Path
    seed_filename: str
    details_filename: str
    pair_timeout_seconds: int
    logger: BridgeLogger
    mode: str
    dry_run: bool = False
    pending_seed: PendingSeed | None = None

    def _now(self) -> float:
        return time.monotonic()

    def _expire_pending_seed_if_needed(self) -> None:
        if self.pending_seed is None:
            return
        elapsed = self._now() - self.pending_seed.received_at
        if elapsed > self.pair_timeout_seconds:
            self.logger.log(
                "SKIPPED",
                reason="pair_expired",
                correlation_key=build_correlation_key(
                    self.pending_seed.symbol,
                    self.pending_seed.direction,
                    self.pending_seed.message_id,
                    self.pending_seed.channel_id,
                ),
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
            self._clear_pending_seed(self.pending_seed)

    def _clear_pending_seed(self, seed: PendingSeed) -> None:
        if self.pending_seed is seed:
            self.pending_seed = None

    def _synthetic_seed_from_details(
        self,
        details: str,
        *,
        message_id: str,
        channel_id: str = "",
        grouped_id: int | None = None,
        telegram_message_id: int | None = None,
    ) -> PendingSeed | None:
        header = parse_details_header_symbol_direction(details)
        if header is None:
            return None
        symbol, direction = header
        return PendingSeed(
            text=f"{symbol} {direction} now",
            message_id=message_id or "synthetic-seed",
            symbol=symbol,
            direction=direction,
            received_at=self._now(),
            channel_id=channel_id,
            grouped_id=str(grouped_id) if grouped_id is not None else None,
            telegram_message_id=telegram_message_id,
        )

    def ingest_seed(self, text: str, message_id: str) -> None:
        self._expire_pending_seed_if_needed()
        symbol, direction = validate_seed_format(text)
        if self.pending_seed is not None:
            self.logger.log(
                "SKIPPED",
                reason="stale_seed_replaced",
                correlation_key=build_correlation_key(
                    self.pending_seed.symbol,
                    self.pending_seed.direction,
                    self.pending_seed.message_id,
                    self.pending_seed.channel_id,
                ),
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
        self.pending_seed = PendingSeed(
            text=text.strip(),
            message_id=message_id or "unknown-seed",
            symbol=symbol,
            direction=direction,
            received_at=self._now(),
        )

    def ingest_details(self, text: str, message_id: str) -> None:
        self._expire_pending_seed_if_needed()
        details = validate_details_text(text)
        seed = self.pending_seed
        if seed is None:
            seed = self._synthetic_seed_from_details(details, message_id=message_id)
            if seed is None:
                self.logger.log(
                    "SKIPPED",
                    reason="details_without_seed",
                    message_id=message_id or "unknown-details",
                    mode=self.mode,
                    timestamp_utc=utc_now_iso(),
                )
                return
        correlation_key = build_correlation_key(
            seed.symbol,
            seed.direction,
            seed.message_id,
            seed.channel_id,
        )
        self.publisher.publish_pair(
            root=self.root,
            seed_filename=self.seed_filename,
            details_filename=self.details_filename,
            seed_text=seed.text,
            details_text=details,
            correlation_key=correlation_key,
            mode=self.mode,
            dry_run=self.dry_run,
        )
        self.pending_seed = None

    def publish_matched_pair(self, seed: PendingSeed, details_text: str, details_message_id: str) -> None:
        details = validate_details_text(details_text)
        correlation_key = build_correlation_key(
            seed.symbol,
            seed.direction,
            seed.message_id,
            seed.channel_id,
        )
        self.publisher.publish_pair(
            root=self.root,
            seed_filename=self.seed_filename,
            details_filename=self.details_filename,
            seed_text=seed.text,
            details_text=details,
            correlation_key=correlation_key,
            mode=self.mode,
            dry_run=self.dry_run,
        )
        if self.pending_seed is seed:
            self.pending_seed = None


@dataclass
class TelegramPairMatcher(PairMatcher):
    _seed_by_grouped_id: dict[str, PendingSeed] = field(default_factory=dict)

    def _unregister_seed(self, seed: PendingSeed) -> None:
        if seed.grouped_id is not None:
            key = str(seed.grouped_id)
            if self._seed_by_grouped_id.get(key) is seed:
                del self._seed_by_grouped_id[key]

    def _clear_pending_seed(self, seed: PendingSeed) -> None:
        self._unregister_seed(seed)
        super()._clear_pending_seed(seed)

    def ingest_telegram_seed(
        self,
        text: str,
        *,
        message_id: str,
        channel_id: str,
        grouped_id: int | None,
        telegram_message_id: int,
    ) -> None:
        self._expire_pending_seed_if_needed()
        symbol, direction = validate_seed_format(text)
        if self.pending_seed is not None:
            self.logger.log(
                "SKIPPED",
                reason="stale_seed_replaced",
                correlation_key=build_correlation_key(
                    self.pending_seed.symbol,
                    self.pending_seed.direction,
                    self.pending_seed.message_id,
                    self.pending_seed.channel_id,
                ),
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
            self._unregister_seed(self.pending_seed)

        seed = PendingSeed(
            text=text.strip(),
            message_id=message_id,
            symbol=symbol,
            direction=direction,
            received_at=self._now(),
            channel_id=channel_id,
            grouped_id=str(grouped_id) if grouped_id is not None else None,
            telegram_message_id=telegram_message_id,
        )
        self.pending_seed = seed
        if seed.grouped_id is not None:
            self._seed_by_grouped_id[seed.grouped_id] = seed

    def find_seed_for_details(
        self,
        details_text: str,
        *,
        grouped_id: int | None,
        reply_to_msg_id: int | None,
    ) -> PendingSeed | None:
        header = parse_details_header_symbol_direction(details_text)

        if grouped_id is not None:
            grouped_seed = self._seed_by_grouped_id.get(str(grouped_id))
            if grouped_seed is not None:
                if header is None or (
                    grouped_seed.symbol == header[0] and grouped_seed.direction == header[1]
                ):
                    return grouped_seed

        if reply_to_msg_id is not None and self.pending_seed is not None:
            if self.pending_seed.telegram_message_id == reply_to_msg_id:
                return self.pending_seed

        if self.pending_seed is not None and header is not None:
            if (
                self.pending_seed.symbol == header[0]
                and self.pending_seed.direction == header[1]
            ):
                return self.pending_seed

        return None

    def ingest_telegram_details(
        self,
        text: str,
        *,
        message_id: str,
        channel_id: str,
        grouped_id: int | None,
        reply_to_msg_id: int | None,
    ) -> None:
        self._expire_pending_seed_if_needed()
        details = validate_details_text(text)
        seed = self.find_seed_for_details(
            details,
            grouped_id=grouped_id,
            reply_to_msg_id=reply_to_msg_id,
        )
        if seed is None:
            seed = self._synthetic_seed_from_details(
                details,
                message_id=message_id,
                channel_id=channel_id,
                grouped_id=grouped_id,
                telegram_message_id=int(message_id) if str(message_id).isdigit() else None,
            )
        if seed is None:
            self.logger.log(
                "SKIPPED",
                reason="details_without_seed",
                message_id=message_id,
                channel_id=channel_id,
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
            return

        self.publish_matched_pair(seed, details, message_id)
        self._unregister_seed(seed)


@dataclass
class TelegramInboundMessage:
    text: str
    message_id: int
    channel_id: int
    grouped_id: int | None = None
    reply_to_msg_id: int | None = None


def normalize_telegram_message(
    *,
    text: str,
    message_id: int,
    channel_id: int,
    grouped_id: int | None = None,
    reply_to_msg_id: int | None = None,
) -> TelegramInboundMessage:
    return TelegramInboundMessage(
        text=text,
        message_id=message_id,
        channel_id=channel_id,
        grouped_id=grouped_id,
        reply_to_msg_id=reply_to_msg_id,
    )


def normalize_telegram_event(event: object) -> TelegramInboundMessage:
    message = getattr(event, "message", event)
    text = getattr(message, "message", None) or getattr(message, "text", "") or ""
    message_id = int(getattr(message, "id"))
    channel_id = int(getattr(event, "chat_id"))
    grouped_id = getattr(message, "grouped_id", None)
    reply_to = getattr(message, "reply_to", None)
    reply_to_msg_id = None
    if reply_to is not None:
        reply_to_msg_id = getattr(reply_to, "reply_to_msg_id", None)
    return normalize_telegram_message(
        text=text,
        message_id=message_id,
        channel_id=channel_id,
        grouped_id=grouped_id,
        reply_to_msg_id=reply_to_msg_id,
    )


class TelegramMessageHandler:
    def __init__(self, matcher: TelegramPairMatcher, logger: BridgeLogger) -> None:
        self.matcher = matcher
        self.logger = logger
        self._seen_message_keys: set[str] = set()
        self._seen_raw_hashes: set[str] = set()

    def handle(self, message: TelegramInboundMessage) -> None:
        cleaned_text = sanitize_signal_text(message.text)
        message_key = f"{message.channel_id}:{message.message_id}"
        if message_key in self._seen_message_keys:
            self.logger.log(
                "SKIPPED",
                reason="telegram_dedup",
                message_id=message.message_id,
                channel_id=message.channel_id,
                mode=self.matcher.mode,
                timestamp_utc=utc_now_iso(),
            )
            return

        classification = classify_telegram_text(cleaned_text)
        if classification == "empty":
            self.logger.log(
                "SKIPPED",
                reason="empty_message",
                message_id=message.message_id,
                channel_id=message.channel_id,
                mode=self.matcher.mode,
                timestamp_utc=utc_now_iso(),
            )
            return
        if classification == "non_ascii":
            self.logger.log(
                "SKIPPED",
                reason="non_ascii_message",
                message_id=message.message_id,
                channel_id=message.channel_id,
                mode=self.matcher.mode,
                timestamp_utc=utc_now_iso(),
            )
            return

        content_hash = raw_message_hash(cleaned_text)
        if content_hash in self._seen_raw_hashes:
            self.logger.log(
                "SKIPPED",
                reason="telegram_dedup",
                message_id=message.message_id,
                channel_id=message.channel_id,
                mode=self.matcher.mode,
                timestamp_utc=utc_now_iso(),
            )
            return

        self._seen_message_keys.add(message_key)
        self._seen_raw_hashes.add(content_hash)

        if classification == "seed":
            self.matcher.ingest_telegram_seed(
                cleaned_text,
                message_id=str(message.message_id),
                channel_id=str(message.channel_id),
                grouped_id=message.grouped_id,
                telegram_message_id=message.message_id,
            )
            return

        if classification == "details":
            self.matcher.ingest_telegram_details(
                cleaned_text,
                message_id=str(message.message_id),
                channel_id=str(message.channel_id),
                grouped_id=message.grouped_id,
                reply_to_msg_id=message.reply_to_msg_id,
            )
            return

        self.logger.log(
            "SKIPPED",
            reason="unrecognized_message",
            message_id=message.message_id,
            channel_id=message.channel_id,
            mode=self.matcher.mode,
            timestamp_utc=utc_now_iso(),
        )


@dataclass
class TelegramConfig:
    api_id: int
    api_hash: str
    session_path: Path
    channel: str
    pair_timeout_seconds: int


def validate_telegram_channel(channel: str) -> str:
    trimmed = channel.strip()
    if not trimmed:
        raise BridgeValidationError("Missing --telegram-channel")
    if trimmed.startswith("http://") or trimmed.startswith("https://"):
        raise BridgeValidationError("Channel invite links are not supported; use numeric ID or @username")
    return trimmed


def validate_telegram_config(args: argparse.Namespace) -> TelegramConfig:
    if not args.telegram_api_id:
        raise BridgeValidationError("Missing --telegram-api-id")
    if not args.telegram_api_hash:
        raise BridgeValidationError("Missing --telegram-api-hash")
    if not args.telegram_session_path:
        raise BridgeValidationError("Missing --telegram-session-path")
    if not args.telegram_channel:
        raise BridgeValidationError("Missing --telegram-channel")

    try:
        api_id = int(str(args.telegram_api_id).strip())
    except ValueError as exc:
        raise BridgeValidationError("--telegram-api-id must be an integer") from exc

    api_hash = str(args.telegram_api_hash).strip()
    if not api_hash:
        raise BridgeValidationError("Missing --telegram-api-hash")

    session_path = Path(str(args.telegram_session_path).strip()).expanduser()
    session_parent = session_path.parent
    if not session_parent.exists():
        raise BridgeValidationError(f"Session parent directory does not exist: {session_parent}")

    channel = validate_telegram_channel(str(args.telegram_channel))
    timeout = int(args.telegram_pair_timeout_seconds or args.pair_timeout_seconds)
    if timeout <= 0:
        raise BridgeValidationError("Pair timeout must be positive")

    return TelegramConfig(
        api_id=api_id,
        api_hash=api_hash,
        session_path=session_path,
        channel=channel,
        pair_timeout_seconds=timeout,
    )


def is_telethon_available() -> bool:
    try:
        import telethon  # noqa: F401
    except ImportError:
        return False
    return True


def read_json_lines(stream: IO[str]) -> list[dict[str, object]]:
    events: list[dict[str, object]] = []
    for line_number, raw_line in enumerate(stream, start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            payload = json.loads(line)
        except json.JSONDecodeError as exc:
            raise BridgeValidationError(
                f"Invalid JSON on line {line_number}: {exc.msg}"
            ) from exc
        if not isinstance(payload, dict):
            raise BridgeValidationError(
                f"JSON object required on line {line_number}"
            )
        events.append(payload)
    return events


def process_stdin_event(matcher: PairMatcher, payload: dict[str, object]) -> None:
    event_type = str(payload.get("type", "")).strip().lower()
    text = payload.get("text")
    message_id = str(payload.get("message_id", "")).strip()
    if not isinstance(text, str):
        raise BridgeValidationError("Event field 'text' must be a string")
    if event_type == "seed":
        matcher.ingest_seed(text, message_id)
        return
    if event_type == "details":
        matcher.ingest_details(text, message_id)
        return
    raise BridgeValidationError(f"Unsupported event type: {event_type}")


def load_text_arg(text: str | None, file_path: str | None, label: str) -> str:
    if text is not None and file_path is not None:
        raise BridgeValidationError(f"Provide only one of --{label}-text or --{label}-file")
    if text is not None:
        return text
    if file_path is not None:
        path = Path(file_path).expanduser()
        return path.read_text(encoding="utf-8")
    raise BridgeValidationError(f"Missing {label} input")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="FastTrack FILE_COMMON bridge with optional Telethon listener."
    )
    parser.add_argument("--file-common-root", required=True)
    parser.add_argument(
        "--seed-filename",
        default="basket_recovery_fasttrack_seed.txt",
    )
    parser.add_argument(
        "--details-filename",
        default="basket_recovery_fasttrack_details.txt",
    )
    parser.add_argument("--pair-timeout-seconds", type=int, default=900)
    parser.add_argument("--simulate-stdin", action="store_true")
    parser.add_argument("--publish-pair", action="store_true")
    parser.add_argument("--telegram-listen", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-file", default="")
    parser.add_argument("--seed-text", default=None)
    parser.add_argument("--details-text", default=None)
    parser.add_argument("--seed-file", default=None)
    parser.add_argument("--details-file", default=None)
    parser.add_argument("--telegram-api-id", default=None)
    parser.add_argument("--telegram-api-hash", default=None)
    parser.add_argument("--telegram-session-path", default=None)
    parser.add_argument("--telegram-channel", default=None)
    parser.add_argument("--telegram-pair-timeout-seconds", type=int, default=None)
    return parser


def run_simulate_stdin(args: argparse.Namespace) -> int:
    root = resolve_root(args.file_common_root)
    logger = BridgeLogger(args.log_file or None)
    publisher = AtomicPublisher(logger)
    matcher = PairMatcher(
        publisher=publisher,
        root=root,
        seed_filename=args.seed_filename,
        details_filename=args.details_filename,
        pair_timeout_seconds=args.pair_timeout_seconds,
        logger=logger,
        mode="simulate-stdin",
        dry_run=args.dry_run,
    )
    events = read_json_lines(sys.stdin)
    for payload in events:
        process_stdin_event(matcher, payload)
    return 0


def run_publish_pair(args: argparse.Namespace) -> int:
    root = resolve_root(args.file_common_root)
    logger = BridgeLogger(args.log_file or None)
    publisher = AtomicPublisher(logger)
    seed_text = load_text_arg(args.seed_text, args.seed_file, "seed")
    details_text = load_text_arg(args.details_text, args.details_file, "details")
    symbol, direction = validate_seed_format(seed_text)
    correlation_key = build_correlation_key(symbol, direction, "publish-pair")
    publisher.publish_pair(
        root=root,
        seed_filename=args.seed_filename,
        details_filename=args.details_filename,
        seed_text=seed_text,
        details_text=details_text,
        correlation_key=correlation_key,
        mode="publish-pair",
        dry_run=args.dry_run,
    )
    return 0


async def _telegram_listen_loop(
    config: TelegramConfig,
    handler: TelegramMessageHandler,
    logger: BridgeLogger,
) -> None:
    from telethon import TelegramClient, events

    client = TelegramClient(
        str(config.session_path),
        config.api_id,
        config.api_hash,
    )

    @client.on(events.NewMessage(chats=config.channel))
    async def on_new_message(event: object) -> None:
        inbound = normalize_telegram_event(event)
        handler.handle(inbound)

    await client.start()
    logger.log(
        "TELEGRAM_LISTENER_READY",
        mode="telegram-listen",
        channel=config.channel,
        timestamp_utc=utc_now_iso(),
    )
    await client.run_until_disconnected()


def run_telegram_listen(args: argparse.Namespace) -> int:
    logger = BridgeLogger(args.log_file or None)
    if not is_telethon_available():
        logger.log(
            "ERROR",
            reason="telethon_not_installed",
            detail="Install with: pip install telethon",
            timestamp_utc=utc_now_iso(),
        )
        return 1

    try:
        config = validate_telegram_config(args)
        root = resolve_root(args.file_common_root)
    except BridgeValidationError as exc:
        logger.log(
            "ERROR",
            reason="validation_failed",
            detail=str(exc),
            timestamp_utc=utc_now_iso(),
        )
        return 2

    publisher = AtomicPublisher(logger)
    matcher = TelegramPairMatcher(
        publisher=publisher,
        root=root,
        seed_filename=args.seed_filename,
        details_filename=args.details_filename,
        pair_timeout_seconds=config.pair_timeout_seconds,
        logger=logger,
        mode="telegram-listen",
        dry_run=args.dry_run,
    )
    handler = TelegramMessageHandler(matcher, logger)
    asyncio.run(_telegram_listen_loop(config, handler, logger))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    mode_count = sum(
        [
            bool(args.simulate_stdin),
            bool(args.publish_pair),
            bool(args.telegram_listen),
        ]
    )
    if mode_count != 1:
        parser.error(
            "Exactly one of --simulate-stdin, --publish-pair, or --telegram-listen is required"
        )

    try:
        if args.simulate_stdin:
            return run_simulate_stdin(args)
        if args.publish_pair:
            return run_publish_pair(args)
        return run_telegram_listen(args)
    except BridgeValidationError as exc:
        BridgeLogger(args.log_file or None).log(
            "ERROR",
            reason="validation_failed",
            detail=str(exc),
            timestamp_utc=utc_now_iso(),
        )
        return 2
    except Exception as exc:
        BridgeLogger(args.log_file or None).log(
            "ERROR",
            reason="unexpected_failure",
            detail=str(exc),
            timestamp_utc=utc_now_iso(),
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
