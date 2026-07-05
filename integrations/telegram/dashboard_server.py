#!/usr/bin/env python3
"""Local-only Telegram Route Dashboard server bootstrap."""

from __future__ import annotations

import argparse
import logging
import sys
from http.server import ThreadingHTTPServer
from pathlib import Path

_INTEGRATIONS_TELEGRAM_DIR = Path(__file__).resolve().parent
if str(_INTEGRATIONS_TELEGRAM_DIR) not in sys.path:
    sys.path.insert(0, str(_INTEGRATIONS_TELEGRAM_DIR))

from dashboard_api import DashboardContext, DashboardRequestHandler
from dashboard_security import (
    ALLOWED_HOST,
    DEFAULT_PORT,
    DashboardSecurityError,
    resolve_default_data_dir,
    validate_host,
)
from dashboard_vault import DashboardCredentialVault
from dashboard_store import DashboardDatabase

logger = logging.getLogger("telegram_dashboard")


def create_server(context: DashboardContext) -> ThreadingHTTPServer:
    handler_cls = type(
        "BoundDashboardHandler",
        (DashboardRequestHandler,),
        {"context": context},
    )
    return ThreadingHTTPServer((context.host, context.port), handler_cls)


def run_server(context: DashboardContext) -> None:
    server = create_server(context)
    vault = DashboardCredentialVault(context.data_dir)
    logger.info(
        "dashboard_event=DATA_DIR_READY vault_file_present=%s",
        vault.vault_file_present(),
    )
    logger.info(
        "dashboard_event=SERVER_READY host=%s port=%s",
        context.host,
        context.port,
    )
    try:
        server.serve_forever()
    finally:
        server.server_close()


def build_context(
    *,
    host: str,
    port: int,
    data_dir: Path,
    dashboard_dir: Path,
) -> DashboardContext:
    db_path = data_dir / "dashboard.sqlite3"
    database = DashboardDatabase(db_path)
    return DashboardContext(
        host=host,
        port=port,
        data_dir=data_dir,
        dashboard_dir=dashboard_dir,
        database=database,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Local Telegram Route Dashboard")
    parser.add_argument("--host", default=ALLOWED_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--data-dir", default=str(resolve_default_data_dir()))
    parser.add_argument("--dashboard-dir", default="integrations/telegram/dashboard")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    try:
        host = validate_host(args.host)
    except DashboardSecurityError as exc:
        logger.error("dashboard_event=ERROR reason=%s", exc)
        return 2

    data_dir = Path(args.data_dir).expanduser().resolve()
    dashboard_dir = Path(args.dashboard_dir).expanduser().resolve()
    context = build_context(
        host=host,
        port=args.port,
        data_dir=data_dir,
        dashboard_dir=dashboard_dir,
    )
    run_server(context)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
