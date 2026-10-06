# 004 — P4：3×3 流式窗口 + 双线性 Demosaic 去马赛克

目标读者：Codex（代码代理）

状态：执行中

本轮目标：在已经通过 P0/P1、P2、P3 验收的 SRAM → Reader → BLC → AWB Gain RAW 链路之后，加入第一个真正的邻域算法模块 Demosaic（去马赛克），完成 RAW12 RGGB → RGB12 的转换。

本轮重点不只是“写一个插值公式”，而是建立后续 Raw NR、EE 等空间算法都会复用的硬件基础：

- 行缓存/行存储；
- 3×3 邻域窗口；
- 图像边界处理；
- 输入帧与输出帧时序重新对齐；
- RAW 单通道流到 RGB 三通道流的接口切换；
- 尾部排空；
- RGB 黄金模型与逐像素精确比较。

本轮不实现 Raw NR、CCM、Gamma、CSC、YCbCr 或 Cortex-M0/AHB。

---

## 0. P3 审阅结论与当前基线

P3 最终记录提交：

c75cba182f942d4d8337a885ce5b7e8f9fd7ed66

已确认的远程仓库事实：

- P3 从计划索引提交 0ef032e 向前推进 16 个提交，按步骤保留实现与验收记录。
- AWB Gain 已采用 16 位 UQ4.12、完整 28 位乘积、+2048 后右移 12 位、RAW12 饱和。
- RGGB 相位直接来自 x/y 奇偶，两个绿色位置共用 gain_g。
- 三路 gain 只在 valid+sof 采样，首像素使用当前帧新配置。
- 新增 blc_pipeline，保留 P2 的 BLC-only C3 边界；正式 top 当前为 SRAM → Reader → BLC → AWB Gain。
- 仓库记录连续两轮 make test-p3-awb PASS、单元穷举、全链黄金对拍和失败注入恢复。
- config/default.yaml 已只启用当前实际实现的 BLC 与 AWB Gain。
- 最新 GitHub commit 没有附着独立 CI status；验收证据来自仓库记录的本机 VCS 回归，而不是本次审阅环境重新执行。

本轮代码审阅没有发现阻断 P4 的已确认功能错误。

非阻断问题：

1. model/isp_model.py 的 docstring 仍写“执行当前已实现的 BLC”，已经落后于实际 BLC → AWB 链路，P4 文档整理时修正。
2. rtl/raw_domain/demosaic.sv 和 rtl/common/window_3x3.sv 仍是占位代码，接口不足以表达完整坐标、帧标志和尾部排空。
3. 当前全链 top 输出还是单路 RAW12；P4 后将正式切换为 RGB12 三通道输出，因此必须保留独立 AWB-only 历史边界，不能直接改旧 P3 测试的接口和周期判据。

---

## 1. P4 算法选择

P4 选择最基础、可解释、可精确验证的 **3×3 双线性 Demosaic**。

这是本次复现的工程基线，不声称原实习实现使用了同一种插值算法。

本轮不直接上 5×5 Malvar-He-Cutler。原因：

- 本阶段第一次引入行缓存和邻域窗口；
- 先把窗口、边界、尾部排空和三通道接口做稳；
- 5×5 算法需要更多行缓存、带符号卷积和更复杂系数，适合作为后续图像质量升级，而不是第一次窗口硬件的同时引入。

输入 Bayer pattern 固定为 RGGB。

---

## 2. 双线性 Demosaic 数值契约

记 3×3 窗口为：

A B C
D E F
G H I

其中 E 是当前待输出中心像素；A/B/C 是上一行左/中/右邻居；D/F 是当前行左/右邻居；G/H/I 是下一行左/中/右邻居。

所有输入都是 RAW12 无符号整数 0..4095。

### 2.1 中心为 R

R = E

G = (B + D + F + H + 2) >> 2

B = (A + C + G + I + 2) >> 2

