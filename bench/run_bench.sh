#!/usr/bin/env bash
#
# 测量 ASan 的运行时间与内存开销，复现论文 Figure 2 与 Table 1 的口径。
#
# 做法：同一份 bench.c 编两份——基线（-O2）与插桩（-O2 + ASan），
# 各跑 REPEAT 次取中位数，计算倍率。
#
# 用法：bash bench/run_bench.sh
# 产物：docs/measured/performance.md

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/build"
OUT="$ROOT_DIR/docs/measured/performance.md"
REPEAT="${REPEAT:-5}"
CC="${CC:-gcc}"

MODES="malloc_heavy access_heavy mixed"
CFLAGS_BASE="-std=c11 -O2 -g -fno-omit-frame-pointer"
CFLAGS_ASAN="$CFLAGS_BASE -fsanitize=address"

mkdir -p "$BIN_DIR" "$(dirname "$OUT")"

$CC $CFLAGS_BASE bench/bench.c -o "$BIN_DIR/bench_base" || exit 1
$CC $CFLAGS_ASAN bench/bench.c -o "$BIN_DIR/bench_asan" || exit 1

median() { sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'; }

# 跑 N 次，输出 "<时间中位数> <VmHWM中位数> <VmPeak中位数> <VmStk中位数>"
measure() {
    local bin="$1" mode="$2" i out
    local ts=() ms=() ps=() ss=()
    for i in $(seq 1 "$REPEAT"); do
        out=$("$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        ts+=("$(echo "$out" | sed -n 's/.*time_ms=\([0-9.]*\).*/\1/p')")
        ms+=("$(echo "$out" | sed -n 's/.*vmhwm_kb=\([0-9-]*\).*/\1/p')")
        ps+=("$(echo "$out" | sed -n 's/.*vmpeak_kb=\([0-9-]*\).*/\1/p')")
        ss+=("$(echo "$out" | sed -n 's/.*vmstk_kb=\([0-9-]*\).*/\1/p')")
    done
    echo "$(printf '%s\n' "${ts[@]}" | median) $(printf '%s\n' "${ms[@]}" | median) $(printf '%s\n' "${ps[@]}" | median) $(printf '%s\n' "${ss[@]}" | median)"
}

cpu_model=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2- | sed 's/^ *//')
cpu_model=${cpu_model:-?}

{
    echo "# 开销测量结果"
    echo
    echo "复现对象：论文 **Figure 2**（运行时间开销）与 **Table 1**（内存开销）。"
    echo "本文件由 \`bench/run_bench.sh\` 在真实运行环境中自动生成，不是预期值。"
    echo
    echo "- 生成时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- CPU：\`$cpu_model\`"
    echo "- 内核：\`$(uname -r)\`"
    echo "- 编译器：\`$($CC --version | head -1)\`"
    echo "- 重复次数：$REPEAT（取中位数）"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "## 运行时间"
    echo
    echo "| 负载 | 基线 (ms) | ASan (ms) | 倍率 | 论文参照 |"
    echo "| --- | --- | --- | --- | --- |"
} > "$OUT"

MEM_ROWS=""
for mode in $MODES; do
    read -r bt bm bp bs <<< "$(measure "$BIN_DIR/bench_base" "$mode")"
    read -r at am ap as_ <<< "$(measure "$BIN_DIR/bench_asan" "$mode")"
    ratio=$(awk -v a="$at" -v b="$bt" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')
    printf '| `%s` | %s | %s | **%sx** | Figure 2 平均 1.73x |\n' "$mode" "$bt" "$at" "$ratio" >> "$OUT"

    mratio=$(awk -v a="$am" -v b="$bm" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')
    MEM_ROWS+=$(printf '| `%s` | %s | %s | **%sx** | %s | %s |\n' "$mode" "$bm" "$am" "$mratio" "$bp" "$ap")
    MEM_ROWS+=$'\n'
done

{
    echo
    echo "## 内存"
    echo
    echo "论文 Table 1 用 VmPeak；本实验主指标取 VmHWM（峰值常驻），理由见下。"
    echo
    echo "| 负载 | 基线 VmHWM (KB) | ASan VmHWM (KB) | 倍率 | 基线 VmPeak (KB) | ASan VmPeak (KB) |"
    echo "| --- | --- | --- | --- | --- | --- |"
    printf '%s' "$MEM_ROWS"
    echo
    echo "## 读法说明"
    echo
    echo "- **为什么用 VmHWM 而不是 VmPeak**：ASan 的影子内存是 \`MAP_NORESERVE\` 的虚拟保留，"
    echo "  会把 VmPeak 撑到 TB 级（见上表最后一列），跨环境比较完全失真。论文 2012 年的数值"
    echo "  （Table 1，平均 3.37x）是真实驻留量级的增长，因此本实验用 VmHWM 计算倍率，"
    echo "  并把 VmPeak 一并列出以示差异。"
    echo "- 负载是微基准，不是 SPEC CPU2006，**绝对值不可与论文的 73% / 3.37x 直接对比**，"
    echo "  可对比的是量级与趋势。完整偏差见 \`report/REPRODUCTION.md\` 的偏差表。"
    echo
    echo "## 复现方式"
    echo
    echo '```'
    echo "构建：bash bench/run_bench.sh"
    echo "产物：build/bench_base（基线）、build/bench_asan（插桩）"
    echo "单次运行：build/bench_asan malloc_heavy"
    echo '```'
} >> "$OUT"

echo "结果已写入 $OUT"
cat "$OUT"
