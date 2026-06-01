# Build simple Linux x86_64 utilities written in NASM assembly.
#
# Each source file in src/*.asm becomes its own binary in build/.
# There is intentionally no shared runtime or multicall dispatcher here;
# the goal is for each utility to be readable on its own.

NASM ?= nasm
LD ?= ld

SRC_DIR := src
BUILD_DIR := build

TOOLS := true false echo yes pwd arch ascii clear uname env printenv sleep usleep hostname hostid logname nproc whoami tty ttysize cat head wc tee rev basename
SOURCES := $(addprefix $(SRC_DIR)/,$(addsuffix .asm,$(TOOLS)))
OBJECTS := $(addprefix $(BUILD_DIR)/,$(addsuffix .o,$(TOOLS)))
BINARIES := $(addprefix $(BUILD_DIR)/,$(TOOLS))

.PHONY: all clean test

all: $(BINARIES)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.asm | $(BUILD_DIR)
	$(NASM) -f elf64 -g -F dwarf -o $@ $<

$(BUILD_DIR)/%: $(BUILD_DIR)/%.o
	$(LD) -o $@ $<

clean:
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	touch $(BUILD_DIR)/.gitkeep

test: all
	./tests/run_tests.sh
