#!/usr/bin/env bash
# BLC 单元入口：复用 VCS 严格判定，所有二进制/日志位于 P2 专用目录。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p2_blc/unit"
compile_vcs "$directory" tb_blc "$ROOT/tb/unit/tb_blc.sv" "$ROOT/rtl/raw_domain/blc.sv"
run_vcs_case "$directory" regression '[PASS] BLC_UNIT' "+CASE=${BLC_CASE:-regression}"
# 正常入口也验证 fatal 不能因 VCS 返回零而冒充成功；要求特定诊断。
expect_vcs_failure "$directory" forced_failure 'BLC_UNIT_FORCED_FAILURE' '+CASE=forced_failure'
