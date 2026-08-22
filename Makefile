Z80_AS ?= pasmo
BUILD_DIR := build
SRC := src/3712test.asm
COM := $(BUILD_DIR)/3712TEST.COM
SYM := $(BUILD_DIR)/3712test.sym

.PHONY: all clean verify

all: $(COM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(COM): $(SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(SRC) $(COM) $(SYM)

verify: $(COM)
	@test -s $(COM)
	@size=$$(wc -c < $(COM)); \
	if [ $$size -gt 64000 ]; then \
		echo "ERROR: COM file unexpectedly large: $$size bytes"; exit 1; \
	fi; \
	echo "3712TEST.COM: $$size bytes"

clean:
	rm -rf $(BUILD_DIR)
