"""从二维 SRAM RAW12 NPY 经 BLC -> AWB -> Demosaic 生成一帧全链 RGB36 黄金 MEM。"""

import argparse
from pathlib import Path

import numpy as np

from model.isp_model import run_pipeline


def main():
    # 文件/配置接口：所有增益必须是 UQ4.12 编码，每帧独立指定三路值。
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', required=True)
    parser.add_argument('--output', required=True)
    parser.add_argument('--black-level', type=int, required=True)
    parser.add_argument('--gain-r', type=int, required=True)
    parser.add_argument('--gain-g', type=int, required=True)
    parser.add_argument('--gain-b', type=int, required=True)
    args = parser.parse_args()
    output = Path(args.output)
    if Path(args.input).resolve() == output.resolve():
        parser.error('input and output must be distinct')
    try:
        output.parent.mkdir(parents=True, exist_ok=True)
        # 先删除当前指定的可重建目标；生成失败不能留下旧黄金供后续误比较。
        if output.exists():
            output.unlink()
        raw = np.load(args.input, allow_pickle=False)
        config = {'pipeline': {'blc': True, 'awb_gain': True, 'demosaic': True},
                  'blc': {'offset': args.black_level},
                  'awb_gain': {'r': args.gain_r, 'g': args.gain_g, 'b': args.gain_b}}
        result = run_pipeline(raw, config)
        # 模型要求至少 2x2 的二维 RGGB；按实际宽/高展开，不能拿大图黄金前缀代替小图。
        with output.open('w', encoding='ascii') as stream:
            for r, g, b in result.reshape(-1, 3):
                word = (int(r) << 24) | (int(g) << 12) | int(b)
                stream.write('{:09x}\n'.format(word))
    except (OSError, ValueError) as error:
        # 删除失败的部分文件；生成失败不能留下旧/部分黄金供后续误用。
        if output.exists():
            output.unlink()
        parser.exit(2, '[FAIL] Demosaic golden generation: {}\n'.format(error))
    print('[PASS] Demosaic golden pixels={}'.format(result.shape[0]*result.shape[1]))


if __name__ == '__main__':
    main()
