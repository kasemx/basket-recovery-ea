"""Read-only MT5 terminal path normalization and multi-terminal discovery."""

from __future__ import annotations

import os
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from dashboard_security import mask_account_login, utc_now_iso
from mt5_account_probe import (
    PROBE_STATUS_TERMINAL_OFFLINE,
    PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
    PROBE_STATUS_VERIFIED,
    ProbeRequest,
    ProbeResult,
    is_terminal_process_running,
    probe_terminal_account,
)
from mt5_target_service import (
    VERIFICATION_INSTANCE_AMBIGUOUS,
    VERIFICATION_VERIFIED_OK,
    build_terminal_instance_key,
    discovery_target_blocking_reason,
    normalize_storage_path,
)

TERMINAL_PATH_NOT_FOUND = "TERMINAL_PATH_NOT_FOUND"
TERMINAL_EXECUTABLE_NOT_FOUND = "TERMINAL_EXECUTABLE_NOT_FOUND"
TERMINAL_PATH_EMPTY = "TERMINAL_PATH_EMPTY"
TERMINAL_PATH_DUPLICATE = "TERMINAL_PATH_DUPLICATE"

TERMINAL_EXECUTABLE_CANDIDATES = ("terminal64.exe", "terminal.exe")

DISCOVERY_SCAN_TTL_SECONDS = 3600

_DISCOVERY_INSTANCES_OVERRIDE: Callable[[str], list[ProbeResult]] | None = None
_discovery_store: "DiscoveryStore | None" = None


@dataclass
class PathNormalizeResult:
    status: str
    message: str
    source_path: str
    terminal_exe_path: str | None = None


@dataclass
class DiscoveryRecord:
    id: int
    scan_id: str
    source_path: str
    terminal_exe_path: str
    status: str
    message: str
    terminal_process_id: int | None = None
    detected_terminal_path: str | None = None
    detected_terminal_data_path: str | None = None
    detected_account_login: str | None = None
    detected_server: str | None = None
    detected_company: str | None = None
    detected_trade_mode: str | None = None
    detected_currency: str | None = None
    detected_equity: float | None = None
    terminal_connected: bool = False
    terminal_trade_allowed: bool | None = None
    xauusd_available: bool = False
    xauusd_trade_mode: str | None = None
    min_volume: float | None = None
    volume_step: float | None = None
    stops_level: int | None = None
    verification_status: str = ""
    verification_message_safe: str = ""
    last_verified_at_utc: str | None = None
    terminal_instance_key: str | None = None
    file_common_root: str | None = None
    can_add_as_target: bool = False
    blocking_reason: str | None = None
    warnings: list[str] = field(default_factory=list)
    created_at_utc: str = field(default_factory=utc_now_iso)


@dataclass
class DiscoveryScanResult:
    scan_id: str
    discoveries: list[DiscoveryRecord]
    path_results: list[PathNormalizeResult]
    duplicate_paths: list[str]
    scanned_at_utc: str = field(default_factory=utc_now_iso)


class DiscoveryStore:
    def __init__(self) -> None:
        self._records: dict[int, DiscoveryRecord] = {}
        self._scans: dict[str, DiscoveryScanResult] = {}
        self._next_id = 1

    def reset(self) -> None:
        self._records.clear()
        self._scans.clear()
        self._next_id = 1

    def add_record(self, record: DiscoveryRecord) -> DiscoveryRecord:
        self._records[record.id] = record
        return record

    def save_scan(self, result: DiscoveryScanResult) -> DiscoveryScanResult:
        self._scans[result.scan_id] = result
        for item in result.discoveries:
            self._records[item.id] = item
        return result

    def get_record(self, discovery_id: int) -> DiscoveryRecord | None:
        return self._records.get(discovery_id)

    def get_scan(self, scan_id: str) -> DiscoveryScanResult | None:
        return self._scans.get(scan_id)

    def latest_scan(self) -> DiscoveryScanResult | None:
        if not self._scans:
            return None
        return max(self._scans.values(), key=lambda item: item.scanned_at_utc)

    def allocate_id(self) -> int:
        value = self._next_id
        self._next_id += 1
        return value


