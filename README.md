# isp_demo

基于 Cortex-M0 控制面的 ISP SoC 复现项目。当前阶段先不复现 SD 卡输入，改为从 SRAM（静态随机存取存储器）读取拜耳原始图像，完成可验证的流式 ISP（图像信号处理器）链路；待图像流水线稳定后，再接入 AHB（高级高性能总线）寄存器控制与 Cortex-M0。

## 当前进度与最短运行命令

已实现到 P5：SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic →
CCM → RGB12 三通道流。软件黄金从原始 Bayer 输入依次执行四个算法，
与实际 RTL 的 RGB36 dump 逐像素精确比较。默认配置启用这四个阶段，
CCM 使用整数单位矩阵。AWB 施加外部三路增益，两个绿色位置共用 gain_g；
自动统计和增益估计留待后续。

从仓库根目录运行完整验收：

```sh
make test-p5-ccm
```

入口先完整运行 P0/P1、P2、P3、P4，再运行 CCM 模型/黄金 CLI、单元及全链。
全部入口共 65 项 Python 测试。CCM 单元在正常和 `SYNTHESIS` 定义下分别
检查 6,504 个周期、6,494 个 RGB 像素和 19,482 项通道结果，覆盖 11 种矩阵、
边界组合、4,096 个连续输入、配置、侧带与复位。集成平台检查五种实际小尺寸
共 95 个完整控制帧、25 个复位中止/恢复场景及容量拒绝，再比较四种 16×16
图案的 A/B、C/D 两组双帧，共 16 帧、4,096 个 RGB 像素。每个坐标、标志、
周期、帧长度及 busy 都通过才打印 `P5 CCM PASS`。VCS fatal 即使原生退出码
为零也必须判失败。

CCM 九个系数为 signed16 二进制补码、12 个小数位，4096 表示 +1。
矩阵行对应输出通道，列对应输入通道。RGB12 显式零扩展为正 signed13，
保留完整 signed29 乘积和 signed31 累加；累加≤0 输出零，正累加加 2048
后右移 12 位，再饱和到 4095。固定两级寄存、每拍一个像素，单位矩阵也
保持两级。九个系数在有效 sof 原子采样，首像素直接使用新矩阵，帧中外部
扰动不影响当前帧；复位恢复单位矩阵。没有 CCM offset、Gamma 或 CSC。

P4 保留为独立 `demosaic_pipeline`，原有周期和断言不变。RGGB/RAW12、
reflect 边界（-1→1，W/H→W/H−2）、三行轮转和 half-up 双线性插值保持不变。
正式顶层接受 W/H≥2、W≤MAX_WIDTH（默认 4096）且帧不超过 SRAM 容量；
输入连续、无反压，输出尺寸不变。

设接受 start 为 C0、N=W×H：Reader/BLC/AWB 独立边界首输出仍为 C2/C3/C4，
P4 首/末/空闲为 C(W+7)/C(N+W+6)/C(N+W+7)。P5 CCM 在 C(W+8) 捕获矩阵，
正式首/末/空闲为 C(W+9)/C(N+W+8)/C(N+W+9)。尺寸在 C0 保存，BLC/AWB
配置在 C3/C4 有效帧首采样。最后 RGB 拍 busy=1；忙时、CCM drain 和 busy
清零沿的 start 都被丢弃，保持高电平不会重启，空闲后需新的上升沿。
正式 `isp_pipeline_top` 增加九个 signed16 输入端口 c00..c22。

依赖容器已有 VCS W-2024.09、Python 3.6.6、NumPy 1.19.5、Make 和 Bash。
可通过 `VCS=/path/to/vcs PYTHON=/path/to/python3` 覆盖可执行路径。
模型接收普通配置字典，不增加 YAML、图片库或测试框架核心依赖。
本轮执行编译与功能仿真，包括 `SYNTHESIS` 定义下的功能验证；未执行综合、
物理时序或 PPA 分析。

独立入口：`make test-p0-p1`、`make test-p2-blc`、`make test-p3-awb`、
`make test-p4-demosaic`、`make test-ccm-model`、`make test-ccm-unit`、
`make test-ccm-pipeline`。`make compare-p5-ccm` 只读取已有 26 份黄金/dump，
不重建文件。RGB36 每像素一行九位 `RRRGGGBBB`，对应 `(R<<24)|(G<<12)|B`，
比较同时检查格式、W×H 数量及首错的 index/x/y/通道/expected/actual。

失败传播复现：

```sh
CCM_CASE=forced_failure make test-ccm-unit
CCM_CORRUPT_OUTPUT=R make test-p5-ccm
make compare-p5-ccm
CCM_GOLDEN_INPUT=/absolute/missing.npy make test-ccm-pipeline
```

损坏注入也支持 G/B，仅改变首矩阵组首图案 frame_0 的 actual index=42
（x=10,y=2）。生成失败删除旧/部分黄金并在编译前停止。取消注入后运行
`make test-ccm-pipeline` 恢复，再运行比较入口；单元 fatal、缺失黄金和三通道
损坏均要求非零退出。

新 RTL 端口按功能分组注释，寄存器按配置、乘积、RGB、坐标、有效位和标志
分块，可综合路径没有 function；既有窗口三段式 FSM 保持不变。P5 构建和
日志集中于 `build/p5_ccm/`，输入/黄金/dump 位于
`testdata/output/p5_ccm/{inputs,golden,integration}/`，持久证据位于
`reports/p5_ccm_execution/`。`make clean` 只清理规定的 P0–P5 可重建产物，
保留 reports 和其他运行目录。最终 clean 后两轮完整 P0–P5 均 PASS，
430 份确定性文件哈希一致且 282 份历史数据不变；详细记录见 [P5 计划](plans/005_p5_ccm.md)。

## 查看处理后的 PNG

P5 两组矩阵分别导出四种图案各两帧的实际 RTL 输出：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/export_demosaic_png.py --stage p5 --matrix-pair identity_swap
PYTHONDONTWRITEBYTECODE=1 python3 tools/export_demosaic_png.py --stage p5 --matrix-pair signed_clip
```

已有数值验收数据即可导出。无参数仍导出原 P4 预览。Pillow 6.2.2 仅为可选
图片工具依赖；导出前检查全部实际像素与黄金一致，保存后回读原尺寸 PNG。
使用固定线性 RGB12→RGB8 映射和最近邻放大，无自动亮度拉伸或伽马。
两组各含八张原尺寸、八张放大版、一张总览及清单，集中于
`testdata/output/p5_ccm/png/<pair>/`，可重建且不提交版本库。
参数、矩阵编码和路径见 [P5 PNG 说明](docs/p5_png_preview.md)；
原命令见 [P4 PNG 说明](docs/p4_png_preview.md)。

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
