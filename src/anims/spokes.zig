// Spokes: eight rays out of the centre whose lengths chase each other, so the
// star appears to turn. The four axes are drawn thick with stroke(), the four
// diagonals thin with line(), which is the point of this demo.
//
// Same contract as every animation: FRAME_MS, init, update, render.

const buttons = @import("../buttons.zig");
const draw = @import("../draw.zig");

pub const FRAME_MS: u16 = 24;

const CX = draw.WIDTH / 2;
const CY = draw.HEIGHT / 2;
const MIN_LEN: i16 = 8;
const MAX_PULSE: i16 = 15; // pulse() range, so the longest ray is MIN_LEN + 15

var phase: i16 = 0;

// Triangle wave 0..15..0 over a 32-step cycle: cheap integer "sine".
fn pulse(offset: i16) i16 {
    const t = (phase + offset) & 31;

    return if (t < 16) t else 31 - t;
}

fn spoke(vx: i16, vy: i16, offset: i16, thick: bool) void {
    const len = MIN_LEN + pulse(offset);

    // The panel is 64x48, so vertical offsets are squashed by 3/4 to keep the
    // star looking round.
    const ex = CX + vx * len;
    const ey = CY + ((vy * len * 3) >> 2);

    if (thick) {
        draw.stroke(CX, CY, ex, ey, 1);
    } else {
        draw.line(CX, CY, ex, ey);
    }
}

// Four rays 90 degrees apart, starting from (1, 0) or (1, 1). Rotating a vector
// by 90 degrees is exact integer arithmetic: (x, y) -> (-y, x).
fn quad(start_x: i16, start_y: i16, phase_offset: i16, thick: bool) void {
    var vx = start_x;
    var vy = start_y;

    var k: i16 = 0;

    while (k < 4) : (k += 1) {
        spoke(vx, vy, phase_offset + k * 8, thick);

        const nx = -vy;
        vy = vx;
        vx = nx;
    }
}

pub fn init() void {
    phase = 0;
}

pub fn update(btn: buttons.State) void {
    var step: i16 = 1;

    if (btn.left) step -= 3; // reverse the spin
    if (btn.right) step += 3; // spin twice as fast

    phase = (phase + step) & 31;
}

pub fn render() void {
    draw.clear();

    quad(1, 0, 0, true);
    quad(1, 1, 4, false);

    draw.ring(CX, CY, 2);
}

test "pulse is a triangle from 0 up to 15 and back" {
    const std = @import("std");

    phase = 0;
    try std.testing.expectEqual(@as(i16, 0), pulse(0));

    phase = 8;
    try std.testing.expectEqual(@as(i16, 8), pulse(0));

    phase = 15;
    try std.testing.expectEqual(MAX_PULSE, pulse(0));

    phase = 16;
    try std.testing.expectEqual(MAX_PULSE, pulse(0));

    phase = 31;
    try std.testing.expectEqual(@as(i16, 0), pulse(0));
}
