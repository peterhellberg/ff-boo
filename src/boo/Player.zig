const ff = @import("ff");

const Circle = @import("Circle.zig");

const Boo = @import("../main.zig");

const Player = @This();

pos: ff.Point = rectCenter(Boo.SPACE),
vec: ff.Vec = rectCenter(Boo.SPACE).vec(),
vel: ff.Vec = .{ 0.01, 0.01 },

d: i32 = Boo.SIZE_PLAYER,
r: f32 = 0.0,

pub fn update(p: *Player) void {
    const pd = padDir(Boo.pad);
    const spd: f32 = 2.5;

    const activeThreshold: f32 = 0.2;

    if (pd.strength > activeThreshold) {
        // Only update velocity when joystick is pushed
        p.vel = pd.dir * @as(ff.Vec, @splat(spd * pd.strength));
    } else {
        // Apply friction to continue moving gradually
        const friction: f32 = 0.9985;
        p.vel *= @as(ff.Vec, @splat(friction));
    }

    p.r = Boo.pad.radius();

    // Move one axis at a time so the shepherd slides along walls.
    p.step(0);
    p.step(1);
}

fn step(p: *Player, comptime axis: usize) void {
    if (p.vel[axis] == 0) return;

    var next = p.vec;
    next[axis] += p.vel[axis];

    const point = ff.Point.from_vec(next);
    const radius = @as(f32, @floatFromInt(p.d)) / 2.0;

    if (!Boo.SPACE.contains(point) or Boo.hitsWall(point, radius)) {
        p.vel[axis] = 0;
        return;
    }

    p.vec = next;
    p.pos = point;
}

pub const PadDir = struct {
    dir: ff.Vec,
    strength: f32,
};

/// Returns a normalized direction vector from a pad,
/// flipping Y for screen coordinates, and also returns the strength (0.0–1.0)
pub inline fn padDir(pad: ff.Pad) PadDir {
    var fx: f32 = @as(f32, @floatFromInt(pad.x));
    var fy: f32 = -@as(f32, @floatFromInt(pad.y)); // flip Y

    const deadzone: f32 = 300.0;
    if (@abs(fx) < deadzone) fx = 0;
    if (@abs(fy) < deadzone) fy = 0;

    var dir: ff.Vec = .{ fx, fy };
    const lenSq = dir[0] * dir[0] + dir[1] * dir[1];

    if (lenSq == 0) return .{ .dir = .{ 0, 0 }, .strength = 0.0 };

    const len = @sqrt(lenSq);
    dir *= @as(ff.Vec, @splat(1.0 / len));

    const strength = @min(len / 1000.0, 1.0);

    return .{
        .dir = dir,
        .strength = strength,
    };
}

const eye_white_style: ff.Style = .{
    .fill_color = .white,
    .stroke_color = .white,
    .stroke_width = 1,
};

const eye_pupil_style: ff.Style = .{
    .fill_color = .black,
};

pub fn render(p: *Player) void {
    const sp = Boo.cam.screen(p.pos);

    Circle.new(
        sp.add(ff.Point.from_vec(p.vel).mul(.new(-@divTrunc(p.d, 2), -@divTrunc(p.d, 2)))),
        @intFromFloat(p.r * 0.004),
    ).draw(.{
        .fill_color = .yellow,
    });

    Circle.new(
        sp.add(ff.Point.from_vec(p.vel).mul(.new(-@divTrunc(p.d, 4), -@divTrunc(p.d, 4)))),
        @intFromFloat(p.r * 0.01),
    ).draw(.{
        .fill_color = .white,
        .stroke_color = .yellow,
        .stroke_width = 1,
    });

    Circle.new(sp, p.d).draw(.{
        .fill_color = .yellow,
        .stroke_color = .orange,
        .stroke_width = 1,
    });

    // Draw eyes only if moving
    const vel_len = @sqrt(p.vel[0] * p.vel[0] + p.vel[1] * p.vel[1]);

    if (vel_len != 0) {
        const dir: ff.Vec = p.vel * @as(ff.Vec, @splat(1.0 / vel_len));
        const perp: ff.Vec = .{ -dir[1], dir[0] };
        const half: ff.Vec = .{ 0.5, 0.5 };

        const eye_offset_forward = @as(f32, @floatFromInt(p.d)) * 0.25;
        const eye_offset_side = @as(f32, @floatFromInt(p.d)) * 0.2;
        const forward = dir * @as(ff.Vec, @splat(eye_offset_forward));
        const side = perp * @as(ff.Vec, @splat(eye_offset_side));
        const eye_size: i32 = @intFromFloat(@as(f32, @floatFromInt(p.d)) * 0.45);
        const pup_size = @divTrunc(eye_size, 2);

        { // Right eye
            const right_eye_pos = sp.add(ff.Point.from_vec(forward + side));
            const right_pup_pos = right_eye_pos.add(
                ff.Point.from_vec((forward * half) + side * half),
            );

            Circle.new(right_eye_pos, eye_size).draw(eye_white_style);
            Circle.new(right_pup_pos, pup_size).draw(eye_pupil_style);
        }

        { // Left eye
            const left_eye_pos = sp.add(ff.Point.from_vec(forward - side));
            const left_pup_pos = left_eye_pos.add(
                ff.Point.from_vec((forward * half) - side * half),
            );

            Circle.new(left_eye_pos, eye_size).draw(eye_white_style);
            Circle.new(left_pup_pos, pup_size).draw(eye_pupil_style);
        }
    }
}

pub fn circle(self: *const Player) Circle {
    return .new(self.pos, self.d);
}

fn rectCenter(r: ff.Rect) ff.Point {
    return .{
        .x = r.size.width / 2,
        .y = r.size.height / 2,
    };
}
