// Radar: a sweep turns around the centre, painting contacts as it crosses
// them. Each contact then fades over roughly one revolution, so the screen
// keeps a short history of where things were.
//
// Same contract as every animation: FRAME_MS, init, update, render.

const buttons = @import("../buttons.zig");
const draw = @import("../draw.zig");
const trig = @import("../trig.zig");

pub const FRAME_MS: u16 = 40;

const CX = draw.WIDTH / 2;
const CY = draw.HEIGHT / 2;
const RANGE: i16 = 22; // outermost ring, in pixels
const CONTACTS = 10;
const FADE_MAX: u8 = 120; // frames an echo lasts, just under one revolution

const Contact = struct {
    angle: u8, // where the sweep must reach to wake it
    x: i16,
    y: i16,
    fade: u8,
};

var sweep: u8 = 0;
var noise: u8 = 0;

// LFSR: the contacts must be random but the same every boot, and a flash
// table would cost an lpm.
fn next() u8 {
    noise ^= noise << 7;
    noise ^= noise >> 5;
    noise ^= noise << 3;

    return noise;
}

fn place(angle: u8, radius: i16) [2]i16 {
    return .{
        CX + @divTrunc(trig.cos(angle) * radius, 256),
        CY + @divTrunc(trig.sin(angle) * radius, 256),
    };
}

// Did the arc from `prev`, moving by `step`, cross `angle`?
fn swept(prev: u8, step: i8, angle: u8) bool {
    const span: u8 = @abs(step);

    return if (step >= 0)
        angle -% prev <= span
    else
        prev -% angle <= span;
}

var contacts: [CONTACTS]Contact = undefined;

pub fn init() void {
    sweep = 0;
    noise = 0xa7;

    var i: usize = 0;
    while (i < CONTACTS) : (i += 1) {
        // One contact per sector, jittered, so none of them hides another.
        const angle: u8 = @as(u8, @intCast(i * 26)) +% (next() & 7);
        const p = place(angle, 6 + (next() & 15));

        contacts[i] = .{ .angle = angle, .x = p[0], .y = p[1], .fade = 0 };
    }
}

pub fn update(btn: buttons.State) void {
    var step: i8 = 2;
    if (btn.left) step = -2; // sweep the other way
    if (btn.right) step = 5; // faster

    var i: usize = 0;
    while (i < CONTACTS) : (i += 1) {
        if (contacts[i].fade > 0) contacts[i].fade -= 1;
        if (swept(sweep, step, contacts[i].angle)) contacts[i].fade = FADE_MAX;
    }

    sweep +%= @as(u8, @bitCast(step));
}

fn blip(x: i16, y: i16, fade: u8) void {
    if (fade > 80) {
        draw.pixel(x, y);
        draw.pixel(x - 1, y);
        draw.pixel(x + 1, y);
        draw.pixel(x, y - 1);
        draw.pixel(x, y + 1);
    } else if (fade > 40) {
        draw.pixel(x, y);
        draw.pixel(x - 1, y);
        draw.pixel(x + 1, y);
    } else {
        draw.pixel(x, y);
    }
}

pub fn render() void {
    draw.clear();

    draw.ring(CX, CY, RANGE);
    draw.ring(CX, CY, RANGE / 2);

    for (contacts) |c| {
        if (c.fade > 0) blip(c.x, c.y, c.fade);
    }

    const end = place(sweep, RANGE);
    draw.line(CX, CY, end[0], end[1]);

    draw.pixel(CX, CY);
}

test "the sweep crosses contacts in both directions, including the wrap" {
    const std = @import("std");

    try std.testing.expect(swept(250, 8, 2)); // forward across 255 -> 0
    try std.testing.expect(!swept(250, 8, 200));
    try std.testing.expect(swept(2, -8, 254)); // backward across 0 -> 255
    try std.testing.expect(!swept(2, -8, 100));
}

test "every contact starts inside the panel" {
    const std = @import("std");

    init();

    for (contacts) |c| {
        try std.testing.expect(c.x >= 0 and c.x < draw.WIDTH);
        try std.testing.expect(c.y >= 0 and c.y < draw.HEIGHT);
        try std.testing.expect(c.fade == 0);
    }
}

test "the sweep wakes a contact and the echo then fades" {
    const std = @import("std");

    init();

    sweep = contacts[0].angle -% 2; // one frame's worth before it
    contacts[0].fade = 0;
    update(.{ .left = false, .right = false });
    try std.testing.expectEqual(FADE_MAX, contacts[0].fade);

    // Move the sweep far away: the echo must now count down.
    sweep = contacts[0].angle +% 128;
    update(.{ .left = false, .right = false });
    try std.testing.expectEqual(FADE_MAX - 1, contacts[0].fade);
}
