"""数值与配置验收，期望含手算边界和独立逐像素整数参考。"""

import unittest

import numpy as np

from model.awb_gain import apply_awb_gain, scale_pixel
from model.isp_model import run_pipeline


class AWBGainTests(unittest.TestCase):
    def test_hand_calculated_boundaries(self):
        cases = [(123, 4096, 123), (4095, 0, 0), (1, 2047, 0),
                 (1, 2048, 1), (1, 2049, 1), (3, 2048, 2),
                 (100, 6144, 150), (100, 8192, 200), (2048, 4097, 2049),
                 (4094, 4096, 4094), (4095, 4096, 4095),
                 (4095, 4097, 4095), (4095, 8192, 4095), (4095, 65535, 4095)]
        for pixel, gain, wanted in cases:
            self.assertEqual(scale_pixel(pixel, gain), wanted)
            self.assertIsInstance(scale_pixel(np.uint16(pixel), np.uint16(gain)), int)

    def test_all_raw_values_for_boundary_gains(self):
        # divmod 判定余数是否达到半码，独立于模型的加偏置实现。
        for gain in (0, 1, 2047, 2048, 2049, 4095, 4096, 4097, 6144, 8192, 65535):
            for pixel in range(4096):
                integer, remainder = divmod(pixel * gain, 4096)
                wanted = min(integer + int(remainder >= 2048), 4095)
                self.assertEqual(scale_pixel(pixel, gain), wanted)

    def test_rggb_shared_green(self):
        raw = np.full((2, 2), 100, dtype=np.uint16)
        np.testing.assert_array_equal(apply_awb_gain(raw, 8192, 2048, 6144),
                                      [[200, 50], [50, 150]])

    def test_odd_shape_widening_and_input_preservation(self):
        raw = ((np.arange(15).reshape(5, 3) * 313) % 4096).astype(np.uint16)
        saved = raw.copy()
        gains = (65535, 4097, 2048)
        expected = np.empty(raw.shape, dtype=np.uint16)
        for y in range(5):
            for x in range(3):
                gain = gains[0] if y % 2 == x % 2 == 0 else (
                    gains[2] if y % 2 == x % 2 == 1 else gains[1])
                q, r = divmod(int(raw[y, x]) * gain, 4096)
                expected[y, x] = min(q + int(r >= 2048), 4095)
        result = apply_awb_gain(raw, *gains)
        self.assertEqual(result.dtype, np.uint16)
        np.testing.assert_array_equal(result, expected)
        np.testing.assert_array_equal(raw, saved)
        self.assertFalse(np.shares_memory(result, raw))

    def test_invalid_scalars(self):
        for value in (-1, 4096, 1.0, True, np.bool_(False)):
            with self.assertRaises(ValueError):
                scale_pixel(value, 4096)
        for value in (-1, 65536, 1.0, True, np.bool_(False)):
            with self.assertRaises(ValueError):
                scale_pixel(1, value)
            for channel in range(3):
                gains = [4096, 4096, 4096]
                gains[channel] = value
                with self.assertRaises(ValueError):
                    apply_awb_gain([[1]], *gains)

    def test_invalid_images(self):
        for raw in (1, [1, 2], [[[1]]], np.empty((0, 2)), [[-1]],
                    [[4096]], [[1.0]], [[True]]):
            with self.assertRaises(ValueError):
                apply_awb_gain(raw, 4096, 4096, 4096)

    def test_pipeline_order_defaults_and_flags(self):
        raw = np.full((2, 2), 100, dtype=np.uint16)
        config = {'pipeline': {'blc': True, 'awb_gain': True},
                  'blc': {'offset': 64}, 'awb_gain': {'r': 8192, 'g': 2048, 'b': 6144}}
        np.testing.assert_array_equal(run_pipeline(raw, config), [[72, 18], [18, 54]])
        self.assertIs(run_pipeline(raw, {}), raw)
        np.testing.assert_array_equal(run_pipeline(raw, {'pipeline': {'awb_gain': True}}), raw)
        config['pipeline']['blc'] = False
        np.testing.assert_array_equal(run_pipeline(raw, config), [[200, 50], [50, 150]])
        config['pipeline']['blc'] = True
        config['pipeline']['awb_gain'] = False
        np.testing.assert_array_equal(run_pipeline(raw, config), np.full((2, 2), 36))


if __name__ == '__main__':
    unittest.main()
