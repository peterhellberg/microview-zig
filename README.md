# Zig MicroView demo

A disc falls under gravity, bounces off the panel edges and drags a fading
trail behind it, on the MicroView's 64x48 SSD1306. No Arduino code involved,
and the two buttons tilt gravity left and right.

Five modules, each with one job:

| File | Job |
|------|-----|
| `src/draw.zig` | 384-byte page buffer, `pixel`, `line`, `stroke`, `disc`, `ring`, plus host tests |
| `src/gpio.zig` | comptime pins: `Pin(.b, 2)`, `drive`, `pullUp`, `read` |
| `src/microview.zig` | SPI, SSD1306 init sequence, `display`, `delay` |
| `src/buttons.zig` | the two buttons on PD2/PD3, `init` and `read` |
| `src/main.zig` | gravity, steering, wall bounce, trail, plus host tests |

`draw.zig` is hardware-free, the hardware modules know nothing about the
animation, and `main.zig` touches no registers. `line` and `stroke` are there
for the next animation; this demo only uses `disc` and `ring`.

Pins are comptime types, so they cost no RAM and each operation folds into one
instruction:

    const b2 = gpio.Pin(.b, 2); // port B, bit 2
    b2.drive(false);            // push-pull output, low
    b2.pullUp();                // input with the internal pull-up
    _ = b2.read();              // electrical level of the pin

The register addresses come from the port index (PINx, DDRx and PORTx are three
apart from 0x20), and a `comptime` block cross-checks that formula against the
datasheet for the two ports this board uses. The panel is a 3.3 V part on a 5 V
board, so its control lines (SS, DC, RST) are driven high as pulled-up inputs
rather than push-pull outputs; that trick lives in `pullUp()`.

Pin map and init sequence come from SparkFun's MicroView library:
DC = PB0, SS = PB2, MOSI = PB3, SCK = PB5, 3.3 V regulator enable = PD4,
OLED reset = PD7. The reset/power sequencing and the 32-column display offset
are the same as `MicroView::begin()` and `MicroView::display()`.

The two buttons on D2/D3 (active low, internal pull-ups) tilt gravity: holding
left pulls the disc left, right pulls it right, and holding both cancels out.
That is the steering from the article's `MicroViewBounce` sketch, softened into
an acceleration instead of a velocity override.

Physics runs in 8.8 fixed point - positions and velocities are `i32` holding
256 sub-pixels per pixel - with a speed cap, four substeps per tick, and walls
that clamp the position and reflect the velocity. The trail is the last few
positions redrawn as circles of shrinking radius: a monochrome stand-in for a
fade, since the panel has no gray levels.

## Build

    make            # build/main.hex, then the host tests
    make test       # draw: buffer, line, stroke, disc, ring; main: physics
    make upload     # flash it (PORT=/dev/ttyUSB0 by default)
    make clean

Tests sit next to the code they cover, in `test` blocks in `draw.zig` and
`main.zig`. `zig test src/main.zig` also runs the tests of the files it
imports, so the second command re-runs draw's six tests alongside main's two.

Zig produces the object (its own AVR link step places `.text` at 0x11000, so
avr-gcc does the link, adding crt0 and the vector table). Output is
`build/main.hex`, about 2.5 KiB of code; `make clean` removes the whole
`build/` directory.

`make upload` runs `avrdude -c arduino -p m328p -P $(PORT) -b 115200`. Override
with `make PORT=/dev/ttyUSB1 upload`, or `make AVRDUDE_FLAGS=...`.

> [!Note]
> The original firmware that was on the board is backed up outside this repo
> (32 KiB flash + EEPROM readback); restoring it is the same avrdude command with
> that `.hex` file.

Zig 0.17 needs three things to build for this chip: compiler_rt does not
compile for AVR (`-fno-compiler-rt`), Zig's own AVR link puts `.text` at
0x11000 (link with avr-gcc instead), and integer initializers on globals do not
always survive into `.data`, so `main` sets the start state explicitly.
