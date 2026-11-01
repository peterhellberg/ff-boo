const std = @import("std");

const ff = @import("ff");

const draw = ff.draw;

const Camera = @import("boo/Camera.zig");
const Cheats = @import("boo/Cheats.zig");
const Ghost = @import("boo/Ghost.zig");
const Player = @import("boo/Player.zig");
const Random = @import("boo/Random.zig");
const Sound = @import("boo/Sound.zig");
const Star = @import("boo/Star.zig");

pub const SIZE_SPACE = 3;
pub const SIZE_PLAYER = 21;
pub const NUM_STARS = 128;
pub const NUM_GHOSTS_MAX = 8;

pub const SPACE = ff.Rect.new(
    0,
    0,
    ff.width * SIZE_SPACE,
    ff.height * SIZE_SPACE,
);

const CLEAR_FRAMES = 120;
const BOARD_SCORE: ff.Board = 1;
const BADGE_SHEPHERD: ff.Badge = 1;

pub var pad: ff.Pad = .{ .x = 0, .y = 0 };
pub var cam: Camera = .{};
pub var player: Player = .{};

var state: State = .Menu;

var menu: Menu = .{};
var init: Init = .{};
var game: Game = .{};
var clear: Clear = .{};
var over: Over = .{};

var buf: [1735]u8 = undefined;
var hud_buf: [32]u8 = undefined;
var fff: ff.Font = undefined;

const NO_BUTTONS: ff.Buttons = .{
    .s = false,
    .e = false,
    .w = false,
    .n = false,
    .menu = false,
};

var btn: ff.Buttons = NO_BUTTONS;
var old: ff.Buttons = NO_BUTTONS;

var frame: u32 = 0;

var level: u32 = 1;
var level_ms: u64 = 0;
var started_at: u64 = 0;
var dawn_step: u32 = 0;

var run_score: i32 = 0;
var clear_bonus: i32 = 0;
var clear_frames: u16 = 0;

var best_level: u32 = 1;
var best_score: i32 = 0;
var best_time_s: u16 = 0;
var total_buried: u32 = 0;

var ghost_count: usize = 0;
var ghosts: [NUM_GHOSTS_MAX]Ghost = @splat(.{});
var graves: [NUM_GHOSTS_MAX]Grave = @splat(.{});

const MAX_WALLS = (MAZE_COLS - 1) * MAZE_ROWS + MAZE_COLS * (MAZE_ROWS - 1);
var wall_count: usize = 0;
var walls: [MAX_WALLS]ff.Rect = @splat(.{});

// Maze grid: 12 x 8 cells of 60 px fills the 720 x 480 world exactly.
const MAZE_COLS = 12;
const MAZE_ROWS = 8;
const CELL: i32 = 60;
const WALL_THICKNESS: i32 = 10;
const BRAID_PERCENT: u32 = 25;

// Start in the middle of a cell so no wall can spawn on top of the shepherd.
const START = ff.Point.new(
    CELL * @as(i32, @intCast(MAZE_COLS / 2)) + @divTrunc(CELL, 2),
    CELL * @as(i32, @intCast(MAZE_ROWS / 2)) + @divTrunc(CELL, 2),
);

var stars: [NUM_STARS]Star = @splat(.{});

var sound: Sound = undefined;
var last_time: u64 = 0;

const GHOST_COLORS = [NUM_GHOSTS_MAX]ff.Color{
    .white,
    .red,
    .cyan,
    .light_green,
    .blue,
    .purple,
    .green,
    .light_blue,
};

const NIGHT: ff.Palette = .{
    .black = 0x131313,
    .dark_gray = 0x505050,
    .gray = 0x8D8D8D,
    .cyan = 0x53C7D6,
    .light_gray = 0xCECECE,
    .white = 0xF2F0E5,
    .light_blue = 0x6FA8FF,
    .orange = 0xF7A41D,
    .dark_green = 0xC77C03,
    .red = 0xD04A4A,
    .purple = 0x8A4FB0,
    .yellow = 0xFFCD75,
    .light_green = 0xA7F070,
    .green = 0x38B764,
    .dark_blue = 0x29366F,
    .blue = 0x3B5DC9,
};

