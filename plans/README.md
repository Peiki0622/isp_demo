# Plans

本目录保存给 Codex（代码代理）逐步骤执行的工程计划。计划文件既是任务说明，也是阶段验收记录。

## 执行约定

1. 一个计划只覆盖一个明确里程碑，避免范围扩张。
2. 按计划中的 Step 顺序执行，不跨步。
3. 每一步先通过验收，再进入下一步。
4. 每一步尽量形成独立提交，方便回退、代码审查和二分定位。
5. 不得通过弱化测试、删除断言或改成肉眼检查来制造“通过”。
6. 每完成一步，要更新对应计划文件末尾的执行记录，并填写实际提交哈希。
7. 遇到环境、工具链或协议冲突时，先记录问题，再决定是否修改计划。

## 已完成

- 001_p0_p1_sram_bootstrap.md：SRAM（静态随机存取存储器）测试数据工具链、同步读图链路、自检查仿真和逐像素精确比较。对应里程碑提交：174f7bd62eec464afea82d052559d96946bfceb9。
- 002_p2_blc.md：SRAM → Reader → BLC（黑电平校正），帧级偏置采样、一级侧带流水、独立 Reader-only 回归与 Python 精确对拍。最终记录提交：99bacf2d196fd10eef13271c6e71f230af32cdf4。
- 003_p3_awb_gain.md：SRAM → Reader → BLC → AWB Gain（白平衡增益施加），UQ4.12 整数增益、RGGB 相位、一级流水和帧首配置。最终记录提交：c75cba182f942d4d8337a885ce5b7e8f9fd7ed66。
- 004_p4_demosaic_bilinear.md：SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → RGB12，3×3 reflect 窗口、尾部排空和 RGB 精确对拍。正式关闭提交：56af88c45669ab6da0e079e36989571116a56c05；随后 e769f67606b1c3251562e86199f5323e5f1eeb94 仅增加已验收 RGB 输出的 PNG 预览工具。

## 当前已验证链路

SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → RGB12。

P4 已建立从 RAW 域进入 RGB 域所需的流式窗口、边界处理和尾部排空能力；当前仍未实现 CCM 之后的颜色空间链路。

## 当前计划

- 005_p5_ccm.md：实现 CCM（Color Correction Matrix，颜色校正矩阵）的 3×3 有符号固定点矩阵乘加。

P5 冻结为：

- 9 个 signed 16-bit coefficient，12 个 fractional bits，4096 表示 +1.0；
- RGB12 输入先显式零扩展为正 signed 数，再与 signed coefficient 相乘；
- Stage 1 注册 9 个乘积；
- Stage 2 做三个 signed accumulator、正数四舍五入、负值下限钳位和 RAW12 上限饱和；
- 固定两级延迟，稳态仍为 1 RGB pixel/cycle；
- 9 个系数在 valid+sof 原子采样，reset identity；
- 新建 Demosaic-only 历史边界，P4 原有周期/结果不能被 P5 改写；
- Python 全链 BLC → AWB → Demosaic → CCM 与 RGB36 精确对拍。

P5 不实现 Gamma、CSC、YCbCr 或 Raw NR。

## 后续方向

P5 完整验收后，默认优先进入 CSC（Color Space Conversion，颜色空间转换），把 RGB12 转为数字 YCbCr，并明确标准、range、offset、定点系数和饱和规则。

是否在 CCM 与 CSC 之间额外加入 Gamma，要在 P5 完成后重新依据原始框图和复现目标判断；原始框图未明确 Gamma，因此不能仅因为开源 ISP 常见就自动加入。

Raw NR（原始域降噪）继续保持旁路，待 RGB 主干稳定后作为独立 RAW-domain 里程碑插回并回归。
