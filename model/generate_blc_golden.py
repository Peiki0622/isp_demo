"""将已生成的二维 RAW12 NPY 经 BLC 模型转换为独立帧黄金 MEM。"""

import argparse
from pathlib import Path

import numpy as np

from model.blc import apply_blc


def main():
    # 文件接口：输入是整数二维数组，输出沿用每行四位十六进制的 MEM。
    # 一个调用只生成一帧，调用方必须为不同帧提供各自采样的黑电平。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--black-level", type=int, required=True)
    args = parser.parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    # 在计算前移除指定的可重建目标；失败时不能留下旧黄金文件供误比较。
    if output.exists():
        output.unlink()
    try:
        raw = np.load(args.input, allow_pickle=False)
        if raw.ndim != 2:
            raise ValueError("golden input must be a two-dimensional array")
        corrected = apply_blc(raw, args.black_level)
        with output.open("w", encoding="ascii") as stream:
            for pixel in corrected.ravel():
                stream.write("{:04x}\n".format(int(pixel)))
    except (OSError, ValueError) as error:
        parser.exit(2, "[FAIL] BLC golden generation: {}\n".format(error))
    print("[PASS] BLC golden pixels={} black_level={}".format(corrected.size, args.black_level))


if __name__ == "__main__":
    main()
