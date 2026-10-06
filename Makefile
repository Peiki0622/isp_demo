# 使用容器现有工具；可显式覆盖可执行路径，不修改系统或许可证环境。
PYTHON ?= python3
VCS ?= vcs
export PYTHON VCS
export PYTHONDONTWRITEBYTECODE := 1

.PHONY: help patterns test-tools test-sram-model test-sram-reader test-pipeline \
        test-p0-p1 compare-p0-p1 test-blc-model test-blc-unit test-blc-pipeline \
        test-p2-blc compare-p2-blc test-awb-model test-awb-unit test-awb-pipeline \
        test-p3-awb compare-p3-awb clean
help:
	@echo "make test-p3-awb       - complete P0/P1, P2 and AWB model/unit/full-chain regression"
	@echo "make test-p2-blc       - complete P0/P1 plus BLC model/unit/integration regression"
	@echo "make test-p0-p1        - independent Reader-only regression"
	@echo "make test-blc-model    - integer golden model and golden-file CLI tests"
	@echo "make test-blc-unit     - cycle-exact BLC unit regression"
	@echo "make test-blc-pipeline - controls, reset, capacity and four-pattern two-frame comparison"
	@echo "make compare-p2-blc    - recheck existing BLC frame dumps without regenerating"
	@echo "make test-awb-model    - exact RGGB integer model and full-chain golden CLI tests"
	@echo "make test-awb-unit     - exhaustive AWB arithmetic and cycle-exact unit regression"
	@echo "make test-awb-pipeline - small-frame controls plus four-pattern two-frame comparison"
	@echo "make compare-p3-awb    - recheck existing AWB frame dumps without regenerating"
	@echo "make clean            - remove only named P0/P1, P2 and P3 generated artifacts"

# 输入向量保持 P0/P1 文件格式和命名；确定性 NPY 与 MEM 内容一一对应。
patterns:
	$(PYTHON) tools/generate_patterns.py --width 16 --height 16 --output testdata/synthetic

test-tools:
	$(PYTHON) -m unittest discover -s tools/tests -p 'test_compare_output.py' -v
	$(PYTHON) -m unittest discover -s tools/tests -p 'test_generate_patterns.py' -v

# RGB 新工具不进入历史 Reader-only 的测试入口，避免引入跨阶段依赖。
test-demosaic-tools:
	$(PYTHON) -m unittest discover -s tools/tests -p 'test_rgb*.py' -v

# 软件参考独立验收，标准库 unittest 不额外引入测试框架。
test-blc-model:
	$(PYTHON) -m unittest discover -s model/tests -p 'test_blc*.py' -v

# P3 软件验收与 P2 discovery 分开，避免旧入口暗中运行新测试。
test-awb-model:
	$(PYTHON) -m unittest discover -s model/tests -p 'test_awb*.py' -v

# P4 软件入口独立于旧 RAW 模型测试，包含后续全链黄金 CLI 用例。
test-demosaic-model:
	$(PYTHON) -m unittest discover -s model/tests -p 'test_demosaic*.py' -v

test-sram-model: patterns
	bash scripts/run_unit_tests.sh model

test-sram-reader: patterns
	bash scripts/run_unit_tests.sh reader

# 保留旧入口名称；它现在测试无算法、无额外寄存的 SRAM RAW Source。
test-pipeline: patterns
	bash scripts/run_pipeline.sh

# VCS 用例顺序执行，防止共享任务目录/许可证竞争；任一失败立即停止。
test-p0-p1: patterns test-tools
	bash scripts/run_unit_tests.sh
	bash scripts/run_pipeline.sh
	@echo "P0/P1 PASS"

compare-p0-p1:
	bash scripts/run_pipeline.sh compare

test-blc-unit:
	bash scripts/run_blc_unit.sh

test-awb-unit:
	bash scripts/run_awb_unit.sh

test-awb-pipeline:
	bash scripts/run_awb_pipeline.sh

test-blc-pipeline: patterns
	bash scripts/run_blc_pipeline.sh

# 不写成可并行的依赖列表：先完整验收 Source，再按顺序执行所有 BLC 环节。
# 递归 Make 保留用户传入的 PYTHON/VCS 路径，同时向上传播非零退出状态。
test-p2-blc:
	$(MAKE) test-p0-p1
	$(MAKE) test-blc-model
	$(MAKE) test-blc-unit
	$(MAKE) test-blc-pipeline
	@echo "P2 BLC PASS"

# compare 不重建 expected 或 dump，避免覆盖被破坏的输出后误报成功。
compare-p2-blc:
	bash scripts/run_blc_pipeline.sh compare

# P3 顺序先验收完整 P0/P1 + P2，再执行 AWB 各层级，任一步失败即停止。
# 不能用并行依赖列出 EDA 目标，以免同一运行目录、日志和许可证发生竞争。
test-p3-awb:
	$(MAKE) test-p2-blc
	$(MAKE) test-awb-model
	$(MAKE) test-awb-unit
	$(MAKE) test-awb-pipeline
	@echo "P3 AWB PASS"

# 仅比较已有的八份 P3 输出；不会重新生成数据而覆盖待定位的错误。
compare-p3-awb:
	bash scripts/run_awb_pipeline.sh compare

# 清理只覆盖本项目规定的可重建产物；保留 reports 验收记录及其他运行目录。
clean:
	rm -rf build/p0_p1 build/p2_blc build/p3_awb testdata/output/p0_p1 testdata/output/p2_blc testdata/output/p3_awb
	@for pattern in addr_ramp flat checker gradient; do \
		rm -f "testdata/synthetic/$${pattern}_16x16.mem" "testdata/synthetic/$${pattern}_16x16.npy" "testdata/synthetic/$${pattern}_16x16.json"; \
	done
