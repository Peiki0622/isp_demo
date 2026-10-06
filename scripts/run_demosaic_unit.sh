#!/usr/bin/env bash
# P4 RGB 单元验收：最近颜色整数 oracle、时序、复位及严格失败传播。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p4_demosaic/unit"
sources=("$ROOT/tb/unit/tb_demosaic.sv" "$ROOT/rtl/raw_domain/demosaic.sv" "$ROOT/rtl/common/window_3x3.sv")
compile_vcs "$directory" tb_demosaic "${sources[@]}"
run_vcs_case "$directory" regression '[PASS] DEMOSAIC_UNIT' "+CASE=${DEMOSAIC_CASE:-regression}"
expect_vcs_failure "$directory" forced_failure 'DEMOSAIC_UNIT_FORCED_FAILURE' '+CASE=forced_failure'
for name in invalid_width invalid_small invalid_height; do
    expect_vcs_failure "$directory" "$name" 'WINDOW_DIMENSIONS_INVALID:' "+CASE=$name"
done
expect_vcs_failure "$directory" overlap 'DEMOSAIC_FRAME_OVERLAP' '+CASE=overlap'
hardware_directory="$ROOT/build/p4_demosaic/unit_hardware"
compile_vcs "$hardware_directory" tb_demosaic +define+SYNTHESIS "${sources[@]}"
run_vcs_case "$hardware_directory" dimension_reject '[PASS] DEMOSAIC_UNIT' '+CASE=dimension_reject'
