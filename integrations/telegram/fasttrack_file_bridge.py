#!/usr/bin/env python3
"""Offline FastTrack FILE_COMMON bridge — stdin simulator and atomic publish."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import IO, TextIO

MAX_BYTES = 8192
SEED_PATTERN = re.compile(
    r"^(?P<symbol>\S+)\s+(?P<direction>buy|sell)\s+now$",
    re.IGNORECASE,
)
SUPPORTED_SYMBOLS = {"gold"}


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


def short_fingerprint(full_hash: str) -> str:
    return full_hash[:12]


def build_correlation_key(
    symbol: str,
    direction: str,
    seed_message_id: str,
) -> str:
    return f"{symbol}|{direction}|{utc_date()}|{seed_message_id}"


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


class AtomicPublisher:
    def __init__(self, logger: BridgeLogger) -> None:
        self._logger = logger
        self._published_fingerprints: set[str] = set()

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
    _dedup_fingerprints: set[str] = field(default_factory=set)

    def _now(self) -> float:
        import time

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
                ),
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
            self.pending_seed = None

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
        if self.pending_seed is None:
            self.logger.log(
                "SKIPPED",
                reason="details_without_seed",
                message_id=message_id or "unknown-details",
                mode=self.mode,
                timestamp_utc=utc_now_iso(),
            )
            return

        seed = self.pending_seed
        correlation_key = build_correlation_key(
            seed.symbol,
            seed.direction,
            seed.message_id,
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
        description="Offline FastTrack FILE_COMMON bridge (no Telegram/network)."
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
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--log-file", default="")
    parser.add_argument("--seed-text", default=None)
    parser.add_argument("--details-text", default=None)
    parser.add_argument("--seed-file", default=None)
    parser.add_argument("--details-file", default=None)
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


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.simulate_stdin and args.publish_pair:
        parser.error("Use either --simulate-stdin or --publish-pair, not both")
    if not args.simulate_stdin and not args.publish_pair:
        parser.error("One of --simulate-stdin or --publish-pair is required")

    try:
        if args.simulate_stdin:
            return run_simulate_stdin(args)
        return run_publish_pair(args)
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