其中，R/G/B 分别表示输出红、绿、蓝通道；A..I 表示窗口内 RAW12 样本；“+”表示整数加法；“>> 2”表示逻辑右移 2 位，相当于除以 4 后取整；额外的 +2 表示正数 round-half-up（四舍五入）；“=”表示左右数值相等。

### 2.2 中心为 B

B = E

G = (B + D + F + H + 2) >> 2

R = (A + C + G + I + 2) >> 2

符号定义与上一节一致。

### 2.3 中心为 Gr（R 行上的 G）

G = E

R = (D + F + 1) >> 1

B = (B + H + 1) >> 1

其中，“>> 1”表示逻辑右移 1 位，相当于除以 2 后取整；额外的 +1 表示正数 round-half-up。

### 2.4 中心为 Gb（B 行上的 G）

G = E

R = (B + H + 1) >> 1

B = (D + F + 1) >> 1

### 2.5 位宽

- 两项和最大为 8190，加 1 最大 8191，需要 13 位。
- 四项和最大为 16380，加 2 最大 16382，需要 14 位。
- 平均结果不会超过 4095，因此正确扩展后不需要额外上限饱和。

不能先用 12 位变量求和再移位。

---

## 3. 边界策略

P4 输出尺寸必须与输入相同，不裁掉 1 像素边框。

采用 **mirror/reflect 边界**，对 3×3 只需要处理距离边界 1 个像素的情况。

对于宽 W、高 H，且 W>=2、H>=2：

- x=-1 映射到 x=1。
- x=W 映射到 x=W-2。
- y=-1 映射到 y=1。
- y=H 映射到 y=H-2。

其中，x/y 是访问邻居时的坐标；W/H 分别表示帧宽和高；“映射”表示使用对应的镜像像素代替越界像素。

该策略有两个目的：

1. 保持输出尺寸 W×H 不变；
2. 镜像一步保持 Bayer 奇偶相位，不会像直接 clamp 到边缘中心像素那样把缺失 G/B 邻居错误替换成另一种颜色相位。

P4 正式 RGB top 只接受 W>=2、H>=2。

P0/P1/P2/P3 保存的旧边界仍继续支持原有小帧测试；这是新 Demosaic stage 的输入约束，不得通过修改旧里程碑来“统一”掉。

---

## 4. 3×3 窗口硬件契约

重写 rtl/common/window_3x3.sv，作为可复用模块。

### 4.1 输入

至少包含：

- clk/rst_n
- in_valid
- in_pixel
- in_x/in_y
- in_sof/in_eol/in_frame_done
- frame_width
- frame_height

frame_width/frame_height 必须来自 top 在整帧 start 被接受时锁存的稳定尺寸，不能直接使用外部可能 mid-frame 改变的 image_width/image_height。

### 4.2 输出

至少包含：

- out_valid
- 9 个 RAW12 window sample
- center_x/center_y
- out_sof/out_eol/out_frame_done
- busy 或 flushing 状态

### 4.3 存储边界

P4 的窗口模块不得保存整帧。

允许为了 correctness-first 使用最多 3 行 RAW12 行存储，并通过行角色轮转实现。

默认 MAX_WIDTH 建议 4096。

不在 P4 声称已经做到“最省两行缓存”或 BRAM 最优映射；如果综合阶段需要，再独立优化到典型 2-line-buffer 结构。

### 4.4 输出顺序

必须输出恰好 W×H 个窗口，中心坐标严格光栅顺序：

(0,0), (1,0), ... (W-1,0), (0,1), ... (W-1,H-1)

其中 W×H 表示宽乘以高；“×”表示乘法。

输入正常帧要求 valid 像素连续，无 backpressure。

可以有启动 warm-up 和 frame_done 后的 tail flush，但从第一个 out_valid 到最后一个 out_valid，要求连续每拍 1 个窗口。

### 4.5 推荐的流式调度

