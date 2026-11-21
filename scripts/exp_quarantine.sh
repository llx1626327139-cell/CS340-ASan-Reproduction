#!/usr/bin/env bash
#
# Detection-side control for paper sections 3.5 / 4.3:
#   "Quarantine size (default: 256MB). This value controls the ability to find
#    heap-use-after-free bugs."
#
# Method: run the same case (01_heap_use_after_free) once at each of two quarantine
# sizes and keep BOTH the verdict and the raw stderr, so that any claim about a class
# difference can be re-checked later.
#
#   quarantine=256MB (default) -> freed memory goes into the quarantine, shadow 0xFD
#   quarantine=0               -> freed memory returns to the allocator free list at
#                                 once, shadow still 0xFD until the block is reused
#
# Note what this program cannot show: it allocates nothing between free() and the read,
# so the block is never reused and no false negative is possible at any setting. A
# real false negative needs `free(p); q = malloc(same size); read p[...]`.
# See docs/measured/exp_quarantine.md.
#
# Output: docs/measured/exp_quarantine.md  (summary, hand-maintained text below)
#         docs/measured/logs/quarantine_<q>MB.log  (raw stderr of each run)

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT_DIR/build/01_heap_use_after_free"
OUT="$ROOT_DIR/docs/measured/exp_quarantine.md"
LOGDIR="$ROOT_DIR/docs/measured/logs"

if [ ! -x "$BIN" ]; then
    echo "error: $BIN not found, run make first" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUT")" "$LOGDIR"

run_case() {
    local q="$1" log verdict code
    log="$LOGDIR/quarantine_${q}MB.log"
    ASAN_OPTIONS="quarantine_size_mb=$q:detect_leaks=0:symbolize=1" "$BIN" > "$log" 2>&1
    code=$?
    verdict=$(grep -m1 -oE 'AddressSanitizer: [a-z][a-z-]*' "$log" | sed 's/AddressSanitizer: //' || true)
    printf '%s|%s' "$code" "$verdict"
}

a=$(run_case 256)
b=$(run_case 0)
code_a=${a%%|*}; cls_a=${a#*|}
code_b=${b%%|*}; cls_b=${b#*|}

{
    echo "# Experiment: does the quarantine size change use-after-free detectability?"
    echo
    echo "Raw stderr of each run is committed as \`docs/measured/logs/quarantine_256MB.log\`"
    echo "and \`docs/measured/logs/quarantine_0MB.log\`; this table is derived from them."
    echo
    echo "- Run time (UTC): \`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo "- commit: \`$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')\`"
    echo
    echo "| quarantine | Exit code | Reported class |"
    echo "| --- | --- | --- |"
    echo "| 256 MB (default) | $code_a | \`${cls_a:-not detected}\` |"
    echo "| 0 MB | $code_b | \`${cls_b:-not detected}\` |"
    echo
    echo "## Reading"
    echo
    if [ "$code_a" != "0" ] && [ "$code_b" = "0" ]; then
        echo "With the quarantine disabled the access is **not reported at all**. That is"
        echo "the false negative the paper's sentence describes, and it would support the"
        echo "claim — check the two logs to see which allocation reused the block."
    elif [ "$code_a" != "0" ] && [ "$code_b" != "0" ]; then
        echo "Both runs terminate. Termination alone does not support the claim: the paper's"
        echo "sentence is about *missing* a use-after-free, and this program allocates nothing"
        echo "between the \`free\` and the read, so the block cannot be reused and the shadow"
        echo "stays \`0xFD\` at either setting. A difference in the reported class (if the two"
        echo "logs show one) means a different error was reported, not a false negative."
        echo
        echo "This control is therefore recorded as **inconclusive**. The experiment that"
        echo "would test the sentence is \`free(p); q = malloc(same size); read p[...]\`:"
        echo "with the default quarantine the read is still reported as"
        echo "\`heap-use-after-free\`, with \`quarantine_size_mb=0\` the block is reused for"
        echo "\`q\` and the read lands in live memory, which is the false negative."
        echo "It is designed in \`docs/measured/exp_quarantine.md\` but not executed here."
    else
        echo "Unexpected outcome (baseline run did not terminate with an error); inspect the"
        echo "two logs before drawing any conclusion."
    fi
    echo
    echo "## Why the parameter is still recorded"
    echo
    echo "The paper measures performance with the quarantine at 0 and hunts bugs with the"
    echo "default 256 MB. Any reproduction that silently fixes one of the two settings is"
    echo "not comparable with the paper, so the parameter has its own row in the deviation"
    echo "table and its cost side is measured separately (see \`performance.md\`)."
} > "$OUT"

echo "result written to $OUT"
cat "$OUT"
