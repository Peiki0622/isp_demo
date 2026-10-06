#!/usr/bin/env bash
# P2 集成入口：本步骤先验证小帧/启动/复位控制，黄金只由 Python 模型生成。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
directory="$ROOT/build/p2_blc/pipeline"
golden_dir="$ROOT/testdata/output/p2_blc/golden/flat"
mkdir -p "$golden_dir"
for frame in 0 1; do
    offset=1024
    if [[ $frame == 1 ]]; then offset=64; fi
    (cd "$ROOT" && "$PYTHON" -m model.generate_blc_golden \
        --input "$ROOT/testdata/synthetic/flat_16x16.npy" \
        --output "$golden_dir/frame_$frame.mem" --black-level "$offset")
done
sources=("$ROOT/tb/integration/tb_blc_pipeline.sv" "$ROOT/tb/models/sram_model.sv" \
         "$ROOT/rtl/top/isp_pipeline_top.sv" "$ROOT/rtl/top/sram_raw_source.sv" \
         "$ROOT/rtl/memory/sram_reader.sv" "$ROOT/rtl/raw_domain/blc.sv")
compile_vcs "$directory" tb_blc_pipeline "${sources[@]}"
args=("+MEM_FILE=$ROOT/testdata/synthetic/flat_16x16.mem" \
      "+GOLDEN0=$golden_dir/frame_0.mem" "+GOLDEN1=$golden_dir/frame_1.mem" '+BLACK0=1024' '+BLACK1=64')
run_vcs_case "$directory" controls '[PASS] BLC_PIPELINE' "${args[@]}" '+CASE=controls'
for case_name in overflow overflow_large; do
    expect_vcs_failure "$directory" "$case_name" 'SRAM_FRAME_TOO_LARGE:' "${args[@]}" "+CASE=$case_name"
done
# 排除仿真诊断重新编译并运行，证明非法容量拒绝属于实际功能逻辑。
hardware_directory="$ROOT/build/p2_blc/pipeline_hardware"
compile_vcs "$hardware_directory" tb_blc_pipeline +define+SYNTHESIS "${sources[@]}"
run_vcs_case "$hardware_directory" capacity_reject '[PASS] BLC_PIPELINE' "${args[@]}" '+CASE=capacity_reject'
