// Frame buffer for the MicroView's 64x48 OLED, in SSD1306 page order:
// byte index = column + page * 64, bit = pixel row within the page.

pub const WIDTH = 64;
pub const HEIGHT = 48;
pub const PAGES = HEIGHT / 8;

pub var buf: [WIDTH * PAGES]u8 = @splat(0);

pub fn clear() void {
    @memset(&buf, 0);
}

pub fn pixel(px: i16, py: i16) void {
    if (px < 0 or px >= WIDTH or py < 0 or py >= HEIGHT) return;

    const col: u8 = @intCast(px);
    const row: u8 = @intCast(py);

    buf[@as(u16, col) + @as(u16, row / 8) * WIDTH] |= @as(u8, 1) << @intCast(row % 8);
}

// Bresenham line from (x0,y0) to (x1,y1). Clipping is free: pixel() bounds-checks.
pub fn line(x0: i16, y0: i16, x1: i16, y1: i16) void {
    const dx: i16 = @intCast(@abs(x1 - x0));
    const dy: i16 = @intCast(@abs(y0 - y1));
    const sx: i16 = if (x0 < x1) 1 else -1;
    const sy: i16 = if (y0 < y1) 1 else -1;

    var err: i16 = dx - dy;
    var x = x0;
    var y = y0;

    while (true) {
        pixel(x, y);
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }
        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

// Stroke: a filled disc of `radius` stamped at every point along the line.
// Thickness = 2*radius + 1 pixels. Endpoints are rounded caps.
pub fn stroke(x0: i16, y0: i16, x1: i16, y1: i16, radius: i16) void {
    if (radius <= 0) {
        line(x0, y0, x1, y1);
        return;
    }

    const dx: i16 = @intCast(@abs(x1 - x0));
    const dy: i16 = @intCast(@abs(y0 - y1));
    const sx: i16 = if (x0 < x1) 1 else -1;
    const sy: i16 = if (y0 < y1) 1 else -1;

    var err: i16 = dx - dy;
    var x = x0;
    var y = y0;

    while (true) {
        disc(x, y, radius);

        if (x == x1 and y == y1) break;

        const e2 = 2 * err;

        if (e2 > -dy) {
            err -= dy;
            x += sx;
        }

        if (e2 < dx) {
            err += dx;
            y += sy;
        }
    }
}

pub fn disc(cx: i16, cy: i16, r: i16) void {
    var dy: i16 = -r;

    while (dy <= r) : (dy += 1) {
        var dx: i16 = -r;

        while (dx <= r) : (dx += 1) {
            if (dx * dx + dy * dy <= r * r) pixel(cx + dx, cy + dy);
        }
    }
}

// Midpoint circle outline: the pixels around the centre at distance ~r, unfilled.
pub fn ring(cx: i16, cy: i16, r: i16) void {
    var x: i16 = 0;
    var y: i16 = r;
    var d: i16 = 1 - r;

    while (x <= y) {
        pixel(cx + x, cy + y);
        pixel(cx - x, cy + y);
        pixel(cx + x, cy - y);
        pixel(cx - x, cy - y);
        pixel(cx + y, cy + x);
        pixel(cx - y, cy + x);
        pixel(cx + y, cy - x);
        pixel(cx - y, cy - x);

        if (d < 0) {
            d += 2 * x + 3;
        } else {
            d += 2 * (x - y) + 5;
            y -= 1;
        }

        x += 1;
    }
}

test "pixel bit packing matches SSD1306 page order" {
    const std = @import("std");

    clear();
    pixel(0, 0);
    try std.testing.expectEqual(@as(u8, 0x01), buf[0]);

    clear();
    pixel(63, 47);
    try std.testing.expectEqual(@as(u8, 0x80), buf[63 + 5 * 64]);

    clear();
    pixel(10, 9);
    try std.testing.expectEqual(@as(u8, 0x02), buf[10 + 64]);

    clear();
    pixel(5, 8);
    try std.testing.expectEqual(@as(u8, 0x01), buf[5 + 64]);
}

test "pixels outside the panel are dropped" {
    const std = @import("std");

    clear();
    pixel(-1, 10);
    pixel(64, 10);
    pixel(10, -1);
    pixel(10, 48);

    for (buf) |b| try std.testing.expectEqual(@as(u8, 0), b);
}

test "disc is round, filled and symmetric" {
    const std = @import("std");

    clear();
    disc(20, 20, 3);

    // centre column is filled from y = 17 to 23, i.e. bits 1..7 of page 2
    try std.testing.expectEqual(@as(u8, 0xFE), buf[20 + 2 * 64]);

    // the outer columns hold the single pixel at y = 20
    try std.testing.expectEqual(@as(u8, 0x10), buf[23 + 2 * 64]);
    try std.testing.expectEqual(@as(u8, 0x10), buf[17 + 2 * 64]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[24 + 2 * 64]);
    try std.testing.expectEqual(@as(u8, 0x00), buf[16 + 2 * 64]);

    // vertical extent stays inside y = 17..23, i.e. page 2 only
    for (buf[0 .. 2 * 64]) |b| try std.testing.expectEqual(@as(u8, 0), b);
    for (buf[3 * 64 ..]) |b| try std.testing.expectEqual(@as(u8, 0), b);

    // nothing outside the 7 pixel wide bounding box
    for (buf, 0..) |b, i| {
        if (b != 0 and (i % 64 < 17 or i % 64 > 23)) return error.OutsideBoundingBox;
    }
}

fn set(x: i16, y: i16) bool {
    const col: u16 = @intCast(x);
    const row: u16 = @intCast(y);

    return (buf[col + (row / 8) * 64] >> @intCast(row % 8) & 1) == 1;
}

test "ring is an outline, not a disc" {
    const std = @import("std");

    clear();
    ring(20, 20, 5);

    // the four cardinal points of r = 5
    try std.testing.expect(set(25, 20));
    try std.testing.expect(set(15, 20));
    try std.testing.expect(set(20, 25));
    try std.testing.expect(set(20, 15));

    // inside and outside stay clear
    try std.testing.expect(!set(20, 20));
    try std.testing.expect(!set(20, 23));
    try std.testing.expect(!set(20, 26));
    try std.testing.expect(!set(26, 20));

    // symmetric about both axes through the centre
    try std.testing.expectEqual(set(24, 23), set(16, 23));
    try std.testing.expectEqual(set(24, 23), set(24, 17));
}
