# isp_demo

基于 Cortex-M0 控制面的 ISP SoC 复现项目。当前阶段先不复现 SD 卡输入，改为从 SRAM（静态随机存取存储器）读取拜耳原始图像，完成可验证的流式 ISP（图像信号处理器）链路；待图像流水线稳定后，再接入 AHB（高级高性能总线）寄存器控制与 Cortex-M0。

## 当前进度与最短运行命令

已实现到 P4：确定性 RGB/Bayer 图案 → 一周期同步 SRAM → Reader →
BLC → AWB Gain → 3×3 Bilinear Demosaic → RGB12 三通道流。软件黄金
从原始 Bayer 输入依次执行 BLC→AWB→Demosaic，与每帧 RGB36 dump 精确比较。
AWB 施加外部三路增益，两个绿色位置共用 gain_g；自动统计和增益估计留待后续。
默认配置启用 BLC、AWB Gain 和 Demosaic。

从仓库根目录运行完整验收：

```sh
make test-p4-demosaic
```

入口先完整运行 P0/P1、P2、P3，再运行 P4 工具/模型/黄金 CLI、窗口、
Demosaic 单元和 RGB 全链。窗口检查 64 帧、22,004 个窗口的 198,036 个
样本，含宽度 4095/4096；RGB 单元独立检查 64 帧、2,566 个像素的三个
通道。顶层检查五种实际小尺寸、70 个完整控制帧及四类复位中止/恢复，
再比较四种 16×16 图案各两帧的 2,048 个 RGB 像素。每个有效坐标、
标志、固定周期、帧长度及 busy 都通过才打印 `P4 DEMOSAIC PASS`。
所有入口合计 50 项 Python 测试；VCS fatal 即使原生退出码为零也判失败。

P4 固定 RGGB，输入 RAW12，输出每通道 RGB12。采用 reflect：-1→1，
W/H→W/H−2，输出尺寸不变；三行轮转存储与当前像素前递保证边界正确。
双线性两项/四项平均采用 13/14 位中间和以及 half-up 舍入。
正式 RGB top 接受 W/H≥2、W≤MAX_WIDTH（默认 4096）且帧不超过 SRAM
容量。输入连续、无反压；首窗口至最后窗口及首 RGB 至最后 RGB 均无气泡。

设接受 start 为 C0、N=W×H：Reader-only `sram_raw_source` 保持 C2，
BLC-only `blc_pipeline` 保持 C3，AWB-only `awb_pipeline` 保持 C4。
正式 top 首 RGB 为 C(W+7)，末 RGB 为 C(N+W+6) 且 busy=1，随后一拍空闲。
尺寸在接受 start 时保存，BLC/AWB 配置分别在 C3/C4 有效帧首采样。
忙时 start、tail 脉冲及跨完成保持高电平都不会自动重启。

依赖容器已有 VCS W-2024.09、Python 3.6.6、NumPy 1.19.5、Make 和 Bash。
可通过 `VCS=/path/to/vcs PYTHON=/path/to/python3` 覆盖可执行路径。
模型接受普通配置字典，不增加 YAML、图片库或测试框架依赖。
本阶段验收编译与功能仿真，后续再进行综合和时序分析。

独立入口：`make test-p0-p1`、`make test-p2-blc`、`make test-p3-awb`、
`make test-demosaic-tools`、`make test-demosaic-model`、`make test-window-3x3`、
`make test-demosaic-unit`、`make test-demosaic-pipeline`。
`make compare-p4-demosaic` 只检查已有黄金和 dump，不重新生成文件。
RGB36 每像素一行 `RRRGGGBBB`，对应 `(R<<24)|(G<<12)|B`；比较同时检查
每行九位格式、实际 W×H 数量和首个错误的 index/x/y/通道/RGB。

失败传播复现：

```sh
WINDOW_CASE=forced_failure make test-window-3x3
DEMOSAIC_CASE=forced_failure make test-demosaic-unit
DEMOSAIC_CORRUPT_OUTPUT=R make test-p4-demosaic
make compare-p4-demosaic
DEMOSAIC_GOLDEN_INPUT=/absolute/missing.npy make test-demosaic-pipeline
```

损坏注入也支持 G/B，仅改变首图案 frame_0 的 actual index=42（x=10,y=2）。
生成失败删除旧/部分黄金并在编译前停止。取消注入，运行
`make test-demosaic-pipeline` 恢复，然后运行比较入口。

