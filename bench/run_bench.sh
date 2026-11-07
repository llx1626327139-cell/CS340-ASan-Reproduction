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

mkdir -p "$BIN_DIR" "$(dirname "$OUT")"

# 基线：不加 ASan；插桩：加 ASan。其余优化选项一致，保证可比。
$CC -std=c11 -O2 -g -fno-omit-frame-pointer bench/bench.c -o "$BIN_DIR/bench_base" || exit 1
$CC -std=c11 -O2 -g -fno-omit-frame-pointer -fsanitize=address bench/bench.c -o "$BIN_DIR/bench_asan" || exit 1

median() { sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'; }

# 跑 N 次，输出 "<时间中位数> <vmhwm中位数> <vmpeak中位数> <vmstk中位数>"
measure() {
    local bin="$1" mode="$2" i out t m vmhwm vmpeak vmstk
    local ts=() ms=() ps=() ss=()
    for i in $(seq 1 "$REPEAT"); do
        out=$("$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        t=$(echo "$out" | sed -n 's/.*time_ms=\([0-9.]*\).*/\1/p')
        m=$(echo "$out" | sed -n 's/.*vmhwm_kb=\([0-9-]*\).*/\1/p')
        vmpeak=$(echo "$out" | sed -n 's/.*vmpeak_kb=\([0-9-]*\).*/\1/p')
        vmstk=$(echo "$out" | sed -n 's/.*vmstk_kb=\([0-9-]*\).*/\1/p')
        ts+=("$t"); ms+=("$m"); ps+=("$vmpeak"); ss+=("$vmstk")
    done
    echo "$(printf '%s\n' "${ts[@]}" | median) $(printf '%s\n' "${ms[@]}" | median) $(printf '%s\n' "${ps[@]}" | median) $(printf '%s\n' "${ss[@]}" | median)"
}

cpu_model=$( (lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2-) || echo "?" )
cpu_model=$(echo "$cpu_model" | sed 's/^ *//')

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

for mode in $MODES; do
    read -r bt bm bp bs <<< "$(measure "$BIN_DIR/bench_base" "$mode")"
    read -r at am ap as_ <<< "$(measure "$BIN_DIR/bench_asan" "$mode")"
    ratio=$(awk -v a="$at" -v b="$bt" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')
    ref="Figure 2 平均 73%"
    printf '| `%s` | %s | %s | **%sx** | %s |\n' "$mode" "$bt" "$at" "$ratio" "$ref" >> "$OUT"
done

{
    echo
    echo "## 内存"
    echo
    echo "| 负载 | 基线 VmHWM (KB) | ASan VmHWM (KB) | 倍率 | 基线 VmPeak (KB) | ASan VmPeak (KB) |"
    echo "| --- | --- | --- | --- | --- | --- |"
} >> "$OUT"

for mode in $MODES; do
    read -r bt bm bp bs <<< "$(measure "$BIN_DIR/bench_base" "$mode")"
    read -r at am ap as_ <<< "$(measure "$BIN_DIR/bench_asan" "$mode")"
    ratio=$(awk -v a="$am" -v b="$bm" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')
    printf '| `%s` | %s | %s | **%sx** | %s | %s |\n' "$mode" "$bm" "$am" "$ratio" "$bp" "$ap" >> "$OUT"
done

{
    echo
    echo "## 读法说明"
    echo
    echo "- **VmHWM**（峰值常驻内存）是这里的主指标。论文用 VmPeak（虚拟峰值），"
    echo "  但 ASan 的影子内存是 \`MAP_NORESERVE\` 的虚拟保留，会把 VmPeak 撑到 TB 级，"
    echo "  跨版本比较完全失真；因此本实验同时给出两者，只用 VmHWM 计算倍率。"
    echo "- 负载是微基准，不是 SPEC CPU2006，绝对值不可与论文的 73% / 3.37x 直接对比，"
    echo "  可对比的是**量级与趋势**。完整偏差见 \`report/REPRODUCTION.md\` 的偏差表。"
    echo
    echo "## 原始输出"
    echo
    echo '```'
    echo "基线可执行文件: build/bench_base"
    echo "插桩可执行文件: build/bench_asan"
    echo "复现命令:       bash bench/run_bench.sh"
    echo '```'
} >> "$OUT"

echo "结果已写入 $OUT"
cat "$OUT"
