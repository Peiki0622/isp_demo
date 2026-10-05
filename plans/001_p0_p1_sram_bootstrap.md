# 001 — P0/P1：SRAM 图像输入链路可验证化

目标读者：Codex（代码代理）

状态：已完成（2026-10-05；从当前工作区推进，不恢复冻结版本）

范围：只完成 P0“测试数据工具链”与 P1“SRAM 读图链路”。本计划不实现 BLC（黑电平校正）、AWB（自动白平衡）、Demosaic（去马赛克）、CCM（颜色校正矩阵）、AHB（高级高性能总线）或 Cortex-M0。

---

## 0. 背景与执行前源码状态

开始本次执行时，当前工作区已有以下骨架（完成结果见执行记录）：

- tools/generate_patterns.py：可生成 16×16 等尺寸的合成测试数据。
- tools/raw_to_mem.py：可把 16 位小端 RAW（原始图像数据）转换成 .mem 内存初始化文件。
- tb/models/sram_model.sv：同步读 SRAM（静态随机存取存储器）模型，读数据为 1 个时钟周期延迟。
- rtl/memory/sram_reader.sv：当前只是占位实现，尚未完成地址递增、读延迟对齐、行列坐标和帧结束控制。
- rtl/top/isp_pipeline_top.sv：当前为空壳。
- tb/integration/tb_isp_pipeline.sv：当前为空壳测试平台。

本计划的任务不是继续铺骨架，而是让下面这条链路真实可运行、可自动判定对错：

Python 生成 16×16 测试图
→ .mem 内存初始化文件
→ SRAM 仿真模型
→ sram_reader
→ 像素流输出 / dump 文件
→ Python 或测试平台逐像素核对

---

## 1. 完成定义

只有同时满足以下条件，本计划才算完成：

- [x] 一条命令可以生成固定、可重复的 16×16 测试向量。
- [x] .mem 文件每行 1 个 16 位十六进制字，高 4 位为 0，有效像素为 12 位。
- [x] sram_reader 能正确处理当前 SRAM 模型的 1 周期同步读延迟。
- [x] sram_reader 从地址 0 连续读取到最后一个像素地址，不重复、不跳地址。
- [x] 输出像素顺序严格是光栅扫描顺序。
- [x] 输出 pixel_x、pixel_y、sof、eol 与 frame_done 和对应像素对齐。
- [x] 16×16 输入必须得到恰好 256 个有效输出像素。
- [x] 测试平台必须自检查：错误时自动失败，而不是靠人看波形判断。
- [x] 可以把输出像素 dump 成文本或 .mem，并和输入基准逐像素比较。
- [x] 连续执行至少两次帧读取能够正确重新开始。
- [x] busy 状态下重复给 start 不得破坏当前帧。
- [x] make test-sram-reader 或等价的单一命令能够完成：生成测试数据 → 编译 → 仿真 → 比较 → 返回成功/失败状态。
- [x] README 或验证文档里有最短可复现命令。
- [x] 本计划末尾的执行记录被 Codex 更新。

---

## 2. 当前接口约定

### 2.1 输入图像格式

阶段 P0/P1 固定为：

- Bayer（拜耳）排列：RGGB。
- 有效像素位宽：12 位无符号整数。
- SRAM 存储字宽：16 位。
- 一个 SRAM 地址保存一个像素。
- 高 4 位必须为 0。
- 地址按光栅扫描顺序排列。

像素地址关系：

addr = y × image_width + x

其中，addr 表示 SRAM 像素地址；x 表示当前像素列坐标；y 表示当前像素行坐标；image_width 表示一行的像素数；符号“×”表示乘法；符号“+”表示加法；符号“=”表示两边数值相等。

### 2.2 SRAM 时序

现有 tb/models/sram_model.sv 使用时钟上升沿寄存读数据，因此本计划固定 SRAM 为同步读、1 个时钟周期读延迟。

不要为了让 sram_reader 更容易写而把 SRAM 模型改成异步组合读。

### 2.3 像素流协议