def get_discovery_store() -> DiscoveryStore:
    global _discovery_store
    if _discovery_store is None:
        _discovery_store = DiscoveryStore()
    return _discovery_store


def reset_discovery_store() -> None:
    get_discovery_store().reset()


def set_discovery_instances_override(
    handler: Callable[[str], list[ProbeResult]] | None,
) -> None:
    global _DISCOVERY_INSTANCES_OVERRIDE
    _DISCOVERY_INSTANCES_OVERRIDE = handler


def parse_terminal_path_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw in text.replace("\r\n", "\n").split("\n"):
        cleaned = raw.strip().strip('"')
        if cleaned:
            lines.append(cleaned)
    return lines


def normalize_terminal_path(source_path: str) -> PathNormalizeResult:
    cleaned = source_path.strip().strip('"')
    if not cleaned:
        return PathNormalizeResult(
            status=TERMINAL_PATH_EMPTY,
            message="Terminal yolu boş olamaz.",
            source_path=source_path,
        )
    path = Path(cleaned).expanduser()
    if not path.exists():
        return PathNormalizeResult(
            status=TERMINAL_PATH_NOT_FOUND,
            message="Belirtilen terminal yolu bulunamadı.",
            source_path=source_path,
        )
    if path.is_file():
        if path.suffix.lower() != ".exe":
            return PathNormalizeResult(
                status=TERMINAL_EXECUTABLE_NOT_FOUND,
                message="Terminal programı (.exe) bulunamadı.",
                source_path=source_path,
            )
        return PathNormalizeResult(
            status="OK",
            message="Terminal programı bulundu.",
            source_path=source_path,
            terminal_exe_path=str(path.resolve()),
        )
    if path.is_dir():
        for candidate_name in TERMINAL_EXECUTABLE_CANDIDATES:
            candidate = path / candidate_name
            if candidate.is_file():
                return PathNormalizeResult(
                    status="OK",
                    message="Terminal programı bulundu.",
                    source_path=source_path,
                    terminal_exe_path=str(candidate.resolve()),
                )
        return PathNormalizeResult(
            status=TERMINAL_EXECUTABLE_NOT_FOUND,
            message="Klasörde terminal64.exe veya terminal.exe bulunamadı.",
            source_path=source_path,
        )
    return PathNormalizeResult(
        status=TERMINAL_PATH_NOT_FOUND,
        message="Belirtilen terminal yolu bulunamadı.",
        source_path=source_path,
    )


def _enumerate_terminal_data_paths(exe_path: Path) -> list[str]:
    appdata = os.environ.get("APPDATA", "").strip()
    if not appdata:
        return []
    terminal_root = Path(appdata) / "MetaQuotes" / "Terminal"
    if not terminal_root.is_dir():
        return []
    matches: list[str] = []
    try:
        exe_resolved = exe_path.resolve()
    except OSError:
        exe_resolved = exe_path
    for child in terminal_root.iterdir():
        if not child.is_dir():
            continue
        origin = child / "origin.txt"
        if not origin.is_file():
            continue
        origin_exe = _read_origin_executable(origin)
        if not origin_exe:
            continue
        try:
            same = Path(origin_exe).resolve() == exe_resolved
        except OSError:
            same = origin_exe.lower() == str(exe_resolved).lower()
        if same:
            matches.append(str(child.resolve()))
    return matches


def _read_origin_executable(origin_file: Path) -> str:
    for encoding in ("utf-16-le", "utf-8", "utf-16"):
        try:
            text = origin_file.read_text(encoding=encoding, errors="ignore").strip()
        except OSError:
            continue
        if text:
            return text.splitlines()[0].strip()
    return ""


def _derive_file_common_root(data_path: str | None) -> str | None:
    if not data_path:
        return None
    common = Path(data_path) / "MQL5" / "Files"
    if common.is_dir():
        return str(common.resolve())
    return None


def _default_display_label(probe: ProbeResult) -> str:
    label = (probe.company or probe.server or "MT5").strip()
    masked = mask_account_login(probe.account_login)
    if masked:
        return f"{label} · {masked}"
    return label


