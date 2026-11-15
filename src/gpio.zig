// Comptime GPIO pins for the ATmega328P: `Pin(.b, 5)` is Arduino D13.
// Each pin is a type, so nothing is stored in RAM and the port address is
// folded into the instruction.

pub const Port = enum(u2) { a, b, c, d };

// Data-space addresses: PINx, DDRx, PORTx are 3 apart, starting at 0x20.
fn regs(comptime port: Port) [3]u8 {
    const pin: u8 = 0x20 + 3 * @as(u8, @intFromEnum(port));
    return .{ pin, pin + 1, pin + 2 };
}

comptime {
    // The formula is the only place a wrong address could hide, so check the
    // two ports this board uses against the datasheet.
    const b = regs(.b);
    if (b[0] != 0x23 or b[1] != 0x24 or b[2] != 0x25) @compileError("port B registers");
    const d = regs(.d);
    if (d[0] != 0x29 or d[1] != 0x2A or d[2] != 0x2B) @compileError("port D registers");
}

pub fn Pin(comptime port: Port, comptime bit: u3) type {
    const r = regs(port);
    return struct {
        const pin_reg: *volatile u8 = @ptrFromInt(r[0]);
        const ddr_reg: *volatile u8 = @ptrFromInt(r[1]);
        const port_reg: *volatile u8 = @ptrFromInt(r[2]);

        pub const mask: u8 = 1 << bit;

        /// Push-pull output. PORT is written before DDR so the pin never glitches.
        pub inline fn drive(level: bool) void {
            if (level) {
                port_reg.* |= mask;
            } else {
                port_reg.* &= ~mask;
            }
            ddr_reg.* |= mask;
        }

        /// Input with the internal pull-up: the safe way to drive a 3.3 V part high.
        pub inline fn pullUp() void {
            port_reg.* |= mask;
            ddr_reg.* &= ~mask;
        }

        /// Electrical level of the pin as an input: true means high.
        pub inline fn read() bool {
            return (pin_reg.* & mask) != 0;
        }
    };
}
