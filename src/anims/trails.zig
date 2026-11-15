// Trails: a disc falls under gravity, bounces off the walls and drags a fading
// wake behind it.
//
// This is one animation for src/main.zig. An animation only has to provide the
// contract main calls:
//
//   pub const FRAME_MS: u16;                 frame pacing
//   pub fn init() void;                      start state
//   pub fn update(btn: buttons.State) void;  one frame of state
//   pub fn render() void;                    clear draw.buf and paint the frame
//
// Physics runs in 8.8 fixed point: positions and velocities are i32 holding
// 256 sub-pixels per pixel, which keeps the arcs smooth and the bounce
// energy-conserving.

const buttons = @import("../buttons.zig");
const draw = @import("../draw.zig");

pub const FRAME_MS: u16 = 16;

const RADIUS = 5;
const EDGE = RADIUS + 1; // bounce band, in pixels
const PHYS_EVERY = 4; // run physics every Nth frame: overall pace knob
const SUBSTEPS = 4; // physics steps per tick: keeps motion smooth and prevents tunneling
const SUBPIXEL = 8; // fixed-point shift: 256 sub-pixels per pixel
const MAX_SPEED = 6 << SUBPIXEL; // px per physics step, in fixed point
const TRAIL = 24; // length of the wake; also the fade scale

// Gravity acceleration, in fixed point: ~0.06 px per step. Gentle arcs.
const GRAVITY = 1 << 4;

// Horizontal steering strength, in fixed point: ~0.25 px per step. Graded.
const STEER = 1 << 4;

var x: i32 = 0;
var y: i32 = 0;
var vx: i32 = 0;
var vy: i32 = 0;

var trail_x: [TRAIL]i16 = undefined;
var trail_y: [TRAIL]i16 = undefined;
var trail_head: usize = 0;

var frame: usize = 0;

fn capSpeed(v: *i32) void {
    if (v.* > MAX_SPEED) v.* = MAX_SPEED;
    if (v.* < -MAX_SPEED) v.* = -MAX_SPEED;
}

fn stepPhysics(gx: i32, gy: i32) void {
    vx += gx;
    vy += gy;

    capSpeed(&vx);
    capSpeed(&vy);

    x += vx;
    y += vy;

    // Bounce against the pixel band using the pixel position.
    const px = x >> SUBPIXEL;
    const py = y >> SUBPIXEL;

    if (px < EDGE) {
        x = EDGE << SUBPIXEL;

        if (vx < 0) vx = -vx;
    } else if (px > draw.WIDTH - EDGE) {
        x = (draw.WIDTH - EDGE) << SUBPIXEL;

        if (vx > 0) vx = -vx;
    }

    if (py < EDGE) {
        y = EDGE << SUBPIXEL;

        if (vy < 0) vy = -vy;
    } else if (py > draw.HEIGHT - EDGE) {
        y = (draw.HEIGHT - EDGE) << SUBPIXEL;

        if (vy > 0) vy = -vy;
    }
}

fn pushTrail(px: i16, py: i16) void {
    trail_x[trail_head] = px;
    trail_y[trail_head] = py;

    trail_head = (trail_head + 1) % TRAIL;
}

// Newer trail points are drawn thicker, older ones thinner: a monochrome
// "fade" by geometric shrinking instead of gray levels.
fn drawTrail() void {
    var i: usize = 1;

    while (i < TRAIL) : (i += 1) {
        const idx = (trail_head + TRAIL - i) % TRAIL;
        const r: i16 = @intCast((TRAIL - i) * RADIUS / TRAIL);

        if (r > 1) draw.disc(trail_x[idx], trail_y[idx], r);
    }
}

pub fn init() void {
    // Zig 0.17 drops integer initializers on globals that only ever hold
    // small values, so the start state is set here instead.
    x = 32 << SUBPIXEL;
    y = 10 << SUBPIXEL;
    vx = 2 << SUBPIXEL;
    vy = 0;
    trail_head = 0;
    frame = 0;
}

pub fn update(btn: buttons.State) void {
    frame +%= 1;

    if (frame % PHYS_EVERY != 0) return;

    // Buttons tilt gravity: left/right steer. Holding both is the same as
    // neither - the disc still falls.
    const gx: i32 = @as(i32, if (btn.left) -STEER else 0) + @as(i32, if (btn.right) STEER else 0);
    const gy: i32 = GRAVITY;

    var s: usize = 0;

    while (s < SUBSTEPS) : (s += 1) {
        stepPhysics(gx, gy);
    }

    // One trail point per physics tick, not per substep - the wake spans
    // TRAIL × PHYS_EVERY frames of motion.
    pushTrail(@intCast(x >> SUBPIXEL), @intCast(y >> SUBPIXEL));
}

pub fn render() void {
    draw.clear();

    drawTrail();

    const px: i16 = @intCast(x >> SUBPIXEL);
    const py: i16 = @intCast(y >> SUBPIXEL);

    draw.disc(px, py, RADIUS);
    draw.ring(px, py, RADIUS + 2); // rim highlight
}

test "capSpeed clamps both directions" {
    const std = @import("std");

    var v: i32 = 99 << SUBPIXEL;

    capSpeed(&v);

    try std.testing.expectEqual(MAX_SPEED, v);

    v = -(99 << SUBPIXEL);

    capSpeed(&v);

    try std.testing.expectEqual(-MAX_SPEED, v);
}

test "walls reflect velocity and clamp position" {
    const std = @import("std");

    // Disc falling into the floor with downward velocity: clamps to the
    // band and reflects.
    x = 32 << SUBPIXEL;
    y = (draw.HEIGHT << SUBPIXEL) - 1;
    vx = 0;
    vy = 6 << SUBPIXEL;

    stepPhysics(0, GRAVITY);

    try std.testing.expectEqual(@as(i32, (draw.HEIGHT - EDGE) << SUBPIXEL), y);
    try std.testing.expect(vy < 0); // now climbing

    // Ceiling: same treatment. vy must outrun one gravity step, otherwise it
    // reaches zero at the wall instead of reflecting.
    x = 32 << SUBPIXEL;
    y = (EDGE << SUBPIXEL) - (3 << SUBPIXEL);
    vy = -(3 << SUBPIXEL);

    stepPhysics(0, GRAVITY);

    try std.testing.expectEqual(@as(i32, EDGE << SUBPIXEL), y);
    try std.testing.expect(vy > 0); // now falling

    // Mid-panel motion is untouched. vy also has to outrun one gravity step
    // for the disc to actually climb.
    x = 32 << SUBPIXEL;
    y = 20 << SUBPIXEL;
    vx = 2 << SUBPIXEL;
    vy = -(4 << SUBPIXEL);

    stepPhysics(0, GRAVITY);

    try std.testing.expectEqual(@as(i32, 34 << SUBPIXEL), x);
    try std.testing.expect(y < 20 << SUBPIXEL);
}
