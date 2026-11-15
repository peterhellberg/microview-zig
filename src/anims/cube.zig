// Cube: a spinning cube whose three visible faces are filled with dither
// patterns, so the face that leans into the light comes out solid and the
// others shade off through halftones.
//
// No trig tables and no floats. sin() is a parabola over a 256-step turn, the
// projection is 8.8 fixed point, and the angles are absolute rather than
// accumulated matrices, so the cube cannot drift.
//
// Same contract as every animation: FRAME_MS, init, update, render.

const buttons = @import("../buttons.zig");
const draw = @import("../draw.zig");
const trig = @import("../trig.zig");

const sin = trig.sin;
const cos = trig.cos;

pub const FRAME_MS: u16 = 30;

const HALF: i16 = 14; // cube half-size in pixels, before projection
const CX = draw.WIDTH / 2;
const CY = draw.HEIGHT / 2;

// Light from the front, upper left, in 8.8 fixed point. Faces that lean into
// it get denser dither.
const LIGHT_X: i32 = 60;
const LIGHT_Y: i32 = -120;
const LIGHT_Z: i32 = 210;

var yaw: u8 = 0;
var pitch: u8 = 0;

const Vec3 = struct { x: i16, y: i16, z: i16 };
const Point = [2]i16;

// The four sin/cos values shared by every vertex and face this frame.
const Basis = struct { cy: i16, sy: i16, cx: i16, sx: i16 };

fn basis(y: u8, p: u8) Basis {
    return .{ .cy = cos(y), .sy = sin(y), .cx = cos(p), .sx = sin(p) };
}

// Yaw about y, then pitch about x.
fn rotate(p: Vec3, b: Basis) Vec3 {
    const x1 = (p.x * b.cy + p.z * b.sy) >> 8;
    const z1 = (p.z * b.cy - p.x * b.sy) >> 8;
    const y2 = (p.y * b.cx - z1 * b.sx) >> 8;
    const z2 = (p.y * b.sx + z1 * b.cx) >> 8;

    return .{ .x = x1, .y = y2, .z = z2 };
}

// Weak perspective: points nearer the viewer (z > 0) come out larger. The
// vertical axis is squashed by 3/4, because the panel is 64x48.
fn project(p: Vec3) Point {
    const f = 256 + p.z * 4;

    return .{
        CX + @divTrunc(p.x * f, 256),
        CY + @divTrunc(p.y * f * 3, 1024),
    };
}

// Vertex i stores its signs in bits 0..2: x, y, z.
fn vertex(i: u4) Vec3 {
    return .{
        .x = if (i & 1 != 0) HALF else -HALF,
        .y = if (i & 2 != 0) HALF else -HALF,
        .z = if (i & 4 != 0) HALF else -HALF,
    };
}

// k walks the four corners of a face - (0,0), (1,0), (1,1), (0,1) in the two
// free coordinates - as Gray bits, so no corner table is needed.
fn corner(axis: u3, sign: u3, k: u3) u3 {
    const c0: u3 = (k ^ (k >> 1)) & 1;
    const c1: u3 = (k >> 1) & 1;

    return switch (axis) {
        0 => sign | (c0 << 1) | (c1 << 2), // free: y, z
        1 => c0 | (sign << 1) | (c1 << 2), // free: x, z
        else => c0 | (c1 << 1) | (sign << 2), // free: x, y
    };
}

// Outward normal of the face on `axis`, rotated with the cube, in 8.8.
fn normal(axis: u3, sign: i16, b: Basis) [3]i32 {
    const col: [3]i32 = switch (axis) {
        0 => .{ b.cy, (@as(i32, b.sy) * b.sx) >> 8, -(@as(i32, b.sy) * b.cx) >> 8 },
        1 => .{ 0, b.cx, b.sx },
        else => .{ b.sy, -(@as(i32, b.cy) * b.sx) >> 8, (@as(i32, b.cy) * b.cx) >> 8 },
    };

    return .{ sign * col[0], sign * col[1], sign * col[2] };
}

// The face normal's dot with the light, mapped to 0..16: 0 is empty, 16 is a
// solid fill. Ordered dither then lights one sixteenth more of the face at a
// time, so it brightens smoothly instead of flipping between four patterns.
fn shade(n: [3]i32) u8 {
    const dot = (n[0] * LIGHT_X + n[1] * LIGHT_Y + n[2] * LIGHT_Z) >> 8;
    const level = (dot + 48) >> 4;

    return @intCast(@max(0, @min(16, level)));
}

// 4x4 ordered dither, computed rather than stored: a table would sit in flash
// and cost an lpm on AVR. It is the usual Bayer matrix,
//
//     0  8  2 10
//    12  4 14  6
//     3 11  1  9
//    15  7 13  5
//
// as bits 3..0 = (x^y), y, (x^y) and y of the low two bits of each coordinate.
fn dither(x: i16, y: i16) u4 {
    const px: u2 = @truncate(@as(u16, @bitCast(x)));
    const py: u2 = @truncate(@as(u16, @bitCast(y)));

    return (@as(u4, (px ^ py) & 1) << 3) |
        (@as(u4, py & 1) << 2) |
        (@as(u4, (px >> 1) ^ (py >> 1)) << 1) |
        @as(u4, py >> 1);
}

