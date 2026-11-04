const ff = @import("ff");

const Circle = @This();

pos: ff.Point,
d: i32,

pub fn new(pos: ff.Point, d: i32) Circle {
    return .{
        .pos = pos,
        .d = d,
    };
}

pub fn draw(c: *const Circle, s: ff.Style) void {
    drawCentered(c.pos, c.d, s);
}

pub fn drawCentered(p: ff.Point, d: i32, s: ff.Style) void {
    ff.drawCircle(.new(
        p.x - @divTrunc(d, 2),
        p.y - @divTrunc(d, 2),
    ), d, s);
}
