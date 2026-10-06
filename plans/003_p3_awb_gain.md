# 003 — P3：AWB Gain 拜耳域增益与定点流水

目标读者：Codex（代码代理）

状态：执行中

本轮目标：在已经通过 P0/P1 和 P2 验收的 SRAM → Reader → BLC（黑电平校正）链路后加入 AWB Gain（White Balance Gain，白平衡增益施加）模块，建立“RGGB 位置判定 → 固定点增益选择 → 乘法 → 舍入 → RAW12 饱和 → 一级寄存输出”的完整硬件与软件精确对拍闭环。

重要边界：本轮只实现“白平衡增益施加”，不实现完整 AWB（Automatic White Balance，自动白平衡）的统计、光源估计或增益自动求解。gain_r/gain_g/gain_b 由外部配置提供。原框图写的是 AWB Gain，因此不得把本轮描述成已经实现灰度世界、白点检测或自动增益估计。

---

## 0. P2 审阅结论与当前基线

P2 最终记录提交：

99bacf2d196fd10eef13271c6e71f230af32cdf4

已确认的远程仓库事实：

- P2 从 168b562 向前推进 16 个提交，Step 1–8 均保留独立实现提交和验收记录。
- 新增 sram_raw_source，P0/P1 Reader-only 时序边界保留。
- BLC 已实现单全局偏置、帧首采样、一级寄存、坐标/valid/sof/eol/frame_done 对齐。
- isp_pipeline_top 已实现 SRAM → Reader → BLC，并把 busy 延长到 BLC 最后一拍。
- Python BLC 黄金模型、RTL 单元测试、顶层控制测试和四图案两帧精确对拍已接通。
- 仓库记录两轮 make test-p2-blc 通过，以及故意破坏输出时的失败传播。
- GitHub 当前没有附着到最新提交的状态检查，因此上述通过结果来自仓库保存的本地 VCS 验收记录，并不是独立的 GitHub Actions 再执行结果。

本轮审阅未发现阻断 P3 的已确认功能错误。

需要在 P3 一并处理的非阻断问题：

1. config/default.yaml 当前把 awb_gain、demosaic、ccm、rgb2ycbcr 都设为 true，但后三级仍未实现，配置语义会误导读者。P3 必须把“实现状态”和默认 enable 对齐。
2. 当前 rtl/raw_domain/awb_gain.sv 只是占位模块，只有 data/valid，没有坐标和帧标志，且 FRAC_W=8 尚未冻结。P3 不沿用其数值格式，重新定义明确的固定点契约。
3. P2 的正式 isp_pipeline_top 将在 P3 增加一级流水。为保留 P2 历史回归，P3 需要建立稳定的 BLC-only 顶层边界，不能直接把旧 P2 测试整体后移一拍。

---

## 1. P3 完成定义

以下条件全部满足才算 P3 完成：

- [ ] make test-p0-p1 继续通过，Reader-only C2 时序不变。
- [ ] make test-p2-blc 继续通过，BLC-only C3 时序不变。
- [ ] 软件侧新增精确整数 AWB Gain 黄金模型。
- [ ] RTL 能根据 RGGB 坐标奇偶正确选择 R/G/B 增益，两个绿色位置使用同一个 gain_g。
- [ ] gain_r/gain_g/gain_b 采用冻结的无符号 UQ4.12 固定点格式。
- [ ] 乘法结果采用 round-half-up（正数四舍五入）后右移 12 位。
- [ ] 超过 RAW12 最大值 4095 的结果饱和为 4095，不允许回绕。
- [ ] AWB Gain 固定为一级寄存输出，稳定后仍为每周期 1 像素吞吐。
- [ ] data、x/y、valid、sof/eol/frame_done 全部严格对齐。
- [ ] 三个增益只在有效 sof 帧首采样；第一像素使用本帧新配置；帧中变化不影响当前帧。
- [ ] isp_pipeline_top 变为 SRAM → Reader → BLC → AWB Gain。
- [ ] 顶层第一个最终像素为 C4，最后一个最终像素为 C(N+3)，busy 在 C(N+4) 清零。
- [ ] 至少四类 16×16 图案、每类两帧，与 Python 全链黄金结果逐像素完全一致。
- [ ] 至少一组测试明确覆盖 R、Gr、Gb、B 四个拜耳位置，证明两个 G 位置使用同一 gain_g。
- [ ] 至少覆盖 unity、0.5、非整数增益、零增益和输出饱和。
- [ ] 故意损坏输出时完整 P3 命令必须失败并定位首个差异。
- [ ] config/default.yaml 不再把未实现算法默认标成启用。
- [ ] README、fixed_point、design_decisions、verification、architecture 和计划执行记录同步。
- [ ] 不实现 Raw NR、Demosaic、CCM、完整 AWB 估计或总线寄存器。