fn lit(level: u8, x: i16, y: i16) bool {
    return dither(x, y) < level;
}

// Scanline fill of a convex quad: for each row find the two edge crossings and
// dither the span between them.
fn fillFace(axis: u3, sign: u3, pts: *const [8]Point, level: u8) void {
    var quad: [4]Point = undefined;

    var k: u3 = 0;
    while (k < 4) : (k += 1) {
        quad[k] = pts[corner(axis, sign, k)];
    }

    var top = quad[0][1];
    var bot = quad[0][1];
    k = 1;
    while (k < 4) : (k += 1) {
        top = @min(top, quad[k][1]);
        bot = @max(bot, quad[k][1]);
    }

    var y = top;
    while (y <= bot) : (y += 1) {
        var lo: i16 = 0;
        var hi: i16 = -1; // still empty

        k = 0;
        while (k < 4) : (k += 1) {
            const a = quad[k];
            const b = quad[(k + 1) & 3];

            // Half-open in y, so a shared vertex is counted once and level
            // edges drop out.
            if ((y >= a[1] and y < b[1]) or (y >= b[1] and y < a[1])) {
                const x = a[0] + @divTrunc((b[0] - a[0]) * (y - a[1]), b[1] - a[1]);

                if (hi < lo) {
                    lo = x;
                    hi = x;
                } else {
                    lo = @min(lo, x);
                    hi = @max(hi, x);
                }
            }
        }

        var x = lo;
        while (x <= hi) : (x += 1) {
            if (lit(level, x, y)) draw.pixel(x, y);
        }
    }
}

fn outlineFace(axis: u3, sign: u3, pts: *const [8]Point) void {
    var k: u3 = 0;
    while (k < 4) : (k += 1) {
        const p = pts[corner(axis, sign, k)];
        const q = pts[corner(axis, sign, (k + 1) & 3)];

        draw.line(p[0], p[1], q[0], q[1]);
    }
}

pub fn init() void {
    yaw = 0;
    pitch = 40; // start on a corner, so three faces are in view
}

pub fn update(btn: buttons.State) void {
    if (btn.left) {
        yaw -%= 2; // reverse
    } else if (btn.right) {
        yaw +%= 5; // faster
    } else {
        yaw +%= 2;
    }

    pitch +%= 1; // slow tumble
}

pub fn render() void {
    draw.clear();

    const b = basis(yaw, pitch);

    var pts: [8]Point = undefined;

    var i: u4 = 0;
    while (i < 8) : (i += 1) {
        pts[i] = project(rotate(vertex(i), b));
    }

    var axis: u3 = 0;
    while (axis < 3) : (axis += 1) {
        var s: u3 = 0;
        while (s < 2) : (s += 1) {
            const sign: i16 = if (s == 0) -1 else 1;
            const n = normal(axis, sign, b);

            if (n[2] <= 0) continue; // this face looks away from the viewer

            fillFace(axis, s, &pts, shade(n));
            outlineFace(axis, s, &pts);
        }
    }
}

test "dither hits every level once in each 4x4 cell" {
    const std = @import("std");

    var seen: [16]bool = undefined;
    @memset(&seen, false);

    var y: i16 = 0;
    while (y < 4) : (y += 1) {
        var x: i16 = 0;
        while (x < 4) : (x += 1) {
            const v = dither(x, y);

            try std.testing.expect(!seen[v]);
            seen[v] = true;
        }
    }

    for (seen) |s| try std.testing.expect(s);
}

test "every spin angle keeps the cube inside the panel" {
    const std = @import("std");

    var y: u8 = 0;
    while (true) : (y +%= 5) {
        var p: u8 = 0;
        while (true) : (p +%= 7) {
            const b = basis(y, p);

            var i: u4 = 0;
            while (i < 8) : (i += 1) {
                const s = project(rotate(vertex(i), b));

                try std.testing.expect(s[0] >= 0 and s[0] < draw.WIDTH);
                try std.testing.expect(s[1] >= 0 and s[1] < draw.HEIGHT);
            }

            if (p >= 250) break;
        }

        if (y >= 250) break;
    }
}

test "back faces are hidden: one to three faces face the viewer" {
    const std = @import("std");

    var y: u8 = 0;
    while (true) : (y +%= 11) {
        var p: u8 = 0;
        while (true) : (p +%= 13) {
            const b = basis(y, p);

            var visible: u8 = 0;

            var axis: u3 = 0;
            while (axis < 3) : (axis += 1) {
                var s: u3 = 0;
                while (s < 2) : (s += 1) {
                    const sign: i16 = if (s == 0) -1 else 1;

                    if (normal(axis, sign, b)[2] > 0) visible += 1;
                }
            }

            // One when the cube is exactly face-on, two when a face is
            // exactly edge-on, otherwise three. A fourth would be a back face.
            try std.testing.expect(visible >= 1 and visible <= 3);

            if (p >= 250) break;
        }

        if (y >= 250) break;
    }
}
