// The MicroView's two buttons on D2/D3: active low, internal pull-ups on, the
// button shorts the pin to ground.

const gpio = @import("gpio.zig");

const left = gpio.Pin(.d, 2); // D2
const right = gpio.Pin(.d, 3); // D3

pub const State = struct {
    left: bool,
    right: bool,
};

pub fn init() void {
    left.pullUp();
    right.pullUp();
}

pub fn read() State {
    return .{
        .left = !left.read(),
        .right = !right.read(),
    };
}
