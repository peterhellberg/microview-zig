# Build and flash the Zig MicroView demo. Zig compiles and links it all;
# avr.ld says where flash and RAM are, src/runtime.zig is the reset vector
# and the compiler-rt/libgcc helpers.

MCU := atmega328p

PORT ?= /dev/ttyUSB0
AVRDUDE_FLAGS ?= -c arduino -p $(MCU) -P $(PORT) -b 115200

OUT := build
SRC := $(wildcard src/*.zig src/*/*.zig)

ZIG ?= zig

# A recipe that dies halfway leaves no artifact that a later make trusts.
.DELETE_ON_ERROR:

all: $(OUT)/main.hex test

$(OUT)/main.elf: $(SRC) avr.ld | $(OUT)
	$(ZIG) build-exe -target avr-freestanding -mcpu=$(MCU) -O ReleaseSmall \
		-fno-compiler-rt -fentry=_start -T avr.ld -femit-bin=$@ src/main.zig

$(OUT)/main.hex: $(OUT)/main.elf
	$(ZIG) objcopy -O hex $< $@
	$(ZIG) objcopy -O binary $< $(OUT)/main.bin
	@printf 'flash: %s bytes\n' "$$(wc -c < $(OUT)/main.bin)"

$(OUT):
	mkdir -p $@

# Zig resolves imports only inside the test root's directory, so a file under
# src/anims/ cannot import ../draw.zig when it is itself the root. One generated
# root in src/ that imports every module with tests covers them all.
TEST_FILES := $(shell grep -lE '^test[ {]' $(SRC) 2>/dev/null)

test: $(SRC)
	@root=src/.tests.tmp.zig; log=$(OUT)/test.log; \
	trap 'rm -f $$root' EXIT; \
	mkdir -p $(OUT); \
	{ echo 'comptime {'; \
	  for f in $(patsubst src/%,%,$(TEST_FILES)); do \
	    echo "    _ = @import(\"$$f\");"; \
	  done; \
	  echo '}'; } > $$root; \
	if $(ZIG) test $$root > $$log 2>&1; then \
	  sed -n 's|^[0-9]*/[0-9]* \(.*\)\.test\..*OK$$|\1|p' $$log | \
	    sed 's|\.|/|g' | sort | uniq -c | \
	    awk '{ printf "  %-18s %d test%s\n", $$2 ".zig", $$1, ($$1 == 1 ? "" : "s") }'; \
	  tail -n 1 $$log; \
	else \
	  cat $$log; \
	  exit 1; \
	fi

upload: $(OUT)/main.hex
	avrdude $(AVRDUDE_FLAGS) -U flash:w:$<:i -D

# Host-only: render one frame of each animation to docs/*.png for the README.
screenshots: $(SRC)
	$(ZIG) run src/screenshots.zig

clean:
	rm -rf $(OUT)

.PHONY: all test screenshots upload clean