---

## 2. 数值契约

### 2.1 增益格式

P3 固定：

- 像素：无符号 RAW12，0..4095。
- 增益寄存器：16 位无符号 UQ4.12。
- FRAC_W = 12。
- 1.0 的编码值为 4096，即 0x1000。
- 最大编码 65535 对应约 15.9998。

UQ4.12 表示 4 个整数位和 12 个小数位的无符号固定点数。

不使用浮点数作为 RTL 或黄金文件之间的交换格式。

### 2.2 Bayer 位置

基线 Bayer pattern（拜耳排列）固定为 RGGB：

- y[0]=0 且 x[0]=0：R。
- y[0]=0 且 x[0]=1：G。
- y[0]=1 且 x[0]=0：G。
- y[0]=1 且 x[0]=1：B。

其中 x[0] 表示列坐标最低位，y[0] 表示行坐标最低位；0/1 分别代表偶数/奇数坐标。

P3 不支持其他 Bayer 排列，也不增加 pattern 可编程参数。

### 2.3 乘法

先选择当前像素颜色 c 对应的增益编码 G_c：

M = P_in × G_c

其中，M 表示未缩放乘积；P_in 表示 BLC 输出的 RAW12 像素；G_c 表示当前 R、G 或 B 通道的 UQ4.12 增益编码；符号“×”表示整数乘法；符号“=”表示左右数值相等。

12 位像素乘 16 位增益至少需要 28 位无符号乘积保存，不允许先截断。

### 2.4 舍入

采用正数 round-half-up：

S = (M + 2^(F-1)) >> F

其中，S 表示去掉固定点小数位后的整数结果；M 表示完整乘积；F 表示小数位数，本阶段 F=12；2^(F-1) 表示舍入常数，本阶段为 2048；符号“+”表示加法；“>>”表示逻辑右移；符号“=”表示左右数值相等。

因此 0.5 像素的正好中点向上取整。例如像素 1 乘 0.5 增益，缩放前对应 0.5，最终输出 1。

### 2.5 饱和

P_out = min(S, 4095)

其中，P_out 表示最终 RAW12 输出；S 表示舍入后的整数；min(a,b) 表示取较小值；4095 是 RAW12 最大值；符号“=”表示左右数值相等。

只做上限饱和；输入和增益均为非负，因此不会出现负值。

---

## 3. 帧配置契约

AWB Gain 有三个外部配置：

- gain_r
- gain_g
- gain_b

三者都只在 in_valid=1 且 in_sof=1 时采样。

首像素必须直接使用该拍外部新增益，而不能因为非阻塞赋值而误用上一帧锁存值。

当前帧中途修改任一 gain，不影响当前帧。

下一帧有效 sof 到来时三个增益一起更新，保证帧级原子性。

复位后锁存增益建议回到 unity，也就是 4096，而不是 0。这样复位后若出现不规范的非 sof 有效像素，不会被无意乘成全黑；正式帧仍必须依赖 sof 更新配置。

如果 Codex 选择复位为 0，必须先修改本计划并解释理由，不能静默改变。

---

## 4. 流水契约

P3 的 AWB Gain 固定为一级寄存输出。

输入周期 T 的有效像素，在 T+1 输出对应结果。

其中，T 表示某个时钟周期编号；“+”表示周期编号加一；T+1 表示下一个周期。

一级内允许组合完成：

坐标奇偶译码 → 三选一增益 → 12×16 乘法 → 舍入 → 饱和 → 输出寄存

本阶段没有目标时钟频率，因此不声称该组合路径满足某个 Fmax（最大工作频率）。如果后续综合显示时序不足，再通过独立计划重定时；P3 不预先增加第二级流水。

与数据一起延迟一拍：

- valid
- x
- y
- sof
- eol
- frame_done

无效输出周期：

- out_valid=0
- out_sof=0
- out_eol=0
- out_frame_done=0
- payload/坐标可以保持上一值

---

## 5. 稳定里程碑边界