P0/P1 暂时不引入 ready/backpressure（就绪/反压握手）。目标是固定吞吐的简单流式输出。

建议将 sram_reader 接口扩展为：

输入：
- clk
- rst_n
- start
- image_width
- image_height
- sram_rdata

输出：
- sram_addr
- busy
- pixel_valid
- pixel_data
- pixel_x
- pixel_y
- sof
- eol
- frame_done

语义必须固定如下：

- start：空闲状态下的启动上升沿；忙时的上升沿被忽略，持续拉高跨越帧结束不会重复启动。
- busy：从接受 start 后置 1，最后一个有效像素输出完成后的下一周期清 0。
- pixel_valid：当前周期 pixel_data、pixel_x、pixel_y、sof、eol 有效。
- sof：只和一帧第一个有效像素同时为 1。
- eol：和每行最后一个有效像素同时为 1。
- frame_done：和整帧最后一个有效像素同时为 1，仅保持一个周期。
- busy 状态下再次收到 start：忽略，不重启、不清计数器。
- image_width 等于 0 或 image_height 等于 0：不得开始读帧；测试平台应覆盖这一非法输入。

### 2.4 流水吞吐

在完成 SRAM 首次读延迟预热后，应做到连续每周期输出 1 个有效像素，直到一帧结束。

---

## 3. Codex 执行规则

Codex 必须按下面顺序逐步推进，不要一次性把所有步骤混在一个大改动里。

每一步都执行：

1. 先阅读该步骤列出的相关文件。
2. 只修改本步骤允许的文件，除非发现阻断问题。
3. 执行本步骤的验证命令。
4. 验证通过后再进入下一步。
5. 建议每一步形成一个独立提交。
6. 如果实际环境和本计划冲突，先记录原因，不要静默改变协议。
7. 不得为了让测试通过而降低断言强度、删除失败用例或改成肉眼检查。
8. 不得提前实现 BLC、AWB、去马赛克等下一阶段算法。

建议工作分支名：codex/p0-p1-sram-bootstrap

如果 Codex 所在环境已经为任务创建了独立分支，则沿用现有任务分支，不必强行新建。

---

# Step 0 — 基线检查与仿真器选择

## 目标

确认仓库当前状态和可用工具，不改功能。

## 检查文件

- README.md
- Makefile
- rtl/memory/sram_reader.sv
- tb/models/sram_model.sv
- tb/integration/tb_isp_pipeline.sv
- tools/generate_patterns.py

## 动作

- [x] 检查当前工作区状态并保留用户改动。
- [x] 检查 Python 3 与 NumPy。
- [x] 检查容器内现有 VCS 的路径、版本、编译和运行能力。
- [x] 仅使用本机现有 VCS，不引入其他 EDA 工具。
- [x] 用故意失败的探针确认仿真失败判据，产物集中到 build/p0_p1/。

## 验收

至少存在可用的 Python 3、NumPy 和本机 VCS，并能编译、运行 SystemVerilog。

执行调整（2026-10-05）：用户明确指定本机 VCS，禁止使用其他 EDA，替代原开源仿真器要求。本机 VCS W-2024.09 的 `$fatal(1, ...)` 探针会返回 0；所有正常测试必须同时检查进程状态、错误日志和完整验收后的唯一 PASS 标记。

执行约束：可综合 RTL 不使用 function；状态机采用状态寄存器、下一状态组合逻辑、分类输出/数据寄存器的三段式结构；端口和长代码段均须详细注释。每步开始回读本计划；清理仅限本任务生成物。

建议提交：本步骤通常无需提交。

---

# Step 1 — 冻结 SRAM Reader 行为契约

## 目标

在写状态机之前把时序行为写清楚，避免测试和实现互相迁就。

## 修改文件

- docs/memory_map.md
- docs/verification.md
- 如有必要，补充 docs/architecture.md

## 动作

