# CS340 ASan 复现 - 构建脚本
#
#   make            编译全部用例到 build/
#   make run        依次运行全部用例，报告存到 reports/
#   make clean      清理产物
#
# 只在 Linux / macOS 上受支持；Windows 的 MinGW 工具链不带 libasan，
# 请改用 docker/ 目录里的镜像、WSL 或 GitHub Actions。
#
# 关于用例 07：返回栈上地址的检测依赖"假栈"（fake stack）机制，需要编译器
# 生成 __asan_stack_malloc_N 调用。GCC 没有实现这部分，只有 Clang 的
# -fsanitize-address-use-after-return 支持。因此 07 优先用 clang 编译，
# 找不到 clang 时退回 $(CC) 并在运行时给出提示。

CC      ?= gcc
CFLAGS  ?= -std=c11 -g -O1 -fno-omit-frame-pointer -Wall -Wextra
# ASan 需在编译与链接两个阶段同时指定
SANFLAGS ?= -fsanitize=address -fno-common

# 用例 07 专用编译器：有 clang 就用 clang
CLANG_BIN := $(shell command -v clang 2>/dev/null)
ifeq ($(CLANG_BIN),)
CC07 := $(CC)
else
CC07 := clang
endif

BIN_DIR := build
SRC_DIR := src
SOURCES := $(wildcard $(SRC_DIR)/*.c)
TARGETS := $(patsubst $(SRC_DIR)/%.c,$(BIN_DIR)/%,$(SOURCES))

.PHONY: all run clean check-env

all: $(TARGETS)

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

# 每个用例独立成一个可执行文件，方便单点复现
$(BIN_DIR)/%: $(SRC_DIR)/%.c $(SRC_DIR)/common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(SANFLAGS) $< -o $@

# 显式规则优先于上面的模式规则：07 换成 $(CC07)
$(BIN_DIR)/07_stack_use_after_return: $(SRC_DIR)/07_stack_use_after_return.c $(SRC_DIR)/common.h | $(BIN_DIR)
	$(CC07) $(CFLAGS) $(SANFLAGS) $< -o $@

run: all
	@bash scripts/run_all.sh

clean:
	@rm -rf $(BIN_DIR) reports
	@echo "cleaned: $(BIN_DIR)/ reports/"

# 快速确认工具链是否真的带 ASan 运行时
check-env:
	@echo "CC      = $(CC)"
	@echo "CC07    = $(CC07)"
	@echo "CFLAGS  = $(CFLAGS)"
	@echo "SANFLAGS= $(SANFLAGS)"
	@$(CC) --version | head -n 1
	@$(CC07) --version 2>/dev/null | head -n 1 || true
