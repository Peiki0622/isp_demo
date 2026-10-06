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
- 005_p5_ccm.md：SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → CCM → RGB12，signed16/12 小数位、两级流水、帧级矩阵和全链精确对拍。产品验收提交：01711cd9fcde0a02501125af1a4cc2dbf4b5a09f；正式关闭提交：185d6e9441c0107d581fb89c217ef58261a77172。

## 当前已验证链路

SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → CCM → RGB12。

P5 已完成 RGB 域有符号矩阵乘加、两级流水、帧级矩阵采样和完整排空控制；独立 Demosaic-only 历史边界继续保留。

## 当前计划

- 006_p6_csc_bt601_full_range.md：实现 RGB12 → YCbCr12 CSC（Color Space Conversion，颜色空间转换），正式从 RGB 域进入亮度/色度域。

P6 冻结为：

- 使用 BT.601 亮度/色度系数；
- 使用 JPEG 风格 full-range（全范围）数字编码，而不是 limited-range；
- RGB12 输入和 YCbCr12 输出范围均为 0..4095；
- Cb/Cr 中性色度中点固定为 2048；
- 9 个 CSC 系数采用 signed 整数、12 个小数位，RTL 中固定为常量；
- Stage 1 注册 9 个乘积，Stage 2 做累加、色度 offset、round-half-up 和 12 位上下限钳位；
- 固定两级延迟，稳态仍为 1 pixel/cycle；
- 新建 CCM-only 历史边界，P5 原有 RGB 结果和周期不得被 P6 改写；
- 新增 YCbCr36 精确比较，黄金链路为 BLC → AWB → Demosaic → CCM → RGB2YCbCr。

该标准/range 是复现工程选择，不声称原实习项目已确认使用 BT.601 full-range。

P6 不加入 Gamma、Chroma NR、Hue、LCC、Edge Enhancement 或 Raw NR。

## 后续方向

P6 完整验收以后再决定 P7。

如果优先继续色度点运算，可评估 Hue（色相）；如果优先继续学习亮度空间算法，可评估 Edge Enhancement（边缘增强）。Chroma NR 和 LCC 的具体算法必须先重新冻结，不能从框图名称直接推断实现。

Raw NR（原始域降噪）继续保持独立待办，后续作为 RAW-domain 回插里程碑处理。
