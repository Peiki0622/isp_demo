#!/usr/bin/env bash
# P5全链（Step6 identity验收，后续同一平台扩展CCM黄金）：生成真实尺寸 RAW 输入及独立 Python RGB36 黄金，统一严格 VCS 判据。
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
# 配置只有整数编码；所有图案两帧都改变 offset 及三路增益。
first=(64 6144 4096 8192)
second=(128 4096 5120 2048)
generate_golden() {
    (cd "$ROOT" && "$PYTHON" -m model.generate_demosaic_golden --input "$1" --output "$2" \
        --black-level "$3" --gain-r "$4" --gain-g "$5" --gain-b "$6")
}
control_args() {
    local size=$1
    args=("+MEM_FILE=$input_root/$size/constant_rgb_$size.mem" \
          "+GOLDEN0=$golden_root/controls/$size/frame_0.mem" "+GOLDEN1=$golden_root/controls/$size/frame_1.mem" \
          "+DUMP_DIR=$dump_root/controls/$size" "+WIDTH=${size%x*}" "+HEIGHT=${size#*x}" \
          "+BLACK0=${first[0]}" "+R0=${first[1]}" "+G0=${first[2]}" "+B0=${first[3]}" \
          "+BLACK1=${second[0]}" "+R1=${second[1]}" "+G1=${second[2]}" "+B1=${second[3]}")
}
# compare-only 没有 mkdir、生成、编译或仿真，任何坏 dump 都会原样被发现。
if [[ $selection != compare ]]; then
    for size in "${sizes[@]}"; do
        "$PYTHON" "$ROOT/tools/generate_patterns.py" --domain rgb --width "${size%x*}" --height "${size#*x}" --output "$input_root/$size"
        generate_golden "$input_root/$size/constant_rgb_$size.npy" "$golden_root/controls/$size/frame_0.mem" "${first[@]}"
        generate_golden "$input_root/$size/constant_rgb_$size.npy" "$golden_root/controls/$size/frame_1.mem" "${second[@]}"
        mkdir -p "$dump_root/controls/$size"
        rm -f "$dump_root/controls/$size/frame_0.mem" "$dump_root/controls/$size/frame_1.mem"
    done
    if [[ $selection == all ]]; then
        "$PYTHON" "$ROOT/tools/generate_patterns.py" --domain rgb --width 16 --height 16 --output "$input_root/16x16"
        for pattern in "${patterns[@]}"; do
            source_npy="$input_root/16x16/${pattern}_16x16.npy"
            first_source=$source_npy
            if [[ $pattern == constant_rgb ]]; then first_source=${CCM_GOLDEN_INPUT:-$source_npy}; fi
            generate_golden "$first_source" "$golden_root/$pattern/frame_0.mem" "${first[@]}"
            generate_golden "$source_npy" "$golden_root/$pattern/frame_1.mem" "${second[@]}"
        done
    fi
    sources=("$ROOT/tb/integration/tb_ccm_pipeline.sv" "$ROOT/tb/models/sram_model.sv" \
             "$ROOT/rtl/top/isp_pipeline_top.sv" "$ROOT/rtl/top/demosaic_pipeline.sv" "$ROOT/rtl/rgb_domain/ccm.sv" "$ROOT/rtl/top/awb_pipeline.sv" "$ROOT/rtl/top/blc_pipeline.sv" \
             "$ROOT/rtl/top/sram_raw_source.sv" "$ROOT/rtl/memory/sram_reader.sv" "$ROOT/rtl/raw_domain/blc.sv" \
             "$ROOT/rtl/raw_domain/awb_gain.sv" "$ROOT/rtl/raw_domain/demosaic.sv" "$ROOT/rtl/common/window_3x3.sv")
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
    expect_vcs_failure "$directory" missing_golden 'CCM_GOLDEN_FILE_ERROR:' \
        "${args[0]}" "+GOLDEN0=$directory/missing-golden.mem" "${args[2]}" '+WIDTH=2' '+HEIGHT=2' '+CASE=controls'
    hardware_directory="$ROOT/build/p5_ccm/pipeline_hardware"
    compile_vcs "$hardware_directory" tb_ccm_pipeline +define+SYNTHESIS "${sources[@]}"
    run_vcs_case "$hardware_directory" capacity_reject '[PASS] CCM_PIPELINE' "${args[@]}" '+CASE=capacity_reject'
fi
# 小帧同样逐文件独立对拍，不能仅用主图案掩盖奇数宽度的边界问题。
for size in "${sizes[@]}"; do
    for frame in 0 1; do
        "$PYTHON" "$ROOT/tools/compare_rgb_output.py" --expected "$golden_root/controls/$size/frame_$frame.mem" \
            --actual "$dump_root/controls/$size/frame_$frame.mem" --width "${size%x*}" --height "${size#*x}"
    done
done
if [[ $selection != controls ]]; then
    for pattern in "${patterns[@]}"; do
        dump_directory="$dump_root/$pattern"
        if [[ $selection == all ]]; then
            mkdir -p "$dump_directory"
            rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
            run_vcs_case "$directory" "$pattern" '[PASS] CCM_PIPELINE' \
                "+MEM_FILE=$input_root/16x16/${pattern}_16x16.mem" \
                "+GOLDEN0=$golden_root/$pattern/frame_0.mem" "+GOLDEN1=$golden_root/$pattern/frame_1.mem" \
                "+DUMP_DIR=$dump_directory" "+BLACK0=${first[0]}" "+R0=${first[1]}" "+G0=${first[2]}" "+B0=${first[3]}" \
                "+BLACK1=${second[0]}" "+R1=${second[1]}" "+G1=${second[2]}" "+B1=${second[3]}" '+CASE=regression'
            # 精确失败注入仅修改首图案实际 dump 的一个指定通道，不碰输入/黄金。
            if [[ ${CCM_CORRUPT_OUTPUT:-0} != 0 && $pattern == constant_rgb ]]; then
                "$PYTHON" - "$dump_directory/frame_0.mem" "$CCM_CORRUPT_OUTPUT" <<'PY'
import sys
from pathlib import Path
shift={'1':24, 'R':24, 'G':12, 'B':0}[sys.argv[2]]
p=Path(sys.argv[1]); words=p.read_text().splitlines()
words[42]='{:09x}'.format(int(words[42],16) ^ (1<<shift))
p.write_text('\n'.join(words)+'\n')
PY
            fi
        fi
        for frame in 0 1; do
            "$PYTHON" "$ROOT/tools/compare_rgb_output.py" --expected "$golden_root/$pattern/frame_$frame.mem" \
                --actual "$dump_directory/frame_$frame.mem" --width 16 --height 16
        done
    done
fi
