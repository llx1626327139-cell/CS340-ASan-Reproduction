#!/usr/bin/env bash
#
# Collect the runtime environment and write docs/measured/environment.md
#
# Covers "the environment (hardware, operating system and kernel version, compiler
# and tool versions, and any settings that affect the results)" from the
# replication requirements. It must run on the same machine or CI runner that
# actually ran the experiments, otherwise the numbers are meaningless.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT_DIR/docs/measured/environment.md}"

mkdir -p "$(dirname "$OUT")"

{
    echo "# Runtime environment"
    echo
    echo "Collected at (UTC): \`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo
    echo "## Hardware"
    echo
    echo '```'
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -E 'Architecture|Model name|^CPU\(s\)|Thread|Core\(s\) per socket|Socket|MHz|BogoMIPS' || true
    else
        grep -E 'model name|cpu cores|processor' /proc/cpuinfo | head -6
    fi
    echo '```'
    echo
    echo "Total memory: \`$(grep MemTotal /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')\`"
    echo
    echo "## Operating system and kernel"
    echo
    echo '```'
    if [ -r /etc/os-release ]; then
        grep -E '^(PRETTY_NAME|VERSION_ID|ID)=' /etc/os-release | tr -d '"'
    fi
    uname -a
    echo '```'
    echo
    echo "- Kernel version: \`$(uname -r)\`"
    echo "- Architecture: \`$(uname -m)\`"
    echo
    echo "## Compilers and tools"
    echo
    echo '```'
    ${CC:-gcc} --version 2>/dev/null | head -n 1 || echo "gcc: not found"
    echo "gcc version: $(${CC:-gcc} -dumpfullversion 2>/dev/null || echo '?')"
    clang --version 2>/dev/null | head -n 2 || echo "clang: not found"
    make --version 2>/dev/null | head -n 1 || true
    bash --version 2>/dev/null | head -n 1 || true
    echo '```'
    echo
    echo "ASan runtime location: \`$(${CC:-gcc} -print-file-name=libasan.so 2>/dev/null)\`"
    echo
    echo "## Settings that affect the results"
    echo
    echo '```'
    echo "ASAN_OPTIONS = ${ASAN_OPTIONS:-<unset>}"
    echo "CFLAGS       = ${CFLAGS:-<default, see Makefile>}"
    echo "SANFLAGS     = ${SANFLAGS:-<default, see Makefile>}"
    echo '```'
    echo
    echo "Timing method: \`clock_gettime(CLOCK_MONOTONIC)\`, single process, serial;"
    echo "every case is repeated five times and the median is reported. Memory figures"
    echo "come from \`/proc/self/status\`."
    echo
    echo "## Code version"
    echo
    echo '```'
    if git -C "$ROOT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
        echo "commit  = $(git -C "$ROOT_DIR" rev-parse HEAD)"
        echo "branch  = $(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
        echo "subject = $(git -C "$ROOT_DIR" log -1 --pretty=%s)"
    else
        echo "not a git working tree"
    fi
    echo "workdir = $ROOT_DIR"
    echo '```'
} > "$OUT"

echo "environment written to $OUT"