const DAWN: ff.Palette = .{
    .black = 0x6E3B4E,
    .dark_gray = 0x7A4A5A,
    .gray = 0xA86A5A,
    .cyan = 0x9FD0C8,
    .light_gray = 0xE0B090,
    .white = 0xFFF0D0,
    .light_blue = 0xAFC4E8,
    .orange = 0xFFB347,
    .dark_green = 0xD97B4A,
    .red = 0xD07068,
    .purple = 0xB08AC0,
    .yellow = 0xFFE08A,
    .light_green = 0xC8D890,
    .green = 0x8AA070,
    .dark_blue = 0x5A4A6A,
    .blue = 0x7A6A9A,
};

const State = enum {
    Menu,
    Init,
    Game,
    Clear,
    Over,

    fn update(s: State) void {
        frame += 1;

        const me = ff.getMe();
        {
            pad = ff.readPad(me).?;

            old = btn;
            btn = ff.readButtons(me);
        }

        tickSound();

        // Cheat: start a fresh game once, so a headless run can be profiled.
        // One-shot, so with the cheat unused this is inert.
        if (cheats.jumpToGame) {
            cheats.jumpToGame = false;
            startRun();
        }

        switch (s) {
            .Menu => menu.update(),
            .Init => init.update(),
            .Game => game.update(),
            .Clear => clear.update(),
            .Over => over.update(),
        }
    }

    fn render(s: State) void {
        ff.clearScreen(.black);

        if (cheats.tagName) {
            text(@tagName(s), .new(10, 10), .dark_blue);
        }

        switch (s) {
            .Menu => menu.render(),
            .Init => {},
            .Game => game.render(),
            .Clear => clear.render(),
            .Over => over.render(),
        }
    }
};

const Menu = struct {
    blink: bool = false,

    fn update(self: *Menu) void {
        if (@mod(frame, 12) == 0) self.blink = !self.blink;

        if (!btn.e and old.e) startRun();

        if (cheats.stateFlip and !btn.s and old.s) enterOver();
    }

    fn render(self: *Menu) void {
        renderStars();

        text("peter.boo", .new(93, 45), if (self.blink) .white else .light_gray);
        text("A FRIENDLY GHOST SHEPHERD", .new(36, 70), .light_gray);
        text("MOVE WITH THE TOUCHPAD", .new(48, 100), .cyan);
        text("GET CLOSE TO MAKE GHOSTS FOLLOW", .new(18, 112), .cyan);
        text("LEAD THEM TO THEIR MATCHING GRAVE", .new(18, 124), .cyan);
        text("PRESS (E) TO START GAME!", .new(48, 144), .white);
    }
};

const Init = struct {
    fn update(_: *Init) void {
        player = .{};
        player.pos = START;
        player.vec = START.vec();

        cam.center(player.pos);
        cam.clamp(SPACE);

        ghost_count = ghostCount(level);
        generate();

        applyPalette(0);
        started_at = ff.getTime();
        level_ms = levelMs(level);

        state = .Game;
    }

    fn render(_: *Init) void {}
};

const Game = struct {
    fn update(_: *Game) void {
        player.update();

        cam.center(player.pos);
        cam.clamp(SPACE);

        for (ghosts[0..ghost_count]) |*ghost| {
            ghost.update();
        }

        separateGhosts();
        buryGhosts();

        const step = dawnStep();
        if (step != dawn_step) applyPalette(step);

        if (allBuried()) {
            enterClear();
            return;
        }

        if (remainingMs() == 0) {
            enterOver();
            return;
        }

        if (cheats.stateFlip and !btn.n and old.n) {
            applyPalette(0);
            state = .Menu;
        }
        if (cheats.stateFlip and !btn.s and old.s) enterOver();
    }

    fn render(_: *Game) void {
        renderWorld(true);
        renderHud();
    }
};

const Clear = struct {
    fn update(_: *Clear) void {
        if (clear_frames > 0) clear_frames -= 1;

        if (clear_frames == 0) {
            level += 1;
            state = .Init;
        }
    }

    fn render(_: *Clear) void {
        renderWorld(true);
        renderSunAndHills();
        renderHud();

        panel(60, 56, 120, 46);
        textCentered("NIGHT CLEARED", 120, 70, .white);

        const b = std.fmt.bufPrint(&hud_buf, "+{d}", .{clear_bonus}) catch return;
        textCentered(b, 120, 90, .yellow);
    }
};

