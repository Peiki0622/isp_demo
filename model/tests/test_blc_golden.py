"""黄金文件 CLI 验收：检查独立输出格式及失败时旧目标不会被误用。"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "build" / "p2_blc" / "python"


class GoldenFileTests(unittest.TestCase):
    def setUp(self):
        # 所有临时文件放在统一 P2 build 目录，不使用散落工作区的临时产物。
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / "input.npy"
        self.output = Path(self.temp.name) / "golden.mem"
        np.save(str(self.source), np.array([[0, 64, 65], [1024, 2048, 4095]], dtype=np.uint16))

    def generate(self, offset=64):
        return subprocess.run(
            [sys.executable, "-m", "model.generate_blc_golden", "--input", str(self.source),
             "--output", str(self.output), "--black-level", str(offset)],
            cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

    def test_exact_raster_file(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_text(), "0000\n0000\n0001\n03c0\n07c0\n0fbf\n")
        self.assertIn("pixels=6", result.stdout)

    def test_invalid_offset_removes_stale_golden(self):
        self.output.write_text("0fff\n")
        result = self.generate(-1)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("[FAIL] BLC golden generation", result.stderr)
        self.assertFalse(self.output.exists())

    def test_missing_or_non_image_input_fails(self):
        self.source.unlink()
        self.assertNotEqual(self.generate().returncode, 0)
        np.save(str(self.source), np.array([0, 64], dtype=np.uint16))
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
