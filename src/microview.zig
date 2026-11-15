// Hardware access for the SparkFun MicroView: the SSD1306 panel over SPI.
// Pin map, init sequence and buffer layout mirror SparkFun's MicroView library.

const draw = @import("draw.zig");
const gpio = @import("gpio.zig");

const TIFR0: *volatile u8 = @ptrFromInt(0x35);
const TCCR0A: *volatile u8 = @ptrFromInt(0x44);
const TCCR0B: *volatile u8 = @ptrFromInt(0x45);
const OCR0A: *volatile u8 = @ptrFromInt(0x47);
const SPCR: *volatile u8 = @ptrFromInt(0x4C);
const SPSR: *volatile u8 = @ptrFromInt(0x4D);
const SPDR: *volatile u8 = @ptrFromInt(0x4E);

// The panel and its 3.3 V regulator hang off these pins.
const dc = gpio.Pin(.b, 0); // PB0, data/command
const ss = gpio.Pin(.b, 2); // PB2, chip select
const mosi = gpio.Pin(.b, 3); // PB3
const sck = gpio.Pin(.b, 5); // PB5
const pwr = gpio.Pin(.d, 4); // PD4, 3.3 V regulator enable
const rst = gpio.Pin(.d, 7); // PD7, OLED reset

const COL_OFFSET = 32; // visible window starts at controller column 32

fn send(b: u8) void {
    SPDR.* = b;

    while ((SPSR.* & 0x80) == 0) {}
}

// SS must already be an output before SPE is set: a low, floating SS pin
// sampled while SPI is enabled clears MSTR and turns the port into a slave.
fn beginPacket() void {
    ss.drive(false);

    SPCR.* |= 0x40; // SPE
}

fn endPacket() void {
    while ((SPSR.* & 0x80) == 0) {}

    SPCR.* &= ~@as(u8, 0x40);

    dc.drive(false);
    ss.pullUp();
}

// One command packet: first byte is the command, the rest are its arguments.
// The tuple is comptime, so this unrolls to a plain run of sends.
fn cmd(args: anytype) void {
    beginPacket();

    inline for (args) |b| send(b);

    endPacket();
}

fn writeMem(bytes: []const u8) void {
    beginPacket();

    dc.pullUp();

    for (bytes) |b| send(b);

    endPacket();
}

fn fillMem(count: u16, value: u8) void {
    beginPacket();

    dc.pullUp();

    var i: u16 = 0;
    while (i < count) : (i += 1) send(value);

    endPacket();
}

// Timer 0 in CTC mode: 16 MHz / 64 / 250 = exactly 1000 compare matches/s.
pub fn delay(ms: u16) void {
    TCCR0A.* = 0x02; // CTC
    OCR0A.* = 249; // 250 ticks per match
    TIFR0.* = 0x02; // clear a stale OCF0A
    TCCR0B.* = 0x03; // clk/64

    var i: u16 = 0;
    while (i < ms) : (i += 1) {
        while ((TIFR0.* & 0x02) == 0) {}
        TIFR0.* = 0x02; // write one to clear
    }

    TCCR0B.* = 0x00; // stop the timer
}

// Wipe the controller's own memory so it cannot show random startup data.
fn clearAll() void {
    cmd(.{ 0x20, 0x00 }); // horizontal addressing
    cmd(.{ 0x21, 0, 127 });
    cmd(.{ 0x22, 0, 7 });
    fillMem(128 * 8, 0);
    cmd(.{ 0x20, 0x02 }); // page addressing
}

pub fn init() void {
    rst.drive(false);
    pwr.drive(true);

    delay(10);

    rst.pullUp();

    delay(5);

    rst.drive(false);

    // Configure SS/DC before enabling SPI: see beginPacket.
    SPSR.* = 0;
    mosi.drive(false);
    sck.drive(false);
    ss.pullUp();
    dc.drive(false);
    SPCR.* = 0x50; // SPE | MSTR, fosc/4 = 4 MHz

    delay(5);

    rst.pullUp();

    delay(10);

    cmd(.{ 0xA8, 0x2F }); // multiplex ratio 48
    cmd(.{ 0x8D, 0x14 }); // charge pump on
    cmd(.{0xA1}); // segment remap
    cmd(.{0xC8}); // COM scan direction
    cmd(.{ 0x81, 0x8F }); // contrast
    cmd(.{ 0xD9, 0xF1 }); // pre-charge period
    cmd(.{ 0xDB, 0x40 }); // VCOM deselect
    cmd(.{0xAF}); // display on

    clearAll();
}

pub fn display() void {
    cmd(.{ 0x20, 0x00 });
    cmd(.{ 0x21, COL_OFFSET, COL_OFFSET + draw.WIDTH - 1 });
    cmd(.{ 0x22, 0, draw.PAGES - 1 });
    writeMem(&draw.buf);
    cmd(.{ 0x20, 0x02 }); // page addressing
}
