PYTHON ?= python3
.PHONY: help patterns clean
help:
	@echo "isp_demo helper targets"
	@echo "  make patterns  - generate synthetic test patterns"
	@echo "  make clean     - remove local build outputs"
patterns:
	$(PYTHON) tools/generate_patterns.py --output testdata/synthetic
clean:
	rm -rf build/*
	rm -rf testdata/output/*
	mkdir -p build testdata/output
	touch build/.gitkeep testdata/output/.gitkeep
