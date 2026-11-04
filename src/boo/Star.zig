const ff = @import("ff");

const Boo = @import("../main.zig");

const Star = @This();

pos: ff.Point = .{},
c: ff.Color = .white,

pub fn render(star: *const Star) void {
    ff.draw.Point(Boo.cam.screen(star.pos), star.c);
}
