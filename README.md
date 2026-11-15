# Zig MicroView demo

A bouncing disc on the MicroView's 64x48 SSD1306, 
no Arduino code involved.

Four modules, each with one job:

| File | Job |
|------|-----|
| `src/draw.zig` | 384-byte page buffer, `pixel`, `line`, `stroke`, `disc`, `ring` (pure, host-tested) |
| `src/microview.zig` | ATmega328P registers, SPI, SSD1306 init, `display`, `delay` |
| `src/buttons.zig` | the two buttons on PD2/PD3, `init` and `read` |
| `src/main.zig` | animation state, bounce/steer policy, wiring the two together |

`draw.zig` is hardware-free, the two hardware modules know nothing about
the animation, and `main.zig` touches no registers.

Pin map and init sequence come from SparkFun's MicroView library:
DC = PB0, SS = PB2, MOSI = PB3, SCK = PB5, 3.3 V regulator enable = PD4,
OLED reset = PD7. The reset/power sequencing and the 32-column display offset
are the same as `MicroView::begin()` and `MicroView::display()`.

The two buttons from the article's `MicroViewBounce` sketch are wired to
D2/D3 (PD2/PD3, active low, internal pull-ups): left steers the disc left,
right steers it right, which is what `ax -= 2` / `ax += 2` in the sketch does
after the velocity clamp. While a button is held its ring is drawn around the disc -
radius 12 on the left one, 16 on the right one, as in the sketch.

## Build

    make            # build/main.hex, then the host tests
    make test       # canvas: bit packing, disc, ring; main: bounce
    make upload     # flash it (PORT=/dev/ttyUSB0 by default)
    make clean

Zig produces the object (its own AVR link step places `.text` at 0x11000, so
avr-gcc does the link, adding crt0 and the vector table). Output is
`build/main.hex`, about 1.5 KiB of code; `make clean` removes the whole
`build/` directory.

`make upload` runs `avrdude -c arduino -p m328p -P $(PORT) -b 115200`. Override
with `make PORT=/dev/ttyUSB1 upload`, or `make AVRDUDE_FLAGS=...`.

> [!Note]
> The original firmware that was on the board is backed up outside this repo
> (32 KiB flash + EEPROM readback); restoring it is the same avrdude command with
> that `.hex` file.

Zig 0.17 needs three things to build for this chip: compiler_rt does not
compile for AVR (`-fno-compiler-rt`), Zig's own AVR link puts `.text` at
0x11000 (link with avr-gcc instead), and integer initializers on globals can be
dropped when the value is only ever ±1, so `main` sets the start state
explicitly.
