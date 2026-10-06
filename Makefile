# 仅使用现有本机工具，允许显式覆盖可执行路径，不修改系统/许可证环境。
PYTHON ?= python3
VCS ?= vcs
export PYTHON VCS
export PYTHONDONTWRITEBYTECODE := 1

.PHONY: help patterns test-tools test-sram-model test-sram-reader test-pipeline test-p0-p1 compare-p0-p1 clean
.PHONY: test-blc-model
help:
	@echo "make patterns          - generate four deterministic 16x16 RAW12 patterns"
	@echo "make test-sram-reader  - VCS reader regression and exact dump comparison"
	@echo "make test-p0-p1        - complete tools/model/reader/top regression"
	@echo "make compare-p0-p1    - recheck existing top-level dumps"
	@echo "make clean            - remove only P0/P1 generated artifacts"

patterns:
	$(PYTHON) tools/generate_patterns.py --width 16 --height 16 --output testdata/synthetic

test-tools:
	$(PYTHON) -m unittest discover -s tools/tests -p 'test_*.py' -v

# 软件黄金模型单独验收；使用标准库 unittest，不增加测试框架依赖。
test-blc-model:
	$(PYTHON) -m unittest discover -s model/tests -p 'test_*.py' -v

test-sram-model: patterns
	bash scripts/run_unit_tests.sh model

test-sram-reader: patterns
	bash scripts/run_unit_tests.sh reader

test-pipeline: patterns
	bash scripts/run_pipeline.sh

# 顺序运行 EDA 回归，避免多个 VCS 运行竞争许可证或共享日志；每个环节失败即停止。
test-p0-p1: patterns test-tools
	bash scripts/run_unit_tests.sh
	bash scripts/run_pipeline.sh
	@echo "P0/P1 PASS"

compare-p0-p1:
	bash scripts/run_pipeline.sh compare

# 清理范围只包含本任务目录与四种命名图案，不删除其他仿真/用户数据目录。
clean:
	rm -rf build/p0_p1 testdata/output/p0_p1
	@for pattern in addr_ramp flat checker gradient; do \
		rm -f "testdata/synthetic/$${pattern}_16x16.mem" "testdata/synthetic/$${pattern}_16x16.npy" "testdata/synthetic/$${pattern}_16x16.json"; \
	done
