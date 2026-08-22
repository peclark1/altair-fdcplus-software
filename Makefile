Z80_AS ?= pasmo
BUILD_DIR := build

TEST_SRC := src/3712test.asm
TEST_COM := $(BUILD_DIR)/3712TEST.COM
TEST_SYM := $(BUILD_DIR)/3712test.sym

BOOT_SRC := src/3712boot.asm
BOOT_COM := $(BUILD_DIR)/3712BOOT.COM
BOOT_SYM := $(BUILD_DIR)/3712boot.sym

.PHONY: all clean verify

all: $(TEST_COM) $(BOOT_COM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TEST_COM): $(TEST_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(TEST_SRC) $(TEST_COM) $(TEST_SYM)

$(BOOT_COM): $(BOOT_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(BOOT_SRC) $(BOOT_COM) $(BOOT_SYM)

verify: $(TEST_COM) $(BOOT_COM)
	@test -s $(TEST_COM)
	@test -s $(BOOT_COM)
	@for file in $(TEST_COM) $(BOOT_COM); do \
		size=$$(wc -c < $$file); \
		if [ $$size -gt 64000 ]; then \
			echo "ERROR: COM file unexpectedly large: $$file ($$size bytes)"; exit 1; \
		fi; \
		echo "$$(basename $$file): $$size bytes"; \
	done

clean:
	rm -rf $(BUILD_DIR)
