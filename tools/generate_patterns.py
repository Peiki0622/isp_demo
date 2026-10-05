#!/usr/bin/env python3
"""Generate small deterministic patterns for RTL debugging."""

import argparse
from pathlib import Path
import numpy as np


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default="testdata/synthetic")
    parser.add_argument("--width", type=int, default=16)
    parser.add_argument("--height", type=int, default=16)
    args = parser.parse_args()

    out = Path(args.output)
    out.mkdir(parents=True, exist_ok=True)
    w, h = args.width, args.height

    gradient = np.tile(np.linspace(0, 4095, w, dtype=np.uint16), (h, 1))
    checker = (((np.indices((h, w)).sum(axis=0) // 2) & 1) * 4095).astype(np.uint16)
    flat = np.full((h, w), 1024, dtype=np.uint16)

    for name, arr in {"gradient": gradient, "checker": checker, "flat": flat}.items():
        np.save(out / f"{name}_{w}x{h}.npy", arr)
        with (out / f"{name}_{w}x{h}.mem").open("w", encoding="ascii") as f:
            for value in arr.ravel():
                f.write(f"{int(value):04x}\n")


if __name__ == "__main__":
    main()
