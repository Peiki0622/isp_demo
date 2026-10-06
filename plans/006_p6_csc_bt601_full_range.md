# 006 — P6：RGB12 → YCbCr12 CSC（BT.601 系数 + 全范围数字编码）

目标读者：Codex（代码代理）

状态：待执行

本轮目标：在已经通过 P0–P5 验收的 SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → CCM → RGB12 链路之后，加入 CSC（Color Space Conversion，颜色空间转换），把 RGB12 转换为 YCbCr12，并第一次正式进入亮度/色度域。

本轮采用 **BT.601 亮度/色度系数 + JPEG 风格 full-range（全范围）数字编码** 作为复现基线。这是新的工程选择，不声称原实习项目已经确认使用该标准。原框图只能确认 CCM 后存在 CSC，并不足以证明具体标准、full/limited range 或系数量化方式。

本轮不加入 Gamma，不实现 Chroma NR、Hue、LCC、Edge Enhancement、Raw NR 或 Cortex-M0/AHB。

---

## 0. P5 审阅结论与当前基线

P5 正式关闭提交：

185d6e9441c0107d581fb89c217ef58261a77172

P5 产品验收提交：

01711cd9fcde0a02501125af1a4cc2dbf4b5a09f

从创建 P5 当前计划索引的 57bcc7c63a1a7663f56bb68de714b2f003c0aa5e 到关闭提交，远程 main 共前进 10 个提交。

已确认的远程仓库事实：

- CCM 已实现 signed16、12 fractional bits 的 3×3 矩阵。
- RGB12 在乘法前显式零扩展为正 signed13。
- Stage 1 保存九个完整 signed29 乘积。
- Stage 2 使用 signed31 累加，A<=0 钳位 0，正值 +2048 后右移 12 位，再饱和到 4095。
- 九个矩阵系数在 valid+sof 原子采样，首像素直接使用当拍新矩阵。
- 新增 demosaic_pipeline，P4 历史边界保持独立。
- 正式 top 当前为 Demosaic → CCM → RGB12，最终首/末/空闲时序为 C(W+9)/C(N+W+8)/C(N+W+9)。
- 仓库记录 clean 后连续两轮完整 P0–P5 回归 PASS、430 份确定性文件哈希一致、R/G/B 故障注入和恢复。
- 最新 GitHub commit 没有附着独立 CI status；上述 PASS 来自仓库保存的本地 VCS 验收证据，本次审阅未在独立 VCS 环境重新执行。

本轮代码审阅没有发现阻断 P6 的已确认功能问题。

非阻断技术债：

1. rtl/ycbcr_domain/rgb2ycbcr.sv 当前仍是占位模块，只包含 RGB 数据和 valid，没有坐标、帧标志、busy 或正式数值契约。
2. 当前 config/default.yaml 只知道 pipeline.rgb2ycbcr=false，没有明确标准/range。P6 必须显式记录使用哪套 YCbCr 数字编码。
3. P4 的 window_3x3 多点组合读是否能理想映射 BRAM 仍需综合才能判断；P6 不改该结构，也不做资源结论。

---

## 1. 为什么 P6 选择这套 CSC

P6 固定为：

- 输入：RGB12 full-range，三个通道都在 0..4095。
- 输出：YCbCr12 full-range，三个通道都在 0..4095。
- Y 使用 BT.601 的 0.299 / 0.587 / 0.114 亮度权重。
- Cb/Cr 使用对应 full-range 色差信号系数。
- 中性 chroma midpoint（色度中点）固定为 2048。
- 系数采用 signed 16-bit、12 fractional bits 的整数编码。
- 系数在 RTL 中为常量，不提供运行时可编程矩阵端口。

选择 full-range 的原因：

- 当前 ISP 内部已经使用完整 RAW12/RGB12 数值范围；
- full-range 便于继续内部算法，不在 P6 提前引入视频 limited-range 的 16/235、16/240 类缩放；
- 原图没有指定电视制式或 HDMI range，因此不能假装 limited-range 是原项目事实。

如果后续 HDMI/视频接口要求 limited-range，应单独建立输出编码计划，不在 P6 偷换语义。

---

## 2. 固定点系数契约

P6 使用 12 个小数位，缩放因子为 4096。

真实系数关系：

coef_real = coef_code / 4096

其中，coef_real 表示数学上的实数系数；coef_code 表示 RTL/Python 使用的 signed 整数系数编码；4096 等于 2 的 12 次幂；“/”表示除法；“=”表示两边表示同一个系数。

