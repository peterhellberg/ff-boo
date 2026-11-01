const std = @import("std");

const ff = @import("ff");

const draw = ff.draw;

const Burial = @import("boo/Burial.zig");
const Camera = @import("boo/Camera.zig");
const Cheats = @import("boo/Cheats.zig");
const Ghost = @import("boo/Ghost.zig");
const Player = @import("boo/Player.zig");
const Random = @import("boo/Random.zig");
const Sound = @import("boo/Sound.zig");
const Star = @import("boo/Star.zig");

pub const DT: f32 = 1.0 / 60.0;

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
    .yellow,
    .light_green,
    .blue,
    .purple,
    .dark_gray,
    .light_blue,
};

const NIGHT: ff.Palette = .{
    // Warm-tinted neutrals: black is slightly warm so it doesn't
    // fight the cream white; grays follow the same temperature.
    .black = 0x1A1A1D,
    .dark_gray = 0x4A4E5A, // cool slate — reads as night shadow, not "missing color"
    .gray = 0x8C8E96,
    .light_gray = 0xCDCFC8, // warm-neutral, bridges gray → cream white
    .white = 0xF2EFE0, // your cream, kept

    // Blues tightened into one family: navy → royal → sky.
    .dark_blue = 0x24356E, // your navy, kept
    .blue = 0x4066D6, // brighter, less violet than before
    .light_blue = 0x7FC4EA, // pushed cyan-ward; previously crowded purple

    // Fire and foliage now actually split: orange is ember, and
    // dark_green is a real dark leaf green instead of a second orange.
    .orange = 0xF79E1D,
    .yellow = 0xFFD075, // your yellow, kept
    .dark_green = 0x2E7D4F, // was 0xC77C03 — that was an orange
    .green = 0x43B364, // your green, kept
    .light_green = 0xA9EE6C, // your light green, kept

    // Accents: red warmed to stop competing with purple's coolness.
    .cyan = 0x5BC9D6, // your cyan, kept
    .red = 0xD85555, // slightly warmer than before
    .purple = 0x9C5BB5, // brightened — it was the muddiest accent
};