推荐使用以下调度，便于保持输出光栅顺序：

- 输入到 (1,1) 后，首次具备输出 (0,0) 的完整镜像窗口。
- 当输入坐标 x>=1、y>=1 时，常规输出中心 (x-1,y-1)。
- 当输入进入下一行 x=0 且 y>=2 时，输出上一输出行的最右像素。
- 输入 frame_done 后继续 tail：
  1. 输出倒数第二行最右像素；
  2. 依次输出最后一行 x=0..W-1。
- 最后一个窗口的 out_frame_done 与 (W-1,H-1) 同拍。

如果 Codex 采用不同内部调度，只要满足完整输出、光栅顺序、连续吞吐、边界结果完全一致即可；必须在计划执行记录中解释。

---

## 5. Demosaic 模块流契约

rtl/raw_domain/demosaic.sv 应内部实例化或消费 window_3x3，不再保留当前占位接口。

最终输出：

- out_valid
- out_r/out_g/out_b，均为 RGB12
- out_x/out_y
- out_sof/out_eol/out_frame_done
- busy

Demosaic 算术部分再使用一级输出寄存。

因此整个 Demosaic subsystem 包含：

输入 RAW stream
→ 行存储/3×3 window
→ Bayer phase decode
→ 双线性整数平均
→ RGB 输出寄存

一旦第一 RGB 像素输出后，必须连续每拍输出 1 个 RGB 像素直到 frame_done。

---

## 6. RGB 黄金文件格式

P0-P3 的 RAW compare 工具保持不变。

P4 新增独立 RGB 比较工具，不修改旧 RAW12 文件格式。

建议每个像素一行 36 位十六进制：

RRRGGGBBB

其中 RRR/GGG/BBB 各为 3 个十六进制字符，对应 12 位 R/G/B。

逻辑打包关系：

rgb36 = (R << 24) | (G << 12) | B

其中，rgb36 表示 36 位打包字；R/G/B 分别表示 12 位通道；“<<”表示左移；“|”表示按位或；“=”表示打包结果定义。

新增 compare_rgb_output.py 应检查：

- 每行恰好 9 个十六进制字符；
- R/G/B 各自都在 0..4095；
- 数量恰好 W×H；
- 首个错误报告 index、x/y、expected RGB、actual RGB；
- 成功返回 0，失败非 0。

---

## 7. 稳定历史边界

P4 必须保留：

- sram_raw_source：P0/P1 Reader-only。
- blc_pipeline：P2 BLC-only。
- 新增 awb_pipeline：P3 AWB-only。

推荐：

1. 将当前 P3 isp_pipeline_top 的实现等价迁移为 rtl/top/awb_pipeline.sv。
2. P3 测试改为实例化 awb_pipeline，原 C4、busy/start 判据不变。
3. 新的 isp_pipeline_top 才加入 demosaic，并把公开像素接口切成 RGB。

不允许直接把 P3 旧测试接口改成 RGB 后声称 P3 回归仍通过。

---

# Step 0 — 重新验证 P3 基线

- [x] 回读 plans/003_p3_awb_gain.md。
- [x] 回读 awb_gain、isp_pipeline_top、demosaic/window 占位文件。
- [x] make clean。
- [x] make test-p3-awb。
- [x] 记录 VCS/Python/NumPy 版本。
- [x] 确认工作区干净。
- [x] 记录最新 P3 HEAD。

验收：任何 P4 修改前，完整 P3 必须 PASS。

建议提交：无。

---

# Step 1 — 冻结 P4 算法、边界与 RGB 接口

修改：

- docs/architecture.md
- docs/pipeline.md
- docs/fixed_point.md
- docs/design_decisions.md
- docs/verification.md
- config/default.yaml
- model/isp_model.py 的过时说明

动作：

