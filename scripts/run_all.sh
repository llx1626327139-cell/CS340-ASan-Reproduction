#!/usr/bin/env bash
#
# 批量运行全部用例，把每份 ASan 报告落到 reports/ 下，
# 并生成一张汇总表（终端 + reports/summary.md）。
#
# 用法：bash scripts/run_all.sh [build 目录]
#
# 说明：每个用例都"故意崩溃"，所以脚本自身始终以 0 退出，
#       崩溃由用例的退出码体现，不要拿本脚本的退出码做 CI 判定。

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${1:-$ROOT_DIR/build}"
OUT_DIR="$ROOT_DIR/reports"

if [ ! -d "$BIN_DIR" ]; then
    echo "错误：找不到 $BIN_DIR，请先执行 make" >&2
    exit 1
fi

mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.md"

# 统一的 ASan 运行参数：
#   symbolize=1            让报告带函数名与行号
#   abort_on_error=0       崩溃后仍走正常退出流程（便于拿到完整的泄漏报告）
#   detect_stack_use_after_return=0  默认关闭，用例 07 单独打开
export ASAN_OPTIONS="symbolize=1:abort_on_error=0:detect_stack_use_after_return=0:detect_leaks=1"

printf '| %-30s | %-6s | %s\n' "用例" "退出码" "首条 ASan/LeakSanitizer 结论"
printf '|%s|%s|%s\n' "--------------------------------" "--------" "----------------------------------------"
{
    echo "# ASan 复现结果汇总"
    echo
    echo "运行时间：$(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo "编译器：$(${CC:-gcc} --version 2>/dev/null | head -n 1)"
    echo
    echo "| 用例 | 退出码 | 首条 ASan/LeakSanitizer 结论 |"
    echo "| --- | --- | --- |"
} > "$SUMMARY"

shopt -s nullglob
for bin in "$BIN_DIR"/*; do
    [ -x "$bin" ] || continue
    name="$(basename "$bin")"
    log="$OUT_DIR/$name.log"

    # 用例 07 需要显式打开"返回后使用"检查
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
    [ -n "$verdict" ] || verdict="（未检测到，退出码 $code）"

    printf '| %-30s | %-6s | %s\n' "$name" "$code" "$verdict"
    echo "| \`$name\` | $code | $verdict |" >> "$SUMMARY"
done

echo
echo "完整报告：$OUT_DIR/*.log"
echo "汇总表格：$SUMMARY"
