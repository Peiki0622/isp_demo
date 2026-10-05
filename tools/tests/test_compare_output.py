"""比较工具 CLI 回归：验证精确匹配、首差异诊断及所有输入失败退出码。"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "build" / "p0_p1" / "python"


class ComparisonTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.expected = Path(self.temp.name) / "expected.mem"
        self.actual = Path(self.temp.name) / "actual.mem"
        self.expected.write_text("0000\n0001\n0fff\n", encoding="ascii")
        self.actual.write_bytes(self.expected.read_bytes())

    def compare(self, *extra):
        return subprocess.run(
            [sys.executable, str(ROOT / "tools/compare_output.py"),
             "--expected", str(self.expected), "--actual", str(self.actual)] + list(extra),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

    def test_equal(self):
        result = self.compare()
        self.assertEqual(result.returncode, 0)
        self.assertIn("pixels=3", result.stdout)

    def test_first_difference_and_coordinate(self):
        self.actual.write_text("0000\n0002\n0003\n")
        result = self.compare("--width", "2")
        self.assertEqual(result.returncode, 1)
        for text in ("index=1", "x=1, y=0", "expected=0x0001", "actual=0x0002"):
            self.assertIn(text, result.stderr)

    def test_missing_and_extra_pixels(self):
        for content, count, index in (("0000\n0001\n", 2, 2),
                                      ("0000\n0001\n0fff\n0003\n", 4, 3)):
            self.actual.write_text(content)
            result = self.compare()
            self.assertEqual(result.returncode, 1)
            self.assertIn("count expected=3 actual={}".format(count), result.stderr)
            self.assertIn("index={}".format(index), result.stderr)
            self.assertIn("missing", result.stderr)

    def test_empty_files_rejected(self):
        self.expected.write_text(""); self.actual.write_text("")
        self.assertEqual(self.compare().returncode, 2)

    def test_malformed_and_unknown_words_rejected(self):
        for word in ("xyz!", "00xz", "001", "00000", "", "@00", "0001 0002"):
            self.actual.write_text(word + "\n")
            self.assertEqual(self.compare().returncode, 2, word)

    def test_upper_bits_rejected(self):
        self.actual.write_text("1000\n")
        result = self.compare()
        self.assertEqual(result.returncode, 2)
        self.assertIn("RAW12", result.stderr)

    def test_missing_file_rejected(self):
        self.actual.unlink()
        self.assertEqual(self.compare().returncode, 2)

    def test_invalid_width_rejected(self):
        for width in ("0", "-1"):
            self.assertEqual(self.compare("--width", width).returncode, 2)


if __name__ == "__main__":
    unittest.main()
