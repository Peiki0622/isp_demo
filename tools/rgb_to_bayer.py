#!/usr/bin/env python3
"""RGB12 数组到 RGGB RAW12；确定性合成颜色图案不依赖图片解码库。"""

import numpy as np


def rgb_to_bayer(rgb12):
    """按中心坐标选取 R/G/G/B，返回新的 uint16 (H,W) Bayer 数组。

    接受非空 HxWx3 整数 RGB12；不截断非法通道，也不改变调用方数组。
    转换工具可处理单行/列，Demosaic 的 >=2 约束由该算法单独检查。
    """
    rgb = np.asarray(rgb12)
    if rgb.ndim != 3 or rgb.shape[2] != 3 or rgb.shape[0] == 0 or rgb.shape[1] == 0:
        raise ValueError("rgb must be a nonempty HxWx3 array")
    if rgb.dtype.kind not in "iu" or np.any(rgb < 0) or np.any(rgb > 4095):
        raise ValueError("rgb channels must be integers in 0..4095")
    raw = np.empty(rgb.shape[:2], dtype=np.uint16)
    for y, x, channel in ((0, 0, 0), (0, 1, 1), (1, 0, 1), (1, 1, 2)):
        raw[y::2, x::2] = rgb[y::2, x::2, channel]
    return raw


def make_rgb_patterns(width, height):
    """返回四类确定性 RGB12 图案；梯度使用整数除法，元数据无时间戳。

    常量场验证精确颜色恢复；三轴梯度覆盖变化与舍入；四色块包含三原色
    和白色；三个通道分别具有竖、横、斜阶跃，暴露方向或相位译码错误。
    """
    if width < 2 or height < 2:
        raise ValueError("RGB patterns require width/height >=2")
    y, x = np.indices((height, width), dtype=np.int64)
    constant = np.empty((height, width, 3), dtype=np.uint16)
    constant[:] = (512, 1024, 2048)
    gradient = np.stack((x*4095//(width-1), y*4095//(height-1),
                         (x+y)*4095//(width+height-2)), axis=2).astype(np.uint16)
    palette = np.array(((4095, 0, 0), (0, 4095, 0),
                        (0, 0, 4095), (4095, 4095, 4095)), dtype=np.uint16)
    blocks = palette[(y >= height//2).astype(int)*2 + (x >= width//2).astype(int)]
    edges = np.stack((x >= width//2, y >= height//2, x*height >= y*width),
                     axis=2).astype(np.uint16)*4095
    return {'constant_rgb': constant, 'rgb_gradient': gradient,
            'color_blocks': blocks, 'edge_pattern': edges}
