"""全链黄金 CLI：独立手算文件、非法输入和失败清除旧目标。"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / 'build' / 'p3_awb' / 'python'


class AWBGoldenTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.source = Path(self.temp.name) / 'input.npy'
        self.output = Path(self.temp.name) / 'golden.mem'
        np.save(str(self.source), np.full((2, 2), 100, dtype=np.uint16))

    def generate(self, black=64, gains=(8192, 2048, 6144)):
        return subprocess.run(
            [sys.executable, '-m', 'model.generate_awb_golden', '--input', str(self.source),
             '--output', str(self.output), '--black-level', str(black),
             '--gain-r', str(gains[0]), '--gain-g', str(gains[1]), '--gain-b', str(gains[2])],
            cwd=str(ROOT), stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

    def test_exact_chain_order_and_raster_file(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        # (100-64) 乘 2/0.5/0.5/1.5 = 72/18/18/54；也捕获 AWB->BLC 错序。
        self.assertEqual(self.output.read_text(), '0048\n0012\n0012\n0036\n')
        self.assertIn('pixels=4', result.stdout)

    def test_invalid_configs_remove_stale_golden(self):
        for black, gains in ((-1, (4096, 4096, 4096)), (4096, (4096, 4096, 4096)),
                             (0, (-1, 4096, 4096)), (0, (4096, 65536, 4096)),
                             (0, (4096, 4096, 65536))):
            self.output.write_text('0fff\n')
            result = self.generate(black, gains)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('[FAIL] AWB golden generation', result.stderr)
            self.assertFalse(self.output.exists())

    def test_missing_input_removes_stale_golden(self):
        self.source.unlink()
        self.output.write_text('0fff\n')
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertFalse(self.output.exists())

    def test_invalid_image_removes_stale_golden(self):
        for raw in (np.array([1, 2]), np.array([[4096]]), np.array([[-1]]),
                    np.array([[1.0]]), np.empty((0, 2))):
            np.save(str(self.source), raw)
            self.output.write_text('0fff\n')
            self.assertNotEqual(self.generate().returncode, 0)
            self.assertFalse(self.output.exists())


if __name__ == '__main__':
    unittest.main()
