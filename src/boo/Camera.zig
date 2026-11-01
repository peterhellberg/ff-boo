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
    const max_x = space.point.x + space.size.width - self.rect.size.width;
    const max_y = space.point.y + space.size.height - self.rect.size.height;

    self.rect.point.x = @max(space.point.x, @min(self.rect.point.x, max_x));
    self.rect.point.y = @max(space.point.y, @min(self.rect.point.y, max_y));
}

pub fn screen(self: *const Camera, point: ff.Point) ff.Point {
    return point.sub(self.rect.point);
}

pub fn sees(self: *const Camera, point: ff.Point) bool {
    return self.rect.contains(point);
}

pub fn intersects(self: *const Camera, r: ff.Rect) bool {
    const camera_right = self.rect.point.x + self.rect.size.width;
    const camera_bottom = self.rect.point.y + self.rect.size.height;

    const rect_right = r.point.x + r.size.width;
    const rect_bottom = r.point.y + r.size.height;

    return self.rect.point.x <= rect_right and
        camera_right >= r.point.x and
        self.rect.point.y <= rect_bottom and
        camera_bottom >= r.point.y;
}
