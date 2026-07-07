"""MT5 target projection, conflict checks, and read-only verification orchestration."""

from __future__ import annotations

from pathlib import Path
from typing import Any

from dashboard_security import (
    DashboardValidationError,
    EXPECTED_ACCOUNT_TYPES,
    mask_account_login,
    validate_basename_safe,
)
from dashboard_store import DashboardDatabase
from mt5_account_probe import (
    ACCOUNT_TYPE_CONTEST,
    ACCOUNT_TYPE_DEMO,
    ACCOUNT_TYPE_REAL,
    PROBE_STATUS_CONNECTOR_UNAVAILABLE,
    PROBE_STATUS_TERMINAL_OFFLINE,
    PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
    PROBE_STATUS_VERIFIED,
    ProbeRequest,
    probe_result_to_store_fields,
    probe_terminal_account,
)

VERIFY_RATE_LIMIT_SECONDS = 15

VERIFICATION_VERIFIED_OK = "VERIFIED_OK"
VERIFICATION_TERMINAL_OFFLINE = "TERMINAL_OFFLINE"
VERIFICATION_CONNECTOR_UNAVAILABLE = "MT5_PYTHON_CONNECTOR_UNAVAILABLE"
VERIFICATION_VERIFY_FAILED = "TERMINAL_OPEN_VERIFY_FAILED"
VERIFICATION_ACCOUNT_MISMATCH = "ACCOUNT_MISMATCH"
VERIFICATION_SERVER_MISMATCH = "SERVER_MISMATCH"
VERIFICATION_REAL_ACCOUNT_WARNING = "REAL_ACCOUNT_WARNING"
VERIFICATION_XAUUSD_NOT_FOUND = "XAUUSD_NOT_FOUND"
VERIFICATION_INSTANCE_AMBIGUOUS = "INSTANCE_AMBIGUOUS"
VERIFICATION_INSTANCE_DATA_MISMATCH = "INSTANCE_DATA_MISMATCH"
VERIFICATION_INSTANCE_PATH_USER_SUPPLIED = "INSTANCE_PATH_USER_SUPPLIED"

CARD_STATUS_VERIFIED = "Bağlı ve Doğrulandı"
CARD_STATUS_TERMINAL_OPEN_FAILED = "Terminal Açık, Hesap Doğrulanamadı"
CARD_STATUS_TERMINAL_OFFLINE = "Terminal Çevrimdışı"
CARD_STATUS_ACCOUNT_MISMATCH = "Hesap Beklenenden Farklı"
CARD_STATUS_EA_PENDING = "EA Doğrulaması Bekliyor"
CARD_STATUS_EXECUTION_LOCKED = "İşlem Yetkisi Kapalı"
CARD_STATUS_INSTANCE_AMBIGUOUS = "Terminal Instance Belirsiz"

INSTANCE_STATUS_VERIFIED = "Doğrulandı"
INSTANCE_STATUS_USER_SUPPLIED = "Kullanıcı Tarafından Girildi"
INSTANCE_STATUS_AMBIGUOUS = "Belirsiz"
INSTANCE_STATUS_CONFLICT = "Başka hedefle çakışıyor"
INSTANCE_STATUS_PENDING = "Doğrulama Bekliyor"

EA_LIVE_STATUS_PENDING = "Henüz doğrulanmadı"

TERMINAL_INSTANCE_CONFLICT_MESSAGE = (
    "Bu MT5 terminal instance'ı başka aktif hedefte zaten kullanılıyor."
)
ACCOUNT_SERVER_DUPLICATE_MESSAGE = (
    "Bu hesap numarası ve sunucu kombinasyonu başka aktif hedefte zaten kayıtlı."
)
FILE_PAIR_CONFLICT_MESSAGE = (
    "Aynı FILE_COMMON dizini ve seed/details dosya çifti başka aktif hedefte kullanılıyor."
)
INSTANCE_AMBIGUOUS_MESSAGE = (
    "Bu terminal program yolu birden fazla hedefte kullanılıyor. "
    "Terminal instance klasörünü belirtmeniz gerekir."
)