def _terminal_label_from_data_path(data_path: str | None) -> str:
    if not data_path:
        return "MT5"
    name = Path(data_path).name
    return name[:12] if name else "MT5"


def _probe_to_discovery_status(probe: ProbeResult) -> str:
    if probe.status == PROBE_STATUS_VERIFIED:
        if probe.detected_terminal_data_path:
            return VERIFICATION_VERIFIED_OK
        return VERIFICATION_INSTANCE_AMBIGUOUS
    return probe.status


def _build_discovery_record(
    *,
    store: DiscoveryStore,
    scan_id: str,
    source_path: str,
    probe: ProbeResult,
    existing_targets: list[dict[str, Any]] | None = None,
) -> DiscoveryRecord:
    verification_status = _probe_to_discovery_status(probe)
    instance_key = build_terminal_instance_key(
        terminal_data_path=probe.detected_terminal_data_path,
        terminal_exe_path=probe.terminal_exe_path,
        account_login=probe.account_login,
        server=probe.server,
    )
    warnings: list[str] = []
    blocking_reason: str | None = None
    can_add = probe.status == PROBE_STATUS_VERIFIED and verification_status != VERIFICATION_INSTANCE_AMBIGUOUS

    if verification_status == VERIFICATION_INSTANCE_AMBIGUOUS:
        blocking_reason = (
            "Terminal instance klasörü belirlenemedi. "
            "Hedef oluşturmak için terminal veri klasörünü seçin."
        )
        can_add = False
    elif probe.status == PROBE_STATUS_TERMINAL_OFFLINE:
        blocking_reason = "Terminal çevrimdışı."
        can_add = False
    elif probe.status != PROBE_STATUS_VERIFIED:
        blocking_reason = probe.user_message
        can_add = False

    if can_add and existing_targets:
        blocking_reason = discovery_target_blocking_reason(probe, existing_targets, instance_key)
        if blocking_reason:
            can_add = False

    if can_add and not _derive_file_common_root(probe.detected_terminal_data_path):
        warnings.append("FILE_COMMON doğrulaması bekliyor.")

    record = DiscoveryRecord(
        id=store.allocate_id(),
        scan_id=scan_id,
        source_path=source_path,
        terminal_exe_path=probe.terminal_exe_path,
        status=verification_status,
        message=probe.user_message,
        terminal_process_id=probe.terminal_process_id,
        detected_terminal_path=probe.detected_terminal_path,
        detected_terminal_data_path=probe.detected_terminal_data_path,
        detected_account_login=probe.account_login,
        detected_server=probe.server,
        detected_company=probe.company,
        detected_trade_mode=probe.trade_mode,
        detected_currency=probe.currency,
        detected_equity=probe.equity,
        terminal_connected=probe.terminal_connected,
        terminal_trade_allowed=probe.terminal_trade_allowed,
        xauusd_available=probe.xauusd_available,
        xauusd_trade_mode=probe.xauusd_trade_mode,
        min_volume=probe.xauusd_volume_min,
        volume_step=probe.xauusd_volume_step,
        stops_level=probe.xauusd_stops_level,
        verification_status=verification_status,
        verification_message_safe=probe.user_message,
        last_verified_at_utc=probe.verified_at_utc if probe.status == PROBE_STATUS_VERIFIED else None,
        terminal_instance_key=instance_key,
        file_common_root=_derive_file_common_root(probe.detected_terminal_data_path),
        can_add_as_target=can_add,
        blocking_reason=blocking_reason,
        warnings=warnings,
    )
    return record


