#!/usr/bin/env bash
# P2 集成入口：all 完整控制/四图案两帧回归；compare 只比较已有产物。
# 复用 VCS 严格 verdict，不改变 P0/P1 根目录或其固定周期断言。
set -euo pipefail
source "$(dirname -- "${BASH_SOURCE[0]}")/vcs_common.sh"
selection=${1:-all}
case "$selection" in all|compare) ;; *) printf 'Usage: %s [all|compare]\n' "$0" >&2; exit 2;; esac

directory="$ROOT/build/p2_blc/pipeline"
golden_root="$ROOT/testdata/output/p2_blc/golden"
dump_root="$ROOT/testdata/output/p2_blc/integration"
patterns=(addr_ramp flat checker gradient)
first_offsets=(64 1024 512 256)
second_offsets=(128 64 4095 0)

if [[ $selection == all ]]; then
    # 每帧由 Python 模型计算不同 expected；计算前移除旧目标，任何失败立即停止。
    # 模型输入和 SRAM MEM 都由同一确定性图案生成器产生，按光栅顺序展开。
    for index in 0 1 2 3; do
        pattern=${patterns[$index]}
        for frame in 0 1; do
            offset=${first_offsets[$index]}
            if [[ $frame == 1 ]]; then offset=${second_offsets[$index]}; fi
            (cd "$ROOT" && "$PYTHON" -m model.generate_blc_golden \
                --input "$ROOT/testdata/synthetic/${pattern}_16x16.npy" \
                --output "$golden_root/$pattern/frame_$frame.mem" --black-level "$offset")
        done
    done
    sources=("$ROOT/tb/integration/tb_blc_pipeline.sv" "$ROOT/tb/models/sram_model.sv" \
             "$ROOT/rtl/top/blc_pipeline.sv" "$ROOT/rtl/top/sram_raw_source.sv" \
             "$ROOT/rtl/memory/sram_reader.sv" "$ROOT/rtl/raw_domain/blc.sv")
    compile_vcs "$directory" tb_blc_pipeline "${sources[@]}"
    args=("+MEM_FILE=$ROOT/testdata/synthetic/flat_16x16.mem" \
          "+GOLDEN0=$golden_root/flat/frame_0.mem" "+GOLDEN1=$golden_root/flat/frame_1.mem" \
          '+BLACK0=1024' '+BLACK1=64')
    run_vcs_case "$directory" controls '[PASS] BLC_PIPELINE' "${args[@]}" '+CASE=controls'
    for case_name in overflow overflow_large; do
        expect_vcs_failure "$directory" "$case_name" 'SRAM_FRAME_TOO_LARGE:' "${args[@]}" "+CASE=$case_name"
    done
    expect_vcs_failure "$directory" forced_failure 'BLC_PIPELINE_FORCED_FAILURE' "${args[@]}" '+CASE=forced_failure'
    # 缺失黄金文件必须导致明确 fatal；绝不能只依赖 readmemh 的警告。
    rm -f "$directory/missing-golden.mem"
    expect_vcs_failure "$directory" missing_golden 'BLC_GOLDEN_FILE_ERROR:' \
        "${args[0]}" "+GOLDEN0=$directory/missing-golden.mem" "${args[2]}" '+CASE=controls'
    # 排除仿真诊断，重新运行实际容量拒绝路径和合法帧恢复。
    hardware_directory="$ROOT/build/p2_blc/pipeline_hardware"
    compile_vcs "$hardware_directory" tb_blc_pipeline +define+SYNTHESIS "${sources[@]}"
    run_vcs_case "$hardware_directory" capacity_reject '[PASS] BLC_PIPELINE' "${args[@]}" '+CASE=capacity_reject'
fi

for index in 0 1 2 3; do
    pattern=${patterns[$index]}
    dump_directory="$dump_root/$pattern"
    if [[ $selection == all ]]; then
        mkdir -p "$dump_directory"
        rm -f "$dump_directory/frame_0.mem" "$dump_directory/frame_1.mem"
        run_vcs_case "$directory" "$pattern" '[PASS] BLC_PIPELINE' \
            "+MEM_FILE=$ROOT/testdata/synthetic/${pattern}_16x16.mem" \
            "+GOLDEN0=$golden_root/$pattern/frame_0.mem" \
            "+GOLDEN1=$golden_root/$pattern/frame_1.mem" \
            "+BLACK0=${first_offsets[$index]}" "+BLACK1=${second_offsets[$index]}" \
            "+DUMP_DIR=$dump_directory" '+CASE=regression'
        # 测试专用破坏开关：只修改本任务的 RTL dump，不修改输入或黄金。
        # 安排在正常仿真后、精确比较前，检验失败能穿透完整 Make 调用链。
        if [[ ${BLC_CORRUPT_OUTPUT:-0} == 1 && $index == 0 ]]; then
            "$PYTHON" - "$dump_directory/frame_0.mem" <<'PY'
import sys
from pathlib import Path
path = Path(sys.argv[1])
words = path.read_text().splitlines()
words[42] = '{:04x}'.format((int(words[42], 16) + 1) % 4096)
path.write_text('\n'.join(words) + '\n')
PY
        fi
    fi
    # 每帧分别比较。旧 compare_frames 对两帧使用同一个 golden，因此不用于 P2。
    # compare 模式不生成文件，才能发现损坏或缺失产物，而不会自动覆盖错误。
    for frame in 0 1; do
        "$PYTHON" "$ROOT/tools/compare_output.py" \
            --expected "$golden_root/$pattern/frame_$frame.mem" \
            --actual "$dump_directory/frame_$frame.mem" --width 16
    done
done