def normalize_storage_path(path: str | None) -> str:
    if not path:
        return ""
    try:
        return str(Path(str(path).strip()).expanduser().resolve()).lower()
    except OSError:
        return str(path).strip().lower()


def build_terminal_instance_key(
    *,
    terminal_data_path: str | None,
    terminal_exe_path: str | None,
    account_login: str | None,
    server: str | None,
) -> str | None:
    data_path = normalize_storage_path(terminal_data_path)
    if data_path:
        return f"data:{data_path}"
    exe_path = normalize_storage_path(terminal_exe_path)
    login = str(account_login or "").strip()
    srv = str(server or "").strip().lower()
    if exe_path and login and srv:
        return f"fallback:{exe_path}|{login}|{srv}"
    return None


def resolve_expected_account_type(row: dict[str, Any]) -> str:
    explicit = str(row.get("expected_account_type") or "").upper().strip()
    if explicit in EXPECTED_ACCOUNT_TYPES:
        return explicit
    legacy = str(row.get("account_mode") or "UNKNOWN").upper().strip()
    if legacy in EXPECTED_ACCOUNT_TYPES:
        return legacy
    return "UNKNOWN"


def account_server_pair(row: dict[str, Any], *, prefer_detected: bool = True) -> tuple[str, str] | None:
    login = ""
    server = ""
    if prefer_detected:
        login = str(row.get("detected_account_login") or "").strip()
        server = str(row.get("detected_server") or "").strip().lower()
    if not login or not server:
        login = str(row.get("expected_account_login") or login or "").strip()
        server = str(row.get("expected_server") or server or "").strip().lower()
    if login and server:
        return login, server
    return None


def is_instance_ambiguous(row: dict[str, Any], all_targets: list[dict[str, Any]]) -> bool:
    if normalize_storage_path(row.get("terminal_data_path")):
        return False
    exe_path = normalize_storage_path(row.get("terminal_exe_path"))
    if not exe_path:
        return True
    active_same_exe = [
        item
        for item in all_targets
        if int(item.get("is_enabled", 1)) == 1
        and item["id"] != row["id"]
        and normalize_storage_path(item.get("terminal_exe_path")) == exe_path
        and not normalize_storage_path(item.get("terminal_data_path"))
    ]
    return len(active_same_exe) > 0


def find_target_conflicts(targets: list[dict[str, Any]], target_id: int | None = None) -> list[str]:
    conflicts: list[str] = []
    active = [row for row in targets if int(row.get("is_enabled", 1)) == 1]
    current = next((row for row in active if row["id"] == target_id), None) if target_id else None
    if current is None and target_id is not None:
        return conflicts

    def other_rows(row: dict[str, Any]) -> list[dict[str, Any]]:
        return [item for item in active if item["id"] != row["id"]]

    rows_to_check = [current] if current else active
    for row in rows_to_check:
        if row is None:
            continue
        seed = str(row.get("seed_filename") or "")
        details = str(row.get("details_filename") or "")
        magic = row.get("magic_number")
        root = normalize_storage_path(str(row.get("file_common_root") or ""))
        data_path = normalize_storage_path(str(row.get("terminal_data_path") or ""))
        pair = account_server_pair(row, prefer_detected=False)

        for other in other_rows(row):
            if data_path and data_path == normalize_storage_path(str(other.get("terminal_data_path") or "")):
                conflicts.append(TERMINAL_INSTANCE_CONFLICT_MESSAGE)
                break

        if pair:
            for other in other_rows(row):
                other_pair = account_server_pair(other, prefer_detected=True)
                if not other_pair:
                    other_pair = account_server_pair(other, prefer_detected=False)
                if other_pair and other_pair == pair:
                    conflicts.append(ACCOUNT_SERVER_DUPLICATE_MESSAGE)
                    break

        for other in other_rows(row):
            other_root = normalize_storage_path(str(other.get("file_common_root") or ""))
            if not root or root != other_root:
                continue
            other_seed = str(other.get("seed_filename") or "")
            other_details = str(other.get("details_filename") or "")
            if seed and details and seed == other_seed and details == other_details:
                conflicts.append(FILE_PAIR_CONFLICT_MESSAGE)
                break

        if magic is not None:
            for other in other_rows(row):
                if other.get("magic_number") == magic:
                    conflicts.append("Magic numarası başka aktif hedefle çakışıyor.")
                    break
    return list(dict.fromkeys(conflicts))