- [x] 写入 3×3 bilinear 公式和位宽。
- [x] 明确 mirror border。
- [x] 明确 W>=2、H>=2。
- [x] 明确 P4 输出 RGB12。
- [x] 明确本阶段不是 Malvar-He-Cutler。
- [x] config.default 仍保持 demosaic=false，直到 Step 8 完整验收后才改为 true。

建议提交信息：

docs: freeze P4 bilinear demosaic contract

---

# Step 2 — Python Demosaic 黄金模型

新增：

- model/demosaic.py
- model/tests/test_demosaic.py

修改：

- model/isp_model.py

建议 API：

apply_demosaic(raw_2d)

返回 shape=(H,W,3) 的 uint16 RGB12。

要求：

- 只接受非空二维 RAW12。
- W/H 小于 2 明确失败。
- 固定 RGGB。
- mirror 边界和 RTL 完全一致。
- 全程整数运算。
- run_pipeline 顺序变为 BLC → AWB Gain → Demosaic。

必须测试：

- 2×2、3×2、2×3、3×5、4×4。
- 常量 RGB 场 mosaicing 后应精确恢复常量 RGB。
- R/Gr/Gb/B 四类中心。
- 左右上下四边和四角。
- /2、/4 舍入中点。
- RAW12 最大值。
- 非法维度/数据失败。

建议提交信息：

model: add exact bilinear demosaic reference

---

# Step 3 — 完成合成 RGB/Bayer 工具与 RGB compare

修改/新增：

- 完成 tools/rgb_to_bayer.py
- 新增 tools/compare_rgb_output.py
- 新增对应 Python tests
- 可完善 tools/mem_to_image.py，支持 RGB36 → PPM 预览，不新增 Pillow 依赖

rgb_to_bayer 至少支持 NumPy RGB12 数组到 RGGB RAW12。

建议增加确定性颜色模式：

- constant_rgb
- rgb_gradient
- color_blocks
- edge_pattern

数值比较仍是正式验收；PPM 只作人工预览。

建议提交信息：

tools: add deterministic RGB Bayer and compare utilities

---

# Step 4 — 保留稳定 AWB-only 边界

新增：

- rtl/top/awb_pipeline.sv

调整 P3 集成测试和脚本只做模块名迁移，不改变原周期断言。

验收：

- make test-p0-p1 PASS。
- make test-p2-blc PASS。
- make test-p3-awb PASS。
- P3 第一个输出仍为 C4。
- P3 最后输出/busy 判据完全不变。

建议提交信息：

refactor: preserve verified AWB pipeline boundary

---

# Step 5 — 实现并验证 window_3x3

重写：

- rtl/common/window_3x3.sv

新增：

- tb/unit/tb_window_3x3.sv
- 相应 Make/script 入口

要求：

- [ ] 不保存整帧。
- [ ] 最多 3 行存储。
- [ ] 支持奇数/偶数宽度。
- [ ] mirror 四角、四边精确正确。
- [ ] 输出坐标严格 raster order。
- [ ] 恰好 W×H 个 window。
- [ ] 第一个 window 到最后一个 window 连续每拍 valid。
- [ ] tail flush 完成前 busy 保持。
- [ ] frame_done 只在最后窗口。
- [ ] reset 中止当前帧并清理 tail。
- [ ] 输入下一帧必须等 busy=0。
- [ ] width>MAX_WIDTH、W<2、H<2 明确拒绝。

测试不允许只检查中心 pixel；9 个 window sample 必须全部核对。

建议提交信息：

rtl: implement streaming mirrored 3x3 window generator

---

# Step 6 — 实现并验证 RTL Demosaic

重写：

- rtl/raw_domain/demosaic.sv

新增：

- tb/unit/tb_demosaic.sv

要求：

- [ ] 实例化/消费已验收 window_3x3。
- [ ] 按 center x/y 奇偶选择 R/Gr/Gb/B 公式。
- [ ] 13/14 位中间和，不能 RAW12 先溢出。
- [ ] /2 加 1 后右移 1。
- [ ] /4 加 2 后右移 2。
- [ ] RGB 输出一级寄存。
- [ ] x/y、valid、flags 同步。
- [ ] out_frame_done 和最后 RGB 像素同拍。
- [ ] busy 覆盖 window tail + 最终 RGB register drain。

