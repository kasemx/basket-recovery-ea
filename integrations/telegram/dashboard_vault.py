"""Windows DPAPI credential vault for local Telegram dashboard API credentials."""

from __future__ import annotations

import base64
import json
import os
import sys
import tempfile
from pathlib import Path

CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM = "CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM"
VAULT_FILENAME = "telegram_credentials.dpapi"
VAULT_VERSION = 1
CRYPTPROTECT_UI_FORBIDDEN = 0x1


class CredentialVaultError(Exception):
    """Raised when the credential vault cannot read, write, or decrypt safely."""

    def __init__(self, error_code: str, message: str) -> None:
        super().__init__(message)
        self.error_code = error_code


def is_vault_platform_supported() -> bool:
    return sys.platform == "win32"


class DashboardCredentialVault:
    def __init__(self, data_dir: Path) -> None:
        self.data_dir = data_dir.expanduser().resolve()
        self.vault_path = self.data_dir / VAULT_FILENAME

    def save_telegram_credentials(self, api_id: str, api_hash: str) -> None:
        self._require_platform()
        cleaned_id = str(api_id).strip()
        cleaned_hash = str(api_hash).strip()
        self._validate_credentials(cleaned_id, cleaned_hash)
        payload = json.dumps(
            {"api_id": cleaned_id, "api_hash": cleaned_hash},
            separators=(",", ":"),
        ).encode("utf-8")
        encrypted = _dpapi_protect(payload)
        envelope = {
            "version": VAULT_VERSION,
            "encrypted_b64": base64.b64encode(encrypted).decode("ascii"),
        }
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self._atomic_write_json(self.vault_path, envelope)

    def load_telegram_credentials(self) -> tuple[str, str] | None:
        if not self.vault_path.exists():
            return None
        self._require_platform()
        try:
            envelope = json.loads(self.vault_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_READ_FAILED",
                "Unable to read credential vault file",
            ) from exc
        encrypted_b64 = envelope.get("encrypted_b64")
        if not isinstance(encrypted_b64, str) or not encrypted_b64:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_INVALID",
                "Credential vault file is invalid",
            )
        try:
            decrypted = _dpapi_unprotect(base64.b64decode(encrypted_b64))
            payload = json.loads(decrypted.decode("utf-8"))
        except (ValueError, json.JSONDecodeError) as exc:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_DECRYPT_FAILED",
                "Unable to decrypt credential vault payload",
            ) from exc
        api_id = str(payload.get("api_id", "")).strip()
        api_hash = str(payload.get("api_hash", "")).strip()
        if not api_id or not api_hash:
            return None
        self._validate_credentials(api_id, api_hash)
        return api_id, api_hash

    def has_telegram_credentials(self) -> bool:
        if not self.vault_path.exists():
            return False
        if not is_vault_platform_supported():
            return False
        try:
            return self.load_telegram_credentials() is not None
        except CredentialVaultError:
            return False

    def vault_file_present(self) -> bool:
        return self.vault_path.is_file()

    def clear_telegram_credentials(self) -> None:
        if self.vault_path.exists():
            self.vault_path.unlink()

    def status_payload(self) -> dict[str, bool]:
        supported = is_vault_platform_supported()
        saved = self.has_telegram_credentials() if supported else False
        return {
            "vault_supported": supported,
            "credentials_saved": saved,
        }

    def _require_platform(self) -> None:
        if not is_vault_platform_supported():
            raise CredentialVaultError(
                CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM,
                "Credential vault is supported on Windows only",
            )

    @staticmethod
    def _validate_credentials(api_id: str, api_hash: str) -> None:
        try:
            parsed_id = int(api_id)
        except ValueError as exc:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_INVALID",
                "API ID must be a positive integer",
            ) from exc
        if parsed_id <= 0:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_INVALID",
                "API ID must be a positive integer",
            )
        if not api_hash or len(api_hash) < 8:
            raise CredentialVaultError(
                "CREDENTIAL_VAULT_INVALID",
                "API hash is invalid",
            )

    def _atomic_write_json(self, target: Path, payload: dict[str, object]) -> None:
        encoded = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        fd, temp_name = tempfile.mkstemp(
            prefix=f".{target.name}.",
            suffix=".tmp",
            dir=str(self.data_dir),
        )
        temp_path = Path(temp_name)
        try:
            with os.fdopen(fd, "wb") as handle:
                handle.write(encoded)
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temp_path, target)
            try:
                os.chmod(target, 0o600)
            except OSError:
                pass
        finally:
            if temp_path.exists():
                temp_path.unlink(missing_ok=True)


def _dpapi_protect(plaintext: bytes) -> bytes:
    if not is_vault_platform_supported():
        raise CredentialVaultError(
            CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM,
            "Credential vault is supported on Windows only",
        )
    import ctypes
    from ctypes import wintypes

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_char)),
        ]

    buffer_in = ctypes.create_string_buffer(plaintext)
    blob_in = DATA_BLOB(len(plaintext), ctypes.cast(buffer_in, ctypes.POINTER(ctypes.c_char)))
    blob_out = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptProtectData(
        ctypes.byref(blob_in),
        None,
        None,
        None,
        None,
        CRYPTPROTECT_UI_FORBIDDEN,
        ctypes.byref(blob_out),
    ):
        raise CredentialVaultError(
            "CREDENTIAL_VAULT_ENCRYPT_FAILED",
            "Unable to encrypt credential payload",
        )
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(blob_out.pbData)


def _dpapi_unprotect(ciphertext: bytes) -> bytes:
    if not is_vault_platform_supported():
        raise CredentialVaultError(
            CREDENTIAL_VAULT_UNSUPPORTED_PLATFORM,
            "Credential vault is supported on Windows only",
        )
    import ctypes
    from ctypes import wintypes

    class DATA_BLOB(ctypes.Structure):
        _fields_ = [
            ("cbData", wintypes.DWORD),
            ("pbData", ctypes.POINTER(ctypes.c_char)),
        ]

    buffer_in = ctypes.create_string_buffer(ciphertext)
    blob_in = DATA_BLOB(len(ciphertext), ctypes.cast(buffer_in, ctypes.POINTER(ctypes.c_char)))
    blob_out = DATA_BLOB()
    if not ctypes.windll.crypt32.CryptUnprotectData(
        ctypes.byref(blob_in),
        None,
        None,
        None,
        None,
        CRYPTPROTECT_UI_FORBIDDEN,
        ctypes.byref(blob_out),
    ):
        raise CredentialVaultError(
            "CREDENTIAL_VAULT_DECRYPT_FAILED",
            "Unable to decrypt credential payload",
        )
    try:
        return ctypes.string_at(blob_out.pbData, blob_out.cbData)
    finally:
        ctypes.windll.kernel32.LocalFree(blob_out.pbData)
