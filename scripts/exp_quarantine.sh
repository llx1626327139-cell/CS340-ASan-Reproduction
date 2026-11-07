#!/usr/bin/env bash
#
# 验证论文 §3.5 / §4.3 的机制性主张：
#   "Quarantine size (default: 256MB). This value controls the ability to find
#    heap-use-after-free bugs."
#
# 做法：同一个用例（01_heap_use_after_free）在两档隔离区下各跑一次。
#   quarantine=256MB（默认）→ 释放的内存进入隔离区，影子内存标记为"已释放"
#   quarantine=0            → 释放的内存立即回到分配器空闲链
#
# 产物：docs/measured/exp_quarantine.md
# 注意：结论由实测结果生成，不预设"一定漏报"。

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/01_heap_use_after_free"
OUT="$ROOT_DIR/docs/measured/exp_quarantine.md"

if [ ! -x "$BIN" ]; then
    echo "错误：找不到 $BIN，请先 make" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")"

run_case() {
    local q="$1" out code verdict
    out=$(ASAN_OPTIONS="quarantine_size_mb=$q:detect_leaks=0:symbolize=1" "$BIN" 2>&1)
    code=$?
    verdict=$(echo "$out" | grep -m1 -oE 'AddressSanitizer: [a-z][a-z-]*' | sed 's/AddressSanitizer: //' || true)
    printf '%s|%s|%s' "$code" "$verdict" "$( [ -n "$verdict" ] && echo yes || echo no )"
}

a=$(run_case 256)
b=$(run_case 0)
code_a=${a%%|*}; rest_a=${a#*|}; cls_a=${rest_a%%|*}; hit_a=${rest_a##*|}
code_b=${b%%|*}; rest_b=${b#*|}; cls_b=${rest_b%%|*}; hit_b=${rest_b##*|}

show() { if [ "$1" = yes ]; then printf '是（`%s`）' "$2"; else printf '**否**（未检出）'; fi; }

{
    echo "# 实验：隔离区大小对 use-after-free 可检出性的影响"
    echo
    echo "对应论文 §3.5（False Negatives）与 §4.3（Tuning Accuracy And Resource Usage）："
    echo
    echo "> Quarantine size (default: 256MB). This value controls the ability to find heap-use-after-free bugs."
    echo
    echo "被测程序：\`src/01_heap_use_after_free.c\`（malloc(16) → free → 再读 \`buf[2]\`）。"
    echo "16 字节小对象属于最容易被分配器立刻复用的尺寸。"
    echo
    echo "- 运行时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- commit：\`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "| quarantine | 退出码 | 是否报错 | 报告类别 |"
    echo "| --- | --- | --- | --- |"
    echo "| 256 MB（默认） | $code_a | $(show "$hit_a" "$cls_a") | \`${cls_a:-—}\` |"
    echo "| 0 MB | $code_b | $(show "$hit_b" "$cls_b") | \`${cls_b:-—}\` |"
    echo
    echo "## 实测结论"
    echo
    if [ "$hit_a" = yes ] && [ "$hit_b" = no ]; then
        echo "关掉隔离区后该 UAF **不再被检出**，与论文 \"quarantine 决定 UAF 可检出性\" 的说法一致。"
    elif [ "$hit_a" = yes ] && [ "$hit_b" = yes ] && [ "$cls_a" != "$cls_b" ]; then
        echo "关掉隔离区后程序**仍然被杀掉**，但报告类别从 \`$cls_a\` 变成了 \`$cls_b\`。"
        echo "也就是说，这条访问并没有被放过，而是被判成了另一种错误。"
        echo
        echo "最可能的原因（推断，未经源码级验证）：\`quarantine_size_mb=0\` 时 free 立即把"
        echo "该块交还 ASan 分配器，整块用户区被重新标记为红区（影子值 \`0xFA/0xFB\`），"
        echo "而不是保留为\"已释放\"标记（\`0xFD\`）。于是同一次访问在检查时落入红区分支，"
        echo "被归为 \`heap-buffer-overflow\`。"
        echo
        echo "**因此这条实验只支持论文主张的一半**：隔离区确实改变了检测结果（类别改变），"
        echo "但在本微基准上并未导致漏报。要观察到真正的漏报，需要释放后紧接着分配一个"
        echo "同尺寸对象把该内存复用——这属于本实验未覆盖的场景。"
    else
        echo "两档隔离区下结果相同：\`${cls_a:-未检出}\`。说明在这个特定程序和分配序列下，"
        echo "隔离区大小没有改变检测结论，不能据此判断论文该条主张成立与否。"
    fi
    echo
    echo "## 为什么这条实验值得做"
    echo
    echo "论文在测性能时把 quarantine 设为 0、在找 bug 时用默认 256MB —— 同一个工具、"
    echo "同一份代码，只改一个参数，可检出性就可能变化。这正是\"影响结果的设置\"里必须"
    echo "记录的一项，也是偏差表中 \`quarantine\` 一行需要给出理由的原因。"
} > "$OUT"

echo "结果已写入 $OUT"
cat "$OUT"
