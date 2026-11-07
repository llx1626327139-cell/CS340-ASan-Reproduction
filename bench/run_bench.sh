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
# 统计口径按课程要求：每个配置跑 REPEAT(>=3) 次，报告 mean ± stddev。
# 每一次运行的原始数值写入 docs/measured/raw_runs.tsv，保证报告里的数字可追溯。
#
# 用法：bash bench/run_bench.sh
# 产物：docs/measured/performance.md、docs/measured/raw_runs.tsv

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/build"
OUT="$ROOT_DIR/docs/measured/performance.md"
RAW="$ROOT_DIR/docs/measured/raw_runs.tsv"
REPEAT="${REPEAT:-5}"
CC="${CC:-gcc}"

MODES="malloc_heavy access_heavy mixed"
CFLAGS_BASE="-std=c11 -O2 -g -fno-omit-frame-pointer"
CFLAGS_ASAN="$CFLAGS_BASE -fsanitize=address"
PAPER_OPTS="quarantine_size_mb=0:redzone=32:malloc_context_size=0"

mkdir -p "$BIN_DIR" "$(dirname "$OUT")"

$CC $CFLAGS_BASE bench/bench.c -o "$BIN_DIR/bench_base" || exit 1
$CC $CFLAGS_ASAN bench/bench.c -o "$BIN_DIR/bench_asan" || exit 1

# 二进制体积（对应论文 §4 正文的 1.5~3.2x、平均 2.5x）
sz_base=$(stat -c%s "$BIN_DIR/bench_base" 2>/dev/null || echo 0)
sz_asan=$(stat -c%s "$BIN_DIR/bench_asan" 2>/dev/null || echo 0)
sz_ratio=$(awk -v a="$sz_asan" -v b="$sz_base" 'BEGIN{printf "%.2f", (b>0)?a/b:0}')

printf 'mode\tconfig\trun\ttime_ms\tvmhwm_kb\tvmpeak_kb\tvmstk_kb\n' > "$RAW"

# 单配置跑 REPEAT 次，逐次追加原始数据
one_run() {
    local bin="$1" mode="$2" cfg="$3" opts="${4:-}" i out
    for i in $(seq 1 "$REPEAT"); do
        if [ -n "$opts" ]; then
            out=$(ASAN_OPTIONS="$opts" "$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        else
            out=$("$bin" "$mode" 2>/dev/null | grep '^RESULT' | tail -1)
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$mode" "$cfg" "$i" \
            "$(echo "$out" | sed -n 's/.*time_ms=\([0-9.]*\).*/\1/p')" \
            "$(echo "$out" | sed -n 's/.*vmhwm_kb=\([0-9-]*\).*/\1/p')" \
            "$(echo "$out" | sed -n 's/.*vmpeak_kb=\([0-9-]*\).*/\1/p')" \
            "$(echo "$out" | sed -n 's/.*vmstk_kb=\([0-9-]*\).*/\1/p')" >> "$RAW"
    done
}

# stats <mode> <config> <列号>
# 输出 "mean std"：逐次运行之间的样本标准差（n-1）
stats() {
    awk -F'\t' -v m="$1" -v c="$2" -v col="$3" '
        $1==m && $2==c && $col!="" {
            n++; v[n]=$col+0; s+=$col+0
        }
        END {
            if (n==0) { print "0.00 0.00"; exit }
            mean=s/n
            ss=0
            if (n>1) {
                for (i=1;i<=n;i++) { d=v[i]-mean; ss+=d*d }
                sd=sqrt(ss/(n-1))
            } else {
                sd=0
            }
            printf "%.2f %.2f\n", mean, sd
        }' "$RAW"
}

cv() { awk -v m="$1" -v s="$2" 'BEGIN{printf "%.1f", (m>0)?100*s/m:0}'; }
ratio() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", (b>0)?a/b:0}'; }

cpu_model=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2- | sed 's/^ *//')
cpu_model=${cpu_model:-?}

for mode in $MODES; do
    one_run "$BIN_DIR/bench_base" "$mode" "base" ""
    one_run "$BIN_DIR/bench_asan" "$mode" "asan_default" ""
    one_run "$BIN_DIR/bench_asan" "$mode" "asan_paper" "$PAPER_OPTS"
done

