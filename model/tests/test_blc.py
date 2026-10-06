"""BLC 数值验收：阈值手算常量、数组契约、非法配置及流水入口。"""

import unittest

import numpy as np

from model.blc import apply_blc
from model.isp_model import run_pipeline


class BlcTests(unittest.TestCase):
    def test_zero_offset_identity(self):
        pixels = np.array([[0, 1, 64], [1024, 2048, 4095]], dtype=np.uint16)
        np.testing.assert_array_equal(apply_blc(pixels, 0), pixels)

    def test_hand_calculated_thresholds(self):
        # 期望值不由模型本身生成，独立覆盖低于/等于阈值的钳位行为。
        for offset, pixels, expected in (
                (64, [0, 63, 64, 65, 4095], [0, 0, 0, 1, 4031]),
                (1024, [0, 1023, 1024, 1025, 4095], [0, 0, 0, 1, 3071]),
                (4095, [0, 4094, 4095], [0, 0, 0])):
            np.testing.assert_array_equal(apply_blc(pixels, offset), expected)

    def test_scalar_and_numpy_integer_configuration(self):
        self.assertEqual(apply_blc(4095, np.int64(64)), 4031)
        self.assertEqual(apply_blc(64, 64), 0)
        self.assertIsInstance(apply_blc(65, 64), int)

    def test_array_shape_type_and_input_preservation(self):
        pixels = np.array([[0, 63, 64], [65, 1024, 4095]], dtype=np.uint16)
        before = pixels.copy()
        result = apply_blc(pixels, 64)
        np.testing.assert_array_equal(result, [[0, 0, 0], [1, 960, 4031]])
        self.assertEqual(result.shape, pixels.shape)
        self.assertEqual(result.dtype, np.dtype("uint16"))
        np.testing.assert_array_equal(pixels, before)

    def test_invalid_offset_rejected(self):
        for offset in (-1, 4096, 1.5, True, np.bool_(True)):
            with self.assertRaises(ValueError):
                apply_blc(64, offset)

    def test_invalid_pixels_rejected(self):
        for pixels in (-1, 4096, [0.5, 64.0], [True, False]):
            with self.assertRaises(ValueError):
                apply_blc(pixels, 64)

    def test_pipeline_enabled(self):
        result = run_pipeline(np.array([[1024, 4095]], dtype=np.uint16),
                              {"pipeline": {"blc": True}, "blc": {"offset": 64}})
        np.testing.assert_array_equal(result, [[960, 4031]])

    def test_pipeline_disabled_and_default(self):
        pixels = np.array([[64]], dtype=np.uint16)
        for cfg in ({}, {"pipeline": {"blc": False}, "blc": {"offset": -1}}):
            self.assertIs(run_pipeline(pixels, cfg), pixels)
        np.testing.assert_array_equal(run_pipeline(pixels, {"pipeline": {"blc": True}}), pixels)


if __name__ == "__main__":
    unittest.main()
