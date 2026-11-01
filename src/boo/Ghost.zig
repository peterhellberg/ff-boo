const ff = @import("ff");

const Circle = @import("Circle.zig");
const Random = @import("Random.zig");

const Boo = @import("../main.zig");

const Ghost = @This();

pub const State = enum { wander, follow, buried };

pos: ff.Point = .{},
vec: ff.Vec = .{ 0, 0 },
dir: ff.Vec = .{ 0, 0 },
state: State = .wander,
color: ff.Color = .white,
wander_frames: u16 = 0,

pub const RADIUS: i32 = 9;
pub const BURY_RADIUS: f32 = 16.0;
pub const SEPARATION: f32 = 18.0;

const WANDER_SPEED: f32 = 0.35;
const FOLLOW_SPEED: f32 = 2.4;
const FOLLOW_RADIUS: f32 = 64.0;
const LOSE_RADIUS: f32 = 140.0;
const TRAIL_DISTANCE: f32 = 26.0;

pub fn spawn(self: *Ghost, grave: ff.Point) void {
    self.pos = spawnPos(grave);

    self.vec = self.pos.vec();
    self.dir = .{ 0, 0 };
    self.state = .wander;
    self.wander_frames = 0;
}

fn spawnPos(grave: ff.Point) ff.Point {
    var p: ff.Point = Boo.player.pos;

    var tries: u8 = 0;
    while (tries < 100) : (tries += 1) {
        const angle = ff.Angle.fromDegrees(
            @floatFromInt(Random.mod(u32, 360)),
        ).radians;
        const dist: f32 = @floatFromInt(130 + Random.mod(u32, 90));

        const raw = Boo.player.pos.add(.new(
            @intFromFloat(@cos(angle) * dist),
            @intFromFloat(@sin(angle) * dist),
        ));

        // Stay inside the world with a small margin.
        p = .{
            .x = @max(20, @min(raw.x, Boo.SPACE.size.width - 20)),
            .y = @max(20, @min(raw.y, Boo.SPACE.size.height - 20)),
        };

        if (!Boo.cam.sees(p) and p.sub(grave).len() >= 120.0) return p;
    }

    return p;
}

pub fn update(self: *Ghost) void {
    switch (self.state) {
        .buried => {},
        .wander => self.wander(),
        .follow => self.follow(),
    }
}

fn wander(self: *Ghost) void {
    if (self.wander_frames == 0) {
        const angle = ff.Angle.fromDegrees(
            @floatFromInt(Random.mod(u32, 360)),
        ).radians;

        self.dir = .{ @cos(angle), @sin(angle) };
        self.wander_frames = @intCast(60 + Random.mod(u32, 120));
    } else {
        self.wander_frames -= 1;
    }

    self.vec += self.dir * @as(ff.Vec, @splat(WANDER_SPEED));
    self.pos = ff.Point.from_vec(self.vec);
    self.bounce();

    if (self.pos.sub(Boo.player.pos).len() < FOLLOW_RADIUS) {
        self.state = .follow;
        Boo.followSound();
    }
}

fn follow(self: *Ghost) void {
    const d = Boo.player.pos.sub(self.pos);
    const dist = d.len();

    if (dist > LOSE_RADIUS) {
        self.state = .wander;
        self.wander_frames = 0;
        return;
    }

    if (dist > 1.0) {
        // Aim for a point TRAIL_DISTANCE from the shepherd, on the line
        // between the shepherd and the ghost.
        const target = Boo.player.pos.sub(d.scale(TRAIL_DISTANCE / dist));
        const to = target.sub(self.pos);
        const to_len = to.len();

        if (to_len > 0.5) {
            const step = @min(to_len * 0.12, FOLLOW_SPEED);
            self.dir = to.vec() * @as(ff.Vec, @splat(step / to_len));
            self.vec += self.dir;
        }
    }

    self.clamp();
}

fn bounce(self: *Ghost) void {
    const lo = Boo.SPACE.min();
    const hi = Boo.SPACE.max();

    const min_x: f32 = @floatFromInt(lo.x);
    const max_x: f32 = @floatFromInt(hi.x);
    const min_y: f32 = @floatFromInt(lo.y);
    const max_y: f32 = @floatFromInt(hi.y);

    if (self.vec[0] < min_x) {
        self.dir[0] = @abs(self.dir[0]);
        self.vec[0] = min_x;
    } else if (self.vec[0] > max_x) {
        self.dir[0] = -@abs(self.dir[0]);
        self.vec[0] = max_x;
    }

    if (self.vec[1] < min_y) {
        self.dir[1] = @abs(self.dir[1]);
        self.vec[1] = min_y;
    } else if (self.vec[1] > max_y) {
        self.dir[1] = -@abs(self.dir[1]);
        self.vec[1] = max_y;
    }

    self.pos = ff.Point.from_vec(self.vec);
}

pub fn clamp(self: *Ghost) void {
    const lo = Boo.SPACE.min();
    const hi = Boo.SPACE.max();

    self.vec[0] = @max(
        @as(f32, @floatFromInt(lo.x)),
        @min(self.vec[0], @as(f32, @floatFromInt(hi.x))),
    );
    self.vec[1] = @max(
        @as(f32, @floatFromInt(lo.y)),
        @min(self.vec[1], @as(f32, @floatFromInt(hi.y))),
    );

    self.pos = ff.Point.from_vec(self.vec);
}

pub fn line(self: *const Ghost) void {
    if (self.state != .follow) return;

    ff.draw.Line(
        Boo.cam.screen(Boo.player.pos),
        Boo.cam.screen(self.pos),
        .{ .color = .orange },
    );
}

fn rect(self: *const Ghost) ff.Rect {
    return self.pos
        .sub(.new(RADIUS, RADIUS))
        .rect(.new(RADIUS * 2, RADIUS * 2));
}

pub fn render(self: *const Ghost) void {
    if (self.state == .buried) return;
    if (!Boo.cam.intersects(self.rect())) return;

    const sp = Boo.cam.screen(self.pos);
    const following = self.state == .follow;

    Circle.drawCentered(sp, RADIUS * 2, .{
        .fill_color = self.color,
        .stroke_color = if (following) .white else .dark_blue,
        .stroke_width = if (following) 2 else 1,
    });

    // A little tail and two eyes make the circle read as a ghost.
    ff.drawTriangle(
        .new(sp.x - 6, sp.y + 2),
        .new(sp.x + 6, sp.y + 2),
        .new(sp.x, sp.y + RADIUS + 3),
        .{ .fill_color = self.color },
    );

    ff.drawCircle(.new(sp.x - 4, sp.y - 4), 2, .{ .fill_color = .black });
    ff.drawCircle(.new(sp.x + 2, sp.y - 4), 2, .{ .fill_color = .black });
}
