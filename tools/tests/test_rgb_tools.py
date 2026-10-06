"""P4 工具公开接口验收，所有临时文件仅位于 P4 的 python 目录。"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
import numpy as np
from tools.rgb_to_bayer import rgb_to_bayer, make_rgb_patterns

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = ROOT / 'build/p4_demosaic/python'


class RGBToolsTests(unittest.TestCase):
    def setUp(self):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=str(SCRATCH))
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.expected, self.actual = self.path/'expected.mem', self.path/'actual.mem'
        self.expected.write_text('001002003\nfff123abc\n')
        self.actual.write_bytes(self.expected.read_bytes())

    def compare(self, width='2', height='1'):
        return subprocess.run([sys.executable, str(ROOT/'tools/compare_rgb_output.py'),
            '--expected', str(self.expected), '--actual', str(self.actual),
            '--width', width, '--height', height], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, universal_newlines=True)

    def test_rgb_to_bayer_four_phases_and_no_mutation(self):
        rgb = np.arange(45).reshape(3, 5, 3)
        saved = rgb.copy()
        raw = rgb_to_bayer(rgb)
        for y in range(3):
            for x in range(5):
                self.assertEqual(raw[y, x], rgb[y, x, ((0, 1), (1, 2))[y%2][x%2]])
        self.assertEqual(raw.dtype, np.uint16)
        np.testing.assert_array_equal(rgb, saved)
        self.assertFalse(np.shares_memory(raw, rgb))

    def test_rgb_to_bayer_rejects_invalid_data(self):
        for value in ([], [1], np.zeros((2, 2)), np.zeros((2, 2, 4)),
                      np.zeros((0, 2, 3)), np.ones((2, 2, 3), dtype=float),
                      np.ones((2, 2, 3), dtype=bool), np.full((2, 2, 3), -1),
                      np.full((2, 2, 3), 4096)):
            with self.assertRaises(ValueError):
                rgb_to_bayer(value)

    def test_equal_and_channel_diagnostics(self):
        self.assertEqual(self.compare().returncode, 0)
        for word, channel in (('ffe123abc', 'R'), ('fff124abc', 'G'), ('fff123abd', 'B')):
            self.actual.write_text('001002003\n'+word+'\n')
            result = self.compare()
            self.assertEqual(result.returncode, 1)
            for text in ('index=1', 'x=1', 'y=0', 'channels='+channel, 'expected RGB=', 'actual RGB='):
                self.assertIn(text, result.stderr)

    def test_required_count_even_when_files_match(self):
        self.assertEqual(self.compare('2', '2').returncode, 1)
        for words in ('001002003\n', '001002003\nfff123abc\n000000000\n'):
            self.actual.write_text(words)
            self.assertEqual(self.compare().returncode, 1)

    def test_file_format_and_missing_file(self):
        for word in ('', '00000000', '0000000000', '00000x000', '00000z000',
                     ' 001002003', '001002003 ', '001 002 003'):
            self.actual.write_text(word+'\n')
            self.assertEqual(self.compare().returncode, 2, word)
        self.actual.unlink()
        self.assertEqual(self.compare().returncode, 2)
        for w, h in (('0', '1'), ('2', '-1')):
            self.assertEqual(self.compare(w, h).returncode, 2)

    def test_rgb_patterns_file_repeatability_and_mosaic(self):
        for name in ('a', 'b'):
            result = subprocess.run([sys.executable, str(ROOT/'tools/generate_patterns.py'),
                '--width', '3', '--height', '5', '--domain', 'rgb', '--output', str(self.path/name)],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        a, b = self.path/'a', self.path/'b'
        self.assertEqual(len(list(a.iterdir())), 16)
        for path in a.iterdir():
            self.assertEqual(path.read_bytes(), (b/path.name).read_bytes())
        for name, rgb in make_rgb_patterns(3, 5).items():
            np.testing.assert_array_equal(np.load(str(a/(name+'_3x5.npy'))), rgb_to_bayer(rgb))
            self.assertEqual(len((a/(name+'_3x5.mem')).read_text().splitlines()), 15)


if __name__ == '__main__':
    unittest.main()
