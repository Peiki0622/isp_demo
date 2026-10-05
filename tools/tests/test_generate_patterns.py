"""验证生成器对外文件契约，而非仅确认脚本正常退出。临时文件集中在 build。"""

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / "build" / "p0_p1" / "python"


class PatternTests(unittest.TestCase):
    """检查字节可重复性、文件格式、独立地址公式及输入错误。"""

    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.out = Path(self.temp.name)

    def generate(self, width, height, output):
        return subprocess.run(
            [sys.executable, str(ROOT / "tools/generate_patterns.py"),
             "--width", str(width), "--height", str(height), "--output", str(output)],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)

    def test_16x16_formats_and_repeatability(self):
        first, second = self.out / "first", self.out / "second"
        self.assertEqual(self.generate(16, 16, first).returncode, 0)
        self.assertEqual(self.generate(16, 16, second).returncode, 0)
        self.assertEqual(len(list(first.iterdir())), 12)
        for name in ("addr_ramp", "flat", "checker", "gradient"):
            stem = name + "_16x16"
            lines = (first / (stem + ".mem")).read_text().splitlines()
            self.assertEqual(len(lines), 256)
            for line in lines:
                self.assertRegex(line, r"^[0-9a-f]{4}$")
                self.assertLessEqual(int(line, 16), 4095)
            array = np.load(str(first / (stem + ".npy")))
            self.assertEqual(array.shape, (16, 16))
            self.assertEqual(array.dtype, np.dtype("uint16"))
            np.testing.assert_array_equal(array.ravel(), [int(v, 16) for v in lines])
            metadata = json.loads((first / (stem + ".json")).read_text())
            self.assertEqual(metadata, dict(width=16, height=16, raw_bits=12,
                                           bayer="RGGB", pattern=name, pixel_count=256))
        for path in first.iterdir():
            self.assertEqual(path.read_bytes(), (second / path.name).read_bytes())
        values = [int(v, 16) for v in (first / "addr_ramp_16x16.mem").read_text().splitlines()]
        for i in (0, 1, 15, 16, 255):
            self.assertEqual(values[i], i)

    def test_rectangle_and_modulo_boundary(self):
        # 3x5 验证行优先排列；64x65 穿过 RAW12 取模边界，检查第 4096 个地址。
        for width, height in ((3, 5), (64, 65)):
            out = self.out / ("{}x{}".format(width, height))
            self.assertEqual(self.generate(width, height, out).returncode, 0)
            array = np.load(str(out / "addr_ramp_{}x{}.npy".format(width, height)))
            for y in range(height):
                for x in range(width):
                    self.assertEqual(int(array[y, x]), (y * width + x) % 4096)

    def test_nonpositive_dimensions_rejected(self):
        for width, height in ((0, 16), (16, 0), (-1, 16), (16, -1)):
            self.assertNotEqual(self.generate(width, height, self.out / "invalid").returncode, 0)
        self.assertFalse((self.out / "invalid").exists())


if __name__ == "__main__":
    unittest.main()