def evaluate_config_match(
    row: dict[str, Any],
    conflicts: list[str],
    all_targets: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    issues: list[str] = []
    seed = str(row.get("seed_filename") or "").strip()
    details = str(row.get("details_filename") or "").strip()
    if not normalize_storage_path(str(row.get("terminal_data_path") or "")):
        issues.append("MT5 terminal veri klasörü (instance kimliği) zorunludur.")
    elif all_targets and is_instance_ambiguous(row, all_targets):
        issues.append(INSTANCE_AMBIGUOUS_MESSAGE)
    if not seed or not details:
        issues.append("Seed ve details dosya adları zorunludur.")
    else:
        try:
            validate_basename_safe(seed)
            validate_basename_safe(details)
        except Exception:
            issues.append("Dosya adları güvenli basename formatında olmalıdır.")
        if seed == details:
            issues.append("Seed ve details dosya adları farklı olmalıdır.")
    issues.extend(conflicts)
    return {
        "status": "OK" if not issues else "CONFLICT",
        "issues": issues,
    }


def derive_terminal_instance_status(
    row: dict[str, Any],
    conflicts: list[str],
    all_targets: list[dict[str, Any]],
) -> str:
    if any(TERMINAL_INSTANCE_CONFLICT_MESSAGE in conflict for conflict in conflicts):
        return INSTANCE_STATUS_CONFLICT
    if (
        str(row.get("verification_status") or "") == VERIFICATION_INSTANCE_AMBIGUOUS
        or is_instance_ambiguous(row, all_targets)
    ):
        return INSTANCE_STATUS_AMBIGUOUS
    if str(row.get("verification_status") or "") == VERIFICATION_INSTANCE_PATH_USER_SUPPLIED:
        return INSTANCE_STATUS_USER_SUPPLIED
    if row.get("terminal_data_path") and row.get("verification_status") == VERIFICATION_VERIFIED_OK:
        return INSTANCE_STATUS_VERIFIED
    if row.get("terminal_data_path") and row.get("last_verified_at_utc"):
        return INSTANCE_STATUS_VERIFIED
    if row.get("terminal_data_path"):
        return INSTANCE_STATUS_PENDING
    return INSTANCE_STATUS_AMBIGUOUS


def derive_card_status(row: dict[str, Any], config_match: dict[str, Any]) -> str:
    if int(row.get("is_enabled", 1)) == 0:
        return "Devre Dışı"
    verification_status = str(row.get("verification_status") or "")
    if verification_status == VERIFICATION_INSTANCE_AMBIGUOUS:
        return CARD_STATUS_INSTANCE_AMBIGUOUS
    if verification_status == PROBE_STATUS_TERMINAL_OFFLINE:
        return CARD_STATUS_TERMINAL_OFFLINE
    if verification_status in {
        PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
        PROBE_STATUS_CONNECTOR_UNAVAILABLE,
        VERIFICATION_VERIFY_FAILED,
        VERIFICATION_INSTANCE_DATA_MISMATCH,
    }:
        return CARD_STATUS_TERMINAL_OPEN_FAILED
    if verification_status in {VERIFICATION_ACCOUNT_MISMATCH, VERIFICATION_SERVER_MISMATCH}:
        return CARD_STATUS_ACCOUNT_MISMATCH
    if verification_status == VERIFICATION_REAL_ACCOUNT_WARNING:
        return CARD_STATUS_ACCOUNT_MISMATCH
    if verification_status == VERIFICATION_VERIFIED_OK:
        if config_match["status"] != "OK":
            return CARD_STATUS_EA_PENDING
        return CARD_STATUS_VERIFIED
    if not row.get("last_verified_at_utc"):
        return CARD_STATUS_EA_PENDING
    return CARD_STATUS_EXECUTION_LOCKED


def xauusd_status_label(row: dict[str, Any]) -> str:
    if row.get("xauusd_available") in (1, True):
        return "Hazır"
    if row.get("verification_status") == VERIFICATION_XAUUSD_NOT_FOUND:
        return "Bulunamadı"
    if row.get("last_verified_at_utc"):
        return "Kapalı"
    return "Bulunamadı"


def project_mt5_target(row: dict[str, Any], all_targets: list[dict[str, Any]]) -> dict[str, Any]:
    expected_type = resolve_expected_account_type(row)
    detected_type = str(row.get("detected_trade_mode") or "UNKNOWN").upper()
    conflicts = find_target_conflicts(all_targets, int(row["id"]))
    config_match = evaluate_config_match(row, conflicts, all_targets)
    expected_login = row.get("expected_account_login")
    detected_login = row.get("detected_account_login")
    payload = {
        "id": row["id"],
        "display_name": row["name"],
        "name": row["name"],
        "terminal_label": row.get("terminal_label"),
        "terminal_exe_path": row.get("terminal_exe_path"),
        "terminal_data_path": row.get("terminal_data_path"),
        "terminal_instance_key": row.get("terminal_instance_key"),
        "terminal_process_id": row.get("terminal_process_id"),
        "expected_account_login_masked": mask_account_login(expected_login),
        "expected_server": row.get("expected_server"),
        "expected_account_type": expected_type,
        "account_mode": row.get("account_mode"),
        "broker_label": row.get("broker_label"),
        "file_common_root": row.get("file_common_root"),
        "seed_filename": row.get("seed_filename"),
        "details_filename": row.get("details_filename"),
        "ea_name": row.get("ea_name") or "Basket Recovery EA",
        "chart_symbol": row.get("chart_symbol") or "XAUUSD",
        "chart_timeframe": row.get("chart_timeframe") or "M1",
        "magic_number": row.get("magic_number"),
        "is_enabled": bool(row.get("is_enabled", 1)),
        "observer_only": bool(row.get("observer_only", 1)),
        "execution_permission": "LOCKED",
        "created_at_utc": row.get("created_at_utc"),
        "updated_at_utc": row.get("updated_at_utc"),
        "detected_account_login_masked": mask_account_login(detected_login),
        "detected_server": row.get("detected_server"),
        "detected_company": row.get("detected_company"),
        "detected_trade_mode": detected_type if detected_type else "UNKNOWN",
        "detected_trade_mode_label": _trade_mode_label(detected_type),
        "detected_currency": row.get("detected_currency"),
        "detected_equity": row.get("detected_equity"),
        "detected_terminal_data_path": row.get("detected_terminal_data_path"),
        "detected_terminal_path": row.get("detected_terminal_path"),
        "terminal_connected": bool(row.get("terminal_connected")),
        "terminal_trade_allowed": row.get("terminal_trade_allowed"),
        "xauusd_status": xauusd_status_label(row),
        "last_verified_at_utc": row.get("last_verified_at_utc"),
        "verification_status": row.get("verification_status"),
        "verification_message_safe": row.get("verification_message_safe"),
        "terminal_instance_status": derive_terminal_instance_status(row, conflicts, all_targets),
        "card_status": derive_card_status(row, config_match),
        "warnings": _collect_warnings(row, expected_type, detected_type),
        "ea_config_match": config_match,
        "ea_live_verification": {
            "status": EA_LIVE_STATUS_PENDING,
            "message": "Canlı EA doğrulaması gelecek sprintte heartbeat ile yapılacak.",
        },
    }
    return payload


def _trade_mode_label(trade_mode: str) -> str:
    mapping = {
        "DEMO": "Demo Hesap",
        "REAL": "Gerçek Hesap",
        "CONTEST": "Yarışma Hesabı",
        "UNKNOWN": "Hesap Türü Belirsiz",
    }
    return mapping.get(trade_mode.upper(), "Hesap Türü Belirsiz")


def _collect_warnings(row: dict[str, Any], expected_type: str, detected_type: str) -> list[str]:
    warnings: list[str] = []
    if expected_type == ACCOUNT_TYPE_DEMO and detected_type == ACCOUNT_TYPE_REAL:
        warnings.append(
            "Dikkat: Bu hedef gerçek hesaba bağlı görünüyor. İşlem yetkisi kilitli tutuldu."
        )
    expected_login = str(row.get("expected_account_login") or "").strip()
    detected_login = str(row.get("detected_account_login") or "").strip()
    if expected_login and detected_login and expected_login != detected_login:
        warnings.append("Dikkat: Açık terminal beklenen hesaba bağlı değil.")
    expected_server = str(row.get("expected_server") or "").strip().lower()
    detected_server = str(row.get("detected_server") or "").strip().lower()
    if expected_server and detected_server and expected_server != detected_server:
        warnings.append("Dikkat: Terminal farklı bir sunucuya bağlı.")
    configured_data = normalize_storage_path(str(row.get("terminal_data_path") or ""))
    detected_data = normalize_storage_path(str(row.get("detected_terminal_data_path") or ""))
    if configured_data and detected_data and configured_data != detected_data:
        warnings.append("Dikkat: Doğrulanan terminal veri klasörü kayıtlı instance ile eşleşmiyor.")
    return warnings


def _resolved_account_type(item: dict[str, Any]) -> str:
    detected = str(item.get("detected_trade_mode") or "").upper()
    if detected in {"DEMO", "REAL", "CONTEST"} and item.get("last_verified_at_utc"):
        return detected
    return str(item.get("expected_account_type") or "UNKNOWN").upper()


def build_targets_summary(targets: list[dict[str, Any]]) -> dict[str, int]:
    projected = [project_mt5_target(row, targets) for row in targets]
    return {
        "total": len(projected),
        "demo_accounts": sum(1 for item in projected if _resolved_account_type(item) == "DEMO"),
        "real_accounts": sum(1 for item in projected if _resolved_account_type(item) == "REAL"),
        "contest_accounts": sum(1 for item in projected if _resolved_account_type(item) == "CONTEST"),
        "terminal_offline": sum(
            1
            for item in projected
            if item.get("verification_status") in {PROBE_STATUS_TERMINAL_OFFLINE, VERIFICATION_TERMINAL_OFFLINE}
            or item.get("card_status") == CARD_STATUS_TERMINAL_OFFLINE
        ),
        "pending_verification": sum(
            1
            for item in projected
            if not item.get("last_verified_at_utc")
            or item.get("verification_status") not in {VERIFICATION_VERIFIED_OK}
        ),
        "pending_ea_match": sum(
            1
            for item in projected
            if item.get("ea_config_match", {}).get("status") != "OK"
            or item.get("card_status") == CARD_STATUS_EA_PENDING
        ),
        "terminal_instance_conflicts": sum(
            1
            for item in projected
            if item.get("terminal_instance_status") == INSTANCE_STATUS_CONFLICT
            or item.get("terminal_instance_status") == INSTANCE_STATUS_AMBIGUOUS
        ),
    }


def validate_target_registration(
    all_targets: list[dict[str, Any]],
    payload: dict[str, Any],
    *,
    target_id: int | None = None,
) -> None:
    if target_id is None:
        candidate = {
            **payload,
            "id": -1,
            "is_enabled": payload.get("is_enabled", 1),
        }
        working_targets = [*all_targets, candidate]
        conflicts = find_target_conflicts(working_targets, -1)
    else:
        working_targets = []
        for row in all_targets:
            if row["id"] == target_id:
                working_targets.append({**row, **payload})
            else:
                working_targets.append(row)
        conflicts = find_target_conflicts(working_targets, target_id)
    blocking = [
        conflict
        for conflict in conflicts
        if conflict
        in {
            TERMINAL_INSTANCE_CONFLICT_MESSAGE,
            ACCOUNT_SERVER_DUPLICATE_MESSAGE,
        }
    ]
    if blocking:
        raise DashboardValidationError(blocking[0])


def compute_instance_fields(row: dict[str, Any]) -> dict[str, Any]:
    pair = account_server_pair(row, prefer_detected=True) or account_server_pair(row, prefer_detected=False)
    login = pair[0] if pair else None
    server = pair[1] if pair else None
    instance_key = build_terminal_instance_key(
        terminal_data_path=str(row.get("terminal_data_path") or "") or None,
        terminal_exe_path=str(row.get("terminal_exe_path") or "") or None,
        account_login=login,
        server=server,
    )
    return {"terminal_instance_key": instance_key}


def verify_target(database: DashboardDatabase, target_id: int) -> dict[str, Any]:
    row = database.get_target(target_id)
    if row is None:
        raise DashboardValidationError("Target not found")
    if not row.get("terminal_exe_path"):
        raise DashboardValidationError("terminal_exe_path is required before verification")

    all_targets = database.list_targets()
    if is_instance_ambiguous(row, all_targets):
        database.save_target_verification(
            target_id,
            {
                "verification_status": VERIFICATION_INSTANCE_AMBIGUOUS,
                "verification_message_safe": (
                    "Aynı terminal program yolu birden fazla hedefte kullanılıyor. "
                    "MT5 terminal veri klasörünü girerek doğru instance'ı ayırt edin."
                ),
            },
        )
        updated = database.get_target(target_id)
        assert updated is not None
        projected = project_mt5_target(updated, all_targets)
        return {
            "target": projected,
            "verification": {
                "status": projected["verification_status"],
                "message": projected["verification_message_safe"],
                "last_verified_at_utc": projected["last_verified_at_utc"],
                "warnings": projected["warnings"],
            },
        }

    allowed, retry_after = database.verify_rate_limit_ok(target_id, VERIFY_RATE_LIMIT_SECONDS)
    if not allowed:
        raise DashboardValidationError(f"Doğrulama için {retry_after} saniye bekleyin.")

    probe = probe_terminal_account(
        ProbeRequest(
            terminal_exe_path=str(row["terminal_exe_path"]),
            terminal_data_path=str(row.get("terminal_data_path") or "") or None,
        )
    )
    store_fields = probe_result_to_store_fields(probe)
    verification_status = probe.status
    warnings: list[str] = []

    if probe.status == PROBE_STATUS_VERIFIED:
        configured_data = normalize_storage_path(str(row.get("terminal_data_path") or ""))
        detected_data = normalize_storage_path(probe.detected_terminal_data_path or "")
        if configured_data and not detected_data:
            verification_status = VERIFICATION_INSTANCE_PATH_USER_SUPPLIED
            warnings.append(
                "Terminal veri klasörü kullanıcı tarafından girildi; probe bu instance yolunu doğrulayamadı."
            )
        elif configured_data and detected_data and configured_data != detected_data:
            verification_status = VERIFICATION_INSTANCE_DATA_MISMATCH
            warnings.append("Dikkat: Doğrulanan terminal veri klasörü kayıtlı instance ile eşleşmiyor.")

        expected_type = resolve_expected_account_type(row)
        if expected_type == ACCOUNT_TYPE_DEMO and probe.trade_mode == ACCOUNT_TYPE_REAL:
            verification_status = VERIFICATION_REAL_ACCOUNT_WARNING
            warnings.append(
                "Dikkat: Bu hedef gerçek hesaba bağlı görünüyor. İşlem yetkisi kilitli tutuldu."
            )
        expected_login = str(row.get("expected_account_login") or "").strip()
        if expected_login and probe.account_login and expected_login != probe.account_login:
            verification_status = VERIFICATION_ACCOUNT_MISMATCH
            warnings.append("Dikkat: Açık terminal beklenen hesaba bağlı değil.")
        expected_server = str(row.get("expected_server") or "").strip().lower()
        if expected_server and probe.server and expected_server != probe.server.strip().lower():
            verification_status = VERIFICATION_SERVER_MISMATCH
            warnings.append("Dikkat: Terminal farklı bir sunucuya bağlı.")
        if not probe.xauusd_available and verification_status == PROBE_STATUS_VERIFIED:
            verification_status = VERIFICATION_XAUUSD_NOT_FOUND

        duplicate_conflicts = find_target_conflicts(
            _targets_with_detected_probe(all_targets, row, probe),
            target_id,
        )
        if any(ACCOUNT_SERVER_DUPLICATE_MESSAGE in conflict for conflict in duplicate_conflicts):
            verification_status = VERIFICATION_ACCOUNT_MISMATCH
            warnings.append(ACCOUNT_SERVER_DUPLICATE_MESSAGE)

        if verification_status in {PROBE_STATUS_VERIFIED, VERIFICATION_INSTANCE_PATH_USER_SUPPLIED}:
            if verification_status == PROBE_STATUS_VERIFIED:
                verification_status = VERIFICATION_VERIFIED_OK

    store_fields["verification_status"] = verification_status
    if warnings:
        store_fields["verification_message_safe"] = " ".join(warnings)
    elif probe.user_message:
        store_fields["verification_message_safe"] = probe.user_message

    database.save_target_verification(target_id, store_fields)
    merged = dict(row)
    merged.update(store_fields)
    instance_fields = compute_instance_fields(merged)
    database.update_target(target_id, instance_fields)

    updated = database.get_target(target_id)
    assert updated is not None
    all_targets = database.list_targets()
    projected = project_mt5_target(updated, all_targets)
    projected["warnings"] = list(dict.fromkeys(projected.get("warnings", []) + warnings))
    return {
        "target": projected,
        "verification": {
            "status": projected["verification_status"],
            "message": projected["verification_message_safe"],
            "last_verified_at_utc": projected["last_verified_at_utc"],
            "warnings": projected["warnings"],
        },
    }


def _apply_detected_probe_to_row(row: dict[str, Any], probe: Any) -> dict[str, Any]:
    merged = dict(row)
    merged["detected_account_login"] = probe.account_login
    merged["detected_server"] = probe.server
    return merged


def _targets_with_detected_probe(
    all_targets: list[dict[str, Any]],
    row: dict[str, Any],
    probe: Any,
) -> list[dict[str, Any]]:
    merged = _apply_detected_probe_to_row(row, probe)
    return [merged if item["id"] == row["id"] else item for item in all_targets]


def normalize_create_payload(payload: dict[str, Any]) -> dict[str, Any]:
    display_name = str(payload.get("display_name") or payload.get("name") or "").strip()
    if not display_name:
        raise DashboardValidationError("display_name is required")
    terminal_data_path = str(payload.get("terminal_data_path") or "").strip()
    if not terminal_data_path:
        raise DashboardValidationError("terminal_data_path is required")
    expected_type = str(
        payload.get("expected_account_type") or payload.get("account_mode") or "UNKNOWN"
    ).upper()
    if expected_type not in EXPECTED_ACCOUNT_TYPES:
        raise DashboardValidationError("expected_account_type must be DEMO, REAL, or UNKNOWN")
    normalized = dict(payload)
    normalized["name"] = display_name
    normalized["terminal_data_path"] = terminal_data_path
    normalized["account_mode"] = expected_type if expected_type != "REAL" else "UNKNOWN"
    normalized["expected_account_type"] = expected_type
    normalized["execution_permission"] = "LOCKED"
    normalized["observer_only"] = True
    return normalized


def prepare_target_row_fields(payload: dict[str, Any]) -> dict[str, Any]:
    fields = compute_instance_fields(payload)
    fields["terminal_data_path"] = str(payload.get("terminal_data_path") or "").strip()
    return fields


def filter_mt5_targets(
    targets: list[dict[str, Any]],
    *,
    is_enabled: bool | None = None,
    account_type: str | None = None,
    search: str | None = None,
) -> list[dict[str, Any]]:
    filtered = list(targets)
    if is_enabled is not None:
        filtered = [item for item in filtered if bool(item.get("is_enabled")) == is_enabled]
    if account_type:
        wanted = account_type.upper()
        filtered = [
            item
            for item in filtered
            if str(item.get("expected_account_type") or item.get("account_mode") or "").upper() == wanted
        ]
    if search:
        needle = search.strip().lower()
        filtered = [
            item
            for item in filtered
            if needle in str(item.get("display_name") or item.get("name") or "").lower()
            or needle in str(item.get("terminal_label") or "").lower()
            or needle in str(item.get("broker_label") or "").lower()
        ]
    return filtered


def paginate_mt5_targets(
    targets: list[dict[str, Any]],
    *,
    page: int,
    page_size: int,
) -> tuple[list[dict[str, Any]], int]:
    safe_page = max(page, 1)
    safe_size = min(max(page_size, 1), 100)
    total = len(targets)
    start = (safe_page - 1) * safe_size
    end = start + safe_size
    return targets[start:end], total