单元测试使用 Python 生成或独立整数 oracle，不读取 DUT 内部状态。

建议提交信息：

rtl: implement bilinear RGGB demosaic

---

# Step 7 — 接入正式 RGB isp_pipeline_top

新的结构：

SRAM
→ sram_raw_source
→ BLC
→ AWB Gain
→ Demosaic
→ RGB12 output

推荐层级：

isp_pipeline_top
  ├─ awb_pipeline
  └─ demosaic

top 在接受 start 时锁存 frame_width/frame_height，提供给 demosaic。

最终 top 输出接口改为：

- pixel_valid
- pixel_r
- pixel_g
- pixel_b
- pixel_x
- pixel_y
- sof/eol/frame_done
- busy

不再用单一 pixel_data 表示最终像素。

top busy 必须覆盖 Demosaic tail flush 和最后一级 RGB register。

Demosaic busy 未清零时：

- 新 start pulse 被忽略；
- held-high start 不能在 busy 解除后自动重启；
- 外部 width/height/config 改变不得污染当前帧。

建议提交信息：

rtl: integrate demosaic into RGB ISP pipeline

---

# Step 8 — 全链 RGB 黄金对拍

新增：

- model/generate_demosaic_golden.py
- tb/integration/tb_demosaic_pipeline.sv
- scripts/run_demosaic_pipeline.sh
- Make targets

黄金必须从原始 Bayer 输入经过 Python：

BLC → AWB Gain → Demosaic

生成 RGB36。

正式至少覆盖：

1. constant_rgb 16×16
2. rgb_gradient 16×16
3. color_blocks 16×16
4. edge_pattern 16×16

每种至少两帧，第二帧改变 BLC/AWB 配置。

此外必须有实际尺寸控制测试：

- 2×2
- 3×2
- 2×3
- 3×5
- 4×4

检查：

- 输出恰好 W×H。
- 坐标从 (0,0) 到 (W-1,H-1) raster order。
- 每行 eol 一次。
- sof 一次。
- frame_done 一次。
- 从第一个 pixel_valid 到最后一个 pixel_valid 无气泡。
- 输入 frame_done 后 tail 期间 busy 仍为 1。
- tail 期间 start pulse 不重启。
- 中途改 image dimensions/config 不污染当前帧。
- RGB 数值与 Python 精确一致。

建议提交信息：

test: add end-to-end RGB demosaic golden comparison

---

# Step 9 — 一键回归、负例和收尾

Make 至少提供：

- make test-p0-p1
- make test-p2-blc
- make test-p3-awb
- make test-window-3x3
- make test-demosaic-model
- make test-demosaic-unit
- make test-demosaic-pipeline
- make test-p4-demosaic
- make compare-p4-demosaic
- make clean

test-p4-demosaic 必须先完整回归 P0-P3。

负例至少包含：

- 强制 window/demosaic fatal。
- 缺失 RGB golden。
- 故意损坏一个 R/G/B 通道值。
- golden 生成失败时旧 golden 必须删除。
- 非法 width<2 / height<2 / width>MAX_WIDTH 不得误启动。

最终：

make clean
make test-p4-demosaic
make test-p4-demosaic

连续两轮 PASS，确定性输入/golden/actual 哈希一致。

Step 9 完成后：

- config/default.yaml demosaic 改为 true。
- README 明确当前已实现：
  SRAM → Reader → BLC → AWB Gain → Bilinear Demosaic → RGB12。
- 不得写成完整 ISP 已完成。
- 不得声称已经综合、达到某个 Fmax 或 BRAM/DSP 数量，除非真的执行综合。

建议提交信息：

