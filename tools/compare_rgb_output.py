#!/usr/bin/env python3
"""严格 RGB36 比较：0=匹配，1=数值/数量错误，2=参数/文件/格式错误。"""

import argparse
import re
import sys
from pathlib import Path


def read_rgb(path):
    """每行必须恰好九个 hex 字符；拒绝空行、空文件、空白及 X/Z。"""
    lines = Path(path).read_text(encoding='ascii').splitlines()
    if not lines:
        raise ValueError('{}: empty RGB file'.format(path))
    result = []
    for number, line in enumerate(lines, 1):
        if re.fullmatch(r'[0-9a-fA-F]{9}', line) is None:
            raise ValueError('{}: line {} requires exactly nine hex digits'.format(path, number))
        word = int(line, 16)
        # 固定 12 位分段，确保不会把 SRAM 高四位或通道排列混入 RGB。
        result.append((word >> 24, (word >> 12) & 4095, word & 4095))
    return result


def main():
    # 宽高是正式文件契约的一部分；不能只检查 expected/actual 相互等长。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected', required=True)
    parser.add_argument('--actual', required=True)
    parser.add_argument('--width', required=True, type=int)
    parser.add_argument('--height', required=True, type=int)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0:
        parser.error('width and height must be positive')
    try:
        expected, actual = read_rgb(args.expected), read_rgb(args.actual)
    except (OSError, UnicodeError, ValueError) as error:
        print('[FAIL] RGB comparison: {}'.format(error), file=sys.stderr)
        return 2
    for index, (wanted, received) in enumerate(zip(expected, actual)):
        if wanted != received:
            channels = ','.join(name for name, a, b in zip('RGB', wanted, received) if a != b)
            print('[FAIL] RGB comparison: index={} x={} y={} channels={} expected RGB={} actual RGB={}'.format(
                index, index % args.width, index // args.width, channels, wanted, received), file=sys.stderr)
            return 1
    total = args.width * args.height
    if len(expected) != total or len(actual) != total:
        index = min(len(expected), len(actual), total)
        print('[FAIL] RGB comparison: index={} x={} y={} count required={} expected={} actual={}'.format(
            index, index % args.width, index // args.width, total, len(expected), len(actual)), file=sys.stderr)
        return 1
    print('[PASS] RGB comparison: pixels={}'.format(total))
    return 0


if __name__ == '__main__':
    sys.exit(main())
