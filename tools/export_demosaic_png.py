#!/usr/bin/env python3
"""导出 P4 四图案两帧的实际 RTL 输出；Pillow 仅为 PNG 预览可选依赖。"""

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont


# 本脚本位于 tools，根目录始终由脚本位置确定，
# 不依赖运行时的当前工作目录；复用现有严格 RGB36 解析器，避免通道重排。
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.compare_rgb_output import read_rgb

OUTPUT_ROOT = ROOT / 'testdata/output/p4_demosaic'
PNG_ROOT = OUTPUT_ROOT / 'png'
PATTERNS = ('constant_rgb', 'rgb_gradient', 'color_blocks', 'edge_pattern')
PARAMETERS = (
    'Frame 0: BLC=64, gains R/G/B=1.50/1.00/2.00',
    'Frame 1: BLC=128, gains R/G/B=1.00/1.25/0.50',
)


def main():
    """先检查八份真实输出，再保存原尺寸、放大版和一张总览图。"""
    # 所有读取和数值一致性检查在写入图片之前完成。尺寸来自对应输入元数据；
    # PNG 展示的像素必须逐个等于已验收黄金值，绝不拿黄金文件代替实际输出。
    frames = []
    for frame in range(2):
        for pattern in PATTERNS:
            metadata_path = OUTPUT_ROOT / 'inputs/16x16/{}_16x16.json'.format(pattern)
            metadata = json.loads(metadata_path.read_text())
            width, height = metadata['width'], metadata['height']
            actual_path = OUTPUT_ROOT / 'integration' / pattern / 'frame_{}.mem'.format(frame)
            golden_path = OUTPUT_ROOT / 'golden' / pattern / 'frame_{}.mem'.format(frame)
            actual, golden = read_rgb(actual_path), read_rgb(golden_path)
            if len(actual) != width * height or actual != golden:
                raise ValueError('Actual RTL output failed golden comparison: {}'.format(actual_path))

            # 使用同一个固定映射 round(RGB12 * 255 / 4095)，不逐图归一化、不做
            # 自动曝光或伽马校正。运算先提升到 uint32，避免乘法溢出；原始 12 位
            # 数据继续保存在 .mem 中，PNG8 仅用于显示这一数值结果。
            rgb12 = np.asarray(actual, dtype=np.uint32).reshape(height, width, 3)
            rgb8 = ((rgb12 * 255 + 2047) // 4095).astype(np.uint8)
            frames.append((frame, pattern, actual_path, Image.fromarray(rgb8, mode='RGB')))

    PNG_ROOT.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default()
    tile = 256
    margin, gap = 20, 20
    row_height = 310
    sheet = Image.new('RGB', (margin * 2 + tile * 4 + gap * 3,
                              70 + row_height * 2 + margin), (24, 27, 33))
    drawing = ImageDraw.Draw(sheet)
    drawing.text((margin, 16), 'P4 ISP: actual RTL output / 16x16 pixels / nearest-neighbor x16',
                 fill=(240, 240, 240), font=font)
    drawing.text((margin, 34), 'RAW -> BLC -> AWB -> bilinear demosaic / RGB12 -> PNG8 linear',
                 fill=(190, 195, 205), font=font)
    records = []
    for frame in range(2):
        drawing.text((margin, 70 + frame * row_height), PARAMETERS[frame],
                     fill=(240, 240, 240), font=font)
    for frame, pattern, actual_path, native in frames:
        filename = '{}_frame_{}.png'.format(pattern, frame)
        native.save(str(PNG_ROOT / filename))

        # 最近邻只复制每个原始像素，不插入额外颜色；单图放大版和总览图采用
        # 相同像素，以便对边缘插值、色块过渡及两帧参数变化进行人工查看。
        preview = native.resize((tile, tile), resample=Image.NEAREST)
        preview_name = '{}_frame_{}_x16.png'.format(pattern, frame)
        preview.save(str(PNG_ROOT / preview_name))
        column = PATTERNS.index(pattern)
        x = margin + column * (tile + gap)
        y = 70 + frame * row_height + 20
        drawing.text((x, y), pattern, fill=(190, 195, 205), font=font)
        sheet.paste(preview, (x, y + 18))
        records.append({'source': str(actual_path.relative_to(ROOT)),
                        'native_png': filename, 'preview_png': preview_name,
                        'width': native.width, 'height': native.height,
                        'golden_match': True})

    sheet_path = PNG_ROOT / 'rtl_rgb_overview.png'
    sheet.save(str(sheet_path))
    manifest = {'mapping': '(RGB12 * 255 + 2047) // 4095',
                'gamma_correction': False, 'preview_resize': 'nearest-neighbor x16',
                'frames': records}
    (PNG_ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    # PNG 回读验证编码格式、尺寸及原尺寸 RGB8 像素，确认交付文件真实有效。
    for frame, pattern, _, native in frames:
        destination = PNG_ROOT / '{}_frame_{}.png'.format(pattern, frame)
        with Image.open(str(destination)) as decoded:
            if decoded.format != 'PNG' or decoded.mode != 'RGB' or decoded.size != native.size:
                raise ValueError('Invalid PNG metadata: {}'.format(destination))
            if not np.array_equal(np.asarray(decoded), np.asarray(native)):
                raise ValueError('PNG pixel round-trip failed: {}'.format(destination))
    print('PASS: 8 actual RTL frames match golden; 8 PNG pixel round-trips match.')
    print(sheet_path)


if __name__ == '__main__':
    main()