const Over = struct {
    fn update(_: *Over) void {
        if (!btn.e and old.e) startRun();

        if (!btn.n and old.n) {
            applyPalette(0);
            state = .Menu;
        }
    }

    fn render(_: *Over) void {
        renderWorld(false);
        renderSunAndHills();

        panel(42, 40, 156, 118);

        textCentered("DAWN", 120, 55, .white);
        textCentered("THE NIGHT IS OVER", 120, 75, .light_gray);

        var b = std.fmt.bufPrint(&hud_buf, "SCORE {d}", .{run_score}) catch return;
        textCentered(b, 120, 95, .yellow);

        b = std.fmt.bufPrint(&hud_buf, "BEST {d} N{d}", .{
            best_score,
            best_level,
        }) catch return;
        textCentered(b, 120, 107, .light_gray);

        if (best_time_s > 0) {
            const t: u64 = best_time_s;
            b = std.fmt.bufPrint(&hud_buf, "SOULS {d}  FAST {d}:{d:0>2}", .{
                total_buried,
                t / 60,
                t % 60,
            }) catch return;
        } else {
            b = std.fmt.bufPrint(&hud_buf, "SOULS {d}", .{total_buried}) catch return;
        }
        textCentered(b, 120, 119, .cyan);

        textCentered("PRESS (E) TO PLAY AGAIN!", 120, 132, .white);
        textCentered("(N) FOR MENU", 120, 144, .light_gray);
    }
};

const GRAVE_W: i32 = 14;
const GRAVE_H: i32 = 18;

const Grave = struct {
    pos: ff.Point = .{},
    filled: bool = false,

    fn render(self: *const Grave, color: ff.Color) void {
        const r = self.pos
            .sub(.new(@divTrunc(GRAVE_W, 2), @divTrunc(GRAVE_H, 2)))
            .rect(.new(GRAVE_W, GRAVE_H));

        if (!cam.intersects(r)) return;

        const sp = cam.screen(self.pos);
        const x = sp.x - @divTrunc(GRAVE_W, 2);
        const y = sp.y - @divTrunc(GRAVE_H, 2);

        draw.rrect(x, y, GRAVE_W, GRAVE_H, 3, 3, .{
            .fill_color = if (self.filled) .green else .dark_gray,
            .stroke_color = .gray,
            .stroke_width = 1,
        });

        if (self.filled) {
            draw.line(sp.x - 3, sp.y - 2, sp.x + 3, sp.y - 2, .{ .color = .light_green });
            draw.line(sp.x, sp.y - 5, sp.x, sp.y + 3, .{ .color = .light_green });
        } else {
            draw.circ(sp.x - 3, sp.y - GRAVE_H, 6, .{ .fill_color = color });
        }
    }
};

fn startRun() void {
    level = 1;
    run_score = 0;
    state = .Init;
}

fn enterClear() void {
    const secs: i32 = @intCast((remainingMs() + 999) / 1000);

    clear_bonus = secs * 5;
    run_score += clear_bonus;

    const elapsed_s: u16 = @intCast(@min(
        (level_ms - remainingMs() + 999) / 1000,
        65535,
    ));
    if (best_time_s == 0 or elapsed_s < best_time_s) best_time_s = elapsed_s;

    best_level = @max(best_level, level);
    best_score = @max(best_score, run_score);
    saveBest();

    clearSound();
    clear_frames = CLEAR_FRAMES;
    state = .Clear;
}

fn enterOver() void {
    applyPalette(5);

    best_level = @max(best_level, level);
    best_score = @max(best_score, run_score);
    saveBest();

    const score: i16 = @intCast(@max(
        0,
        @min(run_score, @as(i32, std.math.maxInt(i16))),
    ));
    _ = ff.addScore(ff.getMe(), BOARD_SCORE, score);

    dawnSound();
    state = .Over;
}

