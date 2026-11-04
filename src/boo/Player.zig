const ff = @import("ff");

const Circle = @import("Circle.zig");

const Boo = @import("../main.zig");

const Player = @This();

pos: ff.Point = rectCenter(Boo.SPACE),
vec: ff.Vec = rectCenter(Boo.SPACE).vec(),
vel: ff.Vec = .{ 0.01, 0.01 },

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
    const vel = p.vel[axis];

    if (vel == 0) return;

    var next = p.vec;

    next[axis] += vel;

    const point = ff.Point.from_vec(next);

    if (!Boo.SPACE.contains(point) or
        Boo.hitsWall(point, 10))
    {
        p.vel[axis] = 0;
        return;
    }

    p.vec[axis] = next[axis];
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
    const pt = ff.Point.from_vec(p.vel);

    Circle.new(
        sp.add(pt.mul(.new(-8, -8))),
        @intFromFloat(p.r * 0.005),
    ).draw(.{ .fill_color = .yellow });

    Circle.new(
        sp.add(pt.mul(.new(-5, -5))),
        @intFromFloat(p.r * 0.01),
    ).draw(.{
        .fill_color = .white,
        .stroke_color = .yellow,
        .stroke_width = 1,
    });

    Circle.new(sp, 20).draw(.{
        .fill_color = .yellow,
        .stroke_color = .orange,
        .stroke_width = 1,
    });

    const vel_len = @sqrt(@reduce(.Add, p.vel * p.vel));

    if (vel_len < 0.01) return;
    { // Eyes
        const dir = p.vel / @as(ff.Vec, @splat(vel_len));
        const side_dir: ff.Vec = .{ -dir[1], dir[0] };
        const forward = dir * @as(ff.Vec, @splat(5.0));
        const side = side_dir * @as(ff.Vec, @splat(4.0));
        const pupil = dir * @as(ff.Vec, @splat(2.0));

        inline for (.{ side, -side }) |offset| {
            const eye_pos = sp.add(.from_vec(forward + offset));

            Circle.new(eye_pos, 9).draw(eye_white_style);
            Circle.new(eye_pos.add(.from_vec(pupil)), 4).draw(eye_pupil_style);
        }
    }
}

fn rectCenter(r: ff.Rect) ff.Point {
    return .{
        .x = r.size.width / 2,
        .y = r.size.height / 2,
    };
}