{
    echo "# 开销测量结果"
    echo
    echo "复现对象：论文 **Figure 2**（运行时间开销，平均 1.73x）与 **Table 1**（内存开销，平均 3.37x）。"
    echo "本文件由 \`bench/run_bench.sh\` 在真实运行环境中自动生成，不是预期值；"
    echo "每次运行的原始数值见 \`docs/measured/raw_runs.tsv\`。"
    echo
    echo "- 生成时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- CPU：\`$cpu_model\`"
    echo "- 内核：\`$(uname -r)\`"
    echo "- 编译器：\`$($CC --version | head -1)\`"
    echo "- 运行次数：每配置 $REPEAT 次，报告 mean ± stddev（样本标准差，n-1）"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "配置：**base** = 不插桩基线；**asan_default** = 默认 ASan 参数；"
    echo "**asan_paper** = ASan + 论文 §4 的测量设置（\`$PAPER_OPTS\`）。"
    echo
    echo "## 表 1  运行时间（ms，mean ± stddev，$REPEAT 次）"
    echo
    echo "| 负载 | base | asan_default | 倍率 | asan_paper | 倍率 |"
    echo "| --- | --- | --- | --- | --- | --- |"
} > "$OUT"

for mode in $MODES; do
    read -r btm bts <<< "$(stats "$mode" base 4)"
    read -r dtm dts <<< "$(stats "$mode" asan_default 4)"
    read -r ptm pts <<< "$(stats "$mode" asan_paper 4)"
    printf '| `%s` | %s ± %s | %s ± %s | **%sx** | %s ± %s | **%sx** |\n' \
        "$mode" "$btm" "$bts" "$dtm" "$dts" "$(ratio "$dtm" "$btm")" \
        "$ptm" "$pts" "$(ratio "$ptm" "$btm")" >> "$OUT"
done

{
    echo
    echo "### 表 1b  测量噪声（变异系数 = stddev / mean）"
    echo
    echo "| 负载 | base | asan_default | asan_paper |"
    echo "| --- | --- | --- | --- |"
} >> "$OUT"

for mode in $MODES; do
    read -r btm bts <<< "$(stats "$mode" base 4)"
    read -r dtm dts <<< "$(stats "$mode" asan_default 4)"
    read -r ptm pts <<< "$(stats "$mode" asan_paper 4)"
    printf '| `%s` | %s%% | %s%% | %s%% |\n' "$mode" "$(cv "$btm" "$bts")" "$(cv "$dtm" "$dts")" "$(cv "$ptm" "$pts")" >> "$OUT"
done

{
    echo
    echo "## 表 2  内存（VmHWM，KB，mean ± stddev，$REPEAT 次）"
    echo
    echo "| 负载 | base | asan_default | 倍率 | asan_paper | 倍率 |"
    echo "| --- | --- | --- | --- | --- | --- |"
} >> "$OUT"

for mode in $MODES; do
    read -r bmm bms <<< "$(stats "$mode" base 5)"
    read -r dmm dms <<< "$(stats "$mode" asan_default 5)"
    read -r pmm pms <<< "$(stats "$mode" asan_paper 5)"
    printf '| `%s` | %s ± %s | %s ± %s | **%sx** | %s ± %s | **%sx** |\n' \
        "$mode" "$bmm" "$bms" "$dmm" "$dms" "$(ratio "$dmm" "$bmm")" \
        "$pmm" "$pms" "$(ratio "$pmm" "$bmm")" >> "$OUT"
done

{
    echo
    echo "## 表 3  二进制体积"
    echo
    echo "对应论文 §4 正文：SPEC CPU2006 上 1.5x~3.2x，平均 2.5x。"
    echo
    echo "| 构建 | 文件 | 字节 | 倍率 |"
    echo "| --- | --- | --- | --- |"
    echo "| base | build/bench_base | $sz_base | 1.00x |"
    echo "| asan | build/bench_asan | $sz_asan | **${sz_ratio}x** |"
    echo
    echo "## 读法说明"
    echo
    echo "1. **内存主指标是 VmHWM 而非论文的 VmPeak**：ASan 的影子内存是 \`MAP_NORESERVE\`"
    echo "   的虚拟保留，VmPeak 会被撑到约 20 TB，无法据此算倍率。论文 2012 年的 3.37x"
    echo "   反映的是真实驻留量级增长。"
    echo "2. **两组 ASan 数字的差异主要来自隔离区**：\`quarantine=0\` 让 free 立即归还，"
    echo "   而默认 256MB 会把 \`malloc_heavy\` 的倍率显著放大。论文测性能时正是关掉隔离区的，"
    echo "   所以 **asan_paper 这一列才是与论文可比的口径**。"
    echo "3. 负载是自造微基准，不是 SPEC CPU2006，绝对值不可与 73% / 3.37x 直接对比，"
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
echo "原始数据已写入 $RAW"
tail -20 "$OUT"