P3 必须保留：

- P0/P1：sram_raw_source
- P2：BLC-only 完整链路

推荐新增：

rtl/top/blc_pipeline.sv

把当前 P2 isp_pipeline_top 的实现等价迁移为 blc_pipeline，接口与 P2 公开接口保持一致。

原 P2 集成测试改为实例化 blc_pipeline，所有 P2 C3/C(N+2)/C(N+3) 断言不变。

新的 isp_pipeline_top 再实现：

SRAM → blc_pipeline → awb_gain → final RAW stream

如果使用不同结构，也必须满足：P2 历史周期和控制回归可独立运行，不能简单把旧 P2 期望整体后移一拍。

---

# Step 0 — 重新验证 P2 基线

- [x] 回读 plans/002_p2_blc.md。
- [x] 回读当前 blc、isp_pipeline_top、awb_gain 占位代码和 Makefile。
- [x] make clean。
- [x] make test-p2-blc。
- [x] 保存当前 VCS/Python/NumPy 版本。
- [x] 确认工作区干净。

验收：任何 P3 修改前，完整 P2 必须 PASS。

建议提交：无。

---

# Step 1 — 冻结 P3 数值、接口与配置语义

修改：

- docs/fixed_point.md
- docs/design_decisions.md
- docs/architecture.md
- docs/verification.md
- config/default.yaml

动作：

- [x] 写入 UQ4.12、round-half-up、RAW12 saturation 契约。
- [x] 明确本模块只是 AWB Gain，不是完整自动白平衡估计。
- [x] 明确 RGGB 位置译码。
- [x] 明确一级寄存延迟和帧首采样三增益。
- [x] 清理 config/default.yaml：未实现的 demosaic、ccm、rgb2ycbcr 必须 false。
- [x] P3 完成后的默认使能只反映已经实现的 BLC 和 AWB Gain。
- [x] AWB 配置改为明确的寄存器编码值，建议：
  - r: 4096
  - g: 4096
  - b: 4096
  并标注格式 UQ4.12。

验收：文档能独立回答 gain=1.0 如何编码、如何舍入、如何饱和、如何判断 R/G/B，以及中途改 gain 何时生效。

建议提交信息：

docs: freeze P3 AWB gain fixed-point contract

---

# Step 2 — 建立 Python AWB Gain 黄金模型

新增：

- model/awb_gain.py
- model/tests/test_awb_gain.py

修改：

- model/isp_model.py
- 必要时 model/README.md

建议 API：

- scale_pixel(pixel, gain_code, frac_bits=12)
- apply_awb_gain(raw_2d, gain_r, gain_g, gain_b)

要求：

- 全程整数运算。
- 中间结果使用足够宽的有符号或无符号整数，禁止 uint16 乘法后溢出。
- 只支持二维 RGGB 数组作为完整 Bayer 图输入。
- 输出 uint16，数值严格在 0..4095。
- run_pipeline 顺序变成：BLC → AWB Gain。

至少测试：

- unity：4096。
- zero：0。
- half：2048。
- 1.5：6144。
- 2.0：8192。
- 最大增益 65535。
- 中点舍入：1 × 2048 最终为 1。
- 饱和：4095 × 8192 最终为 4095。
- 2×2 RGGB 四位置，R/G/G/B 使用正确增益。
- 两个 G 位置输出遵循同一 gain_g。
- 非法像素范围、非法增益范围、非二维输入失败。

建议提交信息：

model: add exact RGGB AWB gain reference

---

# Step 3 — 保留稳定 BLC-only 顶层

新增：

- rtl/top/blc_pipeline.sv

调整：

- P2 集成测试及脚本改为编译 blc_pipeline。
- 当前 P2 行为、周期、busy/start 语义不得变化。

isp_pipeline_top 在本步骤可暂时只包装 blc_pipeline，确保重构本身不引入功能变化。

验收：

- make test-p0-p1 PASS。
- make test-p2-blc PASS。
- P2 第一个输出仍为 C3。
- P2 最后输出仍为 C(N+2)，busy C(N+3) 清零。

建议提交信息：

refactor: preserve verified BLC pipeline boundary

---

# Step 4 — 实现 RTL AWB Gain

重写：

- rtl/raw_domain/awb_gain.sv

建议参数：

- PIXEL_W=12
- GAIN_W=16
- FRAC_W=12

接口至少包含：

