#!/usr/bin/env bash
# P3 全链控制验收：黄金由原始 NPY 经 Python BLC->AWB 生成，不访问 RTL 内部。
# 小帧逐个使用实际尺寸的输入/黄金，防止奇数宽度造成 Bayer 相位误判。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-controls}
case "$selection" in controls) ;; *) printf 'Usage: %s controls\n' "$0" >&2; exit 2;; esac

directory="$ROOT/build/p3_awb/pipeline"
input_root="$ROOT/testdata/output/p3_awb/inputs"
golden_root="$ROOT/testdata/output/p3_awb/golden"
dump_root="$ROOT/testdata/output/p3_awb/integration"

# 一个调用生成一帧，CLI 在计算前删除旧目标，set -e 保证失败立即停止后续仿真。
generate_golden() {
    (cd "$ROOT" && "$PYTHON" -m model.generate_awb_golden --input "$1" --output "$2" \
        --black-level "$3" --gain-r "$4" --gain-g "$5" --gain-b "$6")
}

# 同一尺寸使用两份不同配置的黄金；这里设置外部测试参数而非复制像素公式。
control_args() {
    local width=$1 height=$2 label="${1}x${2}"
    args=("+MEM_FILE=$input_root/$label/flat_${label}.mem" \
          "+GOLDEN0=$golden_root/controls/$label/frame_0.mem" \
          "+GOLDEN1=$golden_root/controls/$label/frame_1.mem" \
          "+WIDTH=$width" "+HEIGHT=$height" '+BLACK0=64' '+BLACK1=128' \
          '+R0=8192' '+G0=2048' '+B0=6144' '+R1=2048' '+G1=6144' '+B1=4097')
}

for size in 1x1 2x2 7x1 1x7 3x5 4x4; do
    width=${size%x*}; height=${size#*x}
    "$PYTHON" "$ROOT/tools/generate_patterns.py" --width "$width" --height "$height" \
        --output "$input_root/$size"
    generate_golden "$input_root/$size/flat_${size}.npy" \
        "$golden_root/controls/$size/frame_0.mem" 64 8192 2048 6144
    generate_golden "$input_root/$size/flat_${size}.npy" \
        "$golden_root/controls/$size/frame_1.mem" 128 2048 6144 4097
done
sources=("$ROOT/tb/integration/tb_awb_pipeline.sv" "$ROOT/tb/models/sram_model.sv" \
         "$ROOT/rtl/top/isp_pipeline_top.sv" "$ROOT/rtl/top/blc_pipeline.sv" \
         "$ROOT/rtl/top/sram_raw_source.sv" "$ROOT/rtl/memory/sram_reader.sv" \
         "$ROOT/rtl/raw_domain/blc.sv" "$ROOT/rtl/raw_domain/awb_gain.sv")
compile_vcs "$directory" tb_awb_pipeline "${sources[@]}"
for size in 1x1 2x2 7x1 1x7 3x5 4x4; do
    control_args "${size%x*}" "${size#*x}"
    run_vcs_case "$directory" "controls_$size" '[PASS] AWB_PIPELINE' "${args[@]}" '+CASE=controls'
done
control_args 1 1
for case_name in overflow overflow_large; do
    expect_vcs_failure "$directory" "$case_name" 'SRAM_FRAME_TOO_LARGE:' "${args[@]}" "+CASE=$case_name"
done
expect_vcs_failure "$directory" forced_failure 'AWB_PIPELINE_FORCED_FAILURE' "${args[@]}" '+CASE=forced_failure'
rm -f "$directory/missing-golden.mem"
expect_vcs_failure "$directory" missing_golden 'AWB_GOLDEN_FILE_ERROR:' \
    "${args[0]}" "+GOLDEN0=$directory/missing-golden.mem" "${args[2]}" '+WIDTH=1' '+HEIGHT=1' '+CASE=controls'
# SYNTHESIS 构建只禁用仿真 fatal；必须仍拒绝两个超容量尺寸，并能重新启动合法帧。
hardware_directory="$ROOT/build/p3_awb/pipeline_hardware"
compile_vcs "$hardware_directory" tb_awb_pipeline +define+SYNTHESIS "${sources[@]}"
run_vcs_case "$hardware_directory" capacity_reject '[PASS] AWB_PIPELINE' "${args[@]}" '+CASE=capacity_reject'
