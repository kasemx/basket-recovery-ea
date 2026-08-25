#!/usr/bin/env python3
"""Write a typical JustGoldDan signal to FILE_COMMON without Telegram or dashboard."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

_INTEGRATIONS_TELEGRAM_DIR = Path(__file__).resolve().parent
if str(_INTEGRATIONS_TELEGRAM_DIR) not in sys.path:
    sys.path.insert(0, str(_INTEGRATIONS_TELEGRAM_DIR))

from candidate_test_arm_service import (
    EXPECTED_DETAILS_FILENAME,
    EXPECTED_SEED_FILENAME,
)
from fasttrack_file_bridge import (
    AtomicPublisher,
    BridgeLogger,
    TelegramInboundMessage,
    TelegramMessageHandler,
    TelegramPairMatcher,
    resolve_root,
)

SAMPLE_JUSTGOLDDAN_TEXT = (
    "🔥 Gold sell now 4014 – 4017\n"
    "SL: 4077\n"
    "TP: 4007"
)


def run_local_signal_test(out_dir: Path) -> dict[str, Path]:
    """Parse one JustGoldDan-style message and write the FastTrack seed/details pair."""
    out_dir.mkdir(parents=True, exist_ok=True)
    root = resolve_root(str(out_dir))
    logger = BridgeLogger()
    publisher = AtomicPublisher(logger)
    matcher = TelegramPairMatcher(
        publisher=publisher,
        root=root,
        seed_filename=EXPECTED_SEED_FILENAME,
        details_filename=EXPECTED_DETAILS_FILENAME,
        pair_timeout_seconds=900,
        logger=logger,
        mode="justgolddan-local-test",
        dry_run=False,
    )
    handler = TelegramMessageHandler(matcher, logger)
    handler.handle(
        TelegramInboundMessage(
            text=SAMPLE_JUSTGOLDDAN_TEXT,
            message_id=1,
            channel_id=-100123,
        )
    )
    seed_path = root / EXPECTED_SEED_FILENAME
    details_path = root / EXPECTED_DETAILS_FILENAME
    if not seed_path.is_file() or not details_path.is_file():
        raise RuntimeError(
            "JustGoldDan test signal did not write seed/details files."
        )
    return {"seed_path": seed_path, "details_path": details_path}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "JustGoldDan test sinyalini FILE_COMMON dosyalarına yazar. "
            "Telegram girişi ve sahte demo kanal gerekmez. Broker emri açılmaz."
        )
    )
    parser.add_argument(
        "--out",
        required=True,
        help="FILE_COMMON klasörü (EA'nın okuduğu Files ortak dizini)",
    )
    args = parser.parse_args(argv)
    try:
        result = run_local_signal_test(Path(args.out).expanduser())
    except Exception as exc:  # noqa: BLE001 - CLI boundary
        print(f"HATA: {exc}", file=sys.stderr)
        return 1
    print("TAMAM: JustGoldDan test sinyali FILE_COMMON dosyalarına yazıldı.")
    print(f"  seed:    {result['seed_path']}")
    print(f"  details: {result['details_path']}")
    print("Broker emri bu adımda açılmaz. EA FastTrack + dosya polling + authorization gerekir.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
