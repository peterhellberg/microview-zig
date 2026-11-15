// What a C toolchain brings to an AVR: the reset vector and the runtime
// routines libgcc would supply. Zig's own compiler_rt does not build for AVR
// (it casts .flash function pointers to *const anyopaque), so the four helpers
// the animations reach for are here, in Zig, with host tests.
//
// The divmod helpers follow libgcc's ABI, not the C one: they return two values
// in r22:r23 and r24:r25, which is why they return a u32 - on AVR a u32 return
// lands its low half in r22:r23 and its high half in r24:r25.

const std = @import("std");
const builtin = @import("builtin");

comptime {
    // Hidden, otherwise the linker keeps all six in every build: only the ones
    // the active animation calls should cost flash.
    @export(&memset, .{ .name = "memset", .visibility = .hidden });
    @export(&memcpy, .{ .name = "memcpy", .visibility = .hidden });
    @export(&__udivmodhi4, .{ .name = "__udivmodhi4", .visibility = .hidden });
    @export(&__udivmodqi4, .{ .name = "__udivmodqi4", .visibility = .hidden });
    @export(&__divmodhi4, .{ .name = "__divmodhi4", .visibility = .hidden });
    @export(&__mulsi3, .{ .name = "__mulsi3", .visibility = .hidden });
}

comptime {
    // The host builds this file for its tests, and only an AVR assembler
    // understands the startup code.
    if (builtin.cpu.arch == .avr) {
        asm (
            \\.section .text.start,"ax",@progbits
            \\.global _start
            \\_start:
            \\  clr r1                  ; r1 is the zero register
            \\  ldi r28, lo8(__stack)
            \\  out 0x3d, r28           ; SPL
            \\  ldi r28, hi8(__stack)
            \\  out 0x3e, r28           ; SPH
            \\  ldi r30, lo8(__data_load)
            \\  ldi r31, hi8(__data_load)
            \\  ldi r26, lo8(__data_start)
            \\  ldi r27, hi8(__data_start)
            \\  ldi r24, lo8(__data_end)
            \\  ldi r25, hi8(__data_end)
            \\  rjmp 2f
            \\1: lpm r0, Z+
            \\  st X+, r0
            \\2: cp r26, r24
            \\  cpc r27, r25
            \\  brne 1b
            \\  ldi r30, lo8(__bss_start)
            \\  ldi r31, hi8(__bss_start)
            \\  ldi r24, lo8(__bss_end)
            \\  ldi r25, hi8(__bss_end)
            \\  rjmp 4f
            \\3: st Z+, r1
            \\4: cp r30, r24
            \\  cpc r31, r25
            \\  brne 3b
            \\  jmp main
        );
    }
}

// Shifting and subtracting, because a "/" here would call this file again.
fn udivmod(comptime T: type, a: T, b: T, rem: *T) T {
    const top: T = 1 << (@bitSizeOf(T) - 1);

    var n = a;
    var q: T = 0;
    var r: T = 0;

    var i: usize = @bitSizeOf(T);
    while (i > 0) : (i -= 1) {
        r = (r << 1) | @intFromBool((n & top) != 0);
        n <<= 1;
        q = (q << 1) | @intFromBool(r >= b);
        if (r >= b) r -= b;
    }

    rem.* = r;

    return q;
}

// C division: truncates toward zero, and the remainder takes the sign of a.
fn divmod(a: i16, b: i16, rem: *i16) i16 {
    // Negating i16 minimum wraps to itself, whose unsigned value is the
    // magnitude wanted - which is why these are plain bitcasts.
    const ua: u16 = if (a < 0) @bitCast(-%a) else @intCast(a);
    const ub: u16 = if (b < 0) @bitCast(-%b) else @intCast(b);

    var ur: u16 = undefined;
    const uq = udivmod(u16, ua, ub, &ur);

    rem.* = if (a < 0) @bitCast(-%ur) else @intCast(ur);

    return if ((a < 0) != (b < 0)) @bitCast(-%uq) else @intCast(uq);
}

fn memset(dst: [*]u8, c: u8, n: usize) callconv(.c) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = c;

    return dst;
}

fn memcpy(dst: [*]u8, src: [*]const u8, n: usize) callconv(.c) [*]u8 {
    var i: usize = 0;
    while (i < n) : (i += 1) dst[i] = src[i];

    return dst;
}

fn __udivmodhi4(a: u16, b: u16) callconv(.c) u32 {
    var r: u16 = undefined;
    const q = udivmod(u16, a, b, &r);

    return (@as(u32, r) << 16) | q;
}

fn __udivmodqi4(a: u8, b: u8) callconv(.c) u16 {
    var r: u8 = undefined;
    const q = udivmod(u8, a, b, &r);

    return (@as(u16, r) << 8) | q;
}

fn __divmodhi4(a: i16, b: i16) callconv(.c) u32 {
    var r: i16 = undefined;
    const q = divmod(a, b, &r);

    return (@as(u32, @as(u16, @bitCast(r))) << 16) | @as(u16, @bitCast(q));
}

fn __mulsi3(a: u32, b: u32) callconv(.c) u32 {
    var acc: u32 = 0;
    var x = a;
    var y = b;

    while (y != 0) : (y >>= 1) {
        if ((y & 1) != 0) acc +%= x;
        x +%= x;
    }

    return acc;
}

test "unsigned division matches the host over its whole small range" {
    var a: u16 = 0;
    while (a < 256) : (a += 1) {
        var b: u16 = 1;
        while (b < 48) : (b += 1) {
            var r: u16 = undefined;

            try std.testing.expectEqual(a / b, udivmod(u16, a, b, &r));
            try std.testing.expectEqual(a % b, r);
        }
    }
}

test "byte division matches the host" {
    var a: u8 = 0;
    while (true) : (a +%= 1) {
        var b: u8 = 1;
        while (b != 0) : (b +%= 1) {
            var r: u8 = undefined;

            try std.testing.expectEqual(a / b, udivmod(u8, a, b, &r));
            try std.testing.expectEqual(a % b, r);
        }

        if (a == 255) break;
    }
}

test "signed division truncates toward zero" {
    var r: i16 = undefined;

    try std.testing.expectEqual(@as(i16, -2), divmod(-7, 3, &r));
    try std.testing.expectEqual(@as(i16, -1), r);

    try std.testing.expectEqual(@as(i16, -2), divmod(7, -3, &r));
    try std.testing.expectEqual(@as(i16, 1), r);

    // -32768 / -1 is the one case that does not fit; C leaves it undefined.
    var a: i16 = -300;
    while (a <= 300) : (a += 7) {
        var b: i16 = -30;
        while (b <= 30) : (b += 7) {
            if (b == 0) continue;

            try std.testing.expectEqual(@divTrunc(a, b), divmod(a, b, &r));
            try std.testing.expectEqual(@rem(a, b), r);
        }
    }
}

test "the long multiply matches the host" {
    var a: u32 = 1;
    while (a < 100000) : (a = a * 3 + 1) {
        var b: u32 = 1;
        while (b < 70000) : (b = b * 5 + 3) {
            try std.testing.expectEqual(a *% b, __mulsi3(a, b));
        }
    }
}