输入：

- clk/rst_n
- in_valid
- in_pixel
- in_x/in_y
- in_sof/in_eol/in_frame_done
- gain_r/gain_g/gain_b

输出：

- out_valid
- out_pixel
- out_x/out_y
- out_sof/out_eol/out_frame_done

不再依赖独立 bayer_phase 输入；相位由 in_x[0] 和 in_y[0] 直接确定，避免坐标和 phase 两套信息不一致。

要求：

- [x] valid+sof 同时锁存三路增益。
- [x] 首像素直接使用当拍新 gain。
- [x] 帧内变化被忽略。
- [x] RGGB 四位置选择正确。
- [x] 乘积保留完整位宽。
- [x] 加 2048 后右移 12 位完成 round-half-up。
- [x] 大于 4095 饱和为 4095。
- [x] 固定一级寄存输出。
- [x] 全部侧带同拍。
- [x] 无效周期标志归零。
- [x] 可综合路径不使用 testbench system task。
- [x] 不实现 gain 自动估计。

建议提交信息：

rtl: implement fixed-point RGGB AWB gain stage

---

# Step 5 — 建立 AWB Gain 自检查单元测试

新增：

- tb/unit/tb_awb_gain.sv
- 对应运行脚本或 Make 入口

必须覆盖：

- 2×2 RGGB 四相位。
- 两个绿色位置相同 gain_g。
- unity/zero/0.5/1.5/2.0/最大增益。
- 精确半值舍入。
- 饱和边界 4094/4095 及超过满量程。
- 连续 valid。
- valid 空洞。
- sof/eol/frame_done 一拍对齐。
- 连续 1×1 帧，不同三路 gain。
- 第一像素使用新配置。
- 帧中改变全部 gain 不影响当前帧。
- 下一帧使用新配置。
- 同步复位。

测试期望必须使用独立整数公式，不读取 DUT 内部寄存器。

建议提交信息：

test: add self-checking AWB gain unit regression

---

# Step 6 — 接入正式 isp_pipeline_top

结构：

SRAM → sram_raw_source → BLC → AWB Gain → output

推荐实际层级：

isp_pipeline_top
  ├─ blc_pipeline
  └─ awb_gain

外部增加：

- gain_r
- gain_g
- gain_b

当前最终 top 时序应为：

- Reader 第一个 RAW：C2。
- BLC 第一个输出：C3。
- AWB 第一个最终输出：C4。
- Reader 最后 RAW：C(N+1)。
- BLC 最后输出：C(N+2)。
- AWB 最后输出：C(N+3)。
- 顶层 busy 在 C(N+3) 仍为 1。
- 顶层 busy 在 C(N+4) 为 0。

其中，N 表示帧像素数；“+”表示周期编号加法。

顶层必须基于“整条流水线 busy”过滤新的 start，AWB-only drain 周期的启动脉冲必须被忽略，保持高电平跨越完成也不能自动重启。

建议提交信息：

rtl: integrate AWB gain into ISP pipeline

---

# Step 7 — 端到端全链黄金对拍

新增/修改：

- 生成 P3 golden 的 Python CLI
- tb/integration/tb_awb_pipeline.sv
- scripts/run_awb_pipeline.sh
- Makefile

黄金文件必须从原始 SRAM 输入出发，经 Python：

BLC → AWB Gain

生成，不能只对 AWB 单阶段复制 RTL 公式。

建议四图案两帧配置：

1. addr_ramp
   - frame0：BLC=64，R=6144，G=4096，B=8192
   - frame1：BLC=128，R=4096，G=5120，B=2048

2. flat
   - frame0：BLC=1024，R=8192，G=4096，B=6144
   - frame1：BLC=64，R=4096，G=4096，B=4096

3. checker
   - frame0：BLC=512，R=65535，G=2048，B=4096
   - frame1：BLC=4095，任意合法 gain，验证全零结果仍正确

4. gradient
   - frame0：BLC=256，R=4097，G=6144，B=8192
   - frame1：BLC=0，R=2048，G=4096，B=5120

所有 gain 数字都是 UQ4.12 编码，不是十进制浮点倍数。

必须逐像素检查：

- 数值
- x/y
- sof/eol/frame_done
- 帧长度
- busy 时序
- 两帧配置切换
- 中途配置扰动不影响当前帧

建议提交信息：

test: add end-to-end AWB gain golden comparison

---

