#!/usr/bin/env bash
#
# Run every case in turn, drop each ASan report into reports/,
# and build a summary table (terminal plus reports/summary.md).
#
# Usage: bash scripts/run_all.sh [build directory]
#
# Note: every case is meant to crash, so this script always exits 0 itself.
#       The crash is visible in each case's own exit code; do not use this
#       script's exit code as a CI verdict.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${1:-$ROOT_DIR/build}"
OUT_DIR="$ROOT_DIR/reports"

if [ ! -d "$BIN_DIR" ]; then
    echo "error: $BIN_DIR not found, run make first" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.md"

# Shared ASan runtime settings:
#   symbolize=1            keep function names and line numbers in reports
#   abort_on_error=0       still take the normal exit path (so leak reports are complete)
#   detect_stack_use_after_return=0  off by default, case 07 turns it on
export ASAN_OPTIONS="symbolize=1:abort_on_error=0:detect_stack_use_after_return=0:detect_leaks=1"

printf '| %-30s | %-6s | %s\n' "case" "exit" "first ASan/LeakSanitizer verdict"
printf '|%s|%s|%s\n' "--------------------------------" "--------" "----------------------------------------"
{
    echo "# ASan reproduction summary"
    echo
    echo "Run time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "Compiler: $(${CC:-gcc} --version 2>/dev/null | head -n 1)"
    echo
    echo "| Case | Exit code | First ASan/LeakSanitizer verdict |"
    echo "| --- | --- | --- |"
} > "$SUMMARY"

shopt -s nullglob
for bin in "$BIN_DIR"/*; do
    [ -x "$bin" ] || continue
    name="$(basename "$bin")"
    log="$OUT_DIR/$name.log"

    # Case 07 needs the use-after-return check switched on explicitly
    case "$name" in
        07_*)
            run_options="detect_stack_use_after_return=1:detect_leaks=0"
            ;;
        *)
            run_options="detect_stack_use_after_return=0:detect_leaks=1"
            ;;
    esac

    ASAN_OPTIONS="$run_options" "$bin" > "$log" 2>&1
    code=$?

    verdict="$(grep -m1 -oE '(AddressSanitizer|LeakSanitizer): [A-Za-z0-9 _-]+' "$log" | cut -c1-56)"
    [ -n "$verdict" ] || verdict="(not detected, exit code $code)"

    printf '| %-30s | %-6s | %s\n' "$name" "$code" "$verdict"
    echo "| \`$name\` | $code | $verdict |" >> "$SUMMARY"
done

echo
echo "full reports: $OUT_DIR/*.log"
echo "summary table: $SUMMARY"