- [x] 把本计划第 2 节的 SRAM 读延迟和像素流信号语义同步进正式文档。
- [x] 明确首版无反压。
- [x] 明确最后一个像素上同时产生 eol=1 和 frame_done=1。
- [x] 明确 busy 状态下 start 被忽略。
- [x] 明确非法宽高不会启动。

## 验收

文档能够单独回答以下问题：

1. 地址什么时候变化？
2. SRAM 数据延迟几周期？
3. 第一个 pixel_valid 什么时候出现？
4. 最后一个像素和 frame_done 是同周期还是不同周期？
5. start 在 busy 状态下是什么行为？

建议提交信息：docs: freeze SRAM reader timing contract

---

# Step 2 — 加固 16×16 合成测试数据

## 目标

生成能快速暴露地址错位、行错位和重复/丢像素的问题的确定性数据。

## 修改文件

- tools/generate_patterns.py
- 必要时新增 testdata/synthetic/README.md

## 必须新增的模式：2D 地址斜坡

每像素都可由坐标唯一推导：

P(x,y) = (y × W + x) mod 4096

其中，P(x,y) 表示坐标 (x,y) 的 12 位像素值；x 表示列坐标；y 表示行坐标；W 表示图像宽度；符号“×”表示乘法；符号“+”表示加法；“mod”表示取模运算，即取除以 4096 后的余数；符号“=”表示两边数值相等。

这个模式是 P1 的主测试向量，因为它能直接检查地址和坐标是否一致。

还保留：

- [x] flat：固定灰度。
- [x] checker：棋盘格。
- [x] gradient：渐变。

## 输出

每个模式至少输出：

- .npy：Python 数组基准。
- .mem：每行一个 4 位十六进制字符表示的 16 位 SRAM 字。

建议同时生成一个轻量元数据文件，例如 JSON（JavaScript 对象表示法文本），包含 width、height、raw_bits、bayer、pattern、pixel_count。

如果不生成 JSON，也必须保证文件名包含尺寸和模式。

## 验收

执行：

python3 tools/generate_patterns.py --width 16 --height 16 --output testdata/synthetic

必须满足：

- [x] 每个 .mem 恰好 256 行。
- [x] 每行可解析为 0～4095 的整数。
- [x] 地址斜坡第 0 个值为 0，第 1 个值为 1，第 15 个值为 15，第 16 个值为 16，第 255 个值为 255。
- [x] 连续执行两次生成结果完全一致。

建议提交信息：testdata: add deterministic SRAM reader patterns

---

# Step 3 — 固定并验证 SRAM 仿真模型

## 目标

确保 SRAM 模型本身行为明确，不让 Reader 的错误被存储器模型掩盖。

## 修改文件

- tb/models/sram_model.sv
- 可新增 tb/unit/tb_sram_model.sv

## 动作

- [x] 保持同步读 1 周期延迟。
- [x] 保持 $readmemh 加载 .mem。
- [x] 如当前仿真器不支持 parameter string，只做最小兼容性修改，不改变读延迟。
- [x] 最好增加一个很小的 SRAM 单元测试，确认地址 0、1、2 的返回数据确实延后一周期。

## 验收

自动测试必须证明：

- 地址在周期 T 提交；
- 对应数据在下一周期成为 SRAM 输出；
- 不允许测试平台假设组合读。

建议提交信息：test: lock synchronous SRAM model behavior

---

# Step 4 — 正式实现 sram_reader

## 目标

把当前占位代码改为真正的帧读取状态机。

## 修改文件

- rtl/memory/sram_reader.sv

## 实现要求

- [x] 接受单周期 start。
- [x] 正确锁存或稳定使用 image_width、image_height。
- [x] 产生地址 0 到最后一个地址。
- [x] 正确补偿 SRAM 的 1 周期数据延迟。
- [x] 地址、返回数据、x/y 坐标必须对齐。
- [x] 第一个返回像素输出时 sof=1。
- [x] 每行最后一个像素输出时 eol=1。
- [x] 最后一帧像素输出时 frame_done=1。
- [x] busy 生命周期符合接口约定。
- [x] busy 状态下忽略新的 start。
- [x] 复位时所有有效信号归零。
- [x] 非法宽高不启动。
- [x] 地址宽度不足以覆盖整帧时，至少在仿真中有明确断言或错误提示。

