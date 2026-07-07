"""Read-only MT5 terminal/account discovery for the local dashboard."""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

from dashboard_security import utc_now_iso

PROBE_STATUS_TERMINAL_OFFLINE = "TERMINAL_OFFLINE"
PROBE_STATUS_CONNECTOR_UNAVAILABLE = "MT5_PYTHON_CONNECTOR_UNAVAILABLE"
PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED = "TERMINAL_OPEN_VERIFY_FAILED"
PROBE_STATUS_VERIFIED = "VERIFIED"

ACCOUNT_TYPE_DEMO = "DEMO"
ACCOUNT_TYPE_REAL = "REAL"
ACCOUNT_TYPE_CONTEST = "CONTEST"
ACCOUNT_TYPE_UNKNOWN = "UNKNOWN"

MT5_TRADE_MODE_DEMO = 0
MT5_TRADE_MODE_CONTEST = 1
MT5_TRADE_MODE_REAL = 2

_PROBE_OVERRIDE: Callable[["ProbeRequest"], "ProbeResult"] | None = None


@dataclass
class ProbeRequest:
    terminal_exe_path: str
    terminal_data_path: str | None = None


@dataclass
class ProbeResult:
    status: str
    user_message: str
    terminal_connected: bool = False
    terminal_exe_path: str = ""
    detected_terminal_path: str | None = None
    detected_terminal_data_path: str | None = None
    terminal_process_id: int | None = None
    account_login: str | None = None
    server: str | None = None
    company: str | None = None
    trade_mode: str = ACCOUNT_TYPE_UNKNOWN
    trade_mode_label: str = "Hesap Türü Belirsiz"
    currency: str | None = None
    equity: float | None = None
    terminal_trade_allowed: bool | None = None
    xauusd_available: bool = False
    xauusd_trade_mode: str | None = None
    xauusd_volume_min: float | None = None
    xauusd_volume_step: float | None = None
    xauusd_stops_level: int | None = None
    verified_at_utc: str = field(default_factory=utc_now_iso)
    raw_error_code: str | None = None


def set_probe_override(handler: Callable[[ProbeRequest], ProbeResult] | None) -> None:
    global _PROBE_OVERRIDE
    _PROBE_OVERRIDE = handler


def classify_trade_mode(trade_mode_value: int | None) -> tuple[str, str]:
    if trade_mode_value == MT5_TRADE_MODE_DEMO:
        return ACCOUNT_TYPE_DEMO, "Demo Hesap"
    if trade_mode_value == MT5_TRADE_MODE_CONTEST:
        return ACCOUNT_TYPE_CONTEST, "Yarışma Hesabı"
    if trade_mode_value == MT5_TRADE_MODE_REAL:
        return ACCOUNT_TYPE_REAL, "Gerçek Hesap"
    return ACCOUNT_TYPE_UNKNOWN, "Hesap Türü Belirsiz"


def _normalize_exe_path(terminal_exe_path: str) -> Path:
    cleaned = terminal_exe_path.strip()
    if not cleaned:
        raise ValueError("terminal_exe_path is required")
    path = Path(cleaned).expanduser()
    if not path.is_file():
        raise ValueError("terminal_exe_path must point to an existing terminal executable")
    return path.resolve()


def _resolve_process_id(exe: Path) -> int | None:
    image_name = exe.name
    if sys.platform != "win32":
        return None
    result = subprocess.run(
        ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/FO", "CSV", "/NH"],
        capture_output=True,
        text=True,
        check=False,
    )
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        return None
    parts = lines[0].split(",")
    if len(parts) < 2:
        return None
    pid_text = parts[1].strip('"')
    return int(pid_text) if pid_text.isdigit() else None


def is_terminal_process_running(terminal_exe_path: str) -> bool:
    exe = _normalize_exe_path(terminal_exe_path)
    image_name = exe.name
    if sys.platform == "win32":
        result = subprocess.run(
            ["tasklist", "/FI", f"IMAGENAME eq {image_name}", "/NH"],
            capture_output=True,
            text=True,
            check=False,
        )
        output = result.stdout.lower()
        return image_name.lower() in output and "no tasks are running" not in output
    result = subprocess.run(["pgrep", "-f", str(exe)], capture_output=True, text=True, check=False)
    return result.returncode == 0


def _coerce_request(request: ProbeRequest | str) -> ProbeRequest:
    if isinstance(request, ProbeRequest):
        return request
    return ProbeRequest(terminal_exe_path=request)


