#!/usr/bin/env bash
# P5两级CCM单测：正常/SYNTHESIS功能构建及精确fatal判据，产物集中保存。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p5_ccm/unit"
sources=("$ROOT/tb/unit/tb_ccm.sv" "$ROOT/rtl/rgb_domain/ccm.sv")
compile_vcs "$directory" tb_ccm "${sources[@]}"
run_vcs_case "$directory" regression '[PASS] CCM_UNIT' "+CASE=${CCM_CASE:-regression}"
expect_vcs_failure "$directory" forced_failure CCM_UNIT_FORCED_FAILURE '+CASE=forced_failure'
hardware_directory="$ROOT/build/p5_ccm/unit_hardware"
compile_vcs "$hardware_directory" tb_ccm +define+SYNTHESIS "${sources[@]}"
run_vcs_case "$hardware_directory" regression '[PASS] CCM_UNIT' '+CASE=regression'
