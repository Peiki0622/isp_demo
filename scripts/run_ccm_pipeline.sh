#!/usr/bin/env bash
# P5全链：真实尺寸RAW输入->独立四级Python黄金->RTL->严格RGB36逐帧比较。
# 所有编译/仿真顺序执行；compare分支只读，不重生成坏数据。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-all}
case "$selection" in all|controls|compare) ;; *) printf 'Usage: %s [all|controls|compare]\n' "$0" >&2; exit 2;; esac
directory="$ROOT/build/p5_ccm/pipeline"
input_root="$ROOT/testdata/output/p5_ccm/inputs"
golden_root="$ROOT/testdata/output/p5_ccm/golden"
dump_root="$ROOT/testdata/output/p5_ccm/integration"
patterns=(constant_rgb rgb_gradient color_blocks edge_pattern)
sizes=(2x2 3x2 2x3 3x5 4x4)
pairs=(identity_swap signed_clip)
first=(64 6144 4096 8192)
second=(128 4096 5120 2048)
# 同一份row-major整数数组用于CLI和TB全部九个端口，不经浮点换算。
matrix_a=(4096 0 0 0 4096 0 0 0 4096)
matrix_b=(0 0 4096 0 4096 0 4096 0 0)
matrix_c=(5120 -512 -512 -256 4608 -256 -512 -512 5120)
matrix_d=(8192 0 0 0 -4096 8192 -4096 0 8192)
select_pair() {
    case "$1" in
        identity_swap) matrix0=("${matrix_a[@]}"); matrix1=("${matrix_b[@]}");;
        signed_clip) matrix0=("${matrix_c[@]}"); matrix1=("${matrix_d[@]}");;
    esac
}
generate_golden() {
    local source=$1 target=$2 black=$3 gain_r=$4 gain_g=$5 gain_b=$6
    shift 6
    (cd "$ROOT" && "$PYTHON" -m model.generate_ccm_golden --input "$source" --output "$target" \
        --black-level "$black" --gain-r "$gain_r" --gain-g "$gain_g" --gain-b "$gain_b" --matrix "$@")
}
# 参数生成仅使用外部尺寸、输入文件和已选择矩阵，TB不读取DUT内部状态。
frame_args() {
    local size=$1 source=$2 golden=$3 dump=$4 i
    args=("+MEM_FILE=$source" "+GOLDEN0=$golden/frame_0.mem" "+GOLDEN1=$golden/frame_1.mem" \
          "+DUMP_DIR=$dump" "+WIDTH=${size%x*}" "+HEIGHT=${size#*x}" \
          "+BLACK0=${first[0]}" "+R0=${first[1]}" "+G0=${first[2]}" "+B0=${first[3]}" \
          "+BLACK1=${second[0]}" "+R1=${second[1]}" "+G1=${second[2]}" "+B1=${second[3]}")
    for ((i=0;i<9;i++)); do args+=("+M0_$i=${matrix0[$i]}" "+M1_$i=${matrix1[$i]}"); done
}
control_args() {
    select_pair signed_clip
    frame_args "$1" "$input_root/$1/constant_rgb_$1.mem" "$golden_root/controls/$1" "$dump_root/controls/$1"
}
if [[ $selection != compare ]]; then
    select_pair signed_clip
    for size in "${sizes[@]}"; do
        "$PYTHON" "$ROOT/tools/generate_patterns.py" --domain rgb --width "${size%x*}" --height "${size#*x}" --output "$input_root/$size"
        generate_golden "$input_root/$size/constant_rgb_$size.npy" "$golden_root/controls/$size/frame_0.mem" "${first[@]}" "${matrix0[@]}"
        generate_golden "$input_root/$size/constant_rgb_$size.npy" "$golden_root/controls/$size/frame_1.mem" "${second[@]}" "${matrix1[@]}"
        mkdir -p "$dump_root/controls/$size"
        rm -f "$dump_root/controls/$size/frame_0.mem" "$dump_root/controls/$size/frame_1.mem"
    done
    if [[ $selection == all ]]; then
        "$PYTHON" "$ROOT/tools/generate_patterns.py" --domain rgb --width 16 --height 16 --output "$input_root/16x16"
        for pair in "${pairs[@]}"; do
            select_pair "$pair"
            for pattern in "${patterns[@]}"; do
                source_npy="$input_root/16x16/${pattern}_16x16.npy"
                first_source=$source_npy
                if [[ $pair == identity_swap && $pattern == constant_rgb ]]; then first_source=${CCM_GOLDEN_INPUT:-$source_npy}; fi
                generate_golden "$first_source" "$golden_root/$pair/$pattern/frame_0.mem" "${first[@]}" "${matrix0[@]}"
                generate_golden "$source_npy" "$golden_root/$pair/$pattern/frame_1.mem" "${second[@]}" "${matrix1[@]}"
            done
        done
    fi
    sources=("$ROOT/tb/integration/tb_ccm_pipeline.sv" "$ROOT/tb/models/sram_model.sv" \
        "$ROOT/rtl/top/isp_pipeline_top.sv" "$ROOT/rtl/top/demosaic_pipeline.sv" "$ROOT/rtl/rgb_domain/ccm.sv" \
        "$ROOT/rtl/top/awb_pipeline.sv" "$ROOT/rtl/top/blc_pipeline.sv" "$ROOT/rtl/top/sram_raw_source.sv" \
        "$ROOT/rtl/memory/sram_reader.sv" "$ROOT/rtl/raw_domain/blc.sv" "$ROOT/rtl/raw_domain/awb_gain.sv" \
        "$ROOT/rtl/raw_domain/demosaic.sv" "$ROOT/rtl/common/window_3x3.sv")
    compile_vcs "$directory" tb_ccm_pipeline "${sources[@]}"
    for size in "${sizes[@]}"; do
        control_args "$size"
        run_vcs_case "$directory" "controls_$size" '[PASS] CCM_PIPELINE' "${args[@]}" '+CASE=controls'
    done
    control_args 2x2
    for name in overflow overflow_large; do
        expect_vcs_failure "$directory" "$name" 'SRAM_FRAME_TOO_LARGE:' "${args[@]}" "+CASE=$name"
    done
    expect_vcs_failure "$directory" forced_failure 'CCM_PIPELINE_FORCED_FAILURE' "${args[@]}" '+CASE=forced_failure'
    rm -f "$directory/missing-golden.mem"
    expect_vcs_failure "$directory" missing_golden 'CCM_GOLDEN_FILE_ERROR:' "${args[0]}" \
        "+GOLDEN0=$directory/missing-golden.mem" "${args[2]}" '+WIDTH=2' '+HEIGHT=2' '+CASE=controls'
    hardware_directory="$ROOT/build/p5_ccm/pipeline_hardware"
    compile_vcs "$hardware_directory" tb_ccm_pipeline +define+SYNTHESIS "${sources[@]}"
    run_vcs_case "$hardware_directory" capacity_reject '[PASS] CCM_PIPELINE' "${args[@]}" '+CASE=capacity_reject'
