#!/usr/bin/env bash
# P4 窗口验收：公开端口检查、精确诊断负例以及独立功能拒绝构建。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p4_demosaic/window"
sources=("$ROOT/tb/unit/tb_window_3x3.sv" "$ROOT/rtl/common/window_3x3.sv")
compile_vcs "$directory" tb_window_3x3 "${sources[@]}"
run_vcs_case "$directory" regression '[PASS] WINDOW_UNIT' "+CASE=${WINDOW_CASE:-regression}"
expect_vcs_failure "$directory" forced_failure 'WINDOW_UNIT_FORCED_FAILURE' '+CASE=forced_failure'
for name in invalid_width invalid_small invalid_height; do
    expect_vcs_failure "$directory" "$name" 'WINDOW_DIMENSIONS_INVALID:' "+CASE=$name"
done
expect_vcs_failure "$directory" overlap 'WINDOW_FRAME_OVERLAP' '+CASE=overlap'
hardware_directory="$ROOT/build/p4_demosaic/window_hardware"
compile_vcs "$hardware_directory" tb_window_3x3 +define+SYNTHESIS "${sources[@]}"
run_vcs_case "$hardware_directory" dimension_reject '[PASS] WINDOW_UNIT' '+CASE=dimension_reject'
