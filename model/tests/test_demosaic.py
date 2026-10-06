"""Demosaic 数值验收：手算、独立坐标 oracle、边界及 API 兼容。"""

import unittest
import numpy as np
from model.demosaic import apply_demosaic
from model.isp_model import run_pipeline


def oracle(raw):
    """逐中心收集目标颜色邻居，用 divmod 舍入，独立于 NumPy halo 实现。"""
    h, w = raw.shape
    result = np.empty((h, w, 3), dtype=np.uint16)
    def reflect(c, length):
        return 1 if c < 0 else length-2 if c >= length else c
    def average(values):
        q, r = divmod(sum(values), len(values))
        return q + int(2*r >= len(values))
    for y in range(h):
        for x in range(w):
            phase = ((0, 1), (1, 2))[y % 2][x % 2]
            for color in range(3):
                if color == phase:
                    value = int(raw[y, x])
                else:
                    offsets = []
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            if dx == dy == 0:
                                continue
                            ry, rx = reflect(y+dy, h), reflect(x+dx, w)
                            neighbor = ((0, 1), (1, 2))[ry % 2][rx % 2]
                            if neighbor == color:
                                offsets.append((abs(dx)+abs(dy), ry, rx))
                    nearest = min(item[0] for item in offsets)
                    value = average([int(raw[ry, rx]) for distance, ry, rx in offsets
                                     if distance == nearest])
                result[y, x, color] = value
    return result


class DemosaicTests(unittest.TestCase):
    def test_hand_four_phases_and_four_corners(self):
        raw = np.array([[100, 30], [50, 200]], dtype=np.uint16)
        np.testing.assert_array_equal(apply_demosaic(raw),
            [[[100, 40, 200], [100, 30, 200]],
             [[100, 50, 200], [100, 40, 200]]])

    def test_required_shapes_and_independent_oracle(self):
        rng = np.random.RandomState(4)
        for w, h in ((2, 2), (3, 2), (2, 3), (3, 5), (4, 4), (7, 6), (6, 7)):
            raw = rng.randint(0, 4096, (h, w)).astype(np.uint16)
            saved = raw.copy()
            got = apply_demosaic(raw)
            np.testing.assert_array_equal(got, oracle(raw))
            np.testing.assert_array_equal(raw, saved)
            self.assertEqual(got.dtype, np.uint16)
            self.assertEqual(got.shape, (h, w, 3))
            self.assertFalse(np.shares_memory(raw, got))

    def test_constant_color_exact_recovery(self):
        for w, h in ((2, 2), (3, 2), (2, 3), (3, 5), (4, 4)):
            for rgb in ((0, 0, 0), (4095, 4095, 4095), (17, 2001, 4095)):
                raw = np.empty((h, w), dtype=np.uint16)
                for y, x, value in ((0, 0, rgb[0]), (0, 1, rgb[1]),
                                    (1, 0, rgb[1]), (1, 1, rgb[2])):
                    raw[y::2, x::2] = value
                np.testing.assert_array_equal(apply_demosaic(raw),
                    np.broadcast_to(np.array(rgb, dtype=np.uint16), (h, w, 3)))

    def test_rounding_midpoints_and_full_scale(self):
        # R 中心的四个 G: 总和 1/2/3，捕获四分之一向下、半值向上。
        for total, wanted in ((1, 0), (2, 1), (3, 1), (16380, 4095)):
            raw = np.zeros((5, 5), dtype=np.uint16)
            values = [total//4 + int(i < total%4) for i in range(4)]
            for (y, x), value in zip(((1, 2), (2, 1), (2, 3), (3, 2)), values):
                raw[y, x] = value
            self.assertEqual(int(apply_demosaic(raw)[2, 2, 1]), wanted)
        raw = np.zeros((4, 4), dtype=np.uint16)
        raw[0, 0] = 1
        self.assertEqual(int(apply_demosaic(raw)[0, 1, 0]), 1)

    def test_illegal_inputs(self):
        for raw in (0, [1, 2], [[[1]]], np.empty((0, 2)), np.zeros((1, 2)),
                    np.zeros((2, 1)), [[-1, 0], [0, 0]], [[4096, 0], [0, 0]],
                    np.ones((2, 2), dtype=float), np.ones((2, 2), dtype=bool)):
            with self.assertRaises(ValueError):
                apply_demosaic(raw)

    def test_pipeline_order_and_raw_compatibility(self):
        raw = np.full((2, 2), 100, dtype=np.uint16)
        cfg = {'pipeline': {'blc': True, 'awb_gain': True, 'demosaic': True},
               'blc': {'offset': 64}, 'awb_gain': {'r': 8192, 'g': 2048, 'b': 6144}}
        np.testing.assert_array_equal(run_pipeline(raw, cfg),
            np.broadcast_to(np.array([72, 18, 54]), (2, 2, 3)))
        cfg['pipeline']['demosaic'] = False
        np.testing.assert_array_equal(run_pipeline(raw, cfg), [[72, 18], [18, 54]])
        self.assertIs(run_pipeline(raw, {}), raw)


if __name__ == '__main__':
    unittest.main()
