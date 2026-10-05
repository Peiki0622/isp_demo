# isp_demo

基于 Cortex-M0 控制面的 ISP SoC 复现项目。当前阶段先不复现 SD 卡输入，改为从 SRAM（静态随机存取存储器）读取拜耳原始图像，完成可验证的流式 ISP（图像信号处理器）链路；待图像流水线稳定后，再接入 AHB（高级高性能总线）寄存器控制与 Cortex-M0。

## 当前进度与最短运行命令

P0/P1 已完成：确定性图案 → 一周期同步 SRAM → SRAM Reader → 顶层 RAW
像素流 → 两帧独立 dump → 精确逐像素比较。Reader 使用三段式状态机，锁存尺寸，
处理读延迟、坐标、行帧标志和复位；顶层尚未接入 BLC 或后续算法。

在仓库根目录执行：

```sh
make test-p0-p1
```

依赖本机现有 `vcs`、Python 3、NumPy、Make 和 Bash；本轮验证使用 VCS
W-2024.09、Python 3.6.6、NumPy 1.19.5。可用 `make test-p0-p1 VCS=/path/to/vcs
PYTHON=/path/to/python3` 显式指定已安装的工具，不配置或修改许可证环境。

命令包含 11 项 Python 工具测试、SRAM 模型测试、Reader 边界回归、四种
16×16 图案各两帧的顶层仿真与精确比较，全部通过才打印 `P0/P1 PASS`。
任何失败都返回非零；VCS 的 `$fatal` 即使返回 0，也会被运行脚本识别。

`make patterns` 只生成向量，`make test-sram-reader` 单独验证 Reader，
`make compare-p0-p1` 重新比较已有顶层 dump。编译、日志、版本和命令记录集中在
`build/p0_p1/`，像素 dump 集中在 `testdata/output/p0_p1/`，可重建向量位于
`testdata/synthetic/`。`make clean` 只清理这些任务产物，不清空其他运行目录。

周期约定见 `docs/memory_map.md`，验收方法及证据位置见 `docs/verification.md`，
逐步执行记录见 `plans/001_p0_p1_sram_bootstrap.md`。

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