## 设计提示

不要把“发出 SRAM 地址”和“消费 SRAM 返回数据”当成同一拍。

建议明确区分：

- 请求侧计数：当前发出的 SRAM 地址；
- 返回侧有效流水：前一拍请求是否有效；
- 返回侧坐标：必须和前一拍发出的地址对应。

不要通过在测试平台里延迟期望数据来掩盖 Reader 的对齐错误。

## 验收

本步骤完成后先做编译检查，保证无语法错误、无未驱动的关键输出。

建议提交信息：rtl: implement synchronous SRAM frame reader

---

# Step 5 — 建立自检查 sram_reader 单元测试

## 目标

在接顶层之前单独证明 Reader 正确。

## 新增/修改文件

- 新增 tb/unit/tb_sram_reader.sv
- 复用 tb/models/sram_model.sv

## 主测试：16×16 地址斜坡

测试平台必须自动检查：

- [x] 输出有效像素总数等于 256。
- [x] 第 i 个有效像素数据等于 i，其中 i 表示从 0 开始的有效像素序号；“等于”表示数值完全一致。
- [x] pixel_x 从 0 到 15 循环。
- [x] pixel_y 从 0 到 15 逐行增加。
- [x] sof 只出现一次，只在坐标 (0,0)。
- [x] eol 恰好出现 16 次，只在 pixel_x=15 时。
- [x] frame_done 只出现一次，只在 (15,15)。
- [x] 第一有效像素前允许有 SRAM 预热延迟，但进入连续输出后不得出现无故气泡。
- [x] 最后一个像素后不得多输出第 257 个像素。

## 边界测试

至少再加：

- [x] 1×1。
- [x] 2×2。
- [x] 宽度为 0。
- [x] 高度为 0。
- [x] 帧进行到一半再次打 start，当前帧仍正常完成。
- [x] 第一帧结束后重新 start，第二帧仍输出正确。

## 失败策略

发现任意不一致必须 $fatal 或用等价机制让仿真返回非 0。

## 验收

单元测试在命令行可以自动通过/失败，不看波形也能判断。

建议提交信息：test: add self-checking SRAM reader regression

---

# Step 6 — 接入 isp_pipeline_top

## 目标

让顶层真正暴露“SRAM → 像素流”的最小链路，为后续 BLC 接入做好稳定边界。

## 修改文件

- rtl/top/isp_pipeline_top.sv
- tb/integration/tb_isp_pipeline.sv

## 顶层要求

isp_pipeline_top 暂时只负责：

SRAM 接口 → sram_reader → RAW 像素流输出

不要在这一阶段串入 blc.sv。

建议顶层暴露：

- SRAM 地址/读数据；
- 启动和图像尺寸；
- RAW 像素流数据和坐标/标志；
- busy/frame_done。

## 集成测试

用 16×16 地址斜坡：

- [x] 外部实例化 SRAM 模型。
- [x] 顶层实例化 sram_reader。
- [x] 集成测试得到和单元测试一致的 256 个像素。
- [x] 把有效像素 dump 到 testdata/output/。

建议提交信息：rtl: integrate SRAM reader into ISP pipeline top

---

# Step 7 — 增加输出比较工具

## 目标

形成从 Python 基准到 RTL 输出的自动比较闭环。

## 修改文件

优先完善：

- tools/compare_output.py

如有必要再完善 tools/mem_to_image.py 的纯 RAW/灰度辅助路径。

## 比较要求

比较工具至少支持 expected .mem 与 actual dump 的精确比较，并检查：

- 元素个数一致；
- 每个像素数值一致；
- 第一个不一致的位置；
- 期望值和实际值；
- 最终返回码：成功为 0，失败为非 0。

不要只打印 match percentage（匹配百分比）后仍返回成功。P0/P1 要求精确逐像素一致。

## 验收