docs: close P4 bilinear demosaic milestone

---

## 8. 本轮明确不做

- Raw NR。
- 5×5 Malvar-He-Cutler。
- Edge-aware demosaic。
- CCM。
- Gamma。
- CSC / YCbCr。
- HDMI。
- Cortex-M0/AHB。
- 真实相机大 RAW 的图像质量调参。
- FPGA 综合、时序收敛和 PPA 结论。
- 把 3 行 correctness-first 存储优化成最小 2-line-buffer BRAM 结构。

---

## 9. 重点易错项

- [ ] 把 Bayer R/Gr/Gb/B 相位判断反。
- [ ] x/y 和 3×3 window 中心错一拍。
- [ ] 12 位直接做四项和导致溢出。
- [ ] /2、/4 直接截断，没有 round-half-up。
- [ ] 左右边界使用 clamp，破坏 Bayer 相位，而不是本计划的 mirror。
- [ ] window 输出少一列/多一列或少最后一行。
- [ ] input frame_done 后立刻 busy=0，导致 bottom border tail 丢失。
- [ ] tail 输出顺序不是 raster order。
- [ ] 第一个 RGB 输出后出现行首气泡。
- [ ] 新一帧在 demosaic tail 尚未完成时启动。
- [ ] P3 历史测试被直接改成 RGB 接口，失去 AWB-only 边界。
- [ ] Python 和 RTL 对 border 采用不同映射。
- [ ] compare 工具只比较 packed word，不指出具体 R/G/B 哪个通道错。

---

## 10. 执行记录

Codex 每完成一步更新实际提交哈希。

| Step | 状态 | 提交 | 验证命令 | 备注 |
|---|---|---|---|---|
| 0 | 完成 | 3c5e140ce36f7253ba0100225c52eebc67aa916e | make clean; make test-p3-awb | 当前版本完整 PASS；版本/日志见 reports/p4_demosaic_execution |
| 1 | 完成 | 80d1225 | git diff --check; contract review | 接口、reflect、位宽和输出周期明确；默认仍关闭 |
| 2 | 完成 | 709c6c4 | make test-blc-model test-awb-model test-demosaic-model | 旧22项及新6项模型测试 PASS |
| 3 | 完成 | 66c1507 | make test-tools test-demosaic-tools | 旧11项和新6项工具测试 PASS；RGB 文件严格校验 |
| 4 | 完成 | 43dc99b | make test-p3-awb; exact migration check | 完整 P0-P3 PASS；C4 与全部旧周期断言保留 |
| 5 | 未开始 | — | — | — |
| 6 | 未开始 | — | — | — |
| 7 | 未开始 | — | — | — |
| 8 | 未开始 | — | — | — |
| 9 | 未开始 | — | — | — |

---

## 11. 下一阶段入口条件

只有 P4 全部验收完成后再规划 P5。

默认下一阶段进入 CCM（Color Correction Matrix，颜色校正矩阵），因为 P4 已经首次得到 RGB12 三通道流；随后可以建立 3×3 颜色矩阵乘加、带符号定点系数、舍入和饱和。

Raw NR 继续暂时旁路，待 RAW→RGB→CCM 主链稳定后再作为独立原始域里程碑插回并回归。

## 当前版本执行补充

- 从当前 HEAD 3c5e140 向前实施，不切换历史冻结提交。
- 三行同步写/组合读，当前样本前递；行首先读旧行再覆盖，末行不轮转。
- 窗口输出一级寄存，RGB 再一级；首 RGB C(W+7)，末 RGB C(N+W+6)，空闲 C(N+W+7)。
- 正式 top 合法启动锁存尺寸，BLC/AWB 仍各自在 C3/C4 采样配置。
- 逐阶段回读原 Step 和本补充，完成后记录实际提交与验收，不跳过完整回归。
- 所有新 RTL 无 function；必要窗口 FSM 采用三段式，寄存器按职责分块。
