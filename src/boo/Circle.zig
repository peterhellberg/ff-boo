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

pub fn intersect(c1: Circle, c2: Circle) bool {
    return circlesIntersect(c1.pos, c1.d, c2.pos, c2.d);
}

pub fn contains(self: Circle, other: Circle) bool {
    const dx = other.pos.x - self.pos.x;
    const dy = other.pos.y - self.pos.y;
    const rs: i32 = @divTrunc(self.d, 2) - @divTrunc(other.d, 2);

    return dx * dx + dy * dy <= rs * rs;
}

pub fn drawCentered(p: ff.Point, d: i32, s: ff.Style) void {
    ff.drawCircle(.new(
        p.x - @divTrunc(d, 2),
        p.y - @divTrunc(d, 2),
    ), d, s);
}

inline fn circlesIntersect(ca: ff.Point, da: i32, cb: ff.Point, db: i32) bool {
    const dx: i32 = cb.x - ca.x;
    const dy: i32 = cb.y - ca.y;
    const sq: i32 = dx * dx + dy * dy;
    const rs: i32 = @divTrunc(da, 2) + @divTrunc(db, 2);

    return sq < rs * rs;
}
