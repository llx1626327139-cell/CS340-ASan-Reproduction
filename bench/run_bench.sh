#!/usr/bin/env bash
#
# 测量 ASan 的运行时间与内存开销，复现论文 Figure 2 与 Table 1 的口径。
#
# 三种配置对照：
#   base         基线：-O2，不插桩
#   asan_default 插桩：-O2 + ASan，运行参数用默认值（quarantine 256MB、redzone 128B）
#   asan_paper   插桩 + 对齐论文 §4 的测量设置（quarantine 0、redzone 32B、malloc 不展开栈）
#
# 论文 §4 原文：'We used 32-byte red zones, disabled the stack unwinding during
# malloc and free and set the quarantine size to zero'。不跟上这条，malloc 密集
# 负载的倍率会被 256MB 隔离区放大一个数量级，与论文完全不可比。
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

# 论文 §4 的测量设置
PAPER_OPTS="quarantine_size_mb=0:redzone=32:malloc_context_size=0"

mkdir -p "$BIN_DIR" "$(dirname "$OUT")"

$CC $CFLAGS_BASE bench/bench.c -o "$BIN_DIR/bench_base" || exit 1
$CC $CFLAGS_ASAN bench/bench.c -o "$BIN_DIR/bench_asan" || exit 1

# 二进制体积（对应论文 §4 正文的 1.5~3.2x、平均 2.5x）
sz_base=$(stat -c%s "$BIN_DIR/bench_base" 2>/dev/null || echo 0)
sz_asan=$(stat -c%s "$BIN_DIR/bench_asan" 2>/dev/null || echo 0)
sz_ratio=$(awk -v a="$sz_asan" -v b="$sz_base" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')

median() { sort -n | awk '{a[NR]=$1} END {print (NR%2) ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2}'; }

# measure <bin> <mode> [ASAN_OPTIONS]
# 输出 "<时间中位数> <VmHWM中位数> <VmPeak中位数> <VmStk中位数>"
measure() {
    local bin="$1" mode="$2" opts="${3:-}" i out
    local ts=() ms=() ps=() ss=()
    for i in $(seq 1 "$REPEAT"); do
        if [ -n "$opts" ]; then
            out=$(ASAN_OPTIONS="$opts" "$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        else
            out=$("$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        fi
        ts+=("$(echo "$out" | sed -n 's/.*time_ms=\([0-9.]*\).*/\1/p')")
        ms+=("$(echo "$out" | sed -n 's/.*vmhwm_kb=\([0-9-]*\).*/\1/p')")
        ps+=("$(echo "$out" | sed -n 's/.*vmpeak_kb=\([0-9-]*\).*/\1/p')")
        ss+=("$(echo "$out" | sed -n 's/.*vmstk_kb=\([0-9-]*\).*/\1/p')")
    done
    echo "$(printf '%s\n' "${ts[@]}" | median) $(printf '%s\n' "${ms[@]}" | median) $(printf '%s\n' "${ps[@]}" | median) $(printf '%s\n' "${ss[@]}" | median)"
}

ratio() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", (b>0)?a/b:0}'; }

cpu_model=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2- | sed 's/^ *//')
cpu_model=${cpu_model:-?}

{
    echo "# 开销测量结果"
    echo
    echo "复现对象：论文 **Figure 2**（运行时间开销，平均 1.73x）与 **Table 1**（内存开销，平均 3.37x）。"
    echo "本文件由 \`bench/run_bench.sh\` 在真实运行环境中自动生成，不是预期值。"
    echo
    echo "- 生成时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- CPU：\`$cpu_model\`"
    echo "- 内核：\`$(uname -r)\`"
    echo "- 编译器：\`$($CC --version | head -1)\`"
    echo "- 重复次数：$REPEAT（取中位数）"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "三组配置：**base** = 不插桩基线；**asan_default** = 默认 ASan 参数；"
    echo "**asan_paper** = ASan + 论文 §4 的测量设置（\`$PAPER_OPTS\`）。"
    echo
    echo "## 运行时间"
    echo
    echo "| 负载 | base (ms) | asan_default (ms) | 倍率 | asan_paper (ms) | 倍率 |"
    echo "| --- | --- | --- | --- | --- | --- |"
} > "$OUT"

MEM_ROWS=""
for mode in $MODES; do
    read -r bt _ _ _ <<< "$(measure "$BIN_DIR/bench_base" "$mode")"
    read -r dt _ _ _ <<< "$(measure "$BIN_DIR/bench_asan" "$mode")"
    read -r pt _ _ _ <<< "$(measure "$BIN_DIR/bench_asan" "$mode" "$PAPER_OPTS")"
    printf '| `%s` | %s | %s | **%sx** | %s | **%sx** |\n' \
        "$mode" "$bt" "$dt" "$(ratio "$dt" "$bt")" "$pt" "$(ratio "$pt" "$bt")" >> "$OUT"

    read -r _ bm bp _ <<< "$(measure "$BIN_DIR/bench_base" "$mode")"
    read -r _ dm dp _ <<< "$(measure "$BIN_DIR/bench_asan" "$mode")"
    read -r _ pm pp _ <<< "$(measure "$BIN_DIR/bench_asan" "$mode" "$PAPER_OPTS")"
    MEM_ROWS+=$(printf '| `%s` | %s | %s | **%sx** | %s | **%sx** | %s | %s |\n' \
        "$mode" "$bm" "$dm" "$(ratio "$dm" "$bm")" "$pm" "$(ratio "$pm" "$bm")" "$bp" "$dp")
    MEM_ROWS+=$'\n'
done

{
    echo
    echo "## 内存（VmHWM，峰值常驻）"
    echo
    echo "| 负载 | base (KB) | asan_default (KB) | 倍率 | asan_paper (KB) | 倍率 | base VmPeak | asan VmPeak |"
    echo "| --- | --- | --- | --- | --- | --- | --- | --- |"
    printf '%s' "$MEM_ROWS"
    echo
    echo "## 二进制体积"
    echo
    echo "对应论文 §4 正文：SPEC CPU2006 上体积膨胀 1.5x~3.2x，平均 2.5x。"
    echo
    echo "| 构建 | 文件 | 字节 | 倍率 |"
    echo "| --- | --- | --- | --- |"
    echo "| base | build/bench_base | $sz_base | 1.00x |"
    echo "| asan | build/bench_asan | $sz_asan | **${sz_ratio}x** |"
    echo
    echo "## 读法说明"
    echo
    echo "1. **为什么内存主指标用 VmHWM 而不是论文的 VmPeak**：ASan 的影子内存是"
    echo "   \`MAP_NORESERVE\` 的虚拟保留，VmPeak 会被撑到约 20 TB（见最后两列），"
    echo "   拿它算倍率毫无意义。论文 2012 年的 3.37x 反映的是真实驻留量级增长，"
    echo "   因此这里用 VmHWM 计算倍率。"
    echo "2. **两组 ASan 数字的差异主要来自隔离区**：\`quarantine=0\` 让 free 立即归还，"
    echo "   而默认 256MB 会把 `malloc_heavy` 的倍率放大一个数量级。论文在测性能时"
    echo "   正是关掉隔离区的，所以 **asan_paper 这一列才是与论文可比的口径**。"
    echo "3. 负载是自造微基准，不是 SPEC CPU2006，绝对值不可与论文 73% / 3.37x 直接对比，"
    echo "   可对比的是量级与趋势。"
    echo
    echo "## 复现方式"
    echo
    echo '```'
    echo "bash bench/run_bench.sh"
    echo "单次运行： ASAN_OPTIONS=$PAPER_OPTS ./build/bench_asan malloc_heavy"
    echo '```'
} >> "$OUT"

echo "结果已写入 $OUT"
cat "$OUT"
