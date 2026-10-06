#!/usr/bin/env python3
"""生成可重复的 RGGB RAW12 基准：二维 NPY、光栅顺序 MEM 和 JSON 元数据。"""

import argparse
import json
from pathlib import Path
import numpy as np


def main() -> None:
    # 命令行接口：width/height 是像素尺寸，output 是本任务向量输出目录。
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="testdata/synthetic")
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    # 默认 RAW 模式保持历史四图案及全部字节内容；RGB 是 P4 显式入口。
    parser.add_argument("--domain", choices=("raw", "rgb"), default="raw")
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0:
        parser.error("width and height must be positive")
    if args.domain == "rgb" and min(args.width, args.height) < 2:
        parser.error("RGB patterns require width/height >=2")

    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    w, h = args.width, args.height

    gradient = np.tile(np.linspace(0, 4095, w, dtype=np.uint16), (h, 1))
    checker = (((np.indices((h, w)).sum(axis=0) // 2) & 1) * 4095).astype(np.uint16)
    flat = np.full((h, w), 1024, dtype=np.uint16)
    # 在较宽整数类型中生成地址再取模，避免 uint16 地址先溢出；随后存为 RAW12。
    addr_ramp = (np.arange(w * h, dtype=np.uint64) % 4096).astype(np.uint16).reshape(h, w)

    arrays = {"gradient": gradient, "checker": checker, "flat": flat,
              "addr_ramp": addr_ramp}
    if args.domain == "rgb":
        # 脚本从 tools/ 直接启动；只在显式 RGB 模式导入新工具。
        from rgb_to_bayer import make_rgb_patterns, rgb_to_bayer
        colors = make_rgb_patterns(w, h)
        arrays = {name: rgb_to_bayer(rgb) for name, rgb in colors.items()}
        for name, rgb in colors.items():
            np.save(out / f"{name}_{w}x{h}_rgb.npy", rgb)
    for name, arr in arrays.items():
        # NPY 保留二维黄金数组，MEM 逐行保存一个 16 位容器；行优先展开对应 SRAM 地址。
        np.save(out / f"{name}_{w}x{h}.npy", arr)
        with (out / f"{name}_{w}x{h}.mem").open("w", encoding="ascii") as f:
            for value in arr.ravel():
                f.write(f"{int(value):04x}\n")
        # 元数据不含时间戳或机器路径，保证重复生成时文件字节完全相同。
        metadata = {"width": w, "height": h, "raw_bits": 12, "bayer": "RGGB",
                    "pattern": name, "pixel_count": w * h}
        if args.domain == "rgb":
            metadata.update(domain="rgb", rgb_bits=12)
        (out / f"{name}_{w}x{h}.json").write_text(
            json.dumps(metadata, sort_keys=True, indent=2) + "\n", encoding="ascii")
    print("[PASS] pattern generation: {}x{}, 4 patterns".format(w, h))


if __name__ == "__main__":
    main()
