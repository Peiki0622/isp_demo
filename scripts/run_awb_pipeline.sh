#!/usr/bin/env bash
# P3 全链控制/四图案两帧验收：黄金由原始 NPY 经 Python BLC->AWB 生成，不访问 RTL 内部。
# 小帧逐个使用实际尺寸的输入/黄金，防止奇数宽度造成 Bayer 相位误判。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-all}
case "$selection" in all|controls|compare) ;; *) printf 'Usage: %s [all|controls|compare]\n' "$0" >&2; exit 2;; esac

directory="$ROOT/build/p3_awb/pipeline"
input_root="$ROOT/testdata/output/p3_awb/inputs"
golden_root="$ROOT/testdata/output/p3_awb/golden"
dump_root="$ROOT/testdata/output/p3_awb/integration"

# 四类 16x16 图案，两帧各自的黑电平和三路 UQ4.12 编码，数组按图案顺序对齐。
patterns=(addr_ramp flat checker gradient)
black_first=(64 1024 512 256); black_second=(128 64 4095 0)
r_first=(6144 8192 65535 4097); r_second=(4096 4096 0 2048)
g_first=(4096 4096 2048 6144); g_second=(5120 4096 65535 4096)
b_first=(8192 6144 4096 8192); b_second=(2048 4096 4096 5120)

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

if [[ $selection != compare ]]; then
for size in 1x1 2x2 7x1 1x7 3x5 4x4; do
    width=${size%x*}; height=${size#*x}
    "$PYTHON" "$ROOT/tools/generate_patterns.py" --width "$width" --height "$height" \
        --output "$input_root/$size"
    generate_golden "$input_root/$size/flat_${size}.npy" \
        "$golden_root/controls/$size/frame_0.mem" 64 8192 2048 6144
    generate_golden "$input_root/$size/flat_${size}.npy" \
        "$golden_root/controls/$size/frame_1.mem" 128 2048 6144 4097
done
if [[ $selection == all ]]; then
    "$PYTHON" "$ROOT/tools/generate_patterns.py" --width 16 --height 16 --output "$input_root/16x16"
    for index in 0 1 2 3; do
        pattern=${patterns[$index]}
        source_npy="$input_root/16x16/${pattern}_16x16.npy"
        # 仅用于验收生成失败传播：覆盖第一份黄金的输入，不修改 SRAM MEM 或其他帧。
        # CLI 会移除该帧旧目标，set -e 在失败时阻止编译/仿真/比较继续执行。
        first_source=$source_npy
        if [[ $index == 0 ]]; then first_source=${AWB_GOLDEN_INPUT:-$source_npy}; fi
        generate_golden "$first_source" "$golden_root/$pattern/frame_0.mem" \
            "${black_first[$index]}" "${r_first[$index]}" "${g_first[$index]}" "${b_first[$index]}"
        generate_golden "$source_npy" "$golden_root/$pattern/frame_1.mem" \
            "${black_second[$index]}" "${r_second[$index]}" "${g_second[$index]}" "${b_second[$index]}"
    done
fi

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
fi

if [[ $selection != controls ]]; then
for index in 0 1 2 3; do
    pattern=${patterns[$index]}
    dump_directory="$dump_root/$pattern"
    if [[ $selection == all ]]; then
        mkdir -p "$dump_directory"
        rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
        run_vcs_case "$directory" "$pattern" '[PASS] AWB_PIPELINE' \
            "+MEM_FILE=$input_root/16x16/${pattern}_16x16.mem" \
            "+GOLDEN0=$golden_root/$pattern/frame_0.mem" "+GOLDEN1=$golden_root/$pattern/frame_1.mem" \
            "+BLACK0=${black_first[$index]}" "+BLACK1=${black_second[$index]}" \
            "+R0=${r_first[$index]}" "+G0=${g_first[$index]}" "+B0=${b_first[$index]}" \
            "+R1=${r_second[$index]}" "+G1=${g_second[$index]}" "+B1=${b_second[$index]}" \
            "+DUMP_DIR=$dump_directory" '+CASE=regression'
        # 测试开关只破坏首图案实际输出的 index=42，不碰黄金/输入；检验 Make 失败传播。
        if [[ ${AWB_CORRUPT_OUTPUT:-0} == 1 && $index == 0 ]]; then
            "$PYTHON" - "$dump_directory/frame_0.mem" <<'INJECT'
import sys
from pathlib import Path
path = Path(sys.argv[1])
words = path.read_text().splitlines()
words[42] = '{:04x}'.format((int(words[42], 16) + 1) % 4096)
path.write_text('\n'.join(words) + '\n')
INJECT
        fi
    fi
    # 每帧独立校验值、数量、格式；compare 不重新生成任何输入、黄金或实际输出。
    for frame in 0 1; do
        "$PYTHON" "$ROOT/tools/compare_output.py" --expected "$golden_root/$pattern/frame_$frame.mem" \
            --actual "$dump_directory/frame_$frame.mem" --width 16
    done
done
fi
