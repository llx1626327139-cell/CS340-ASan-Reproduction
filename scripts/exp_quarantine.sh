#!/usr/bin/env bash
#
# Test the mechanism claim from paper sections 3.5 / 4.3:
#   "Quarantine size (default: 256MB). This value controls the ability to find
#    heap-use-after-free bugs."
#
# Method: run the same case (01_heap_use_after_free) once at each of two quarantine
# sizes.
#   quarantine=256MB (default) -> freed memory goes into the quarantine, its shadow
#                                 is marked as "freed"
#   quarantine=0               -> freed memory returns to the allocator free list
#                                 immediately
#
# Output: docs/measured/exp_quarantine.md
# Note: the conclusion is generated from the measured result; "will miss" is not
# assumed in advance.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/01_heap_use_after_free"
OUT="$ROOT_DIR/docs/measured/exp_quarantine.md"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found, run make first" >&2
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

show() { if [ "$1" = yes ]; then printf 'yes (`%s`)' "$2"; else printf '**no** (not detected)'; fi; }

{
    echo "# Experiment: effect of the quarantine size on use-after-free detectability"
    echo
    echo "Corresponds to paper section 3.5 (False Negatives) and section 4.3 (Tuning"
    echo "Accuracy And Resource Usage):"
    echo
    echo "> Quarantine size (default: 256MB). This value controls the ability to find heap-use-after-free bugs."
    echo
    echo "Program under test: \`src/01_heap_use_after_free.c\` (malloc(16) -> free -> read"
    echo "\`buf[2]\`). A 16-byte object is exactly the size an allocator reuses at once."
    echo
    echo "- Run time (UTC): \`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- commit: \`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "| quarantine | Exit code | Reported | Error class |"
    echo "| --- | --- | --- | --- |"
    echo "| 256 MB (default) | $code_a | $(show "$hit_a" "$cls_a") | \`${cls_a:-n/a}\` |"
    echo "| 0 MB | $code_b | $(show "$hit_b" "$cls_b") | \`${cls_b:-n/a}\` |"
    echo
    echo "## Measured conclusion"
    echo
    if [ "$hit_a" = yes ] && [ "$hit_b" = no ]; then
        echo "With the quarantine disabled the UAF is **no longer detected**, which is"
        echo "consistent with the paper's statement that the quarantine decides whether a"
        echo "UAF is detectable."
    elif [ "$hit_a" = yes ] && [ "$hit_b" = yes ] && [ "$cls_a" != "$cls_b" ]; then
        echo "With the quarantine disabled the program **is still killed**, but the reported"
        echo "class changes from \`$cls_a\` to \`$cls_b\`. In other words the access is not let"
        echo "through; it is classified as a different error."
        echo
        echo "The most likely reason (inferred, not verified at source level): with"
        echo "\`quarantine_size_mb=0\` the free returns the block to the ASan allocator at once,"
        echo "so the whole user area is re-marked as a redzone (shadow \`0xFA/0xFB\`) instead of"
        echo "keeping the \"freed\" marker (\`0xFD\`). The same access therefore falls into the"
        echo "redzone branch during the check and is reported as \`heap-buffer-overflow\`."
        echo
        echo "**This experiment therefore supports only half of the paper's claim**: the"
        echo "quarantine does change the detection result (the class changes), but on this"
        echo "microbenchmark it does not produce a false negative. Observing a real false"
        echo "negative would require allocating an object of the same size immediately after"
        echo "the free so that the memory is reused - a scenario this experiment does not cover."
    else
        echo "Both quarantine sizes give the same result: \`${cls_a:-not detected}\`. For this"
        echo "particular program and allocation sequence the quarantine size does not change"
        echo "the verdict, so nothing can be concluded about the paper's claim from it."
    fi
    echo
    echo "## Why this experiment is worth running"
    echo
    echo "The paper sets the quarantine to 0 when measuring performance and keeps the"
    echo "default 256 MB when hunting for bugs - same tool, same code, one parameter"
    echo "changed, and detectability can change with it. That is exactly the kind of"
    echo "\"setting that affects the results\" which has to be recorded, and the reason the"
    echo "\`quarantine\` row in the deviation table needs a justification."
} > "$OUT"

echo "result written to $OUT"
cat "$OUT"
