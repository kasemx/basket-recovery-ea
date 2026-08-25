"""JustGoldDan local FILE_COMMON smoke — no Telegram, no dashboard, no fake demo channels."""

from __future__ import annotations

import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import run_justgolddan_local_test as local_test  # noqa: E402
from candidate_test_arm_service import (  # noqa: E402
    EXPECTED_DETAILS_FILENAME,
    EXPECTED_SEED_FILENAME,
)


class JustGoldDanLocalTestCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = Path(tempfile.mkdtemp(prefix="justgolddan_local_test_"))

    def tearDown(self) -> None:
        for path in sorted(self.temp_dir.rglob("*"), reverse=True):
            if path.is_file():
                path.unlink()
            elif path.is_dir():
                path.rmdir()
        if self.temp_dir.exists():
            self.temp_dir.rmdir()

    def test_writes_seed_and_details_from_typical_justgolddan_message(self) -> None:
        result = local_test.run_local_signal_test(self.temp_dir)
        seed_path = self.temp_dir / EXPECTED_SEED_FILENAME
        details_path = self.temp_dir / EXPECTED_DETAILS_FILENAME
        self.assertTrue(seed_path.is_file())
        self.assertTrue(details_path.is_file())
        self.assertEqual(seed_path.read_text(encoding="utf-8").strip().lower(), "gold sell now")
        details = details_path.read_text(encoding="utf-8")
        self.assertIn("SL: 4077", details)
        self.assertIn("4014 - 4017", details)
        self.assertEqual(result["seed_path"], seed_path)
        self.assertEqual(result["details_path"], details_path)

    def test_cli_exit_zero_and_prints_file_paths(self) -> None:
        stdout = io.StringIO()
        with patch.object(sys, "stdout", stdout):
            code = local_test.main(["--out", str(self.temp_dir)])
        self.assertEqual(code, 0)
        output = stdout.getvalue()
        self.assertIn(EXPECTED_SEED_FILENAME, output)
        self.assertIn(EXPECTED_DETAILS_FILENAME, output)
        self.assertIn("Broker emri", output)
        self.assertTrue((self.temp_dir / EXPECTED_SEED_FILENAME).is_file())


if __name__ == "__main__":
    unittest.main()