fn generate() void {
    // Same layout every time a night is attempted.
    ff.setSeed(0xB00 + level);

    const margin: i32 = 48;
    const inner = ff.Rect.new(
        margin,
        margin,
        SPACE.size.width - margin * 2,
        SPACE.size.height - margin * 2,
    );
    const center = START;

    for (0..ghost_count) |i| {
        var p = Random.pos(inner).add(.new(margin, margin));

        var tries: u16 = 0;
        while (tries < 200 and !graveSpotOk(p, i, center)) : (tries += 1) {
            p = Random.pos(inner).add(.new(margin, margin));
        }

        graves[i] = .{ .pos = p };
        ghosts[i] = .{ .color = GHOST_COLORS[i] };
        ghosts[i].spawn(p);
    }

    generateWalls();
}

fn generateWalls() void {
    wall_count = 0;

    var v_wall: [MAZE_COLS][MAZE_ROWS]bool = @splat(@splat(true));
    var h_wall: [MAZE_COLS][MAZE_ROWS]bool = @splat(@splat(true));

    // Randomized depth-first search carves a perfect maze, then braiding
    // removes some walls so it has loops instead of dead ends.
    var visited: [MAZE_COLS * MAZE_ROWS]bool = @splat(false);
    var stack: [MAZE_COLS * MAZE_ROWS]usize = undefined;

    var sp: usize = 1;
    visited[0] = true;
    stack[0] = 0;

    while (sp > 0) {
        const cur = stack[sp - 1];
        const cx = cur % MAZE_COLS;
        const cy = cur / MAZE_COLS;

        var next: [4]usize = undefined;
        var n: usize = 0;

        if (cx > 0 and !visited[cur - 1]) {
            next[n] = cur - 1;
            n += 1;
        }
        if (cx + 1 < MAZE_COLS and !visited[cur + 1]) {
            next[n] = cur + 1;
            n += 1;
        }
        if (cy > 0 and !visited[cur - MAZE_COLS]) {
            next[n] = cur - MAZE_COLS;
            n += 1;
        }
        if (cy + 1 < MAZE_ROWS and !visited[cur + MAZE_COLS]) {
            next[n] = cur + MAZE_COLS;
            n += 1;
        }

        if (n == 0) {
            sp -= 1;
            continue;
        }

        const pick = next[Random.mod(u32, @intCast(n))];
        const px = pick % MAZE_COLS;

        if (px == cx) {
            h_wall[cx][@min(cy, pick / MAZE_COLS)] = false;
        } else {
            v_wall[@min(cx, px)][cy] = false;
        }

        visited[pick] = true;
        stack[sp] = pick;
        sp += 1;
    }

    for (0..MAZE_COLS - 1) |c| {
        for (0..MAZE_ROWS) |r| {
            if (!v_wall[c][r]) continue;
            if (Random.mod(u32, 100) < BRAID_PERCENT) continue;

            addWall(ff.Rect.new(
                @as(i32, @intCast(c + 1)) * CELL - WALL_THICKNESS / 2,
                @as(i32, @intCast(r)) * CELL,
                WALL_THICKNESS,
                CELL,
            ));
        }
    }

    for (0..MAZE_COLS) |c| {
        for (0..MAZE_ROWS - 1) |r| {
            if (!h_wall[c][r]) continue;
            if (Random.mod(u32, 100) < BRAID_PERCENT) continue;

            addWall(ff.Rect.new(
                @as(i32, @intCast(c)) * CELL,
                @as(i32, @intCast(r + 1)) * CELL - WALL_THICKNESS / 2,
                CELL,
                WALL_THICKNESS,
            ));
        }
    }
}

fn addWall(r: ff.Rect) void {
    if (wall_count >= walls.len) return;

    for (graves[0..ghost_count]) |g| {
        if (pointRectDist(g.pos, r) < 32.0) return;
    }

    walls[wall_count] = r;
    wall_count += 1;
}

fn pointRectDist(p: ff.Point, r: ff.Rect) f32 {
    const min = r.min();
    const max = r.max();

    const px: f32 = @floatFromInt(p.x);
    const py: f32 = @floatFromInt(p.y);
    const cx = @max(
        @as(f32, @floatFromInt(min.x)),
        @min(px, @as(f32, @floatFromInt(max.x))),
    );
    const cy = @max(
        @as(f32, @floatFromInt(min.y)),
        @min(py, @as(f32, @floatFromInt(max.y))),
    );

    const dx = px - cx;
    const dy = py - cy;

    return @sqrt(dx * dx + dy * dy);
}

