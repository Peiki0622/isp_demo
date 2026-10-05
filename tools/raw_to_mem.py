#!/usr/bin/env python3
"""Convert unpacked little-endian uint16 Bayer RAW into one-hex-word-per-pixel MEM."""

import argparse
from pathlib import Path
import numpy as np


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--raw-bits", type=int, default=12)
    args = p.parse_args()

    data = np.fromfile(args.input, dtype="<u2")
    data &= (1 << args.raw_bits) - 1

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="ascii") as f:
        for value in data:
            f.write(f"{int(value):04x}\n")


if __name__ == "__main__":
    main()
