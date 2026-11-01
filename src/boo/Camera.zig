const ff = @import("ff");

const Camera = @This();

rect: ff.Rect = .new(0, 0, ff.width, ff.height),

pub fn center(self: *Camera, point: ff.Point) void {
    self.rect.point = point.sub(
        .new(
            @divTrunc(self.rect.size.width, 2),
            @divTrunc(self.rect.size.height, 2),
        ),
    );
}

pub fn clamp(self: *Camera, space: ff.Rect) void {
    const maxX = space.point.x + space.size.width - self.rect.size.width;
    const maxY = space.point.y + space.size.height - self.rect.size.height;

    self.rect.point.x = @max(space.point.x, @min(self.rect.point.x, maxX));
    self.rect.point.y = @max(space.point.y, @min(self.rect.point.y, maxY));
}

pub fn screen(self: *const Camera, point: ff.Point) ff.Point {
    return point.sub(self.rect.point);
}

pub fn sees(self: *const Camera, point: ff.Point) bool {
    return self.rect.contains(point);
}

pub fn intersects(self: *const Camera, r: ff.Rect) bool {
    const aMin = self.rect.min();
    const aMax = self.rect.max();
    const bMin = r.min();
    const bMax = r.max();

    return !(aMax.x < bMin.x or aMin.x > bMax.x or aMax.y < bMin.y or aMin.y > bMax.y);
}