/// True when a circle at `p` overlaps any wall. Ghosts ignore this.
pub fn hitsWall(p: ff.Point, radius: f32) bool {
    for (walls[0..wall_count]) |w| {
        if (pointRectDist(p, w) < radius) return true;
    }

    return false;
}

fn graveSpotOk(p: ff.Point, i: usize, center: ff.Point) bool {
    if (p.sub(center).len() < 80.0) return false;

    for (graves[0..i]) |g| {
        if (p.sub(g.pos).len() < 96.0) return false;
    }

    return true;
}

fn separateGhosts() void {
    for (ghosts[0..ghost_count], 0..) |*a, i| {
        if (a.state == .buried) continue;

        for (ghosts[i + 1 .. ghost_count]) |*b| {
            if (b.state == .buried) continue;

            const delta = b.vec - a.vec;
            const dist_sq = delta[0] * delta[0] + delta[1] * delta[1];
            const min = Ghost.SEPARATION;

            if (dist_sq == 0 or dist_sq >= min * min) continue;

            const dist = @sqrt(dist_sq);
            const push = (min - dist) * 0.5;
            const direction = delta * @as(ff.Vec, @splat(1.0 / dist));
            const correction = direction * @as(ff.Vec, @splat(push));

            a.vec -= correction;
            b.vec += correction;

            a.clamp();
            b.clamp();
        }
    }
}

fn buryGhosts() void {
    for (ghosts[0..ghost_count], 0..) |*ghost, i| {
        if (ghost.state != .follow or graves[i].filled) continue;

        if (ghost.pos.sub(graves[i].pos).len() < Ghost.BURY_RADIUS) {
            ghost.state = .buried;
            graves[i].filled = true;

            run_score += 100;
            total_buried += 1;

            _ = ff.addProgress(ff.getMe(), BADGE_SHEPHERD, 1);
            burialSound();
        }
    }
}

fn allBuried() bool {
    for (graves[0..ghost_count]) |g| {
        if (!g.filled) return false;
    }

    return true;
}

fn filledGraves() usize {
    var n: usize = 0;

    for (graves[0..ghost_count]) |g| {
        if (g.filled) n += 1;
    }

    return n;
}

fn renderWorld(show_player: bool) void {
    renderStars();
    renderSunAndHills();
    renderWalls();

    for (graves[0..ghost_count], ghosts[0..ghost_count]) |*grave, *ghost| {
        grave.render(ghost.color);
    }

    for (ghosts[0..ghost_count]) |*ghost| {
        ghost.render();
    }

    if (show_player) player.render();

    if (cheats.followLines) {
        for (ghosts[0..ghost_count]) |*ghost| {
            ghost.line();
        }
    }
}

fn renderWalls() void {
    for (walls[0..wall_count]) |w| {
        if (!cam.intersects(w)) continue;

        const p = cam.screen(w.point);
        const horizontal = w.size.width >= w.size.height;
        const long = if (horizontal) w.size.width else w.size.height;

        draw.rect(p.x, p.y, w.size.width, w.size.height, .{
            .fill_color = .dark_gray,
            .stroke_color = .gray,
            .stroke_width = 1,
        });

        // Brick seams, one every 14 px along the long axis.
        var offset: i32 = 14;
        while (offset < long) : (offset += 14) {
            if (horizontal) {
                draw.line(
                    p.x + offset,
                    p.y + 1,
                    p.x + offset,
                    p.y + w.size.height - 1,
                    .{ .color = .gray },
                );
            } else {
                draw.line(
                    p.x + 1,
                    p.y + offset,
                    p.x + w.size.width - 1,
                    p.y + offset,
                    .{ .color = .gray },
                );
            }
        }
    }
}

fn renderStars() void {
    const step: usize = @intCast(dawn_step);

    for (stars, 0..) |star, i| {
        if (@mod(i + step, 6) < step) continue;
        star.render();
    }
}

const HORIZON_Y: i32 = 150;