def probe_terminal_account(request: ProbeRequest | str) -> ProbeResult:
    probe_request = _coerce_request(request)
    if _PROBE_OVERRIDE is not None:
        return _PROBE_OVERRIDE(probe_request)

    try:
        exe = _normalize_exe_path(probe_request.terminal_exe_path)
    except ValueError as exc:
        return ProbeResult(
            status=PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
            user_message=str(exc),
            terminal_exe_path=probe_request.terminal_exe_path.strip(),
            raw_error_code="INVALID_TERMINAL_PATH",
        )

    if not is_terminal_process_running(str(exe)):
        return ProbeResult(
            status=PROBE_STATUS_TERMINAL_OFFLINE,
            user_message="Terminal çevrimdışı. MT5 terminalini açıp tekrar doğrulayın.",
            terminal_exe_path=str(exe),
            raw_error_code="TERMINAL_OFFLINE",
        )

    try:
        import MetaTrader5 as mt5  # noqa: PLC0415
    except ImportError:
        return ProbeResult(
            status=PROBE_STATUS_CONNECTOR_UNAVAILABLE,
            user_message="MT5 doğrulama bileşeni bu bilgisayarda hazır değil.",
            terminal_exe_path=str(exe),
            raw_error_code="MT5_PYTHON_CONNECTOR_UNAVAILABLE",
        )

    initialized = False
    try:
        if not mt5.initialize(path=str(exe)):
            error = mt5.last_error()
            return ProbeResult(
                status=PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
                user_message="Terminal açık görünüyor ancak doğrulama bağlantısı kurulamadı.",
                terminal_exe_path=str(exe),
                raw_error_code=f"MT5_INIT_FAILED:{error}",
            )
        initialized = True

        terminal_info = mt5.terminal_info()
        account_info = mt5.account_info()
        if terminal_info is None or account_info is None:
            return ProbeResult(
                status=PROBE_STATUS_TERMINAL_OPEN_VERIFY_FAILED,
                user_message="Terminal açık ancak hesap bilgisi okunamadı.",
                terminal_exe_path=str(exe),
                raw_error_code="ACCOUNT_INFO_UNAVAILABLE",
            )

        trade_mode, trade_mode_label = classify_trade_mode(getattr(account_info, "trade_mode", None))
        xauusd = mt5.symbol_info("XAUUSD")
        xauusd_available = xauusd is not None and getattr(xauusd, "name", "") != ""
        xauusd_trade_mode = None
        volume_min = None
        volume_step = None
        stops_level = None
        if xauusd is not None:
            xauusd_trade_mode = str(getattr(xauusd, "trade_mode", ""))
            volume_min = float(getattr(xauusd, "volume_min", 0.0) or 0.0)
            volume_step = float(getattr(xauusd, "volume_step", 0.0) or 0.0)
            stops_level = int(getattr(xauusd, "trade_stops_level", 0) or 0)

        login_value = getattr(account_info, "login", None)
        detected_terminal_path = str(getattr(terminal_info, "path", "") or "") or str(exe)
        detected_terminal_data_path = str(getattr(terminal_info, "data_path", "") or "") or None
        if not detected_terminal_data_path and probe_request.terminal_data_path:
            detected_terminal_data_path = str(probe_request.terminal_data_path).strip() or None

        return ProbeResult(
            status=PROBE_STATUS_VERIFIED,
            user_message="Hesap bilgileri okundu.",
            terminal_connected=bool(getattr(terminal_info, "connected", False)),
            terminal_exe_path=str(exe),
            detected_terminal_path=detected_terminal_path,
            detected_terminal_data_path=detected_terminal_data_path,
            terminal_process_id=_resolve_process_id(exe),
            account_login=str(login_value) if login_value is not None else None,
            server=str(getattr(account_info, "server", "") or "") or None,
            company=str(getattr(account_info, "company", "") or "") or None,
            trade_mode=trade_mode,
            trade_mode_label=trade_mode_label,
            currency=str(getattr(account_info, "currency", "") or "") or None,
            equity=float(getattr(account_info, "equity", 0.0) or 0.0),
            terminal_trade_allowed=bool(getattr(terminal_info, "trade_allowed", False)),
            xauusd_available=xauusd_available,
            xauusd_trade_mode=xauusd_trade_mode,
            xauusd_volume_min=volume_min,
            xauusd_volume_step=volume_step,
            xauusd_stops_level=stops_level,
        )
    finally:
        if initialized:
            mt5.shutdown()


def probe_result_to_store_fields(result: ProbeResult) -> dict[str, Any]:
    return {
        "detected_account_login": result.account_login,
        "detected_server": result.server,
        "detected_company": result.company,
        "detected_trade_mode": result.trade_mode,
        "detected_currency": result.currency,
        "detected_equity": result.equity,
        "terminal_connected": int(result.terminal_connected),
        "terminal_trade_allowed": int(result.terminal_trade_allowed)
        if result.terminal_trade_allowed is not None
        else None,
        "xauusd_available": int(result.xauusd_available),
        "xauusd_trade_mode": result.xauusd_trade_mode,
        "detected_terminal_path": result.detected_terminal_path,
        "detected_terminal_data_path": result.detected_terminal_data_path,
        "terminal_process_id": result.terminal_process_id,
        "last_verified_at_utc": result.verified_at_utc if result.status == PROBE_STATUS_VERIFIED else None,
        "verification_status": result.status,
        "verification_message_safe": result.user_message,
    }
