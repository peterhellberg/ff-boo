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
pub const BURY_RADIUS: f32 = 24.0;
pub const SEPARATION: f32 = 18.0;

const WANDER_SPEED: f32 = 0.3;
const FOLLOW_SPEED: f32 = 1.9;
const FOLLOW_RADIUS: f32 = 56.0;
const LOSE_RADIUS: f32 = 150.0;
const TRAIL_DISTANCE: f32 = 30.0;

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

    // Follow ghosts get a white outline, but a white ghost would
    // disappear against it — fall back to light gray for those.
    const outline: ff.Color = blk: {
        if (self.state != .follow) break :blk .black;
        break :blk if (self.color == .white) .black else .black;
    };

    const stroke: i32 = if (following) 2 else 1;

    // Pass 1: dark discs forming the hem's outline. Drawn BEFORE the
    // body so the body covers their upper halves — only their lower
    // union survives, as one continuous dark band, not three rings.
    const hem_y = sp.y + RADIUS - 3;

    inline for ([_]i32{ -4, 0, 4 }) |ox| {
        ff.drawCircle(.new(sp.x + ox - 7, hem_y - 7), 14, .{ .fill_color = outline });
    }

    // Pass 2: body. Covers the top halves of the dark discs; its own
    // stroke continues the outline around the rest of the silhouette.
    Circle.drawCentered(.new(sp.x, sp.y - 2), RADIUS * 2, .{
        .fill_color = self.color,
        .stroke_color = outline,
        .stroke_width = stroke,
    });

    // Pass 3: fill discs (10px, centers 4 apart → 6px overlap each
    // side). They merge with each other and with the body fill,
    // covering the body's bottom stroke under the skirt. What remains
    // of the dark discs is a single wavy rim ~2px thick that dips
    // between scallops — one hem, zero internal rings.
    inline for ([_]i32{ -4, 0, 4 }) |ox| {
        ff.drawCircle(.new(sp.x + ox - 5, hem_y - 5), 10, .{ .fill_color = self.color });
    }

    const bottom_y = sp.y + RADIUS - 2; // ON the body's bottom stroke

    // Scallop separators. The body's bottom arc rises ~1px by x = ±5,
    // so the outer ticks start and end 1px higher than the center
    // tick — they follow the curve instead of cutting flat across it.
    // All bottoms stay ≤ hem_y + 5, inside the fill discs, so no tick
    // can poke past the silhouette.
    inline for ([_]struct { x: i32, top: i32, len: i32 }{
        .{ .x = -5, .top = 0, .len = 4 },
        .{ .x = 0, .top = 1, .len = 3 },
        .{ .x = 5, .top = 0, .len = 4 },
    }) |t| {
        ff.drawLine(
            .new(sp.x + t.x, bottom_y + t.top),
            .new(sp.x + t.x, bottom_y + t.top + t.len),
            .{ .color = outline, .width = stroke },
        );
    }

    // Eyes: white sclera with the same outline as the body, black
    // pupils that glance in the direction of travel.
    // NOTE: ff.drawCircle's position is the TOP-LEFT corner, so we add
    // half the diameter to land the visual center where we intend.
    const dx: i32 = if (self.dir[0] < -0.01) -1 else if (self.dir[0] > 0.01) 1 else 0;
    const dy: i32 = if (self.dir[1] < -0.01) -1 else if (self.dir[1] > 0.01) 1 else 0;

    inline for ([_]i32{ -4, 3 }) |ex| {
        const ex_c = sp.x + ex; // intended eye center x
        const ey_c = sp.y - 4; // intended eye center y

        ff.drawCircle(.new(ex_c - 4, ey_c - 4), 8, .{ .fill_color = .light_gray });
        ff.drawCircle(.new(ex_c - 3, ey_c - 3), 6, .{ .fill_color = .white });
        ff.drawCircle(.new(ex_c + dx - 1, ey_c + dy - 1), 2, .{ .fill_color = .black });
    }
}
