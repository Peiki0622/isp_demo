#!/usr/bin/env bash
# 模块测试入口：all/model/reader。所有编译、日志与 dump 均使用专用目录。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-all}
case "$selection" in all|model|reader) ;; *) printf 'Usage: %s [all|model|reader]\n' "$0" >&2; exit 2;; esac

if [[ $selection == all || $selection == model ]]; then
    directory="$BUILD_ROOT/sram_model"
    compile_vcs "$directory" tb_sram_model "$ROOT/tb/unit/tb_sram_model.sv" "$ROOT/tb/models/sram_model.sv"
    run_vcs_case "$directory" regression '[PASS] SRAM_MODEL' "+MEM_FILE=$MEM_FILE"
    # 特意不存在的文件位于本任务目录，保留错误证据但绝不修改其他输入数据。
    rm -f "$directory/missing-input.mem"
    expect_vcs_failure "$directory" missing_file 'SRAM_INIT_FILE_ERROR:' "+MEM_FILE=$directory/missing-input.mem"
fi

if [[ $selection == all || $selection == reader ]]; then
    directory="$BUILD_ROOT/sram_reader"
    dump_directory="$OUTPUT_ROOT/unit"
    mkdir -p "$dump_directory"
    rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
    sources=("$ROOT/tb/unit/tb_sram_reader.sv" "$ROOT/tb/models/sram_model.sv" "$ROOT/rtl/memory/sram_reader.sv")
    compile_vcs "$directory" tb_sram_reader "${sources[@]}"
    # READER_CASE 仅用于重放测试平台用例；正常入口默认执行完整 regression。
    run_vcs_case "$directory" regression '[PASS] SRAM_READER' "+MEM_FILE=$MEM_FILE" \
        "+DUMP_DIR=$dump_directory" "+CASE=${READER_CASE:-regression}"
    compare_frames "$MEM_FILE" "$dump_directory"
    for case_name in overflow overflow_large; do
        expect_vcs_failure "$directory" "$case_name" 'SRAM_FRAME_TOO_LARGE:' \
            "+MEM_FILE=$MEM_FILE" "+CASE=$case_name"
    done
    expect_vcs_failure "$directory" forced_failure 'SRAM_READER_FORCED_FAILURE' \
        "+MEM_FILE=$MEM_FILE" '+CASE=forced_failure'
    # 再编译排除仿真诊断的功能路径，证明容量拒绝并非只靠 $fatal。
    hardware_directory="$BUILD_ROOT/sram_reader_hardware"
    compile_vcs "$hardware_directory" tb_sram_reader +define+SYNTHESIS "${sources[@]}"
    run_vcs_case "$hardware_directory" capacity_reject '[PASS] SRAM_READER_CAPACITY_REJECT' \
        "+MEM_FILE=$MEM_FILE" '+CASE=capacity_reject'
fi