故意修改一个输出像素时，比较工具必须失败并指出位置；恢复正确后必须通过。

建议提交信息：tools: add exact pixel output comparison

---

# Step 8 — 串成一条命令

## 目标

开发者和后续 Codex 不需要记住零散命令。

## 修改文件

- Makefile
- scripts/run_unit_tests.sh
- scripts/run_pipeline.sh

## 至少提供

- make patterns
- make test-sram-reader
- make test-p0-p1

其中：

make patterns：生成 16×16 测试数据。

make test-sram-reader：编译 sram_reader 单元测试 → 运行仿真 → 自检查。

make test-p0-p1：生成测试数据 → 编译集成测试 → 运行 SRAM 到 top 到 dump → compare_output.py 精确比较。

命令任意一步失败，整体必须返回失败。

## 验收

从干净仓库执行 make test-p0-p1，应得到唯一明确的 PASS/FAIL（通过/失败）结果。

建议提交信息：build: add reproducible P0 P1 regression targets

---

# Step 9 — 最终回归和文档收尾

## 目标

确认 P0/P1 可以作为后续 ISP 模块的可靠输入源，而不是一次性的 demo。

## 动作

- [x] 清理临时调试打印。
- [x] 确认生成物没有误提交到 Git。
- [x] 执行 make clean。
- [x] 从干净状态执行 make test-p0-p1。
- [x] 再执行一次，确认结果可重复。
- [x] 更新 README 的“当前进度”和最短运行命令。
- [x] 更新 docs/verification.md。
- [x] 在本文件下面填写执行记录。
- [x] 不开始 BLC。

## 最终验收输出

最终命令行应清楚显示类似：

[PASS] pattern generation
[PASS] SRAM reader unit tests
[PASS] top-level SRAM input simulation
[PASS] exact pixel comparison
P0/P1 PASS

具体文本可以不同，但结果必须明确且机器可判定。

建议提交信息：docs: close P0 P1 SRAM input milestone

---

## 4. 本计划明确不做的事情

以下内容不属于 P0/P1，即使“顺手很容易”也不要加入：

- BLC 黑电平校正功能接入顶层；
- AWB 自动白平衡增益；
- RAW 域降噪；
- Demosaic 去马赛克；
- CCM 颜色校正矩阵；
- RGB 到 YCbCr 的颜色空间转换；
- AHB 寄存器；
- Cortex-M0 固件；
- HDMI（高清多媒体接口）；
- SD 卡；
- 真实相机 RAW12 紧凑打包解码；
- AXI（高级可扩展接口）流式总线改造；
- 性能综合或 FPGA（现场可编程门阵列）上板。

这些内容分别进入后续计划。

---

## 5. 易错点清单

Codex 在实现时必须特别检查：

- [x] 同步 SRAM 延迟错一拍。
- [x] 第一地址 0 是否真的被请求并输出。
- [x] 最后一地址是否被请求一次且只请求一次。
- [x] 最后一拍的 pixel_valid、eol、frame_done 是否对齐。
- [x] 从地址计数推导坐标时是否在行边界多加或少加一次。
- [x] start 被保持多周期时是否意外重复启动。
- [x] 第二帧开始时地址、坐标和有效流水是否完全清零。
- [x] 复位解除后 SRAM 返回的旧值是否被错误标成有效像素。
- [x] image_width × image_height 是否可能超出地址位宽；符号“×”表示乘法。
- [x] 仿真器对 SystemVerilog 字符串参数、数组和 always_ff 的兼容性。

---

## 6. 交付物清单

计划完成时仓库里应该至少有：

- plans/001_p0_p1_sram_bootstrap.md
- tools/generate_patterns.py
- tools/compare_output.py
- rtl/memory/sram_reader.sv
- rtl/top/isp_pipeline_top.sv
- tb/models/sram_model.sv
- tb/unit/tb_sram_reader.sv
- 可选 tb/unit/tb_sram_model.sv
- tb/integration/tb_isp_pipeline.sv
- testdata/synthetic/
- testdata/output/
- Makefile
- README.md
- docs/verification.md
- docs/memory_map.md

