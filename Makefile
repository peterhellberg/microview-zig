# Build and flash the Zig MicroView demo.
# Zig compiles the object; avr-gcc supplies crt0, the vector table and the
# linker script (Zig's own AVR link step puts .text at 0x11000).

MCU := atmega328p
F_CPU := 16000000

AVR_BIN ?= $(firstword $(wildcard $(HOME)/.arduino15/packages/arduino/tools/avr-gcc/*/bin))
AVR_PREFIX := $(if $(AVR_BIN),$(AVR_BIN)/)

PORT ?= /dev/ttyUSB0
AVRDUDE_FLAGS ?= -c arduino -p $(MCU) -P $(PORT) -b 115200

OUT := build
SRC := $(wildcard src/*.zig src/*/*.zig)

ZIG ?= zig

# A recipe that dies halfway leaves no artifact that a later make trusts.
.DELETE_ON_ERROR:

all: $(OUT)/main.hex test

$(OUT)/main.o: $(SRC) | $(OUT)
	$(ZIG) build-obj -target avr-freestanding -mcpu=$(MCU) -O ReleaseSmall \
		-fno-compiler-rt -femit-bin=$@ src/main.zig

$(OUT)/main.elf: $(OUT)/main.o
	$(AVR_PREFIX)avr-gcc -mmcu=$(MCU) -DF_CPU=$(F_CPU)UL -Os -o $@ $<

$(OUT)/main.hex: $(OUT)/main.elf
	$(AVR_PREFIX)avr-objcopy -O ihex -R .eeprom $< $@
	$(AVR_PREFIX)avr-size $<

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
