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
SRC := $(wildcard src/*.zig)

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

test: $(SRC)
	$(ZIG) test src/draw.zig
	$(ZIG) test src/main.zig

upload: $(OUT)/main.hex
	avrdude $(AVRDUDE_FLAGS) -U flash:w:$<:i -D

clean:
	rm -rf $(OUT)

.PHONY: all test upload clean
