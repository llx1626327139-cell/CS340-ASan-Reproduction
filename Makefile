# CS340 ASan reproduction - build script
#
#   make            compile every case into build/
#   make run        run the cases in order, reports land in reports/
#   make clean      remove build artefacts
#
# Supported on Linux and macOS only. MinGW on Windows ships no libasan, so use
# the image in docker/, WSL, or GitHub Actions instead.
#
# About case 07: detecting a use of a stack address after return relies on the
# "fake stack" mechanism, which requires the compiler to emit calls to
# __asan_stack_malloc_N. GCC never implemented that part; only Clang's
# -fsanitize-address-use-after-return does. Case 07 is therefore built with
# clang when available, and falls back to $(CC) with a runtime hint otherwise.

CC      ?= gcc
CFLAGS  ?= -std=c11 -g -O1 -fno-omit-frame-pointer -Wall -Wextra
# ASan has to be requested at both compile and link time
SANFLAGS ?= -fsanitize=address -fno-common

# Dedicated compiler for case 07: prefer clang when present
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

# Each case becomes its own executable so a single case can be reproduced alone
$(BIN_DIR)/%: $(SRC_DIR)/%.c $(SRC_DIR)/common.h | $(BIN_DIR)
	$(CC) $(CFLAGS) $(SANFLAGS) $< -o $@

# An explicit rule overrides the pattern rule above: case 07 uses $(CC07)
$(BIN_DIR)/07_stack_use_after_return: $(SRC_DIR)/07_stack_use_after_return.c $(SRC_DIR)/common.h | $(BIN_DIR)
	$(CC07) $(CFLAGS) $(SANFLAGS) $< -o $@

run: all
	@bash scripts/run_all.sh

clean:
	@rm -rf $(BIN_DIR) reports
	@echo "cleaned: $(BIN_DIR)/ reports/"

# Quick check that the toolchain really ships the ASan runtime
check-env:
	@echo "CC      = $(CC)"
	@echo "CC07    = $(CC07)"
	@echo "CFLAGS  = $(CFLAGS)"
	@echo "SANFLAGS= $(SANFLAGS)"
	@$(CC) --version | head -n 1
	@$(CC07) --version 2>/dev/null | head -n 1 || true