冻结的整数系数：

Y：
- R：1225
- G：2404
- B：467

Cb：
- R：-691
- G：-1357
- B：2048

Cr：
- R：2048
- G：-1715
- B：-333

必须保留以下整数不变量：

1225 + 2404 + 467 = 4096

其中，1225/2404/467 是 Y 对 R/G/B 的编码系数；4096 是 1.0 的固定点编码；“+”表示整数加法；“=”表示三项精确求和。

-691 + -1357 + 2048 = 0

其中，-691/-1357/2048 是 Cb 对 R/G/B 的编码系数；0 表示灰阶输入时 Cb 的颜色差分部分精确为零；“+”表示有符号整数加法；“=”表示求和结果。

2048 + -1715 + -333 = 0

其中，2048/-1715/-333 是 Cr 对 R/G/B 的编码系数；0 表示灰阶输入时 Cr 的颜色差分部分精确为零；“+”表示有符号整数加法；“=”表示求和结果。

---

## 3. 整数 CSC 数学契约

输入 R、G、B 都是 12 位无符号整数 0..4095。

### 3.1 Y

A_Y = 1225×R + 2404×G + 467×B

其中，A_Y 表示还保留 12 个固定点小数位的亮度累加值；R/G/B 表示输入三通道；1225/2404/467 是固定整数系数；“×”表示整数乘法；“+”表示整数加法；“=”表示右侧定义 A_Y。

### 3.2 Cb

A_Cb = -691×R - 1357×G + 2048×B + (2048<<12)

其中，A_Cb 表示带数字中点偏置、仍保留 12 个固定点小数位的 Cb 累加值；R/G/B 表示输入三通道；-691/-1357/2048 是 Cb 固定整数系数；2048 是 12 位色度中点；“<<12”表示左移 12 位，把输出域 offset 转换到固定点累加域；“-”和“+”表示有符号整数加减；“=”表示右侧定义 A_Cb。

### 3.3 Cr

A_Cr = 2048×R - 1715×G - 333×B + (2048<<12)

其中，A_Cr 表示带数字中点偏置、仍保留 12 个固定点小数位的 Cr 累加值；R/G/B 表示输入三通道；2048/-1715/-333 是 Cr 固定整数系数；2048 是色度中点；“<<12”表示左移 12 位；“-”和“+”表示有符号整数加减；“=”表示右侧定义 A_Cr。

### 3.4 舍入与饱和

对 A_Y、A_Cb、A_Cr 分别计算：

S = (A + 2048) >>> 12

其中，A 表示当前 Y/Cb/Cr 的带 12 位小数累加值；2048 是 half-up（正数四舍五入）的半 LSB 偏置；“+”表示整数加法；“>>>12”表示有符号算术右移 12 位；S 表示移除固定点小数后的整数结果；“=”表示右侧定义 S。

最终：

P_out = clamp(S, 0, 4095)

其中，P_out 表示最终 Y、Cb 或 Cr 的 12 位输出；S 表示舍入结果；clamp(v,lo,hi) 表示把 v 限制在 lo 到 hi 之间；0 和 4095 是 YCbCr12 full-range 的下上限；“=”表示最终输出定义。

即使理论系数使大多数合法输入自然位于范围内，RTL/Python 仍必须做明确上下限钳位，防止系数量化边缘值出现 4096 或未来修改造成回绕。

---

## 4. 强不变量

P6 必须通过以下性质验证。

### 4.1 灰阶保持

当 R=G=B=P 时：

Y = P

其中，R/G/B 表示输入三通道，P 表示同一个灰阶值，Y 表示输出亮度；“=”表示全范围灰阶亮度必须精确保持。

Cb = 2048

其中，Cb 表示蓝色色差通道；2048 是 12 位中性色度中点；“=”表示灰阶输入必须精确落在中点。

Cr = 2048

其中，Cr 表示红色色差通道；2048 是 12 位中性色度中点；“=”表示灰阶输入必须精确落在中点。

这三个性质应对 P=0..4095 做全量测试，而不是只测黑白两点。

### 4.2 黑白

黑色 RGB=(0,0,0) 必须得到 YCbCr=(0,2048,2048)。

白色 RGB=(4095,4095,4095) 必须得到 YCbCr=(4095,2048,2048)。