新 RTL 端口按功能分组注释，寄存器按配置、行角色、计数、数据、坐标、
有效位和标志分块；窗口采用三段式 FSM，可综合 RTL 不使用 function。
P4 编译/日志集中于 `build/p4_demosaic/`，输入/黄金/dump 集中于
`testdata/output/p4_demosaic/{inputs,golden,integration}/`。持久证据在
`reports/p4_demosaic_execution/`；`make clean` 仅清理规定的 P0–P4
可重建产物，保留 reports 和其他运行目录。两轮完整验收及 282 份确定性文件哈希一致的
证据均已保存。详细执行记录见 `plans/004_p4_demosaic_bilinear.md`，周期和数值说明见 docs。

## 查看处理后的 PNG

P4 验收生成四种 16×16 合成图案各两帧的实际 RTL RGB 输出。
运行可选 PNG 导出工具即可查看结果：

```sh
make test-p4-demosaic
PYTHONDONTWRITEBYTECODE=1 python3 tools/export_demosaic_png.py
```

已有验收数据时只需执行第二行。PNG 导出使用 Pillow；当前环境验证版本为
6.2.2。Pillow 仅用于这个人工预览工具，正式模型和数值验收依赖保持不变。
工具先逐像素核对全部八份实际 dump 与独立黄金，再导出 PNG 并回读核对像素。
完整参数、图案含义、数值映射和输出文件说明见
[P4 PNG 预览说明](docs/p4_png_preview.md)。

总览图为 `testdata/output/p4_demosaic/png/rtl_rgb_overview.png`，同目录保存
八份原尺寸 PNG、八份放大版及 `manifest.json`。生成图片随 P4 产物清理，
不提交版本库；导出工具和复现说明纳入版本管理。

## 后续完整 ISP 目标

第一版端到端链路：

```text
SRAM
  -> BLC 黑电平校正
  -> AWB Gain 白平衡增益
  -> Demosaic 去马赛克
  -> CCM 颜色校正矩阵
  -> RGB to YCbCr 颜色空间转换
  -> Output
```

以下模块先保留接口并默认旁路，后续逐步补齐：

- Raw NR：拜耳原始域降噪
- Chroma NR：色度降噪
- Hue：色调调节
- LCC：局部对比度校正
- EE：边缘增强

## 输入数据约定

首版统一采用：

- Bayer pattern（拜耳排列）：RGGB
- 有效像素位宽：12 bit
- SRAM 存储字宽：16 bit
- 每个 SRAM 地址保存 1 个像素
- 高 4 bit 置 0
- 像素按 raster scan（光栅扫描）顺序存放

仿真时使用 `.mem` 十六进制文本文件加载 SRAM 模型，避免在第一阶段引入真实 RAW12 打包格式带来的额外复杂度。

## 目录

- `rtl/`：可综合 RTL（寄存器传输级）硬件
- `tb/`：模块级与端到端仿真
- `model/`：Python 软件黄金参考模型
- `tools/`：RAW、Bayer、SRAM 初始化文件与结果图之间的转换工具
- `testdata/`：合成测试向量、RAW 输入、黄金输出与 RTL 输出
- `firmware/cm0/`：后续 Cortex-M0 固件
- `docs/`：架构、定点、寄存器与验证设计说明
- `config/`：算法参数与测试配置
- `reports/`：综合、时序与验证报告
- `build/`：本地构建输出，不提交生成文件

## 验证原则

每个关键算法模块都采用三件套：

```text
Python golden model
        |
        v
expected output

RTL module + testbench
        |
        v
actual output
```

最终使用逐像素比较确认 RTL 与软件参考模型一致，而不是只依赖肉眼判断图像效果。

## 复现说明

本仓库是对早期实习项目的重新构建。原始代码已不可用，因此这里会明确区分：

1. 原项目框图中可以确认的模块与接口；
2. 本次复现重新选择的具体算法与定点实现；
3. 为便于验证而做的工程简化，例如 SRAM 输入与 16 bit 像素容器。

具体决策记录在 `docs/design_decisions.md`。

## 参考项目

本仓库的实现会参考但不直接整体复制以下开源项目：

- AMD mini-isp：硬件流水线、行缓存、定点和验证结构
- cruxopen/openISP：完整 ISP 算法链路
- QiuJueqin/fast-openISP：软件算法与快速参考模型
- 10x-Engineers/Infinite-ISP：RAW 数据与算法参考
- mushfiqulalam/isp：多种 Bayer RAW 测试数据
