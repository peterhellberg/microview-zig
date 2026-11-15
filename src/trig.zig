// Shared trig for the animations: 8.8 fixed point, a 256-step turn, and a
// parabola approximation that is about 5% off true sine. No tables, because a
// const array would live in flash and cost an lpm on AVR.

pub fn sin(a: u8) i16 {
    const half: u16 = a & 127;
    const v: i16 = @intCast((half * (128 - half)) >> 4);

    return if (a < 128) v else -v;
}

pub fn cos(a: u8) i16 {
    return sin(a +% 64);
}

test "sin is a sine wave to within a few percent" {
    const std = @import("std");

    try std.testing.expectEqual(@as(i16, 0), sin(0));
    try std.testing.expectEqual(@as(i16, 256), cos(0));
    try std.testing.expectEqual(@as(i16, 256), sin(64));
    try std.testing.expectEqual(@as(i16, -256), sin(192));

    // The only value allowed near a zero crossing is "small".
    try std.testing.expect(@abs(sin(127)) < 10);
    try std.testing.expect(@abs(sin(255)) < 10);
}
