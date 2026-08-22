Z80_AS ?= pasmo
BUILD_DIR := build

TEST_SRC := src/3712test.asm
TEST_COM := $(BUILD_DIR)/3712TEST.COM
TEST_SYM := $(BUILD_DIR)/3712test.sym

BOOT_SRC := src/3712boot.asm
BOOT_COM := $(BUILD_DIR)/3712BOOT.COM
BOOT_SYM := $(BUILD_DIR)/3712boot.sym

PREP_SRC := src/3712prep.asm
PREP_COM := $(BUILD_DIR)/3712PREP.COM
PREP_SYM := $(BUILD_DIR)/3712prep.sym

SVC_SRC := src/3712svc.asm
SVC_BIN := $(BUILD_DIR)/3712SVC.BIN
SVC_SYM := $(BUILD_DIR)/3712svc.sym

HAND_SRC := src/3712hand.asm
HAND_COM := $(BUILD_DIR)/3712HAND.COM
HAND_SYM := $(BUILD_DIR)/3712hand.sym

.PHONY: all clean verify

all: $(TEST_COM) $(BOOT_COM) $(PREP_COM) $(SVC_BIN) $(HAND_COM)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(TEST_COM): $(TEST_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(TEST_SRC) $(TEST_COM) $(TEST_SYM)

$(BOOT_COM): $(BOOT_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(BOOT_SRC) $(BOOT_COM) $(BOOT_SYM)

$(PREP_COM): $(PREP_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(PREP_SRC) $(PREP_COM) $(PREP_SYM)

$(SVC_BIN): $(SVC_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(SVC_SRC) $(SVC_BIN) $(SVC_SYM)

$(HAND_COM): $(HAND_SRC) $(SVC_BIN) | $(BUILD_DIR)
	$(Z80_AS) --bin $(HAND_SRC) $(HAND_COM) $(HAND_SYM)

verify: $(TEST_COM) $(BOOT_COM) $(PREP_COM) $(SVC_BIN) $(HAND_COM)
	@test -s $(TEST_COM)
	@test -s $(BOOT_COM)
	@test -s $(PREP_COM)
	@test -s $(SVC_BIN)
	@test -s $(HAND_COM)
	@svc_size=$$(wc -c < $(SVC_BIN)); \
	if [ $$svc_size -gt 12288 ]; then \
		echo "ERROR: C000 service layer exceeds C000-EFFF RAM ($$svc_size bytes)"; exit 1; \
	fi; \
	echo "$$(basename $(SVC_BIN)): $$svc_size bytes"
	@for file in $(TEST_COM) $(BOOT_COM) $(PREP_COM) $(HAND_COM); do \
		size=$$(wc -c < $$file); \
		if [ $$size -gt 64000 ]; then \
			echo "ERROR: COM file unexpectedly large: $$file ($$size bytes)"; exit 1; \
		fi; \
		echo "$$(basename $$file): $$size bytes"; \
	done

clean:
	rm -rf $(BUILD_DIR)
