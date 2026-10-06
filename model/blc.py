"""RAW12 全局黑电平参考：使用整数计算，与一级 RTL 的数值路径一致。"""

from numbers import Integral

import numpy as np


def apply_blc(raw, black_level):
    """校正单个整数或整数数组；标量返回 int，数组返回同形状 uint16。

    black_level 是一帧已采样的配置，必须为 0..4095 的整数。此函数只
    模拟像素数值；帧首采样和流水周期由 RTL 单元/集成测试验证。
    不修改调用方数组，不接受浮点近似或超出 RAW12 范围的像素。
    """
    if isinstance(black_level, (bool, np.bool_)) or not isinstance(black_level, Integral):
        raise ValueError("black_level must be an integer in 0..4095")
    if not 0 <= black_level <= 4095:
        raise ValueError("black_level must be in 0..4095")

    values = np.asarray(raw)
    if values.dtype.kind not in "iu" or np.any(values < 0) or np.any(values > 4095):
        raise ValueError("raw pixels must be integers in 0..4095")

    # 必须先拓宽为有符号类型：uint16 直接相减会在低于阈值时回绕，
    # 回绕后再 maximum(..., 0) 无法恢复正确结果。RAW12 用 int32 足够。
    corrected = np.maximum(values.astype(np.int32) - int(black_level), 0)
    if values.ndim == 0:
        return int(corrected)
    return corrected.astype(np.uint16)
