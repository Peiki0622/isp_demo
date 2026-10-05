#!/usr/bin/env bash
# 两个测试入口共享的最小 VCS 编译/运行判据；不配置或修改工具/许可证环境。
# 必须由设置 set -euo pipefail 的 bash 脚本 source，不提供其他仿真器分支。
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_ROOT="$ROOT/build/p0_p1"
OUTPUT_ROOT="$ROOT/testdata/output/p0_p1"
VCS=${VCS:-vcs}
PYTHON=${PYTHON:-python3}
MEM_FILE=${MEM_FILE:-"$ROOT/testdata/synthetic/addr_ramp_16x16.mem"}
export PYTHONDONTWRITEBYTECODE=1

# 编译接口：隔离目录、顶层名、随后为源文件及额外 VCS 编译选项。
# 删除旧可执行文件与 VCS 时间戳并覆盖日志，防止失败编译后误用旧产物。
# 仅删 simv 时，VCS 可能据时间戳跳过编译并返回 0，却不重新生成可执行文件。
compile_vcs() {
    local directory=$1 top=$2
    shift 2
    mkdir -p "$directory"
    printf 'work_directory=%s\n' "$directory" > "$directory/context.txt"
    rm -f "$directory/simv" "$directory/simv.daidir/.vcs.timestamp" "$directory/compile.log"
    if ! command -v "$VCS" >/dev/null; then
        printf '[FAIL] VCS executable unavailable: %s\n' "$VCS" >&2
        return 1
    fi
    "$VCS" -ID > "$directory/version.txt" 2>&1
    # 保留可复现的精确 argv；%q 使用 bash 转义，记录本身不执行任何内容。
    printf '%q ' "$VCS" -full64 -sverilog -timescale=1ns/1ps -top "$top" \
        -Mdir=csrc -o simv -l compile.log "$@" > "$directory/command.txt"
    printf '\n' >> "$directory/command.txt"
    if ! (cd "$directory" && timeout 120s "$VCS" -full64 -sverilog \
        -timescale=1ns/1ps -top "$top" -Mdir=csrc -o simv -l compile.log "$@") \
        > "$directory/compile.stdout" 2>&1; then
        printf '[FAIL] VCS compilation: %s\n' "$top" >&2
        tail -n 40 "$directory/compile.stdout" >&2
        return 1
    fi
    if [[ ! -x "$directory/simv" ]] || \
        grep -Eq '^(Fatal:|Error(:|-\[)|\[FAIL\])' "$directory/compile.stdout"; then
        printf '[FAIL] VCS compilation verdict: %s\n' "$top" >&2
        return 1
    fi
}

# 运行接口：编译目录、用例名、唯一完整通过标记，随后为仿真 plusargs。
# 不能仅信任 simv 的退出码：当前 VCS 的 $fatal 可返回 0。
# 同时验证进程状态、完整 stdout/stderr、PASS 次数；本次运行前移除旧日志。
run_vcs_case() {
    local directory=$1 case_name=$2 marker=$3 native_status=0 pass_count
    shift 3
    rm -f "$directory/$case_name.log" "$directory/$case_name.stdout"
    printf '%q ' ./simv "$@" -l "$case_name.log" > "$directory/$case_name.command"
    printf '\n' >> "$directory/$case_name.command"
    (cd "$directory" && timeout 30s ./simv "$@" -l "$case_name.log") \
        > "$directory/$case_name.stdout" 2>&1 || native_status=$?
    printf 'process_exit=%s\n' "$native_status" > "$directory/$case_name.status"
    pass_count=$(grep -Fxc -- "$marker" "$directory/$case_name.stdout" || true)
    if [[ $native_status -ne 0 || $pass_count -ne 1 ]] || \
        grep -Eq '^(Fatal:|Error(:|-\[)|\[FAIL\])' "$directory/$case_name.stdout"; then
        printf 'verdict=FAIL\n' >> "$directory/$case_name.status"
        printf '[FAIL] VCS case=%s exit=%s PASS-count=%s; log=%s\n' \
            "$case_name" "$native_status" "$pass_count" "$directory/$case_name.stdout" >&2
        tail -n 20 "$directory/$case_name.stdout" >&2
        return 1
    fi
    printf 'verdict=PASS\n' >> "$directory/$case_name.status"
    printf '%s\n' "$marker"
}

# 预期失败仍先经同一判据得到非零，再核对 fatal 的指定诊断。
# 这样编译/许可证/超时错误不会冒充容量负例通过；诊断不符即失败。
expect_vcs_failure() {
    local directory=$1 case_name=$2 diagnostic=$3
    shift 3
    if run_vcs_case "$directory" "$case_name" '[PASS] UNEXPECTED_NEGATIVE_SUCCESS' "$@" \
        > "$directory/$case_name.verdict" 2>&1; then
        printf '[FAIL] negative case unexpectedly passed: %s\n' "$case_name" >&2
        return 1
    fi
    if ! grep -q '^Fatal:' "$directory/$case_name.stdout" || \
        ! grep -Fq -- "$diagnostic" "$directory/$case_name.stdout" || \
        grep -q '^\[PASS\]' "$directory/$case_name.stdout"; then
        printf '[FAIL] negative case diagnostic mismatch: %s\n' "$case_name" >&2
        cat "$directory/$case_name.verdict" >&2
        return 1
    fi
    printf '[PASS] expected failure: %s\n' "$case_name"
}

# 每个帧单独比较，不把两帧合并成 512 字而遗漏单帧长度错误。
compare_frames() {
    local expected_file=$1 directory=$2 frame
    for frame in 0 1; do
        "$PYTHON" "$ROOT/tools/compare_output.py" --expected "$expected_file" \
            --actual "$directory/frame_$frame.mem" --width 16
    done
}
