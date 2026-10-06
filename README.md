# isp_demo

基于 Cortex-M0 控制面的 ISP SoC 复现项目。当前阶段先不复现 SD 卡输入，改为从 SRAM（静态随机存取存储器）读取拜耳原始图像，完成可验证的流式 ISP（图像信号处理器）链路；待图像流水线稳定后，再接入 AHB（高级高性能总线）寄存器控制与 Cortex-M0。

## 当前进度与最短运行命令

P0/P1、P2 BLC 和 P3 AWB Gain 已实现：确定性图案 → 一周期同步 SRAM →
Reader → 一级 BLC → 一级 AWB Gain → RAW12 像素流 → 独立帧 dump →
Python BLC→AWB 全链整数黄金模型逐像素比较。AWB Gain 施加外部三路增益，
两个绿色位置共用 gain_g；自动白平衡统计和增益估计留待后续。

BLC 计算 `max(pixel - black_level, 0)`；AWB 使用 16 位 UQ4.12 编码，
4096 表示 1 倍，计算 `min((pixel * gain_code + 2048) >> 12, 4095)`。
各级在自己的有效首像素沿采样配置，首像素立即使用新值，帧中变化不影响当帧。
默认配置只启用已实现的 BLC 和 AWB Gain。

在仓库根目录执行完整验收：

```sh
make test-p3-awb
```

命令依次运行完整 P0/P1、P2 和 P3，包括 33 项 Python 工具/模型/黄金 CLI
测试、AWB 45,664 拍单元检查、60 个实际尺寸小帧的控制/复位测试、容量拒绝、
四种 16×16 图案各两帧全链对拍。P3 八帧共 2,048 个像素独立比较，
所有数值、坐标、标志、帧长度和 busy 时序都通过才打印 `P3 AWB PASS`。
VCS fatal 即使原始退出码为零，也由脚本判失败。

依赖容器已有 VCS W-2024.09、Python 3.6.6、NumPy 1.19.5、Make 和 Bash。
可用 `VCS=/path/to/vcs PYTHON=/path/to/python3` 覆盖路径；软件模型使用
普通配置字典，不依赖 PyYAML。本阶段完成编译/功能仿真，未做综合或时序收敛。

可分别运行 `make test-p0-p1`、`make test-p2-blc`、`make test-awb-model`、
`make test-awb-unit`、`make test-awb-pipeline`；`make compare-p0-p1`、
`make compare-p2-blc`、`make compare-p3-awb` 只重查已有数据。Reader-only
`sram_raw_source` 保持 C2 首像素，独立 `blc_pipeline` 保持 C3；正式
`isp_pipeline_top` 首像素 C4，末像素 C(N+3) 且 busy=1，C(N+4) 才空闲。

新增 RTL 端口按功能分组注释，寄存器按配置/数据/坐标/有效位/标志分块，
无 function 和额外 FSM，Reader 保留三段式状态机。编译和日志统一位于
`build/p0_p1/`、`build/p2_blc/`、`build/p3_awb/`；P3 输入、黄金和实际
数据分别位于 `testdata/output/p3_awb/{inputs,golden,integration}/`。
`make clean` 只删除规定的可重建目录，保留 reports 和其他运行目录。

失败传播验收：`AWB_CORRUPT_OUTPUT=1 make test-p3-awb` 必须非零退出，
定位实际输出 index=42、x=10、y=2；随后的 `make compare-p3-awb` 也必须失败。
`AWB_CASE=forced_failure make test-awb-unit` 检查 fatal 传播；
`AWB_GOLDEN_INPUT=/absolute/missing.npy make test-awb-pipeline` 检查黄金生成
失败后删除旧目标并立即停止。取消注入变量，运行 `make test-awb-pipeline`
恢复产物，再运行比较命令确认。

两轮完整验收、确定性文件哈希及负例/恢复证据保存在
`reports/p3_awb_execution/`。数值、周期和验证细节见 `docs/fixed_point.md`、
`docs/architecture.md`、`docs/verification.md`；各阶段实际提交和验收记录
见 `plans/003_p3_awb_gain.md`。

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
