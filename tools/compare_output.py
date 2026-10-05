#!/usr/bin/env python3
"""精确比较 RAW12 MEM 文件；成功为 0，像素/数量不匹配为 1，输入错误为 2。"""

import argparse
import re
import sys
from pathlib import Path


def read_pixels(path):
    """文件接口：每行一个四位十六进制字，拒绝空文件、X/Z 与高四位非零。"""
    lines = Path(path).read_text(encoding="ascii").splitlines()
    if not lines:
        raise ValueError("{}: empty pixel file".format(path))
    pixels = []
    for line_number, line in enumerate(lines, 1):
        word = line.strip()
        if re.fullmatch(r"[0-9a-fA-F]{4}", word) is None:
            raise ValueError("{}: line {} requires one four-digit hex word".format(path, line_number))
        value = int(word, 16)
        if value > 4095:
            raise ValueError("{}: line {} exceeds RAW12 range: 0x{:04x}".format(path, line_number, value))
        pixels.append(value)
    return pixels


def position(index, width):
    """可选宽度只用于诊断坐标，不改变按文件顺序精确比较的行为。"""
    result = "index={}".format(index)
    if width is not None:
        result += " (x={}, y={})".format(index % width, index // width)
    return result


def main():
    # 对外 CLI：expected 与 actual 为必需路径，width 可选且必须为正。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True)
    parser.add_argument("--actual", required=True)
    parser.add_argument("--width", type=int)
    args = parser.parse_args()
    if args.width is not None and args.width <= 0:
        parser.error("width must be positive")
    try:
        expected = read_pixels(args.expected)
        actual = read_pixels(args.actual)
    except (OSError, UnicodeError, ValueError) as error:
        print("[FAIL] exact pixel comparison: {}".format(error), file=sys.stderr)
        return 2

    # 先检查公共前缀，保证同时存在内容与长度错误时仍报告最早的内容差异。
    for index, (wanted, received) in enumerate(zip(expected, actual)):
        if wanted != received:
            print("[FAIL] exact pixel comparison: {} expected=0x{:04x} actual=0x{:04x}; counts={}/{}".format(
                position(index, args.width), wanted, received, len(expected), len(actual)), file=sys.stderr)
            return 1
    if len(expected) != len(actual):
        index = min(len(expected), len(actual))
        wanted = "missing" if index >= len(expected) else "0x{:04x}".format(expected[index])
        received = "missing" if index >= len(actual) else "0x{:04x}".format(actual[index])
        print("[FAIL] exact pixel comparison: count expected={} actual={}; {} expected={} actual={}".format(
            len(expected), len(actual), position(index, args.width), wanted, received), file=sys.stderr)
        return 1
    print("[PASS] exact pixel comparison: pixels={}".format(len(expected)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