def _probe_instances_for_exe(exe_path: str, source_path: str) -> list[ProbeResult]:
    if _DISCOVERY_INSTANCES_OVERRIDE is not None:
        return _DISCOVERY_INSTANCES_OVERRIDE(exe_path)

    if not is_terminal_process_running(exe_path):
        return [
            ProbeResult(
                status=PROBE_STATUS_TERMINAL_OFFLINE,
                user_message="Terminal çevrimdışı. MT5 terminalini açıp tekrar tarayın.",
                terminal_exe_path=exe_path,
                raw_error_code="TERMINAL_OFFLINE",
            )
        ]

    probe = probe_terminal_account(
        ProbeRequest(
            terminal_exe_path=exe_path,
        )
    )
    results = [probe]

    if probe.status != PROBE_STATUS_VERIFIED:
        return results

    data_paths = _enumerate_terminal_data_paths(Path(exe_path))
    if len(data_paths) <= 1:
        return results

    detected_norm = normalize_storage_path(probe.detected_terminal_data_path)
    extras: list[ProbeResult] = []
    for data_path in data_paths:
        if normalize_storage_path(data_path) == detected_norm:
            continue
        extras.append(
            ProbeResult(
                status=PROBE_STATUS_VERIFIED,
                user_message="Terminal instance bulundu ancak hesap bilgisi doğrulanamadı.",
                terminal_exe_path=exe_path,
                detected_terminal_data_path=data_path,
                detected_terminal_path=exe_path,
                terminal_process_id=probe.terminal_process_id,
                trade_mode=probe.trade_mode,
                trade_mode_label=probe.trade_mode_label,
            )
        )
    for extra in extras:
        extra.status = PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED
        extra.user_message = (
            "Bu terminal instance için hesap bilgisi okunamadı. "
            "Doğru terminal penceresini aktif edip yeniden tarayın."
        )
    return results


def discover_terminal_paths(
    raw_paths: list[str],
    *,
    existing_targets: list[dict[str, Any]] | None = None,
) -> DiscoveryScanResult:
    store = get_discovery_store()
    scan_id = str(uuid.uuid4())
    path_results: list[PathNormalizeResult] = []
    duplicate_paths: list[str] = []
    discoveries: list[DiscoveryRecord] = []
    seen_exe: set[str] = set()

    for source_path in raw_paths:
        normalized = normalize_terminal_path(source_path)
        path_results.append(normalized)
        if normalized.status != "OK" or not normalized.terminal_exe_path:
            continue
        exe_key = normalize_storage_path(normalized.terminal_exe_path)
        if exe_key in seen_exe:
            duplicate_paths.append(source_path)
            continue
        seen_exe.add(exe_key)

        probes = _probe_instances_for_exe(normalized.terminal_exe_path, source_path)
        for probe in probes:
            if (
                probe.status == PROBE_STATUS_VERIFIED
                and not probe.detected_terminal_data_path
                and len(_enumerate_terminal_data_paths(Path(normalized.terminal_exe_path))) > 1
            ):
                probe = ProbeResult(
                    status=PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
                    user_message=(
                        "Birden fazla terminal instance bulundu. "
                        "Terminal veri klasörünü belirtmeniz gerekir."
                    ),
                    terminal_exe_path=normalized.terminal_exe_path,
                    raw_error_code=VERIFICATION_INSTANCE_AMBIGUOUS,
                )
            record = _build_discovery_record(
                store=store,
                scan_id=scan_id,
                source_path=source_path,
                probe=probe,
                existing_targets=existing_targets,
            )
            discoveries.append(record)

    result = DiscoveryScanResult(
        scan_id=scan_id,
        discoveries=discoveries,
        path_results=path_results,
        duplicate_paths=duplicate_paths,
    )
    store.save_scan(result)
    return result


def refresh_discovery_record(
    discovery_id: int,
    *,
    existing_targets: list[dict[str, Any]] | None = None,
) -> DiscoveryRecord:
    store = get_discovery_store()
    existing = store.get_record(discovery_id)
    if existing is None:
        raise ValueError("Discovery not found")

    probe = probe_terminal_account(
        ProbeRequest(
            terminal_exe_path=existing.terminal_exe_path,
            terminal_data_path=existing.detected_terminal_data_path,
        )
    )
    refreshed = _build_discovery_record(
        store=store,
        scan_id=existing.scan_id,
        source_path=existing.source_path,
        probe=probe,
        existing_targets=existing_targets,
    )
    refreshed.id = existing.id
    store.add_record(refreshed)
    if existing.scan_id in store._scans:
        scan = store._scans[existing.scan_id]
        scan.discoveries = [
            refreshed if item.id == existing.id else item for item in scan.discoveries
        ]
    return refreshed


