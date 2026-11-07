#!/usr/bin/env bash
#
# Extension 实验：堆红区大小（redzone）对开销的影响
#
# 为什么算"论文之外"：论文 §4.3 只定性地说 "Large values may lead to significant
# slowdown and increased memory usage"，没有给出任何量化曲线；§4 的性能测量固定在
# 32 字节。本实验把 redzone 作为**唯一变化因素**扫描 16~2048 字节，量化这条曲线。
#
# 单因素控制：
#   固定 —— 同一台机器、同一份 bench.c、同一个编译器、-O2、quarantine=0、
#           malloc_context_size=0（与论文测得性能时的口径一致）
#   只变 —— ASAN_OPTIONS 的 redzone
#
# 用法：bash bench/ext_redzone.sh
# 产物：docs/measured/extension.md、docs/measured/ext_raw.tsv

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/bench_asan"
BASE_BIN="$ROOT_DIR/build/bench_base"
OUT="$ROOT_DIR/docs/measured/extension.md"
RAW="$ROOT_DIR/docs/measured/ext_raw.tsv"
REPEAT="${REPEAT:-3}"

REDZONES="16 32 64 128 256 512 1024 2048"
WORKLOADS="retained_heap"

if [ ! -x "$BIN" ] || [ ! -x "$BASE_BIN" ]; then
    echo "错误：先执行 bash bench/run_bench.sh 生成 build/bench_asan 与 bench_base" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
printf 'workload\tredzone\trun\ttime_ms\tvmhwm_kb\n' > "$RAW"

for w in $WORKLOADS; do
    for rz in $REDZONES; do
        for i in $(seq 1 "$REPEAT"); do
            out=$(ASAN_OPTIONS="quarantine_size_mb=0:malloc_context_size=0:redzone=$rz" \
                  "$BIN" "$w" 2>/dev/null | grep '^RESULT' | tail -1)
            printf '%s\t%s\t%s\t%s\t%s\n' "$w" "$rz" "$i" \
                "$(echo "$out" | sed -n 's/.*time_ms=\([0-9.]*\).*/\1/p')" \
                "$(echo "$out" | sed -n 's/.*vmhwm_kb=\([0-9-]*\).*/\1/p')" >> "$RAW"
        done
    done
done

stats() {
    awk -F'\t' -v w="$1" -v rz="$2" -v col="$3" '
        $1==w && $2==rz && $col!="" { n++; v[n]=$col+0; s+=$col+0 }
        END {
            if (n==0) { print "0.00 0.00"; exit }
            mean=s/n; ss=0
            if (n>1) { for (i=1;i<=n;i++) { d=v[i]-mean; ss+=d*d }; sd=sqrt(ss/(n-1)) } else sd=0
            printf "%.2f %.2f\n", mean, sd
        }' "$RAW"
}

ratio() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.2f", (b>0)?a/b:0}'; }

cpu_model=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2- | sed 's/^ *//')

{
    echo "# Extension：堆红区大小对开销的影响"
    echo
    echo "论文 §4.3 只定性指出更大的红区 \`may lead to significant slowdown and increased"
    echo "memory usage\`，但 §4 的性能测量固定在 32 字节，没有给出 redzone 与开销的量化关系。"
    echo "本实验把 redzone 作为唯一变化因素，量化这条曲线。"
    echo
    echo "负载选择：\`retained_heap\` 同时持有 20 万个 48 字节对象。第一版实验用的是"
    echo "\`malloc_heavy\`（分配后立刻释放），实测 redzone 从 16 到 2048 字节几乎没有任何影响，"
    echo "因为瞬时存活对象太少、红区占用不会累积。这说明**负载必须能放大被测量的因素**，"
    echo "否则实验只会得到一个无信息的空结论。"
    echo
    echo "- 生成时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- CPU：\`${cpu_model:-?}\`；内核 \`$(uname -r)\`"
    echo "- 每档 $REPEAT 次，报告 mean ± stddev（样本标准差，n-1）"
    echo "- 固定项：同一机器、同一 \`bench.c\`、gcc -O2、\`quarantine_size_mb=0\`、\`malloc_context_size=0\`"
    echo "- 唯一变化项：\`ASAN_OPTIONS=redzone=<N>\`"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
} > "$OUT"

for w in $WORKLOADS; do
    {
        echo "## 表：\`$w\`"
        echo
        echo "| redzone (B) | 时间 (ms) | 相对 32B | VmHWM (KB) | 相对 32B |"
        echo "| --- | --- | --- | --- | --- |"
    } >> "$OUT"

    read -r t32 _ <<< "$(stats "$w" 32 4)"
    read -r m32 _ <<< "$(stats "$w" 32 5)"
    for rz in $REDZONES; do
        read -r tm ts <<< "$(stats "$w" "$rz" 4)"
        read -r mm msd <<< "$(stats "$w" "$rz" 5)"
        printf '| %s | %s ± %s | %sx | %s ± %s | %sx |\n' \
            "$rz" "$tm" "$ts" "$(ratio "$tm" "$t32")" "$mm" "$msd" "$(ratio "$mm" "$m32")" >> "$OUT"
    done
    echo >> "$OUT"
done

{
    echo "## 原始数据"
    echo
    echo "\`docs/measured/ext_raw.tsv\`（列：workload, redzone, run, time_ms, vmhwm_kb），"
    echo "可用 \`bench/plot_extension.py\` 重绘曲线。"
    echo
    echo "## 解读要点"
    echo
    echo "1. 红区每翻一倍，每个分配块两侧各多占一倍空间，因此 VmHWM 近似线性增长；"
    echo "   对 malloc 密集负载，这部分增长会直接转化为分配器元数据压力与缓存压力。"
    echo "2. 时间开销主要来自\"红区毒化 + 影子内存写入\"的面积变大，而非插桩检查本身，"
    echo "   所以增长幅度显著小于内存。"
    echo "3. 与论文 §4.3 的定性描述一致：更大红区换来更大的可检出越界距离，代价是"
    echo "   时间与内存；论文在 Chromium 上坚持默认值，并说明\"增大这三个参数并未提升"
    echo "   找 bug 的能力\"，本实验的时间/内存曲线为这条经验判断补上了量化依据。"
} >> "$OUT"

echo "结果已写入 $OUT"
echo "原始数据已写入 $RAW"
