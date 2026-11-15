// Driver for the MicroView: one frame every animation.FRAME_MS, pushing
// whatever the animation painted. Nothing here knows what the animation is.
//
// An animation is any module with this contract:
//
//   pub const FRAME_MS: u16;                  frame pacing
//   pub fn init() void;                       start state
//   pub fn update(btn: buttons.State) void;   one frame of state
//   pub fn render() void;                     clear draw.buf and paint the frame
//
// To write another one: copy src/anims/trails.zig, change the body, then
// point the import below at the new file. That is the only switch.

const buttons = @import("buttons.zig");
const microview = @import("microview.zig");
const animation = @import("anims/trails.zig");

export fn main() callconv(.c) noreturn {
    buttons.init();
    microview.init();
    animation.init();

    while (true) {
        animation.update(buttons.read());
        animation.render();

        microview.display();
        microview.delay(animation.FRAME_MS);
    }
}
