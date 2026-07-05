"""Security helpers for the local Telegram route dashboard."""

from __future__ import annotations

import json
import re
import sys
from datetime import datetime, timezone
from http import HTTPStatus
from pathlib import Path
from typing import Any

_INTEGRATIONS_TELEGRAM_DIR = Path(__file__).resolve().parent
if str(_INTEGRATIONS_TELEGRAM_DIR) not in sys.path:
    sys.path.insert(0, str(_INTEGRATIONS_TELEGRAM_DIR))

from fasttrack_file_bridge import BridgeValidationError as BridgeFileValidationError
from fasttrack_file_bridge import validate_basename

ALLOWED_HOST = "127.0.0.1"
DEFAULT_PORT = 8787
DEFAULT_DATA_DIR = Path("integrations/telegram/local-data")

FORBIDDEN_CREDENTIAL_KEYS = frozenset(
    {
        "api_id",
        "api_hash",
        "session",
        "session_string",
        "password",
        "code",
        "phone_code",
        "phone_code_hash",
        "two_factor_password",
    }
)
SECRET_SUBSTRINGS = (
    "api_hash",
    "api_id",
    "session",
    "password",
    "phone_code",
    "phone_code_hash",
    "code",
    "two_factor",
    "token",
    "secret",
)
ROUTE_MODES = frozenset({"DISABLED", "OBSERVER_ONLY"})
ACCOUNT_MODES = frozenset({"DEMO", "UNKNOWN"})

STATIC_ASSET_MAP = {
    "/": "index.html",
    "/index.html": "index.html",
    "/app.js": "app.js",
    "/styles.css": "styles.css",
}


class DashboardSecurityError(Exception):
    """Raised when a security constraint is violated."""


class DashboardValidationError(Exception):
    """Raised when request payload validation fails."""


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def mask_session_path(path: str) -> str:
    cleaned = path.strip()
    if not cleaned:
        return "[REDACTED]"
    name = Path(cleaned).name
    if not name:
        return "[REDACTED]"
    if len(name) <= 4:
        return f"***{name}"
    return f"***{name[-4:]}"


def mask_phone(phone: str) -> str:
    cleaned = phone.strip()
    digits = re.sub(r"\D", "", cleaned)
    if len(digits) < 4:
        raise DashboardValidationError("Phone number must contain at least 4 digits")
    last_four = digits[-4:]
    if cleaned.startswith("+"):
        prefix_digits = digits[:-4]
        if len(prefix_digits) >= 2:
            visible_prefix = "+" + prefix_digits[:2]
        else:
            visible_prefix = "+" + prefix_digits
        masked_len = max(6, len(prefix_digits) - len(visible_prefix) + 1)
        return f"{visible_prefix}{'*' * masked_len}{last_four}"
    masked_len = max(4, len(digits) - 4)
    return f"{'*' * masked_len}{last_four}"


def redact_text(value: str) -> str:
    redacted = value
    for needle in SECRET_SUBSTRINGS:
        pattern = re.compile(re.escape(needle) + r"\s*[:=]\s*\S+", re.IGNORECASE)
        redacted = pattern.sub(f"{needle}=[REDACTED]", redacted)
    redacted = re.sub(r"\+?\d{8,}", "[REDACTED_PHONE]", redacted)
    return redacted


def redact_metadata(metadata: dict[str, Any] | None) -> dict[str, Any] | None:
    if metadata is None:
        return None
    cleaned: dict[str, Any] = {}
    for key, value in metadata.items():
        lower_key = key.lower()
        if lower_key in FORBIDDEN_CREDENTIAL_KEYS or any(
            secret in lower_key for secret in SECRET_SUBSTRINGS
        ):
            cleaned[key] = "[REDACTED]"
            continue
        if isinstance(value, str):
            cleaned[key] = redact_text(value)
        else:
            cleaned[key] = value
    return cleaned


def security_headers() -> dict[str, str]:
    return {
        "Cache-Control": "no-store",
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "Referrer-Policy": "no-referrer",
        "Content-Security-Policy": "default-src 'self'; style-src 'self'; script-src 'self'",
    }


def json_response(
    data: Any,
    status: HTTPStatus = HTTPStatus.OK,
) -> tuple[int, dict[str, str], bytes]:
    body = json.dumps(data, indent=2).encode("utf-8")
    headers = {
        "Content-Type": "application/json; charset=utf-8",
        "Content-Length": str(len(body)),
        **security_headers(),
    }
    return status.value, headers, body


def parse_json_body(raw: bytes) -> dict[str, Any]:
    if not raw:
        return {}
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise DashboardValidationError(f"Invalid JSON body: {exc.msg}") from exc
    if not isinstance(payload, dict):
        raise DashboardValidationError("JSON object required")
    return payload


def reject_literal_credentials(
    payload: dict[str, Any],
    *,
    allowed: frozenset[str] | None = None,
) -> None:
    allowed_keys = allowed or frozenset()
    for key in payload:
        lower = key.lower()
        if lower in allowed_keys:
            continue
        if lower in FORBIDDEN_CREDENTIAL_KEYS:
            raise DashboardValidationError(
                "Use local environment configuration; do not send credentials to dashboard API."
            )


def validate_host(host: str) -> str:
    if host != ALLOWED_HOST:
        raise DashboardSecurityError("only 127.0.0.1 is allowed")
    return host


def validate_basename_safe(name: str) -> str:
    try:
        return validate_basename(name)
    except BridgeFileValidationError as exc:
        raise DashboardValidationError(str(exc)) from exc


def assert_static_path_allowed(path: str) -> str:
    if ".." in path or path.startswith("//"):
        raise DashboardSecurityError("Path traversal rejected")
    if path not in STATIC_ASSET_MAP:
        raise FileNotFoundError(path)
    return STATIC_ASSET_MAP[path]


def resolve_static_file(dashboard_dir: Path, path: str) -> tuple[Path, str]:
    asset_name = assert_static_path_allowed(path)
    file_path = (dashboard_dir / asset_name).resolve()
    dashboard_root = dashboard_dir.resolve()
    if not str(file_path).startswith(str(dashboard_root)):
        raise DashboardSecurityError("Path traversal rejected")
    if not file_path.exists():
        raise FileNotFoundError(path)
    content_type = "text/html; charset=utf-8"
    if file_path.suffix == ".js":
        content_type = "application/javascript; charset=utf-8"
    elif file_path.suffix == ".css":
        content_type = "text/css; charset=utf-8"
    return file_path, content_type
