"""Tests for FastTrack FILE_COMMON atomic publish (temporary directories only)."""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import fasttrack_file_bridge as bridge  # noqa: E402


VALID_SEED = "Gold sell now"
VALID_DETAILS = (
    "Gold sell now 4014 - 4017\n"
    "SL: 4077\n"
    "TP: 4007\n"
    "TP: 4005\n"
    "TP: 4003\n"
    "TP: 4002\n"
    "TP: open"
)
SEED_NAME = "basket_recovery_fasttrack_seed.txt"
DETAILS_NAME = "basket_recovery_fasttrack_details.txt"


class AtomicPublishTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.temp_dir = tempfile.mkdtemp(prefix="fasttrack_bridge_test_")
        self.root = Path(self.temp_dir)
        self.logger = bridge.BridgeLogger()
        self.publisher = bridge.AtomicPublisher(self.logger)

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def publish(
        self,
        seed_text: str = VALID_SEED,
        details_text: str = VALID_DETAILS,
        dry_run: bool = False,
    ) -> bridge.PublishResult:
        return self.publisher.publish_pair(
            root=self.root,
            seed_filename=SEED_NAME,
            details_filename=DETAILS_NAME,
            seed_text=seed_text,
            details_text=details_text,
            correlation_key="gold|sell|2026-07-05|test",
            mode="test",
            dry_run=dry_run,
        )

    def read_finals(self) -> tuple[str, str]:
        seed = (self.root / SEED_NAME).read_text(encoding="utf-8")
        details = (self.root / DETAILS_NAME).read_text(encoding="utf-8")
        return seed, details

    def test_successful_publish(self) -> None:
        result = self.publish()
        seed, details = self.read_finals()
        self.assertEqual(seed, VALID_SEED)
        self.assertEqual(details, VALID_DETAILS)
        self.assertTrue(result.fingerprint)
        leftovers = list(self.root.glob("*.hold.*")) + list(self.root.glob("*.part.*"))
        self.assertEqual(leftovers, [])

    def test_invalid_filename_reject(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            self.publisher.publish_pair(
                root=self.root,
                seed_filename="../evil.txt",
                details_filename=DETAILS_NAME,
                seed_text=VALID_SEED,
                details_text=VALID_DETAILS,
                correlation_key="x",
                mode="test",
            )

    def test_root_escape_reject(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            bridge.assert_within_root(self.root, self.root.parent / "escaped.txt")

    def test_empty_seed_reject(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            self.publish(seed_text="   ")

    def test_empty_details_reject(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            self.publish(details_text="\n")

    def test_non_ascii_reject(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            self.publish(seed_text="Gold sell now €")

    def test_oversize_payload_reject(self) -> None:
        huge = "A" * (bridge.MAX_BYTES + 1)
        with self.assertRaises(bridge.BridgeValidationError):
            self.publish(details_text=huge)

    def test_dedup_skips_second_publish(self) -> None:
        self.publish()
        with mock.patch.object(bridge.os, "replace", wraps=bridge.os.replace) as replace_mock:
            self.publish()
            replace_mock.assert_not_called()

    def test_details_without_seed_skipped(self) -> None:
        matcher = bridge.PairMatcher(
            publisher=self.publisher,
            root=self.root,
            seed_filename=SEED_NAME,
            details_filename=DETAILS_NAME,
            pair_timeout_seconds=900,
            logger=self.logger,
            mode="test",
        )
        with mock.patch.object(self.logger, "log") as log_mock:
            matcher.ingest_details(VALID_DETAILS, "details-001")
            log_mock.assert_any_call(
                "SKIPPED",
                reason="details_without_seed",
                message_id="details-001",
                mode="test",
                timestamp_utc=mock.ANY,
            )
        self.assertFalse((self.root / SEED_NAME).exists())
        self.assertFalse((self.root / DETAILS_NAME).exists())

    def test_new_seed_replaces_stale_unmatched_seed(self) -> None:
        matcher = bridge.PairMatcher(
            publisher=self.publisher,
            root=self.root,
            seed_filename=SEED_NAME,
            details_filename=DETAILS_NAME,
            pair_timeout_seconds=900,
            logger=self.logger,
            mode="test",
        )
        with mock.patch.object(self.logger, "log") as log_mock:
            matcher.ingest_seed("Gold sell now", "seed-001")
            matcher.ingest_seed("Gold sell now", "seed-002")
            log_mock.assert_any_call(
                "SKIPPED",
                reason="stale_seed_replaced",
                correlation_key=mock.ANY,
                mode="test",
                timestamp_utc=mock.ANY,
            )
        self.assertIsNotNone(matcher.pending_seed)
        self.assertEqual(matcher.pending_seed.message_id, "seed-002")

    def test_publish_failure_restores_previous_pair(self) -> None:
        old_seed = "Gold sell now"
        old_details = "Gold sell now 4010 - 4012\nSL: 4080\nTP: open"
        self.publish(seed_text=old_seed, details_text=old_details)

        replace_calls = {"count": 0}
        original_replace = bridge.os.replace

        def flaky_replace(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
            replace_calls["count"] += 1
            if replace_calls["count"] == 4:
                raise OSError("simulated seed replace failure")
            original_replace(src, dst)

        new_seed = "Gold buy now"
        new_details = "Gold buy now 4020 - 4025\nSL: 4010\nTP: open"
        with mock.patch.object(bridge.os, "replace", side_effect=flaky_replace):
            with self.assertRaises(OSError):
                self.publish(seed_text=new_seed, details_text=new_details)

        seed, details = self.read_finals()
        self.assertEqual(seed, old_seed)
        self.assertEqual(details, old_details)
        leftovers = list(self.root.glob("*.hold.*")) + list(self.root.glob("*.part.*"))
        self.assertEqual(leftovers, [])

    def test_details_first_window_has_no_final_seed(self) -> None:
        old_seed = "Gold sell now"
        old_details = "Gold sell now 4010 - 4012\nSL: 4080\nTP: open"
        self.publish(seed_text=old_seed, details_text=old_details)

        observed: list[bool] = []
        original_replace = bridge.os.replace

        def observing_replace(src: str | os.PathLike[str], dst: str | os.PathLike[str]) -> None:
            original_replace(src, dst)
            dst_path = Path(dst)
            if dst_path.name == DETAILS_NAME:
                observed.append((self.root / SEED_NAME).exists())

        new_details = (
            "Gold sell now 4014 - 4017\nSL: 4077\nTP: 4007\nTP: open"
        )
        with mock.patch.object(bridge.os, "replace", side_effect=observing_replace):
            self.publish(details_text=new_details)

        self.assertEqual(observed, [False])

    def test_dry_run_writes_no_files(self) -> None:
        self.publish(dry_run=True)
        self.assertFalse((self.root / SEED_NAME).exists())
        self.assertFalse((self.root / DETAILS_NAME).exists())


class ValidationHelperTests(unittest.TestCase):
    def test_validate_basename_rejects_colon(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            bridge.validate_basename("bad:name.txt")

    def test_invalid_seed_format(self) -> None:
        with self.assertRaises(bridge.BridgeValidationError):
            bridge.validate_seed_format("Gold sell later")


class TelegramListenerTests(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.temp_dir = tempfile.mkdtemp(prefix="fasttrack_telegram_test_")
        self.root = Path(self.temp_dir)
        self.logger = bridge.BridgeLogger()
        self.publisher = bridge.AtomicPublisher(self.logger)
        self.matcher = bridge.TelegramPairMatcher(
            publisher=self.publisher,
            root=self.root,
            seed_filename=SEED_NAME,
            details_filename=DETAILS_NAME,
            pair_timeout_seconds=900,
            logger=self.logger,
            mode="telegram-listen",
            dry_run=True,
        )
        self.handler = bridge.TelegramMessageHandler(self.matcher, self.logger)

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def msg(
        self,
        text: str,
        message_id: int = 1,
        channel_id: int = -100123,
        grouped_id: int | None = None,
        reply_to_msg_id: int | None = None,
    ) -> bridge.TelegramInboundMessage:
        return bridge.normalize_telegram_message(
            text=text,
            message_id=message_id,
            channel_id=channel_id,
            grouped_id=grouped_id,
            reply_to_msg_id=reply_to_msg_id,
        )

    def test_telethon_missing_returns_error_exit_code(self) -> None:
        parser = bridge.build_parser()
        args = parser.parse_args(
            [
                "--telegram-listen",
                "--file-common-root",
                str(self.root),
                "--telegram-api-id",
                "12345",
                "--telegram-api-hash",
                "hash",
                "--telegram-session-path",
                str(self.root / "session"),
                "--telegram-channel",
                "@channel",
            ]
        )
        with mock.patch.object(bridge, "is_telethon_available", return_value=False):
            with mock.patch.object(bridge.BridgeLogger, "log") as log_mock:
                exit_code = bridge.run_telegram_listen(args)
        self.assertEqual(exit_code, 1)
        log_mock.assert_any_call(
            "ERROR",
            reason="telethon_not_installed",
            detail="Install with: pip install telethon",
            timestamp_utc=mock.ANY,
        )

    def test_credential_validation_missing_api_id(self) -> None:
        parser = bridge.build_parser()
        args = parser.parse_args(
            [
                "--telegram-listen",
                "--file-common-root",
                str(self.root),
                "--telegram-api-hash",
                "hash",
                "--telegram-session-path",
                str(self.root / "session"),
                "--telegram-channel",
                "@channel",
            ]
        )
        with self.assertRaises(bridge.BridgeValidationError):
            bridge.validate_telegram_config(args)

    def test_normalize_telegram_event_metadata(self) -> None:
        class FakeReply:
            reply_to_msg_id = 42

        class FakeMessage:
            id = 99
            message = VALID_SEED
            grouped_id = 777
            reply_to = FakeReply()

        class FakeEvent:
            message = FakeMessage()
            chat_id = -100555

        inbound = bridge.normalize_telegram_event(FakeEvent())
        self.assertEqual(inbound.message_id, 99)
        self.assertEqual(inbound.channel_id, -100555)
        self.assertEqual(inbound.grouped_id, 777)
        self.assertEqual(inbound.reply_to_msg_id, 42)
        self.assertEqual(inbound.text, VALID_SEED)

    def test_empty_message_skipped(self) -> None:
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(self.msg("   ", message_id=10))
        log_mock.assert_any_call(
            "SKIPPED",
            reason="empty_message",
            message_id=10,
            channel_id=-100123,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
        )

    def test_non_ascii_message_skipped(self) -> None:
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(self.msg("Gold sell now €", message_id=11))
        log_mock.assert_any_call(
            "SKIPPED",
            reason="non_ascii_message",
            message_id=11,
            channel_id=-100123,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
        )

    def test_duplicate_message_id_skipped(self) -> None:
        first = self.msg(VALID_SEED, message_id=12)
        second = self.msg("Gold buy now", message_id=12)
        self.handler.handle(first)
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(second)
        log_mock.assert_any_call(
            "SKIPPED",
            reason="telegram_dedup",
            message_id=12,
            channel_id=-100123,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
        )

    def test_duplicate_raw_hash_skipped(self) -> None:
        self.handler.handle(self.msg(VALID_SEED, message_id=20))
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(self.msg(VALID_SEED, message_id=21))
        log_mock.assert_any_call(
            "SKIPPED",
            reason="telegram_dedup",
            message_id=21,
            channel_id=-100123,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
        )

    def test_seed_details_fallback_match(self) -> None:
        self.handler.handle(self.msg(VALID_SEED, message_id=30))
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(self.msg(VALID_DETAILS, message_id=31))
        log_mock.assert_any_call(
            "PUBLISH_READY",
            correlation_key=mock.ANY,
            pair_fingerprint=mock.ANY,
            seed_file=SEED_NAME,
            details_file=DETAILS_NAME,
            seed_bytes=mock.ANY,
            details_bytes=mock.ANY,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
            dry_run="true",
        )

    def test_grouped_id_priority(self) -> None:
        grouped = 9001
        self.handler.handle(
            self.msg(VALID_SEED, message_id=40, grouped_id=grouped)
        )
        self.matcher.pending_seed = None
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(
                self.msg(VALID_DETAILS, message_id=41, grouped_id=grouped)
            )
        log_mock.assert_any_call(
            "PUBLISH_READY",
            correlation_key=mock.ANY,
            pair_fingerprint=mock.ANY,
            seed_file=SEED_NAME,
            details_file=DETAILS_NAME,
            seed_bytes=mock.ANY,
            details_bytes=mock.ANY,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
            dry_run="true",
        )

    def test_reply_to_priority(self) -> None:
        self.handler.handle(self.msg(VALID_SEED, message_id=50))
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(
                self.msg(VALID_DETAILS, message_id=51, reply_to_msg_id=50)
            )
        log_mock.assert_any_call(
            "PUBLISH_READY",
            correlation_key=mock.ANY,
            pair_fingerprint=mock.ANY,
            seed_file=SEED_NAME,
            details_file=DETAILS_NAME,
            seed_bytes=mock.ANY,
            details_bytes=mock.ANY,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
            dry_run="true",
        )

    def test_unrecognized_message_skipped(self) -> None:
        with mock.patch.object(self.logger, "log") as log_mock:
            self.handler.handle(self.msg("hello world", message_id=60))
        log_mock.assert_any_call(
            "SKIPPED",
            reason="unrecognized_message",
            message_id=60,
            channel_id=-100123,
            mode="telegram-listen",
            timestamp_utc=mock.ANY,
        )


if __name__ == "__main__":
    unittest.main()
