#!/usr/bin/env bash
#
# 采集运行环境，生成 docs/measured/environment.md
#
# 对应复现要求里的 "the environment (hardware, operating system and kernel
# version, compiler and tool versions, and any settings that affect the results)"。
# 必须在真正跑实验的同一台机器 / 同一个 CI runner 上执行，否则数字无意义。

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT_DIR/docs/measured/environment.md}"

mkdir -p "$(dirname "$OUT")"

{
    echo "# 运行环境"
    echo
    echo "采集时间（UTC）：\`$(date -u '+%Y-%m-%d %H:%M:%S')\`"
    echo
    echo "## 硬件"
    echo
    echo '```'
    if command -v lscpu >/dev/null 2>&1; then
        lscpu | grep -E 'Architecture|Model name|^CPU\(s\)|Thread|Core\(s\) per socket|Socket|MHz|BogoMIPS' || true
    else
        grep -E 'model name|cpu cores|processor' /proc/cpuinfo | head -6
    fi
    echo '```'
    echo
    echo "内存总量：\`$(grep MemTotal /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')\`"
    echo
    echo "## 操作系统与内核"
    echo
    echo '```'
    if [ -r /etc/os-release ]; then
        grep -E '^(PRETTY_NAME|VERSION_ID|ID)=' /etc/os-release | tr -d '"'
    fi
    uname -a
    echo '```'
    echo
    echo "- 内核版本：\`$(uname -r)\`"
    echo "- 架构：\`$(uname -m)\`"
    echo
    echo "## 编译器与工具"
    echo
    echo '```'
    ${CC:-gcc} --version 2>/dev/null | head -n 1 || echo "gcc: not found"
    echo "gcc version: $(${CC:-gcc} -dumpfullversion 2>/dev/null || echo '?')"
    clang --version 2>/dev/null | head -n 2 || echo "clang: not found"
    make --version 2>/dev/null | head -n 1 || true
    bash --version 2>/dev/null | head -n 1 || true
    echo '```'
    echo
    echo "ASan 运行库来源：\`$(${CC:-gcc} -print-file-name=libasan.so 2>/dev/null)\`"
    echo
    echo "## 影响结果的设置"
    echo
    echo '```'
    echo "ASAN_OPTIONS = ${ASAN_OPTIONS:-<unset>}"
    echo "CFLAGS       = ${CFLAGS:-<默认值，见 Makefile>}"
    echo "SANFLAGS     = ${SANFLAGS:-<默认值，见 Makefile>}"
    echo '```'
    echo
    echo "基准计时方式：\`clock_gettime(CLOCK_MONOTONIC)\`，单进程串行执行，"
    echo "每个用例重复 5 次取中位数；内存取自 \`/proc/self/status\`。"
    echo
    echo "## 代码版本"
    echo
    echo '```'
    if git -C "$ROOT_DIR" rev-parse --short HEAD >/dev/null 2>&1; then
        echo "commit  = $(git -C "$ROOT_DIR" rev-parse HEAD)"
        echo "branch  = $(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
        echo "subject = $(git -C "$ROOT_DIR" log -1 --pretty=%s)"
    else
        echo "非 git 工作区"
    fi
    echo "workdir = $ROOT_DIR"
    echo '```'
} > "$OUT"

echo "环境信息已写入 $OUT"