这里括号内三个数依次表示 R/G/B 或 Y/Cb/Cr 三个通道；“=”表示输入与预期输出的对应关系。

---

## 5. 位宽契约

像 P5 一样，RGB12 输入在乘法前显式扩展为正 signed13：

{1'b0, pixel[11:0]}

系数统一按 signed16 常量参与乘法。

每个乘积保存为 signed29。

Stage 2 的 Y/Cb/Cr accumulator 至少使用 signed31。

色度固定偏置：

CHROMA_OFFSET_SCALED = 2048 << 12

其中，CHROMA_OFFSET_SCALED 表示放在累加器尺度上的色度中点；2048 是输出域中点；“<<12”表示左移 12 位；“=”表示该常量的定义。

不得：

- 把 RGB12 直接解释成 signed12；
- 在 signed29 乘积加法前先截断；
- 把色度 offset 在窄 12 位结果上相加后允许回绕；
- 在上下限比较之前先截成 12 位。

---

## 6. 两级流水契约

rgb2ycbcr 固定两级。

### Stage 1 — 常系数乘法

输入有效周期：

- 同时计算并寄存 Y/Cb/Cr 共 9 个 signed29 product。
- x/y/sof/eol/frame_done 同步寄存到 Stage 1。
- stage1_valid <= in_valid。

本阶段系数是固定常量，不存在帧配置寄存器。

### Stage 2 — 累加、offset、舍入、钳位

下一周期：

- 三组 product 分别做 signed31 累加。
- Cb/Cr 加 CHROMA_OFFSET_SCALED。
- 三通道加 2048 后右移 12 位。
- 明确 clamp 到 0..4095。
- 注册 Y/Cb/Cr、x/y/flags。
- out_valid <= stage1_valid。

因此 CSC 固定延迟 2 个时钟周期，稳态吞吐仍为 1 pixel/cycle。

禁止“灰阶”或某些常量输入走零延迟旁路。

---

## 7. 稳定 P5 历史边界

P6 必须新增：

rtl/top/ccm_pipeline.sv

它必须等价迁移当前 P5 isp_pipeline_top：

SRAM → Reader → BLC → AWB Gain → Demosaic → CCM → RGB12

P5 的公开接口、数值结果和时序必须不变：

- 第一个最终 RGB：C(W+9)
- 最后一个最终 RGB：C(N+W+8)
- busy 清零：C(N+W+9)

其中，W 表示图像宽度；N 表示帧像素总数；C(k) 表示 accepted start 为 C0 后的第 k 个周期；“+”表示周期编号加法；“=”表示对应关系。

新的 isp_pipeline_top 才实现：

ccm_pipeline → rgb2ycbcr

不允许把 P5 旧测试整体再加两拍后称作“P5 回归”。

---

## 8. P6 顶层公开接口

P6 正式 top 的最终输出从 RGB 改成 YCbCr。

为避免“Y 亮度”和坐标 pixel_y 同名，正式 top 统一使用：

- pixel_luma
- pixel_cb
- pixel_cr
- pixel_x
- pixel_y
- pixel_valid
- sof/eol/frame_done
- busy

不要把亮度通道命名成 pixel_y。

内部 rgb2ycbcr 模块可以保留 out_y/out_cb/out_cr，因为其坐标输出可命名 out_x/out_coord_y；但正式 top 必须避免歧义。

---

## 9. P6 顶层周期

P5 第一个 RGB 在 C(W+9)。

CSC 两级后：

- CSC Stage 1 首次采样：C(W+10)
- 第一个最终 YCbCr：C(W+11)
- P5 最后一个 RGB：C(N+W+8)
- 最后一个最终 YCbCr：C(N+W+10)
- 最后 YCbCr/frame_done 拍 busy 仍为 1
- C(N+W+11) busy=0

其中，W 表示宽度；N 表示像素数；C(k) 表示 accepted start 后第 k 个周期；“+”表示周期编号加法；“=”表示时序对应。

整链 busy 由 ccm_pipeline busy 与 CSC 两级占用共同决定。

忙时 start pulse、busy 清零沿的 start、以及保持高电平跨过完成的 start 都不得自动启动下一帧。

---

# Step 0 — 重新验证 P5 基线

- [ ] 回读 plans/005_p5_ccm.md。
- [ ] 回读 ccm、isp_pipeline_top、rgb2ycbcr 占位模块。
- [ ] make clean。
- [ ] make test-p5-ccm。
- [ ] make compare-p5-ccm。
- [ ] 记录 VCS/Python/NumPy 版本。
- [ ] 确认工作区干净。
- [ ] 记录 P5 product SHA=01711cd9 和 close SHA=185d6e94。

验收：任何 P6 修改之前，完整 P5 必须 PASS。

建议提交：无。

---

# Step 1 — 冻结 P6 标准、range、整数系数和接口

修改：

- docs/architecture.md
- docs/pipeline.md
- docs/fixed_point.md
- docs/design_decisions.md
- docs/verification.md
- config/default.yaml

动作：

- [ ] 明确是 BT.601 coefficients + JPEG-style full-range coding。
- [ ] 明确不是 limited-range。
- [ ] 明确不是原实习项目已确认标准。
- [ ] 写入 9 个整数系数。
- [ ] 写入 Cb/Cr midpoint=2048。
- [ ] 写入两级固定流水。
- [ ] 写入最终 top 的 pixel_luma/pixel_cb/pixel_cr 命名。
- [ ] config 新增 rgb2ycbcr.standard=bt601、range=full、fraction_bits=12、chroma_midpoint=2048。
- [ ] pipeline.rgb2ycbcr 在最终 P6 验收前保持 false。

建议提交信息：

docs: freeze P6 full-range YCbCr CSC contract

---

# Step 2 — Python RGB→YCbCr 黄金模型

新增：

- model/rgb2ycbcr.py
- model/tests/test_rgb2ycbcr.py

修改：

- model/isp_model.py
- model/README.md

建议 API：

apply_rgb_to_ycbcr(rgb_3d)

输入 shape=(H,W,3) uint/integer RGB12，输出 shape=(H,W,3) uint16，通道顺序固定 Y/Cb/Cr。

要求：

- [ ] 全程 int64。
- [ ] 不使用 float 系数。
- [ ] 输入严格检查 0..4095。
- [ ] 精确使用冻结的 9 个整数系数。
- [ ] 精确使用 2048<<12 色度 offset。
- [ ] 三通道使用相同 +2048 后右移 12 的规则。
- [ ] 最后 clamp 0..4095。
- [ ] run_pipeline 顺序变成 BLC → AWB → Demosaic → CCM → RGB2YCbCr。
- [ ] 如果 cfg 显式提供 standard/range，非 bt601/full 必须报错，不能静默套用另一标准。

必须测试：

- black。
- white。
- red/green/blue 最大原色。
- 4096 个完整灰阶值，Y 必须逐点等于输入，Cb/Cr 必须全为 2048。
- 舍入余数在 half-up 临界附近的定向向量。
- 上限饱和。
- 非法 shape/type/range。

建议提交信息：

model: add exact full-range YCbCr reference

---

# Step 3 — 保留稳定 CCM-only 边界

新增：

- rtl/top/ccm_pipeline.sv

调整：

- P5 集成测试和 scripts/run_ccm_pipeline.sh 改为实例化 ccm_pipeline。
- 只做模块边界迁移，不改变 P5 数值或周期。

验收：

- make test-p0-p1 PASS
- make test-p2-blc PASS
- make test-p3-awb PASS
- make test-p4-demosaic PASS
- make test-p5-ccm PASS
- P5 首/末/idle 仍是 C(W+9)/C(N+W+8)/C(N+W+9)

建议提交信息：

refactor: preserve verified CCM pipeline boundary

---

# Step 4 — 实现 RTL rgb2ycbcr 两级流水

重写：

- rtl/ycbcr_domain/rgb2ycbcr.sv

接口至少包含：

输入：

- clk/rst_n
- in_valid
- in_r/in_g/in_b
- in_x/in_y
- in_sof/in_eol/in_frame_done

输出：

- out_valid
- out_y/out_cb/out_cr
- out_x/out_y_coord 或其他不与亮度 Y 冲突的坐标命名
- out_sof/out_eol/out_frame_done
- busy

实现要求：

- [ ] RGB12 显式零扩展为正 signed13。
- [ ] 9 个固定 signed16 integer coefficients。
- [ ] Stage 1 保存 9 个 signed29 product。
- [ ] Stage 1 保存全部 sideband。
- [ ] Stage 2 使用 signed31 或更宽 accumulator。
- [ ] Cb/Cr 加 scaled midpoint。
- [ ] 三通道 +2048 后右移 12。
- [ ] 三通道明确下限 0 / 上限 4095 clamp。
- [ ] Stage 2 注册 Y/Cb/Cr 和全部 sideband。
- [ ] busy=stage1_valid || out_valid 或行为等价。
- [ ] invalid 拍 out_valid/flags 为 0。
- [ ] 无 runtime coefficient ports。
- [ ] 无 FSM、无 backpressure、无 Gamma。

建议提交信息：

rtl: implement two-stage full-range RGB to YCbCr CSC

---

# Step 5 — CSC 自检查单元测试

新增：

- tb/unit/tb_rgb2ycbcr.sv
- scripts/run_rgb2ycbcr_unit.sh
- Make target test-rgb2ycbcr-unit

必须覆盖：

1. black → (0,2048,2048)。
2. white → (4095,2048,2048)。
3. 最大 R/G/B 三个原色。
4. 4096 个灰阶值全覆盖。
5. 至少数千个确定性 RGB 组合。
6. 正/负系数乘法。
7. round-half-up 临界余数。
8. 0 和 4095 clamp。
9. valid hole。
10. sof/eol/frame_done 两级延迟。
11. invalid flags 不外泄。
12. reset 清空两级 pipeline。
13. back-to-back unit-level frames。

oracle 必须独立使用 signed 宽位整数公式，不读取 DUT 内部 product/accumulator。

建议提交信息：

test: add self-checking RGB to YCbCr CSC regression

---

# Step 6 — 接入正式 isp_pipeline_top

新的正式结构：

SRAM
→ Reader
→ BLC
→ AWB Gain
→ Bilinear Demosaic
→ CCM
→ RGB-to-YCbCr CSC
→ YCbCr12 output

推荐层级：

isp_pipeline_top
  ├─ ccm_pipeline
  └─ rgb2ycbcr

正式 top：

- 输入继续保留 BLC/AWB/CCM 配置。
- 不增加 CSC runtime coefficients。
- 输出改为 pixel_luma/pixel_cb/pixel_cr。
- 坐标仍为 pixel_x/pixel_y。
- busy 必须覆盖 P5 上游和 CSC 两级 drain。

验收周期：

- first final：C(W+11)
- last final：C(N+W+10)
- idle：C(N+W+11)

忙时 start 语义保持此前所有里程碑约定。

建议提交信息：

rtl: integrate YCbCr CSC into ISP pipeline

---

# Step 7 — YCbCr36 工具与全链黄金对拍

新增：

- model/generate_ycbcr_golden.py
- tools/compare_ycbcr_output.py
- tb/integration/tb_ycbcr_pipeline.sv
- scripts/run_ycbcr_pipeline.sh
- 对应 Python tests / Make targets

P0–P5 的 RAW/RGB compare 格式全部保持不变。

P6 每个像素使用 36 位打包：

packed = (Y<<24) | (Cb<<12) | Cr

其中，packed 表示单个 36 位输出字；Y/Cb/Cr 分别表示三个 12 位通道；“<<”表示左移；“|”表示按位或；“=”表示打包结果定义。

文本每行恰好 9 个十六进制字符：

- 前 3 个字符：Y
- 中间 3 个字符：Cb
- 后 3 个字符：Cr

compare 工具必须报告：

- index
- x/y
- 错误通道 Y/Cb/Cr
- expected
- actual
- 总像素数错误

黄金必须从原始 SRAM Bayer 输入完整执行：

BLC → AWB → Demosaic → CCM → RGB2YCbCr

正式主图案继续使用：

- constant_rgb
- rgb_gradient
- color_blocks
- edge_pattern

至少两帧，并继续改变上游 CCM matrix，确保 CSC 在不同 RGB 分布下都正确。

小尺寸继续覆盖：

- 2×2
- 3×2
- 2×3
- 3×5
- 4×4

建议提交信息：

test: add end-to-end YCbCr golden comparison

---

# Step 8 — 控制、失败传播和边界验证

必须验证：

- P5 最后一拍后 CSC 两级正确 drain。
- 最终 frame_done 与最后 YCbCr 同拍。
- 最后 YCbCr 有效拍 busy=1。
- 下一拍 busy=0。
- CSC drain 期间 start pulse 被忽略。
- busy 清零沿的 start 不自动重启。
- held-high start 跨过结束不自动重启。
- reset 在 CSC Stage 1 / Stage 2 中止后能重新启动。
- 中途改变 BLC/AWB/CCM 外部配置不影响已锁存的各自帧语义。

负例：

- CSC_CASE=forced_failure。
- 缺失 YCbCr golden。
- golden generation 输入错误必须删除旧 target 并在编译前停止。
- 分别损坏 Y、Cb、Cr actual 的 index=42 或其他固定位置。
- compare-only 必须返回非零并指出具体通道。

建议提交信息：

test: harden P6 CSC control and failure propagation

---

# Step 9 — 一键完整回归和收尾

Make 至少提供：

- make test-p0-p1
- make test-p2-blc
- make test-p3-awb
- make test-p4-demosaic
- make test-p5-ccm
- make test-rgb2ycbcr-model
- make test-rgb2ycbcr-unit
- make test-ycbcr-pipeline
- make test-p6-csc
- make compare-p6-csc
- make clean

test-p6-csc 必须先完整回归 P0–P5，再执行 P6。

最终：

make clean
make test-p6-csc
make test-p6-csc

连续两轮全部 PASS。

要求：

- 所有确定性 input/golden/actual hash 两轮一致。
- P2/P3/P4/P5/P6 compare-only 全部 PASS。
- 正常和 SYNTHESIS-defined 功能仿真都通过。
- 最终 config/default.yaml 设置 pipeline.rgb2ycbcr=true。
- README 只能声明当前实现到 YCbCr12，不得说整个 YUV 后处理已经完成。
- plans/006_p6_csc_bt601_full_range.md 填写实际 commit SHA。
- plans/README.md 更新完成状态。
- 不得声称已经综合或满足某个 Fmax/PPA。

建议提交信息：

docs: close P6 YCbCr CSC milestone

---

## 10. 本轮明确不做

- BT.709。
- limited-range / studio swing。
- runtime 可配置 CSC coefficient。
- Gamma。
- Chroma NR。
- Hue/Saturation。
- LCC。
- Edge Enhancement。
- Raw NR。
- Cortex-M0/AHB。
- HDMI range adaptation。
- FPGA 综合、时序、DSP/LUT/PPA 结论。

---

## 11. 重点易错项

- [ ] 把 BT.601 系数和 limited-range 数字编码混在一起。
- [ ] 把 YCbCr 误称为模拟 YUV，导致 offset/range 语义模糊。
- [ ] Cb/Cr 忘记 +2048 中点。
- [ ] 2048 offset 在右移后以窄位相加导致回绕。
- [ ] RGB12 被当成 signed12。
- [ ] 负色度系数参与 unsigned 表达式导致符号扩展错误。
- [ ] 乘积或累加在窄位宽中先溢出。
- [ ] 舍入后 4096 直接截断到 0。
- [ ] 灰阶 Cb/Cr 不是精确 2048。
- [ ] 把亮度 Y 输出和坐标 pixel_y 命名冲突。
- [ ] P5 旧 RGB 测试被直接改成 YCbCr，失去 CCM-only 历史边界。
- [ ] CSC 固定两级但 sideband 只延迟一级。
- [ ] 顶层 busy 忽略 CSC Stage 1 或最后 out_valid。
- [ ] Python 使用 float，而 RTL 使用整数系数。
- [ ] 默认配置提前打开 rgb2ycbcr，造成“配置表示已实现”与实际进度不一致。

---

## 12. 执行记录

Codex 每完成一步更新实际提交哈希。

| Step | 状态 | 提交 | 验证命令 | 备注 |
|---|---|---|---|---|
| 0 | 未开始 | — | — | — |
| 1 | 未开始 | — | — | — |
| 2 | 未开始 | — | — | — |
| 3 | 未开始 | — | — | — |
| 4 | 未开始 | — | — | — |
| 5 | 未开始 | — | — | — |
| 6 | 未开始 | — | — | — |
| 7 | 未开始 | — | — | — |
| 8 | 未开始 | — | — | — |
| 9 | 未开始 | — | — | — |

---

## 13. 下一阶段入口条件

只有 P6 全部验收完成后再创建 P7。

P6 完成后，主链已经真正进入 YCbCr 域。下一阶段不提前拍板：

- 若优先继续点运算和色度支路，可评估 Hue（色相）；
- 若优先学习亮度空间滤波，可评估 Edge Enhancement（边缘增强）；
- Chroma NR 和 LCC 的具体算法仍需要先重新冻结，不能从原框图名称直接推断实现细节。

Raw NR 继续保持独立待办，后续应作为 RAW-domain 回插里程碑处理。
