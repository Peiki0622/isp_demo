# P5 CCM PNG 预览

完成 `make test-p5-ccm` 的数值验收后，可复用已有导出工具查看实际 RTL
的 CCM 输出。Pillow 仅为这个可选预览工具的依赖，正式验收不读取 PNG。

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/export_demosaic_png.py --stage p5 --matrix-pair identity_swap
PYTHONDONTWRITEBYTECODE=1 python3 tools/export_demosaic_png.py --stage p5 --matrix-pair signed_clip
```

无参数执行仍导出 P4 Demosaic 结果，原命令与图片内容保持兼容。

## 数据来源与显示规则

读取 `testdata/output/p5_ccm/integration/<pair>/<pattern>/frame_<n>.mem`
中的实际 RTL 输出，先与同组独立黄金逐像素比较，再生成图片。任一帧错误
均停止导出，工具不在显示时重算 CCM，也不以黄金文件代替实际输出。

每张总览四列依次为 `constant_rgb`、`rgb_gradient`、`color_blocks` 和
`edge_pattern`，上排 frame 0、下排 frame 1。图像为 16×16，放大版为
256×256 最近邻复制。每通道使用 `(RGB12*255+2047)//4095` 固定线性映射，
无逐图亮度拉伸、自动曝光或伽马校正。原始 12 位精度仍保留在 RGB36 文件。

两组图像的上游配置相同：frame 0 黑电平 64，R/G/B 增益编码为
6144/4096/8192；frame 1 黑电平 128，增益编码为 4096/5120/2048。

## 矩阵组

`identity_swap`：frame 0 使用单位矩阵 A，结果应与同配置 P4 一致；
frame 1 使用 R/B 交换矩阵 B，可观察红蓝互换，绿色保持原值。

`signed_clip`：frame 0 使用 signed correction 矩阵 C，包含大于一及负系数；
frame 1 使用 clipping stress 矩阵 D，包含明确的负值下限钳位和上限饱和。

```text
A = [4096,    0,    0;     0, 4096,    0;     0,    0, 4096]
B = [   0,    0, 4096;     0, 4096,    0;  4096,    0,    0]
C = [5120, -512, -512;  -256, 4608, -256;  -512, -512, 5120]
D = [8192,    0,    0;     0,-4096, 8192; -4096,    0, 8192]
```

编码均为 signed16、12 小数位，4096 表示 +1。矩阵行选择输出通道，
列选择输入通道；负累加输出零，正累加 half-up 舍入后饱和到 4095。

## 产物和检查

每组图片集中保存在 `testdata/output/p5_ccm/png/<pair>/`：八份原尺寸 PNG、
八份放大版、一份 `rtl_rgb_overview.png` 及 `manifest.json`。清单记录实际
源文件、宽高、映射、矩阵组和两帧矩阵编码。工具保存后回读八份原尺寸 PNG，
确认 RGB 格式、尺寸和全部量化像素一致。

PNG 和清单是可重建产物，由 `.gitignore` 忽略并随 P5 输出清理。精确数值、
坐标、帧标志、延迟和 busy 的验收仍由模型、单元与集成平台完成。