# Step 8 — 一键回归、负例与收尾

Make 至少提供：

- make test-p0-p1
- make test-p2-blc
- make test-awb-model
- make test-awb-unit
- make test-awb-pipeline
- make test-p3-awb
- make compare-p3-awb
- make clean

test-p3-awb 必须先回归 P0/P1 和 P2，再执行 P3。

负例至少包含：

- 强制 RTL fatal。
- 缺失 golden。
- 故意损坏某个实际输出像素。
- 如果黄金生成失败，不得继续使用旧 golden。

最终：

make clean
make test-p3-awb

连续两次通过，确定性文件哈希一致。

更新：

- README.md
- docs/architecture.md
- docs/fixed_point.md
- docs/design_decisions.md
- docs/verification.md
- config/default.yaml
- plans/003_p3_awb_gain.md
- plans/README.md

README 只能声明当前实现到：

SRAM → Reader → BLC → AWB Gain

不得写成完整自动白平衡或完整 ISP 已完成。

建议提交信息：

docs: close P3 AWB gain milestone

---

## 6. 本轮明确不做

- AWB 统计。
- Gray World（灰度世界）增益估计。
- 白点检测。
- 色温估计。
- 四通道 R/Gr/Gb/B 独立增益；P3 两个 G 共用 gain_g。
- Raw NR。
- Demosaic。
- CCM。
- RGB/YCbCr。
- Cortex-M0/AHB 控制。
- 真实大图视觉展示。
- 综合、布局布线、时序收敛或 PPA 结论。

---

## 7. 重点易错项

- [ ] 把 gain 的 4096 当成 4096 倍，而不是 UQ4.12 的 1.0。
- [ ] 12×16 乘法结果被 16 位变量截断。
- [ ] 直接右移导致始终向下截断，没有加 2048 舍入。
- [ ] 舍入后超过 4095 回绕而不是饱和。
- [ ] Gr/Gb 相位选错。
- [ ] x/y 与像素数据错一拍，导致 Bayer 相位错色。
- [ ] 第一像素仍使用上一帧 gain。
- [ ] 帧中外部 gain 变化渗入当前帧。
- [ ] gain=1.0 时数值正确，但模块为了“优化”变成零延迟，破坏固定时序。
- [ ] P2 旧测试被整体后移一拍而失去历史边界。
- [ ] 顶层 busy 在 AWB 最后一拍提前清零。
- [ ] Python 使用 float，RTL 使用定点，造成边界像素无法精确对拍。
- [ ] config/default.yaml 继续把未实现模块标成 true。

---

## 8. 执行记录

Codex 每完成一步更新实际提交哈希。

| Step | 状态 | 提交 | 验证命令 | 备注 |
|---|---|---|---|---|
| 0 | 完成 | 0ef032e | make clean; make test-p2-blc | 当前 HEAD 全回归 PASS；版本存于 reports/p3_awb_execution |
| 1 | 完成 | 6e9ca6461d5da3a9fd108914b678d76a65bed742 | git diff --check; manual contract review | UQ4.12、RGGB、帧首采样和一级流水已明确；AWB 待最终验收启用 |
| 2 | 完成 | ef9813e18748307c942526a22c07cc891891aad5 | make test-blc-model test-awb-model | 11 项 P2 + 7 项 AWB 测试；11 个边界增益穷举全部 RAW12 |
| 3 | 完成 | 559d387fae4d9e5653da594b8930e83dc298a6a9 | make test-p2-blc | P0/P1 + P2 全通过；源码等价迁移，C3 断言未修改 |
| 4 | 完成 | bcc9c0e6823169ccfc7a33e54755972291cfa77a | VCS W-2024.09 +define+SYNTHESIS compile; RTL review | 28 位乘积、29 位偏置和宽位饱和；分类寄存器、无 function |
| 5 | 未开始 | — | — | — |
| 6 | 未开始 | — | — | — |
| 7 | 未开始 | — | — | — |
| 8 | 未开始 | — | — | — |

---

## 9. 下一阶段入口条件

P3 全部验收完成后再规划下一阶段。

默认建议优先进入 Demosaic（去马赛克），因为它会首次引入行缓存、邻域窗口和边界处理，是从逐像素 ISP 模块进入空间滤波硬件结构的关键台阶。

Raw NR 仍可保持旁路，待基础 RGB 链路跑通后再单独插回原始域并验收。