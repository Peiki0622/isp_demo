# isp_demo

基于 Cortex-M0 控制面的 ISP SoC 复现项目。当前阶段先不复现 SD 卡输入，改为从 SRAM（静态随机存取存储器）读取拜耳原始图像，完成可验证的流式 ISP（图像信号处理器）链路；待图像流水线稳定后，再接入 AHB（高级高性能总线）寄存器控制与 Cortex-M0。

## 当前进度与最短运行命令

P0/P1 与 P2 BLC 已完成：确定性图案 → 一周期同步 SRAM → Reader →
一级 BLC → RAW12 像素流 → 每帧独立 dump → Python 黄金模型精确逐像素比较。
BLC 使用单一全局偏置，计算 `max(pixel - black_level, 0)`，在有效首像素
采样配置；帧中修改只影响下一帧。当前链路尚未实现后续 ISP 算法。

在仓库根目录执行完整验收：

```sh
make test-p2-blc
```

命令先执行独立 Reader-only P0/P1，再运行 BLC 软件模型、一级流水单元回归、
顶层控制/复位/容量测试和四种 16×16 图案各两帧的精确对拍。
包含 11 项工具测试与 11 项模型/黄金文件测试；全部环节通过才打印
`P2 BLC PASS`。错误或 VCS fatal 即使原始退出码为零，也会由脚本判失败。

依赖容器已有 VCS W-2024.09、Python 3.6.6、NumPy 1.19.5、Make 和 Bash。
可通过 `VCS=/path/to/vcs PYTHON=/path/to/python3` 覆盖工具路径。
软件模型使用普通配置字典，不依赖 PyYAML。

可分别运行 `make test-p0-p1`、`make test-blc-model`、`make test-blc-unit`、
`make test-blc-pipeline`；`make compare-p0-p1` 和 `make compare-p2-blc`
只重查已有产物。BLC 后首像素为 C3，末像素和 frame_done 同拍且 busy=1，
下一周期 busy 解除；Source 独立回归仍保持 C2 首像素。

编译、版本、命令和仿真日志统一存于 `build/p0_p1/`、`build/p2_blc/`；
黄金与实际数据位于 `testdata/output/p2_blc/golden/` 和 `integration/`。
`make clean` 仅删除规定的任务产物和四种生成图案，保留其他目录和 reports。
本轮两次验收、哈希及失败负例证据保存在 `reports/p2_blc_execution/`。

人为破坏比较链路：`BLC_CORRUPT_OUTPUT=1 make test-p2-blc` 必须非零退出，
报告第 42 个像素差异。取消该变量后重新运行可恢复正确产物。

数值、周期和验证说明分别见 `docs/fixed_point.md`、`docs/architecture.md`、
`docs/verification.md`；逐步骤提交和验收记录见 `plans/002_p2_blc.md`。

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
