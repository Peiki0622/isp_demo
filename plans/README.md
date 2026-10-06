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

## 当前已验证链路

SRAM → Reader → BLC → AWB Gain。

P3 只实现外部可配置 R/G/B 增益的施加，不包含自动白平衡统计或增益估计。

## 当前计划

- 004_p4_demosaic_bilinear.md：建立 3×3 流式邻域窗口和双线性 Demosaic（去马赛克），把当前 RAW12 单通道流转换成 RGB12 三通道流。

P4 的主要新硬件能力：

- correctness-first 的最多 3 行行存储；
- 3×3 邻域窗口；
- mirror/reflect 图像边界；
- frame_done 后尾部排空；
- RGGB 双线性整数插值；
- RGB36 黄金文件与逐通道精确比较；
- 保留 P0/P1 Reader-only、P2 BLC-only、P3 AWB-only 三层历史回归边界。

P4 选择基础 3×3 bilinear（双线性）作为复现基线，不声称原实习代码使用该算法，也不在本轮直接实现 5×5 Malvar-He-Cutler。

## 后续方向

P4 完整验收后，默认进入 CCM（Color Correction Matrix，颜色校正矩阵），开始 RGB 域的 3×3 带符号定点矩阵乘加。

Raw NR（原始域降噪）继续保持旁路，待 RAW → RGB → CCM 主链稳定后再作为独立里程碑插回并验收。