生成出的波形、编译产物和临时 dump 如果属于构建产物，应留在被 .gitignore 忽略的位置；只提交必要的小型确定性测试向量。

---

## 7. 执行记录

Codex 每完成一步后在这里追加一行，不要提前填写完成状态。

提交列“本次里程碑提交”指包含本执行记录的 P0/P1 完整实现提交；可用 `git log -1 -- plans/001_p0_p1_sram_bootstrap.md` 查询提交哈希与详细说明。

| Step | 状态 | 提交 | 验证命令 | 备注 |
|---|---|---|---|---|
| 0 | 完成 | 本次里程碑提交 | `vcs -ID`；现有源码编译/运行；正常与 fatal 探针 | VCS W-2024.09；Python 3.6.6 / NumPy 1.19.5；fatal 原始退出码 0；初始探针已随 clean 清理，最终证据见 build/p0_p1/sram_reader/version.txt 和 forced_failure.status |
| 1 | 完成 | 本次里程碑提交 | `git diff --check`；逐拍契约检查 | 已写明 C0/C1/C2、有效请求窗口、busy、启动边沿、复位与容量边界 |
| 2 | 完成 | 本次里程碑提交 | `python3 -m unittest discover -s tools/tests -p test_generate_patterns.py -v`；规定的 16×16 生成命令 | 3 项回归通过：四种图案、格式/元数据、字节可重复、矩形/取模边界、非法尺寸 |
| 3 | 完成 | 本次里程碑提交 | VCS `-top tb_sram_model`；正常向量和缺失文件测试 | 地址 0/1/2、沿前保持与沿后更新通过；缺失文件有明确 fatal，日志在 build/p0_p1/sram_model/ |
| 4 | 完成 | 本次里程碑提交 | VCS `-top sram_reader`；再加 `+define+SYNTHESIS` 编译 | 三段式 FSM、分类寄存器、无 function；两种编译均无警告/错误，功能验收在 Step 5 |
| 5 | 完成 | 本次里程碑提交 | VCS `-top tb_sram_reader`；两种溢出负例、强制失败、SYNTHESIS 容量拒绝；两帧 dump 字节比较 | 所有逐周期/逐像素、零尺寸、薄帧、矩形、重复/保持启动、尺寸锁存、帧中复位检查通过；日志在 build/p0_p1/sram_reader/ |
| 6 | 完成 | 本次里程碑提交 | VCS `-top tb_isp_pipeline`；Reader 半帧重复启动/忙时保持启动补充回归 | 默认 20 位地址顶层，两帧各 256 像素和所有控制信号通过；无算法接入 |
| 7 | 完成 | 本次里程碑提交 | `python3 -m unittest discover -s tools/tests -p test_compare_output.py -v`；四份 dump 精确比较；第 42 像素破坏负例 | 8 项工具回归通过；正确 dump 为 0，破坏副本为 1 并报告 index=42、坐标及期望/实际值 |
| 8 | 完成 | 本次里程碑提交 | `make test-p0-p1` 两次；`make test-sram-reader`；`make compare-p0-p1`；四种命令负例 | 四图案各两帧逐像素通过；fatal/缺失文件/编译失败/破坏 dump 的 make 退出码均为 2；已处理 VCS 增量时间戳，产物集中 |
| 9 | 完成 | 本次里程碑提交 | `make clean`；`make test-p0-p1` 两次；最终 Reader/比较与四类命令负例；`git diff --check` | 11 项 Python 测试、SRAM/Reader/顶层均通过；22 个产物哈希一致；四类负例 make 均退出 2；证据在 build/p0_p1/acceptance/ |

---

## 8. 下一计划的入口条件

只有当本计划“完成定义”全部满足后，才能创建并执行下一份计划：

002_p2_blc.md

下一阶段再把 BLC（黑电平校正）接到已验证的 RAW 像素流后面，并建立 Python 黄金模型和 RTL 精确对拍。