const DAWN: ff.Palette = .{
    // Neutrals stay plum-toned but now actually span the range.
    .black = 0x42202E, // deep plum — was mid-tone, silhouettes vanished
    .dark_gray = 0x6B4A52,
    .gray = 0x9E7B72,
    .light_gray = 0xE3BDA4,
    .white = 0xFFF3D9, // warm cream, kept

    // Cool tones get a "morning mist" cast — desaturated but present,
    // and now distinct from each other (before, dark_blue/blue/
    // light_blue were three near-identical mauves).
    .dark_blue = 0x3E3A5C,
    .blue = 0x6E6FA8,
    .light_blue = 0xA9C7DD, // misty sky
    .cyan = 0x8FC5BC,

    // Warm tones deepened slightly so they don't all read as "beige".
    .orange = 0xE8913F,
    .red = 0xC4554E, // was 0xD07068 — needed to actually be red
    .dark_green = 0xB06A3A, // warm umber, still sunset-compatible
    .yellow = 0xF5D98C,
    .green = 0x7B9955, // deepened; was nearly gray-green mush
    .light_green = 0xB8CE7E,
    .purple = 0x9A6FA5, // pulled toward actual purple
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

        switch (s) {
            .Menu => menu.render(),
            .Init => {},
            .Game => game.render(),
            .Clear => clear.render(),
            .Over => over.render(),
        }

        if (cheats.stateName) {
            text(@tagName(s), .new(4, 21), .orange);
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

    fn textBlockCentered(
        lines: []const []const u8,
        colors: []const ff.Color,
        cx: i32,
        band_y: i32,
        band_h: i32,
        pitch: i32,
    ) void {
        const line_h: i32 = 8;
        const block_h = @as(i32, @intCast(lines.len - 1)) * pitch + line_h;
        var y = band_y + @divTrunc(band_h - block_h, 2);
        for (lines, colors) |line, col| {
            textCentered(line, cx, y, col);
            y += pitch;
        }
    }

    fn render(self: *Menu) void {
        renderStars();

        // Title panel: y 26..68, center 47
        cpanel(35, 26, 170, 42, .{
            .fill_color = .dark_gray,
        });
        textBlockCentered(
            &.{ "peter.boo", "A FRIENDLY GHOST SHEPHERD" },
            &.{
                if (self.blink) .yellow else .orange,
                .light_gray,
            },
            120,
            30,
            42,
            14,
        );

        // Instructions panel: y 78..122, center 100
        cpanel(10, 78, 220, 44, .{
            .fill_color = .dark_blue,
        });
        textBlockCentered(
            &.{
                "MOVE WITH THE TOUCHPAD",
                "GET CLOSE TO MAKE GHOSTS FOLLOW",
                "LEAD THEM TO THEIR MATCHING GRAVE",
            },
            &.{ ff.Color.blue, ff.Color.cyan, ff.Color.light_blue },
            120,
            84,
            44,
            14,
        );

        // Prompt, centered in the gap below the panel
        if (self.blink) {
            textBlockCentered(
                &.{"PRESS (E) TO START GAME!"},
                &.{ff.Color.white},
                120,
                122,
                38,
                12,
            );
        }
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
        Burial.update(DT);

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
        Burial.update(DT);

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

        panel(42, 26, 156, 118);

        textCentered("DAWN", 120, 41, .white);
        textCentered("THE NIGHT IS OVER", 120, 61, .light_gray);

        var b = std.fmt.bufPrint(&hud_buf, "SCORE {d}", .{run_score}) catch return;
        textCentered(b, 120, 81, .yellow);

        b = std.fmt.bufPrint(&hud_buf, "BEST {d} N{d}", .{
            best_score,
            best_level,
        }) catch return;
        textCentered(b, 120, 93, .light_gray);

        if (best_time_s > 0) {
            const t: u64 = best_time_s;
            b = std.fmt.bufPrint(&hud_buf, "SOULS {d} FASTEST {d}:{d:0>2}", .{
                total_buried,
                t / 60,
                t % 60,
            }) catch return;
        } else {
            b = std.fmt.bufPrint(&hud_buf, "SOULS {d}", .{total_buried}) catch return;
        }
        textCentered(b, 120, 105, .cyan);

        textCentered("PRESS (E) TO PLAY AGAIN!", 120, 118, .white);
        textCentered("(N) FOR MENU", 120, 130, .light_gray);
    }
};

const GRAVE_W: i32 = 14;
const GRAVE_H: i32 = 18;

const Grave = struct {
    pos: ff.Point = .{},
    filled: bool = false,
    ghost_color: ff.Color = .white, // color of the ghost laid to rest

    fn render(self: *const Grave, color: ff.Color) void {
        const r = self.pos
            .sub(.new(@divTrunc(GRAVE_W, 2), @divTrunc(GRAVE_H, 2)))
            .rect(.new(GRAVE_W, GRAVE_H));

        if (!cam.intersects(r)) return;

        const sp = cam.screen(self.pos);
        const x = sp.x - @divTrunc(GRAVE_W, 2);
        const y = sp.y - @divTrunc(GRAVE_H, 2);

        // Tombstone body: rounded top half only, flat bottom — the
        // classic headstone profile. Occupied stones take on the
        // buried ghost's color.
        draw.rrect(x, y, GRAVE_W, GRAVE_H, @divTrunc(GRAVE_W, 2), @divTrunc(GRAVE_W, 2), .{
            .fill_color = if (self.filled) self.ghost_color else .gray,
            .stroke_color = .dark_gray,
            .stroke_width = 1,
        });
        // Square off the bottom corners the rounded rect rounded.
        draw.rect(x, y + GRAVE_H - @divTrunc(GRAVE_W, 2), GRAVE_W, @divTrunc(GRAVE_W, 2), .{
            .fill_color = if (self.filled) self.ghost_color else .gray,
        });

        // Base plinth: a wider foot anchors the stone into the ground
        // and gives every grave the same "footprint" in both states.
        draw.rect(x - 1, y + GRAVE_H - 2, GRAVE_W + 2, 3, .{
            .fill_color = .dark_gray,
        });

        if (self.filled) {
            draw.circ(sp.x - 5, y - 3, 10, .{ .fill_color = color });
            draw.circ(sp.x - 4, y - 2, 4, .{ .fill_color = .white });
        } else {
            // Empty plot: dug hole in front, with the ghost's color orb
            // centered on the headstone crest — the marker for which
            // ghost belongs here.
            draw.elli(sp.x - 7, sp.y + 1, 14, 5, .{ .fill_color = .black });
            draw.circ(sp.x - 5, y - 3, 10, .{ .fill_color = color });
            draw.circ(sp.x - 4, y - 2, 4, .{ .fill_color = .white });
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

            const ghostColor = ghost.color;
            graves[i].ghost_color = ghostColor;
            graves[i].filled = true;

            Burial.trigger(graves[i].pos, ghostColor);

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

    Burial.render(cam, draw);

    if (cheats.followLines) {
        for (ghosts[0..ghost_count]) |*ghost| {
            ghost.line();
        }
    }

    for (ghosts[0..ghost_count]) |*ghost| {
        ghost.render();
    }

    if (show_player) player.render();
}

/// Small deterministic hash — same inputs always give same output.
fn hash2(x: u32, y: u32) u32 {
    var h = x *% 374761393 +% y *% 668265263;
    h = (h ^ (h >> 13)) *% 1274126177;
    return h ^ (h >> 16);
}

fn renderWalls() void {
    for (walls[0..wall_count]) |w| {
        if (!cam.intersects(w)) continue;

        const p = cam.screen(w.point);
        const horizontal = w.size.width >= w.size.height;

        // Base fill + dark outer outline.
        draw.rect(p.x, p.y, w.size.width, w.size.height, .{
            .fill_color = .dark_gray,
            .stroke_color = .black,
            .stroke_width = 1,
        });

        // Bevel.
        draw.line(p.x, p.y, p.x + w.size.width - 1, p.y, .{ .color = .gray });
        draw.line(p.x, p.y, p.x, p.y + w.size.height - 1, .{ .color = .gray });
        draw.line(p.x, p.y + w.size.height - 1, p.x + w.size.width - 1, p.y + w.size.height - 1, .{ .color = .black });
        draw.line(p.x + w.size.width - 1, p.y, p.x + w.size.width - 1, p.y + w.size.height - 1, .{ .color = .black });

        const bx = p.x + 1;
        const by = p.y + 1;
        const bw = w.size.width - 2;
        const bh = w.size.height - 2;
        if (bw <= 0 or bh <= 0) continue;

        const brick_len: i32 = 16;
        const row_h: i32 = 8;

        // World-space seed so the pattern is stable across frames AND
        // continuous across adjacent wall segments.
        const seed: u32 = @bitCast(w.point.x *% 31 +% w.point.y *% 733);

        if (horizontal) {
            var row: i32 = 0;
            while (row < bh) : (row += row_h) {
                if (row > 0) {
                    draw.line(bx, by + row, bx + bw - 1, by + row, .{ .color = .gray });
                }
                const stagger = if (@mod(@divTrunc(row, row_h), 2) == 1) brick_len / 2 else 0;
                var joint = stagger;
                while (joint < bw) : (joint += brick_len) {
                    if (joint == 0) continue;
                    draw.line(bx + joint, by + row, bx + joint, by + @min(row + row_h, bh) - 1, .{ .color = .gray });
                }
            }

            // Speckles: iterate bricks (not pixels) so each brick gets
            // 2-3 deterministic dots.
            var brow: i32 = 0;
            while (brow < bh) : (brow += row_h) {
                var bcol: i32 = 0;
                while (bcol < bw) : (bcol += brick_len) {
                    const h = hash2(
                        seed +% @as(u32, @bitCast(bcol)),
                        @as(u32, @bitCast(brow)),
                    );
                    const n_specks = 2 + (h % 2); // 2 or 3 specks per brick
                    var s: u32 = 0;
                    while (s < n_specks) : (s += 1) {
                        const hx = hash2(h, s *% 2 +% 1);
                        const hy = hash2(h, s *% 2 +% 2);
                        const sx = bcol + @as(i32, @intCast(hx % @as(u32, @intCast(brick_len - 1))));
                        const sy = brow + @as(i32, @intCast(hy % @as(u32, @intCast(row_h - 1))));

                        if (sx < bw and sy < bh) {
                            // Alternate light/dark specks for grit.
                            const color: ff.Color = if (hx & 1 == 0) .gray else .black;
                            draw.Point(.new(bx + sx, by + sy), color);
                        }
                    }
                }
            }
        } else {
            var row: i32 = 0;
            while (row < bw) : (row += row_h) {
                if (row > 0) {
                    draw.line(bx + row, by, bx + row, by + bh - 1, .{ .color = .gray });
                }
                const stagger = if (@mod(@divTrunc(row, row_h), 2) == 1) brick_len / 2 else 0;
                var joint = stagger;
                while (joint < bh) : (joint += brick_len) {
                    if (joint == 0) continue;
                    draw.line(bx + row, by + joint, bx + @min(row + row_h, bw) - 1, by + joint, .{ .color = .gray });
                }
            }

            // Speckles, axes swapped: rows run along the width, bricks along
            // the height.
            var brow: i32 = 0;
            while (brow < bw) : (brow += row_h) {
                var bcol: i32 = 0;
                while (bcol < bh) : (bcol += brick_len) {
                    const h = hash2(
                        seed +% @as(u32, @bitCast(bcol)),
                        @as(u32, @bitCast(brow)),
                    );
                    const n_specks = 2 + (h % 2); // 2 or 3 specks per brick
                    var s: u32 = 0;
                    while (s < n_specks) : (s += 1) {
                        const hx = hash2(h, s *% 2 +% 1);
                        const hy = hash2(h, s *% 2 +% 2);
                        const sx = brow + @as(i32, @intCast(hx % @as(u32, @intCast(row_h - 1))));
                        const sy = bcol + @as(i32, @intCast(hy % @as(u32, @intCast(brick_len - 1))));

                        if (sx < bw and sy < bh) {
                            // Alternate light/dark specks for grit.
                            const color: ff.Color = if (hx & 1 == 0) .gray else .black;
                            draw.Point(.new(bx + sx, by + sy), color);
                        }
                    }
                }
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
    // Sun starts fully below the horizon (center = horizon + radius +
    // glow margin) and climbs to its mid-sky perch as dawn progresses.
    // The hills and ground are drawn on top, so the sun emerges from
    // behind them — no gate needed, it's simply invisible at first.
    const p = dawnProgress();
    const cx: i32 = 178;
    const start_y: f32 = @as(f32, HORIZON_Y) + 44.0; // fully hidden
    const end_y: f32 = 78.0;
    const cy: i32 = @intFromFloat(start_y - p * (start_y - end_y));

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

    // Rolling hills sit on the horizon; the ground strip covers their bases.
    draw.elli(-24, 138, 128, 36, .{ .fill_color = .dark_gray });
    draw.elli(74, 132, 168, 44, .{ .fill_color = .dark_gray });
    draw.elli(186, 138, 120, 34, .{ .fill_color = .dark_gray });

    draw.rect(0, HORIZON_Y, ff.width, ff.height - HORIZON_Y, .{
        .fill_color = .gray,
    });
    draw.line(0, HORIZON_Y, ff.width, HORIZON_Y, .{ .color = .black });
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
    // Smoothstep on t: at 6 steps the raw linear ramp makes steps 0-1
    // and 4-5 look nearly identical (the eye discriminates best at
    // mid-lightness). Ease so both ends get visible motion.
    const t_raw = @as(f32, @floatFromInt(step)) / 5.0;
    const t = t_raw * t_raw * (3.0 - 2.0 * t_raw);

    var p: ff.Palette = NIGHT;
    inline for (@typeInfo(ff.Palette).@"struct".field_names) |name| {
        @field(p, name) = lerpHex(@field(NIGHT, name), @field(DAWN, name), t);
    }
    p.set();

    dawn_step = step;
}

fn lerpHex(a: u32, b: u32, t: f32) u32 {
    var result: u32 = 0;
    inline for (0..3) |i| {
        const shift = 8 * (2 - i); // r, g, b order in 0xRRGGBB
        const ca: f32 = @floatFromInt((a >> @intCast(shift)) & 0xFF);
        const cb: f32 = @floatFromInt((b >> @intCast(shift)) & 0xFF);
        const mixed = ca + (cb - ca) * t;
        const rounded: u32 = @intFromFloat(mixed + 0.5); // round, don't truncate
        result |= rounded << @intCast(shift);
    }
    return result;
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

var follow_gate_ms: u32 = 0; // module scope, rate-limits the sound

pub fn followSound() void {
    // Rate-limit: at most once every 90 ms, so fast movement produces
    // a soft patter instead of a shrill machine-gun of notes.
    if (sound.elapsed_ms < follow_gate_ms) return;
    follow_gate_ms = sound.elapsed_ms + 90;

    // Short rising flick: quick slide up, slightly detuned by
    // alternating direction each trigger so it doesn't fatigue.
    sound.sine(.e4, .g4, 70, 0.06, 0);
}

fn burialSound() void {
    const now = sound.elapsed_ms;

    // The drop: a fast slide down about an octave, landing at the bottom.
    sound.sineAt(now, .e4, .a2, 100, 0.15);

    // The thump: one short, quiet, low note right as the drop lands.
    sound.sineAt(now + 100, .a2, .a2, 70, 0.08);
}

/// Clearing an area / objective: bright ascending arpeggio flourish —
/// "success" shape (rising, major-ish triad), ends on a held top note.
fn clearSound() void {
    sound.arp(&.{ .c4, .e4, .g4, .c5 }, 90, 0.12, 15, true);
    // Resolving anchor note: slide up to it slightly for shine.
    sound.melody(&.{
        .{ .from = .b4, .to = .c5, .duration_ms = 280, .amplitude = 0.15 },
    }, 20);
}

/// Dawn / new day: slow, wide downward slide resolving to a warm low
/// dyad. Long durations and low amplitude so it feels like ambience
/// rather than an event ping.
fn dawnSound() void {
    sound.melody(&.{
        .{ .from = .a4, .to = .a3, .duration_ms = 400, .amplitude = 0.12 }, // light falls
        .{ .from = .a3, .to = .e3, .duration_ms = 500, .amplitude = 0.12, .gap_ms = 60 }, // settles
    }, 0);
    // Warm low dyad under the tail (needs 2 free voices; fires last
    // so the melody notes have mostly expired).
    sound.chord(&.{ .e3, .b3 }, 600, 0.08, 40);
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
    cpanel(x, y, w, h, .{
        .fill_color = .black,
        .stroke_color = .gray,
        .stroke_width = 1,
    });
}

fn cpanel(x: i32, y: i32, w: i32, h: i32, s: ff.Style) void {
    draw.rrect(x, y, w, h, 6, 6, s);
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
    if (lerpHex(0x000000, 0xFFFFFF, 0.5) != 0x808080) {
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
