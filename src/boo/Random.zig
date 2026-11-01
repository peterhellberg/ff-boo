//! Random value helpers built on the host-provided RNG (`ff.getRandom`).

const ff = @import("ff");

/// Uniform random value in [0, d), for any signed or unsigned integer type.
///
/// Uses Lemire-style multiply-shift instead of modulo: a single 64-bit
/// multiply and shift, avoiding a runtime division. The random value is
/// masked to 31 bits so the product cannot overflow u64.
pub inline fn mod(comptime T: type, d: T) T {
    const r: u64 = ff.getRandom() & 0x7FFF_FFFF;

    return @intCast((r * @as(u64, @intCast(d))) >> 31);
}

/// Uniform random point inside `space`, drawn from a single RNG call:
/// the low 16 bits select x, the high 16 bits select y.
pub inline fn pos(space: ff.Rect) ff.Point {
    const r: u32 = ff.getRandom();

    return .{
        .x = @mod(@as(i32, @intCast(r & 0xFFFF)), space.size.width),
        .y = @mod(@as(i32, @intCast(r >> 16)), space.size.height),
    };
}

/// Randomly picks one of the two star grays with 50/50 probability.
pub inline fn starColor() ff.Color {
    return if ((ff.getRandom() & 1) == 0) .light_gray else .dark_gray;
}
