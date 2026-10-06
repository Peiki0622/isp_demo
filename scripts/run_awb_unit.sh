#!/usr/bin/env bash
# P3 单元入口：完整数值/时序回归及 fatal 负例，统一隔离至 build/p3_awb。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p3_awb/unit"
compile_vcs "$directory" tb_awb_gain "$ROOT/tb/unit/tb_awb_gain.sv" "$ROOT/rtl/raw_domain/awb_gain.sv"
run_vcs_case "$directory" regression '[PASS] AWB_UNIT' "+CASE=${AWB_CASE:-regression}"
expect_vcs_failure "$directory" forced_failure 'AWB_UNIT_FORCED_FAILURE' '+CASE=forced_failure'
