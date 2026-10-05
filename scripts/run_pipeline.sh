#!/usr/bin/env bash
# 顶层回归入口：all 编译/仿真/比较四种图案；compare 仅重新比较已有 dump。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-all}
case "$selection" in all|compare) ;; *) printf 'Usage: %s [all|compare]\n' "$0" >&2; exit 2;; esac

directory="$BUILD_ROOT/pipeline"
if [[ $selection == all ]]; then
    compile_vcs "$directory" tb_isp_pipeline "$ROOT/tb/integration/tb_isp_pipeline.sv" \
        "$ROOT/rtl/top/isp_pipeline_top.sv" "$ROOT/rtl/memory/sram_reader.sv" "$ROOT/tb/models/sram_model.sv"
fi
# 相同测试平台还检查 flat、checker、gradient 的 RAW12 高位，编译只需一次。
for pattern in addr_ramp flat checker gradient; do
    expected_file="$ROOT/testdata/synthetic/${pattern}_16x16.mem"
    dump_directory="$OUTPUT_ROOT/integration/$pattern"
    if [[ $selection == all ]]; then
        mkdir -p "$dump_directory"
        rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
        run_vcs_case "$directory" "$pattern" '[PASS] ISP_PIPELINE' \
            "+MEM_FILE=$expected_file" "+DUMP_DIR=$dump_directory"
    fi
    compare_frames "$expected_file" "$dump_directory"
done
