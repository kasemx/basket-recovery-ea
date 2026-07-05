#!/usr/bin/env python3
"""Backward-compatible entrypoint for the local Telegram route dashboard."""

from __future__ import annotations

import sys
from pathlib import Path

_INTEGRATIONS_TELEGRAM_DIR = Path(__file__).resolve().parent
if str(_INTEGRATIONS_TELEGRAM_DIR) not in sys.path:
    sys.path.insert(0, str(_INTEGRATIONS_TELEGRAM_DIR))

from dashboard_server import main


if __name__ == "__main__":
    raise SystemExit(main())