def project_discovery(record: DiscoveryRecord) -> dict[str, Any]:
    trade_labels = {
        "DEMO": "Demo Hesap",
        "REAL": "Gerçek Hesap",
        "CONTEST": "Yarışma Hesabı",
        "UNKNOWN": "Hesap Türü Belirsiz",
    }
    trade_mode = str(record.detected_trade_mode or "UNKNOWN").upper()
    return {
        "id": record.id,
        "scan_id": record.scan_id,
        "source_path": record.source_path,
        "display_label": _default_display_label(
            ProbeResult(
                status=record.verification_status,
                user_message=record.message,
                terminal_exe_path=record.terminal_exe_path,
                account_login=record.detected_account_login,
                server=record.detected_server,
                company=record.detected_company,
            )
        ),
        "terminal_exe_path": record.terminal_exe_path,
        "terminal_process_id": record.terminal_process_id,
        "detected_terminal_path": record.detected_terminal_path,
        "detected_terminal_data_path": record.detected_terminal_data_path,
        "detected_account_login_masked": mask_account_login(record.detected_account_login),
        "detected_server": record.detected_server,
        "detected_company": record.detected_company,
        "detected_trade_mode": trade_mode,
        "detected_trade_mode_label": trade_labels.get(trade_mode, "Hesap Türü Belirsiz"),
        "detected_currency": record.detected_currency,
        "detected_equity": record.detected_equity,
        "terminal_connected": record.terminal_connected,
        "terminal_trade_allowed": record.terminal_trade_allowed,
        "xauusd_available": record.xauusd_available,
        "xauusd_status": "Hazır" if record.xauusd_available else "Bulunamadı",
        "xauusd_trade_mode": record.xauusd_trade_mode,
        "min_volume": record.min_volume,
        "volume_step": record.volume_step,
        "stops_level": record.stops_level,
        "verification_status": record.verification_status,
        "verification_message_safe": record.verification_message_safe,
        "last_verified_at_utc": record.last_verified_at_utc,
        "terminal_instance_key": record.terminal_instance_key,
        "file_common_root": record.file_common_root,
        "file_common_status": (
            "Doğrulandı"
            if record.file_common_root
            else "FILE_COMMON doğrulaması bekliyor"
        ),
        "can_add_as_target": record.can_add_as_target,
        "blocking_reason": record.blocking_reason,
        "warnings": list(record.warnings),
        "execution_permission": "LOCKED",
        "terminal_status_label": (
            "Terminal Açık"
            if record.verification_status
            not in {PROBE_STATUS_TERMINAL_OFFLINE, VERIFICATION_INSTANCE_AMBIGUOUS}
            and record.terminal_connected
            else (
                "Terminal Çevrimdışı"
                if record.verification_status in {PROBE_STATUS_TERMINAL_OFFLINE}
                else "Terminal Durumu Belirsiz"
            )
        ),
        "created_at_utc": record.created_at_utc,
    }


def project_scan(result: DiscoveryScanResult) -> dict[str, Any]:
    return {
        "scan_id": result.scan_id,
        "scanned_at_utc": result.scanned_at_utc,
        "discoveries": [project_discovery(item) for item in result.discoveries],
        "path_results": [
            {
                "source_path": item.source_path,
                "status": item.status,
                "message": item.message,
                "terminal_exe_path": item.terminal_exe_path,
            }
            for item in result.path_results
        ],
        "duplicate_paths": list(result.duplicate_paths),
    }


def discovery_record_target_source(record: DiscoveryRecord) -> dict[str, Any]:
    payload = project_discovery(record)
    payload["detected_account_login"] = record.detected_account_login
    payload["detected_terminal_path"] = record.detected_terminal_path
    return payload


def list_discoveries(scan_id: str | None = None) -> dict[str, Any]:
    store = get_discovery_store()
    if scan_id:
        scan = store.get_scan(scan_id)
        if scan is None:
            return {"scan_id": scan_id, "discoveries": [], "path_results": [], "duplicate_paths": []}
        return project_scan(scan)
    latest = store.latest_scan()
    if latest is None:
        return {"scan_id": None, "discoveries": [], "path_results": [], "duplicate_paths": []}
    return project_scan(latest)
