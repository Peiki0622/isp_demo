"""RGB12 3×3 CCM：signed16 系数、12 小数位，完全整数的帧级黄金模型。"""

from numbers import Integral
import numpy as np

IDENTITY_MATRIX = ((4096, 0, 0), (0, 4096, 0), (0, 0, 4096))


def apply_ccm(rgb_3d, matrix_codes):
    """返回新的 uint16 (H,W,3)，不修改输入像素或矩阵。

    RGB 输入必须非空且为整数 0..4095；独立 CCM 允许 1×1，正式链路的
    Demosaic 另行要求宽高至少 2。矩阵行选择输出通道、列选择输入通道。
    系数必须逐元素为非 bool 的整数 -32768..32767，4096 表示 +1.0。
    本模型只计算帧数值；配置采样、valid hole 和两级流水由 RTL 平台检查。
    """
    rgb = np.asarray(rgb_3d)
    if rgb.ndim != 3 or rgb.shape[2] != 3 or rgb.size == 0:
        raise ValueError('rgb must be a nonempty HxWx3 array')
    if rgb.dtype.kind not in 'iu' or np.any(rgb < 0) or np.any(rgb > 4095):
        raise ValueError('rgb channels must be integers in 0..4095')

    # 用 object 保留九个原始元素的类型：普通列表中的 bool/float 不能先被
    # NumPy 隐式提升为整数或浮点矩阵，再丢失配置错误的原始证据。
    matrix = np.asarray(matrix_codes, dtype=object)
    if matrix.shape != (3, 3):
        raise ValueError('matrix must have shape 3x3')
    for value in matrix.flat:
        if isinstance(value, (bool, np.bool_)) or not isinstance(value, Integral):
            raise ValueError('matrix codes must be integers, excluding bool/float')
        if not -32768 <= value <= 32767:
            raise ValueError('matrix codes must be in -32768..32767')

    # 转置只服务于行向量乘法：结果[...,i] = sum(rgb[...,j]*matrix[i,j])。
    # 两侧先提升至 int64，避免 uint16 与 signed 系数混乘、窄位累加回绕。
    accumulator = np.matmul(rgb.astype(np.int64), matrix.astype(np.int64).T)
    # A<=0 的语义为直接钳位零；正数商用固定半 LSB 偏置实现 half-up。
    # 宽位比较/钳位全部完成后才转回 uint16，超限结果不能截断回绕。
    positive = np.maximum(accumulator, 0)
    rounded = (positive + 2048) // 4096
    return np.minimum(rounded, 4095).astype(np.uint16)