fi
# 五个实际小尺寸均比较两份独立黄金；不能拿大图前缀替代奇数宽度。
for size in "${sizes[@]}"; do
    for frame in 0 1; do
        "$PYTHON" "$ROOT/tools/compare_rgb_output.py" --expected "$golden_root/controls/$size/frame_$frame.mem" \
            --actual "$dump_root/controls/$size/frame_$frame.mem" --width "${size%x*}" --height "${size#*x}"
    done
done
if [[ $selection != controls ]]; then
    for pair in "${pairs[@]}"; do
        select_pair "$pair"
        for pattern in "${patterns[@]}"; do
            dump_directory="$dump_root/$pair/$pattern"
            if [[ $selection == all ]]; then
                mkdir -p "$dump_directory"
                rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
                frame_args 16x16 "$input_root/16x16/${pattern}_16x16.mem" "$golden_root/$pair/$pattern" "$dump_directory"
                run_vcs_case "$directory" "${pair}_$pattern" '[PASS] CCM_PIPELINE' "${args[@]}" '+CASE=regression'
                # 一次只改指定通道的一个LSB，输入和黄金完全不动。
                if [[ ${CCM_CORRUPT_OUTPUT:-0} != 0 && $pair == identity_swap && $pattern == constant_rgb ]]; then
                    "$PYTHON" - "$dump_directory/frame_0.mem" "$CCM_CORRUPT_OUTPUT" <<'PY'
import sys
from pathlib import Path
shift={'1':24,'R':24,'G':12,'B':0}[sys.argv[2]]
p=Path(sys.argv[1]);words=p.read_text().splitlines()
words[42]='{:09x}'.format(int(words[42],16) ^ (1<<shift))
p.write_text('\n'.join(words)+'\n')
PY
                fi
            fi
            for frame in 0 1; do
                "$PYTHON" "$ROOT/tools/compare_rgb_output.py" --expected "$golden_root/$pair/$pattern/frame_$frame.mem" \
                    --actual "$dump_directory/frame_$frame.mem" --width 16 --height 16
            done
        done
    done
fi
