"""精确 RAW12 RGGB -> RGB12 双线性参考，reflect 保持边界颜色相位。"""

import numpy as np


def apply_demosaic(raw_2d):
    """返回独立的 uint16 (H,W,3) RGB 数组；输入必须是至少 2x2 的 RAW12。

    此 API 计算整帧数值，不模拟寄存器或配置采样周期。镜像不重复边缘
    中心：越界 -1 使用 1，越界 length 使用 length-2。首先拓宽到 int32，
    再计算邻居平均，避免 uint16/RAW12 加法溢出；不改变调用方数组。
    """
    raw = np.asarray(raw_2d)
    if raw.ndim != 2 or min(raw.shape) < 2:
        raise ValueError("raw must be a two-dimensional RGGB array with width/height >=2")
    if raw.dtype.kind not in "iu" or np.any(raw < 0) or np.any(raw > 4095):
        raise ValueError("raw pixels must be integers in 0..4095")

    # 一个像素的 reflect halo 足够描述全部 3x3 边界；四角同时镜像两轴。
    # 九个切片均保持原始 HxW 尺寸，p11 始终与输出中心坐标一一对应。
    h, w = raw.shape
    halo = np.pad(raw.astype(np.int32), 1, mode="reflect")
    p00, p01, p02 = (halo[0:h, x:x+w] for x in range(3))
    p10, p11, p12 = (halo[1:h+1, x:x+w] for x in range(3))
    p20, p21, p22 = (halo[2:h+2, x:x+w] for x in range(3))
    cross = (p01 + p10 + p12 + p21 + 2) // 4
    diagonal = (p00 + p02 + p20 + p22 + 2) // 4
    horizontal = (p10 + p12 + 1) // 2
    vertical = (p01 + p21 + 1) // 2

    # RGB 最后一轴的顺序固定 R/G/B。奇偶切片自然支持奇数宽高；相位
    # 只由中心坐标确定，不能借用输入流的当前像素坐标或邻居的颜色。
    result = np.empty((h, w, 3), dtype=np.uint16)
    for y, x, channels in (
            (0, 0, (p11, cross, diagonal)),
            (0, 1, (horizontal, p11, vertical)),
            (1, 0, (vertical, p11, horizontal)),
            (1, 1, (diagonal, cross, p11))):
        for channel, values in enumerate(channels):
            result[y::2, x::2, channel] = values[y::2, x::2]
    return result