fn renderSunAndHills() void {
    if (dawn_step >= 2) {
        const p = dawnProgress();
        const cx: i32 = 178;
        const cy: i32 = @intFromFloat(162.0 - p * 84.0);

        // Rays turn slowly and reach further as the sun climbs. Alternating
        // lengths make the turn visible, since evenly spaced rays look static.
        const spin: f32 = @as(f32, @floatFromInt(frame)) * 0.004;

        for (0..12) |i| {
            const a = spin + @as(f32, @floatFromInt(i)) * (std.math.pi / 6.0);
            const reach: f32 = if (i % 2 == 0) 18.0 + p * 18.0 else 8.0 + p * 8.0;

            const dx = @cos(a);
            const dy = @sin(a);

            draw.line(
                cx + @as(i32, @intFromFloat(dx * 20.0)),
                cy + @as(i32, @intFromFloat(dy * 20.0)),
                cx + @as(i32, @intFromFloat(dx * (20.0 + reach))),
                cy + @as(i32, @intFromFloat(dy * (20.0 + reach))),
                .{ .color = .orange },
            );
        }

        draw.circ(cx - 18, cy - 18, 36, .{
            .fill_color = .orange,
            .stroke_color = .yellow,
            .stroke_width = 1,
        });
        draw.circ(cx - 8, cy - 8, 16, .{ .fill_color = .yellow });
    }

    // Rolling hills sit on the horizon; the ground strip covers their bases.
    draw.elli(-24, 138, 128, 36, .{ .fill_color = .purple });
    draw.elli(74, 132, 168, 44, .{ .fill_color = .purple });
    draw.elli(186, 138, 120, 34, .{ .fill_color = .purple });

    draw.rect(0, HORIZON_Y, ff.width, ff.height - HORIZON_Y, .{
        .fill_color = .dark_blue,
    });
    draw.line(0, HORIZON_Y, ff.width, HORIZON_Y, .{ .color = .dark_green });
}

fn renderHud() void {
    const filled = filledGraves();

    var b = std.fmt.bufPrint(&hud_buf, "SOULS {d}/{d}", .{
        filled,
        ghost_count,
    }) catch return;
    text(b, .new(4, 12), .white);

    const secs: u64 = (remainingMs() + 999) / 1000;
    b = std.fmt.bufPrint(&hud_buf, "{d}:{d:0>2}", .{
        secs / 60,
        secs % 60,
    }) catch return;
    text(b, .new(ff.width - @as(i32, @intCast(b.len)) * 6 - 4, 12), .white);

    b = std.fmt.bufPrint(&hud_buf, "NIGHT {d}", .{level}) catch return;
    text(b, .new(ff.width - @as(i32, @intCast(b.len)) * 6 - 4, 24), .light_gray);
}

fn remainingMs() u64 {
    const end = started_at + level_ms * 1000; // getTime() is microseconds
    const now = ff.getTime();

    if (now >= end) return 0;

    return (end - now) / 1000;
}

fn dawnProgress() f32 {
    if (level_ms == 0) return 1.0;

    const rem = remainingMs();
    const p = 1.0 - @as(f32, @floatFromInt(rem)) /
        @as(f32, @floatFromInt(level_ms));

    return @max(0.0, @min(p, 1.0));
}

fn dawnStep() u32 {
    const n: u32 = @intFromFloat(dawnProgress() * 6.0);

    return @min(n, 5);
}

fn applyPalette(step: u32) void {
    const t = @as(f32, @floatFromInt(step)) / 5.0;

    var p: ff.Palette = NIGHT;
    inline for (@typeInfo(ff.Palette).@"struct".field_names) |name| {
        @field(p, name) = lerpHex(@field(NIGHT, name), @field(DAWN, name), t);
    }
    p.set();

    dawn_step = step;
}

fn lerpHex(a: u32, b: u32, t: f32) u32 {
    var out: u32 = 0;

    inline for (0..3) |i| {
        const shift: u5 = @intCast((2 - i) * 8);
        const ca: f32 = @floatFromInt((a >> shift) & 0xFF);
        const cb: f32 = @floatFromInt((b >> shift) & 0xFF);
        const c: u32 = @intFromFloat(ca + (cb - ca) * t);

        out |= c << shift;
    }

    return out;
}

fn ghostCount(l: u32) usize {
    return @intCast(@min(3 + l, 8));
}

