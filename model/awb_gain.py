"""RGGB AWB 增益参考：固定 RAW12/UQ4.12，全程精确整数运算。"""

from numbers import Integral

import numpy as np


def _integer(value, maximum, name):
    """拒绝 bool/float 和越界配置；将 NumPy 整数拓宽为 Python int。"""
    if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
        raise ValueError("{} must be an integer in 0..{}".format(name, maximum))
    if not 0 <= value <= maximum:
        raise ValueError("{} must be in 0..{}".format(name, maximum))
    return int(value)


def scale_pixel(pixel, gain_code):
    """缩放单个像素，返回 Python int；4096 表示 1 倍，正中点向上取整。"""
    pixel = _integer(pixel, 4095, "pixel")
    gain_code = _integer(gain_code, 65535, "gain_code")
    return min((pixel * gain_code + 2048) // 4096, 4095)


def apply_awb_gain(raw_2d, gain_r, gain_g, gain_b):
    """按坐标选择 RGGB 增益，返回新建、同形状的 uint16 RAW12 数组。

    三个参数是一帧已采样的 UQ4.12 编码；两个绿色位置共用 gain_g。
    帧首采样和流水周期由 RTL 测试验证，此 API 只计算完整二维帧。
    输入必须非空、二维、整数且在 RAW12 范围内，调用方数组不会改变。
    """
    gains = [_integer(code, 65535, name) for code, name in
             ((gain_r, "gain_r"), (gain_g, "gain_g"), (gain_b, "gain_b"))]
    raw = np.asarray(raw_2d)
    if raw.ndim != 2 or raw.size == 0:
        raise ValueError("raw must be a nonempty two-dimensional RGGB array")
    if raw.dtype.kind not in "iu" or np.any(raw < 0) or np.any(raw > 4095):
        raise ValueError("raw pixels must be integers in 0..4095")

    # 先拓宽后乘，不能用 uint16 中间数组；最大乘积约 2.68e8。
    # 分别处理四个奇偶切片，奇数宽/高也自然保持实际坐标相位。
    widened = raw.astype(np.int64)
    result = np.empty(raw.shape, dtype=np.uint16)
    for y, x, code in ((0, 0, gains[0]), (0, 1, gains[1]),
                       (1, 0, gains[1]), (1, 1, gains[2])):
        scaled = (widened[y::2, x::2] * code + 2048) // 4096
        result[y::2, x::2] = np.minimum(scaled, 4095).astype(np.uint16)
    return result
