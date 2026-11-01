const ff = @import("ff");

const Palette = @This();

pub var dawn_step: u32 = 0;

pub const NIGHT: ff.Palette = .{
    .black = 0x1A1A1D,
    .dark_gray = 0x4A4E5A,
    .gray = 0x8C8E96,
    .light_gray = 0xCDCFC8,
    .white = 0xF2EFE0,
    .dark_blue = 0x24356E,
    .blue = 0x4066D6,
    .light_blue = 0x7FC4EA,
    .orange = 0xF79E1D,
    .yellow = 0xFFD075,
    .dark_green = 0x2E7D4F,
    .green = 0x43B364,
    .light_green = 0xA9EE6C,
    .cyan = 0x5BC9D6,
    .red = 0xD85555,
    .purple = 0x9C5BB5,
};

pub const DAWN: ff.Palette = .{
    .black = 0x42202E,
    .dark_gray = 0x6B4A52,
    .gray = 0x9E7B72,
    .light_gray = 0xE3BDA4,
    .white = 0xFFF3D9,
    .dark_blue = 0x3E3A5C,
    .blue = 0x6E6FA8,
    .light_blue = 0xA9C7DD,
    .cyan = 0x8FC5BC,
    .orange = 0xE8913F,
    .red = 0xC4554E,
    .dark_green = 0xB06A3A,
    .yellow = 0xF5D98C,
    .green = 0x7B9955,
    .light_green = 0xB8CE7E,
    .purple = 0x9A6FA5,
};

pub fn apply(step: u32) void {
    // Smoothstep on t: at 6 steps the raw linear ramp makes steps 0-1
    // and 4-5 look nearly identical (the eye discriminates best at
    // mid-lightness). Ease so both ends get visible motion.
    const t_raw = @as(f32, @floatFromInt(step)) / 5.0;
    const t = t_raw * t_raw * (3.0 - 2.0 * t_raw);
    const t_q: u8 = @intFromFloat(t * 255.0 + 0.5);

    var p: ff.Palette = NIGHT;
    inline for (@typeInfo(ff.Palette).@"struct".field_names) |name| {
        @field(p, name) = lerpHex(@field(NIGHT, name), @field(DAWN, name), t_q);
    }
    p.set();

    dawn_step = step;
}

fn lerpHex(a: u32, b: u32, t_q: u8) u32 { // t_q = 0..255
    var result: u32 = 0;
    inline for (0..3) |i| {
        const shift: u5 = @intCast(8 * (2 - i));
        const ca: u32 = (a >> shift) & 0xFF;
        const cb: u32 = (b >> shift) & 0xFF;
        const mixed = (ca * (255 - t_q) + cb * t_q + 127) / 255;
        result |= mixed << shift;
    }
    return result;
}

comptime {
    if (lerpHex(0x000000, 0xFFFFFF, 128) != 0x808080) {
        @compileError("lerpHex midpoint is wrong");
    }
}