fn levelMs(l: u32) u64 {
    if (l <= 1) return 90_000;

    return 90_000 - @as(u64, @min(l - 1, 9)) * 5_000;
}

fn tickSound() void {
    const now = ff.getTime();
    const delta: u32 = if (now > last_time)
        @intCast(@min((now - last_time) / 1000, 100))
    else
        0;

    last_time = now;
    sound.tick(delta);
}

pub fn followSound() void {
    sound.sine(ff.audio.Freq.e4, ff.audio.Freq.e4, 90, 0.12, 0);
}

fn burialSound() void {
    sound.sine(ff.audio.Freq.c5, ff.audio.Freq.e5, 140, 0.15, 0);
}

fn clearSound() void {
    sound.sine(ff.audio.Freq.g4, ff.audio.Freq.c5, 260, 0.15, 0);
}

fn dawnSound() void {
    sound.sine(ff.audio.Freq.a3, ff.audio.Freq.e3, 600, 0.15, 0);
}

var stash_buf: [16]u8 = @splat(0);

fn loadBest() void {
    const s = ff.loadStash(ff.getMe(), &stash_buf) orelse return;

    if (s.len < 12) return;
    if (s[0] != 'B' or s[1] != 'O' or s[2] != 'O' or s[3] != '1') return;

    best_level = @max(1, readU16(s[4..6]));
    best_score = @intCast(readU16(s[6..8]));
    total_buried = readU32(s[8..12]);
    if (s.len >= 14) best_time_s = readU16(s[12..14]);
}

fn saveBest() void {
    stash_buf[0] = 'B';
    stash_buf[1] = 'O';
    stash_buf[2] = 'O';
    stash_buf[3] = '1';

    writeU16(stash_buf[4..6], @intCast(@min(best_level, 65535)));
    writeU16(stash_buf[6..8], @intCast(@max(0, @min(best_score, 65535))));
    writeU32(stash_buf[8..12], total_buried);
    writeU16(stash_buf[12..14], best_time_s);

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

pub fn text(t: ff.String, p: ff.Point, c: ff.Color) void {
    draw.Text(t, fff, p, c);
}

/// Opaque rounded panel so overlay text stays readable over the board.
fn panel(x: i32, y: i32, w: i32, h: i32) void {
    draw.rrect(x, y, w, h, 6, 6, .{
        .fill_color = .black,
        .stroke_color = .gray,
        .stroke_width = 1,
    });
}

fn textCentered(t: ff.String, cx: i32, y: i32, c: ff.Color) void {
    text(t, .new(cx - @as(i32, @intCast(t.len)) * 3, y), c);
}

var cheats: Cheats = .{};

pub export fn cheat(cmd: i32, val: i32) i32 {
    return cheats.apply(cmd, val);
}

pub export fn boot() void {
    applyPalette(0);

    fff = ff.loadFile("font", buf[0..]);

    for (&stars) |*s| {
        s.pos = Random.pos(SPACE);
        s.c = Random.starColor();
    }

    sound = Sound.init();
    loadBest();
}

pub export fn update() void {
    state.update();
}

pub export fn render() void {
    state.render();
}

pub export fn before_exit() void {
    saveBest();
}

comptime {
    if (lerpHex(0x000000, 0xFFFFFF, 0.5) != 0x7F7F7F) {
        @compileError("lerpHex midpoint is wrong");
    }
    if (levelMs(1) != 90_000) @compileError("level 1 should be 90 s");
    if (levelMs(99) != 45_000) @compileError("level time should bottom out at 45 s");
    if (ghostCount(1) != 4) @compileError("level 1 should have 4 ghosts");
    if (ghostCount(99) != 8) @compileError("ghost count should cap at 8");

    // Wall helpers are pure, so check them at compile time.
    {
        const r = ff.Rect.new(100, 100, 20, 20);

        if (@abs(pointRectDist(.new(110, 110), r)) > 0.001) {
            @compileError("a point inside a wall should be at distance 0");
        }
        if (@abs(pointRectDist(.new(90, 110), r) - 10.0) > 0.001) {
            @compileError("a point left of a wall should be 10 px away");
        }
    }
    if (@sizeOf(@TypeOf(stash_buf)) != 16) @compileError("stash layout changed");
}
