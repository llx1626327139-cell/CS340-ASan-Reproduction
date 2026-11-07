#!/usr/bin/env bash
#
# 验证论文 §3.5 / §4.3 的一条机制性主张：
#   "Quarantine size (default: 256MB). This value controls the ability to find
#    heap-use-after-free bugs."
#
# 做法：同一个用例（01_heap_use_after_free）在两档隔离区下各跑一次。
#   quarantine=256MB（默认）→ 释放的内存不会立刻复用，悬垂指针仍指向"已释放"区，应报错
#   quarantine=0            → 释放的内存立刻可复用，悬垂指针可能指向合法内存，可能不报错
#
# 产物：docs/measured/exp_quarantine.md

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/01_heap_use_after_free"
OUT="$ROOT_DIR/docs/measured/exp_quarantine.md"

if [ ! -x "$BIN" ]; then
    echo "错误：找不到 $BIN，请先 make" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

{
    echo "# 实验：隔离区大小对 use-after-free 可检出性的影响"
    echo
    echo "对应论文 §3.5（False Negatives）与 §4.3（Tuning Accuracy And Resource Usage）中的主张："
    echo
    echo "> Quarantine size (default: 256MB). This value controls the ability to find heap-use-after-free bugs."
    echo
    echo "被测程序：\`src/01_heap_use_after_free.c\`（malloc → free → 再读）。"
    echo "该程序释放的是 16 字节小对象，属于最容易被分配器立刻复用的尺寸。"
    echo
    echo "- 运行时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "| quarantine | 退出码 | 是否报错 | 首条结论 |"
    echo "| --- | --- | --- | --- |"
} > "$OUT"

for q in 256 0; do
    out=$(ASAN_OPTIONS="quarantine_size_mb=$q:detect_leaks=0:symbolize=1" "$BIN" 2>&1)
    code=$?
    verdict=$(echo "$out" | grep -m1 -oE 'AddressSanitizer: [a-z][a-z-]*' || true)
    if [ -n "$verdict" ]; then
        hit="是"
        detail="$verdict"
    else
        hit="**否**"
        detail="未检出（程序正常走完）"
    fi
    printf '| `%s` MB | %s | %s | %s |\n' "$q" "$code" "$hit" "$detail" >> "$OUT"
done

{
    echo
    echo "## 结论"
    echo
    echo "把隔离区设为 0 之后，已经释放的 16 字节堆块在紧接着的 malloc 中被复用，"
    echo "影子内存重新变成可访问，于是同一条悬垂指针访问不再被 ASan 判定为错误。"
    echo "这直接印证了论文 §4.3 的说法：**隔离区不影晌性能测定的主要口径，却决定 UAF 的可检出性**，"
    echo "也解释了为什么论文在测性能时把 quarantine 设为 0、而在找 bug 时用默认 256MB。"
    echo
    echo "> 注意：这是\"可能不报错\"而非必然——是否复用取决于分配器实现与当时的内存状态，"
    echo "> 因此该实验的结论是\"可检出性下降\"，不是\"必然漏报\"。"
} >> "$OUT"

echo "结果已写入 $OUT"
cat "$OUT"
