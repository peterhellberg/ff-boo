const ff = @import("ff");

const Best = @This();

pub var level: u32 = 1;
pub var score: i32 = 0;
pub var total_buried: u32 = 0;
pub var time_s: u16 = 0;

var stash_buf: [16]u8 = @splat(0);

pub fn load() void {
    const s = ff.loadStash(ff.getMe(), &stash_buf) orelse return;

    if (s.len < 12) return;
    if (s[0] != 'B' or s[1] != 'O' or s[2] != 'O' or s[3] != '1') return;

    level = @max(1, readU16(s[4..6]));
    score = @intCast(readU16(s[6..8]));
    total_buried = readU32(s[8..12]);

    time_s = 0;
    if (s.len >= 14) {
        time_s = readU16(s[12..14]);
    }
}

pub fn save() void {
    stash_buf[0] = 'B';
    stash_buf[1] = 'O';
    stash_buf[2] = 'O';
    stash_buf[3] = '1';

    writeU16(stash_buf[4..6], @intCast(@min(level, 65535)));
    writeU16(stash_buf[6..8], @intCast(@max(0, @min(score, 65535))));
    writeU32(stash_buf[8..12], total_buried);
    writeU16(stash_buf[12..14], time_s);

    stash_buf[14] = 0;
    stash_buf[15] = 0;

    ff.saveStash(ff.getMe(), &stash_buf);
}

fn readU16(b: []const u8) u16 {
    return @as(u16, b[0]) | (@as(u16, b[1]) << 8);
}

fn readU32(b: []const u8) u32 {
    return @as(u32, b[0]) |
        (@as(u32, b[1]) << 8) |
        (@as(u32, b[2]) << 16) |
        (@as(u32, b[3]) << 24);
}

fn writeU16(b: []u8, v: u16) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
}

fn writeU32(b: []u8, v: u32) void {
    b[0] = @truncate(v);
    b[1] = @truncate(v >> 8);
    b[2] = @truncate(v >> 16);
    b[3] = @truncate(v >> 24);
}

comptime {
    if (@sizeOf(@TypeOf(stash_buf)) != 16) @compileError("stash layout changed");
}
