// Host-only tool: render one frame of each animation to an upscaled PNG, for
// the README gallery. Nothing here runs on the AVR.
//
//   make screenshots        (or: zig run src/screenshots.zig)
//
// The animation contract makes this trivial: init(), nudge it forward with
// update() a fixed number of times, then render() paints draw.buf - the same
// buffer the driver sends to the panel.

const std = @import("std");
const buttons = @import("buttons.zig");
const draw = @import("draw.zig");

const SCALE = 4; // each OLED pixel becomes a 4x4 block
const W = draw.WIDTH * SCALE;
const H = draw.HEIGHT * SCALE;
const ROW_BYTES = (W + 7) / 8;

// 1-bit grayscale, so a 256x192 screenshot is still a few kilobytes. Filter
// byte 0 (none) in front of every packed row.
const RAW_LEN = H * (1 + ROW_BYTES);

const Shot = struct {
    name: []const u8,
    anim: type,
    frames: usize, // frames to run before capturing
};

// `frames` is chosen so the frame shows the animation's character: a bent
// trail, uneven spokes, three shaded faces.
const shots = [_]Shot{
    .{ .name = "trails", .anim = @import("anims/trails.zig"), .frames = 70 },
    .{ .name = "spokes", .anim = @import("anims/spokes.zig"), .frames = 30 },
    .{ .name = "cube", .anim = @import("anims/cube.zig"), .frames = 240 },
};

fn pixelOn(buf: *const [draw.WIDTH * draw.PAGES]u8, x: usize, y: usize) bool {
    const b = buf[x + (y / 8) * draw.WIDTH];

    return (b >> @intCast(y % 8)) & 1 != 0;
}

fn putBe(buf: []u8, v: u32) void {
    buf[0] = @truncate(v >> 24);
    buf[1] = @truncate(v >> 16);
    buf[2] = @truncate(v >> 8);
    buf[3] = @truncate(v);
}

fn chunk(io: std.Io, file: std.Io.File, kind: *const [4]u8, data: []const u8) !void {
    var head: [8]u8 = undefined;
    putBe(head[0..4], @intCast(data.len));
    @memcpy(head[4..8], kind);
    try file.writeStreamingAll(io, &head);
    try file.writeStreamingAll(io, data);

    var crc = std.hash.Crc32.init();
    crc.update(kind);
    crc.update(data);

    var tail: [4]u8 = undefined;
    putBe(&tail, crc.final());
    try file.writeStreamingAll(io, &tail);
}

fn packRow(buf: *const [draw.WIDTH * draw.PAGES]u8, y: usize, row: []u8) void {
    @memset(row, 0);

    var x: usize = 0;
    while (x < W) : (x += 1) {
        if (pixelOn(buf, x / SCALE, y / SCALE)) {
            row[x / 8] |= @as(u8, 0x80) >> @intCast(x % 8);
        }
    }
}

fn writePng(io: std.Io, path: []const u8, buf: *const [draw.WIDTH * draw.PAGES]u8) !void {
    var raw: [RAW_LEN]u8 = undefined;

    var p: usize = 0;
    var y: usize = 0;
    while (y < H) : (y += 1) {
        raw[p] = 0; // filter: none
        p += 1;
        packRow(buf, y, raw[p .. p + ROW_BYTES]);
        p += ROW_BYTES;
    }

    // zlib stream around one uncompressed deflate block. Storing the image
    // raw keeps the writer to a few lines and the files are tiny anyway.
    var z: [2 + 5 + RAW_LEN + 4]u8 = undefined;
    z[0] = 0x78; // deflate, 32 KiB window
    z[1] = 0x01; // no dictionary, check bits valid
    z[2] = 0x01; // final block, stored
    const n: u16 = RAW_LEN;
    z[3] = @truncate(n);
    z[4] = @truncate(n >> 8);
    z[5] = @truncate(~n);
    z[6] = @truncate(~n >> 8);
    @memcpy(z[7 .. 7 + RAW_LEN], &raw);

    // Adler-32 of the raw data, big-endian after the deflate stream.
    var a: u32 = 1;
    var b: u32 = 0;
    for (raw) |byte| {
        a = (a + byte) % 65521;
        b = (b + a) % 65521;
    }
    putBe(z[7 + RAW_LEN ..][0..4], (b << 16) | a);

    var ihdr: [13]u8 = undefined;
    putBe(ihdr[0..4], W);
    putBe(ihdr[4..8], H);
    ihdr[8] = 1; // 1 bit per pixel
    ihdr[9] = 0; // grayscale
    ihdr[10] = 0; // deflate
    ihdr[11] = 0; // adaptive filtering
    ihdr[12] = 0; // no interlace

    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    try file.writeStreamingAll(io, &.{ 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' });
    try chunk(io, file, "IHDR", &ihdr);
    try chunk(io, file, "IDAT", &z);
    try chunk(io, file, "IEND", &.{});
}

test "packRow puts lit OLED pixels in the right place at 4x" {
    var buf: [draw.WIDTH * draw.PAGES]u8 = @splat(0);
    buf[0] |= 1; // OLED pixel (0, 0)
    buf[draw.WIDTH - 1 + (draw.HEIGHT / 8 - 1) * draw.WIDTH] |= 0x80; // pixel (63, 47)

    var row: [ROW_BYTES]u8 = undefined;

    packRow(&buf, 0, &row);
    try std.testing.expectEqual(@as(u8, 0xf0), row[0]);
    try std.testing.expectEqual(@as(u8, 0x00), row[1]);

    packRow(&buf, H - 1, &row);
    try std.testing.expectEqual(@as(u8, 0x0f), row[ROW_BYTES - 1]);
    try std.testing.expectEqual(@as(u8, 0x00), row[0]);
}

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    try std.Io.Dir.cwd().createDirPath(io, "docs");

    inline for (shots) |s| {
        s.anim.init();

        var i: usize = 0;
        while (i < s.frames) : (i += 1) {
            s.anim.update(.{ .left = false, .right = false });
        }
        s.anim.render();

        var path_buf: [64]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "docs/{s}.png", .{s.name});
        try writePng(io, path, &draw.buf);

        std.debug.print("{s}: {d} frames -> {s}\n", .{ s.name, s.frames, path });
    }
}
