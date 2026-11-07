# CS340 ASan 复现 - 构建脚本
#
#   make            编译全部用例到 build/
#   make run        依次运行全部用例，报告存到 reports/
#   make clean      清理产物
#
# 只在 Linux / macOS 上受支持；Windows 的 MinGW 工具链不带 libasan，
# 请改用 docker/ 目录里的镜像或 WSL。

CC      ?= gcc
CFLAGS  ?= -std=c11 -g -O1 -fno-omit-frame-pointer -Wall -Wextra
# ASan 需在编译与链接两个阶段同时指定
SANFLAGS ?= -fsanitize=address -fno-common

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

run: all
	@bash scripts/run_all.sh

clean:
	@rm -rf $(BIN_DIR) reports
	@echo "cleaned: $(BIN_DIR)/ reports/"

# 快速确认工具链是否真的带 ASan 运行时
check-env:
	@echo "CC      = $(CC)"
	@echo "CFLAGS  = $(CFLAGS)"
	@echo "SANFLAGS= $(SANFLAGS)"
	@$(CC) --version | head -n 1
