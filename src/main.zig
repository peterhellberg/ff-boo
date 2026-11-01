const std = @import("std");

const ff = @import("ff");

const draw = ff.draw;

const Best = @import("boo/Best.zig");
const Burial = @import("boo/Burial.zig");
const Camera = @import("boo/Camera.zig");
const Cheats = @import("boo/Cheats.zig");
const Ghost = @import("boo/Ghost.zig");
const Palette = @import("boo/Palette.zig");
const Player = @import("boo/Player.zig");
const Random = @import("boo/Random.zig");
const Sound = @import("boo/Sound.zig");
const Star = @import("boo/Star.zig");

const CLEAR_FRAMES = 120;
const BOARD_SCORE: ff.Board = 1;

const BADGE_GRAVEDIGGER: ff.Badge = 1;
const BADGE_GHOSTBUSTER: ff.Badge = 2;
const BADGE_SHEPHERD: ff.Badge = 3;

pub const DT: f32 = 1.0 / 60.0;
pub const SIZE_SPACE = 3;
pub const SIZE_PLAYER = 20;
pub const NUM_STARS = 64;
pub const NUM_GHOSTS_MAX = 8;

pub const SPACE: ff.Rect = .new(
    0,
    0,
    ff.width * SIZE_SPACE,
    ff.height * SIZE_SPACE,
);

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

var run_score: i32 = 0;
var clear_bonus: i32 = 0;
var clear_frames: u16 = 0;

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

        tickSound();
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
            &.{ .blue, .cyan, .light_blue },
            120,
            84,
            44,
            14,
        );

        // Prompt, centered in the gap below the panel
        if (self.blink) {
            textBlockCentered(
                &.{"PRESS (E) TO START GAME!"},
                &.{.white},
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

        Palette.apply(0);

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
        if (step != Palette.dawn_step) Palette.apply(step);

        if (allBuried()) {
            enterClear();
            return;
        }

        if (remainingMs() == 0) {
            enterOver();
            return;
        }

        if (cheats.stateFlip and !btn.n and old.n) {
            Palette.apply(0);

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
        renderHud();

        panel(60, 56, 120, 46);
        textCentered("NIGHT CLEARED", 120, 70, .white);

        const b = hudPrint("+{d}", .{clear_bonus}) catch return;
        textCentered(b, 120, 90, .yellow);
    }
};

const Over = struct {
    fn update(_: *Over) void {
        if (!btn.e and old.e) startRun();

        if (!btn.n and old.n) {
            Palette.apply(0);

            state = .Menu;
        }
    }

    fn render(_: *Over) void {
        renderWorld(false);
        renderSunAndHills();

        panel(42, 26, 156, 118);

        textCentered("DAWN", 120, 41, .white);
        textCentered("THE NIGHT IS OVER", 120, 61, .light_gray);

        var b = hudPrint("SCORE {d}", .{run_score}) catch return;
        textCentered(b, 120, 81, .yellow);

        b = hudPrint("BEST {d} N{d}", .{
            Best.score,
            Best.level,
        }) catch return;
        textCentered(b, 120, 93, .light_gray);

        if (Best.time_s > 0) {
            const t: u64 = Best.time_s;
            b = hudPrint("SOULS {d} FASTEST {d}:{d:0>2}", .{
                Best.total_buried,
                t / 60,
                t % 60,
            }) catch return;
        } else {
            b = hudPrint("SOULS {d}", .{
                Best.total_buried,
            }) catch return;
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
    if (Best.time_s == 0 or elapsed_s < Best.time_s) Best.time_s = elapsed_s;

    Best.level = @max(Best.level, level);
    Best.score = @max(Best.score, run_score);
    Best.save();

    clearSound();
    clear_frames = CLEAR_FRAMES;
    state = .Clear;
}

fn enterOver() void {
    Palette.apply(5);

    Best.level = @max(Best.level, level);
    Best.score = @max(Best.score, run_score);
    Best.save();

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
    const inner: ff.Rect = .new(
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

            addWall(.new(
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

            addWall(.new(
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
        if (pointRectDistSq(g.pos, r) < 1024.0) return;
    }

    walls[wall_count] = r;
    wall_count += 1;
}

fn pointRectDistSq(p: ff.Point, r: ff.Rect) f32 {
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

    return dx * dx + dy * dy;
}

/// True when a circle at `p` overlaps any wall. Ghosts ignore this.
pub fn hitsWall(p: ff.Point, radius: f32) bool {
    const radius_sq = radius * radius;

    for (walls[0..wall_count]) |w| {
        if (pointRectDistSq(p, w) < radius_sq) {
            return true;
        }
    }

    return false;
}

fn graveSpotOk(p: ff.Point, i: usize, center: ff.Point) bool {
    const center_delta = p.sub(center);
    const center_dist_sq =
        @as(f32, @floatFromInt(center_delta.x)) *
        @as(f32, @floatFromInt(center_delta.x)) +
        @as(f32, @floatFromInt(center_delta.y)) *
            @as(f32, @floatFromInt(center_delta.y));

    if (center_dist_sq < 6400.0) return false;

    for (graves[0..i]) |g| {
        const delta = p.sub(g.pos);
        const dist_sq =
            @as(f32, @floatFromInt(delta.x)) *
            @as(f32, @floatFromInt(delta.x)) +
            @as(f32, @floatFromInt(delta.y)) *
                @as(f32, @floatFromInt(delta.y));

        if (dist_sq < 9216.0) return false;
    }

    return true;
}

fn separateGhosts() void {
    const min = Ghost.SEPARATION;
    const min_sq = min * min;

    for (ghosts[0..ghost_count], 0..) |*a, i| {
        if (a.state == .buried) continue;

        for (ghosts[i + 1 .. ghost_count]) |*b| {
            if (b.state == .buried) continue;

            const delta = b.vec - a.vec;
            const dist_sq = delta[0] * delta[0] + delta[1] * delta[1];

            if (dist_sq == 0 or dist_sq >= min_sq) continue;

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

        const delta = ghost.pos.sub(graves[i].pos);
        const dist_sq =
            @as(f32, @floatFromInt(delta.x)) * @as(f32, @floatFromInt(delta.x)) +
            @as(f32, @floatFromInt(delta.y)) * @as(f32, @floatFromInt(delta.y));

        const radius = Ghost.BURY_RADIUS;

        if (dist_sq < radius * radius) {
            ghost.state = .buried;

            const ghostColor = ghost.color;

            graves[i].ghost_color = ghostColor;
            graves[i].filled = true;

            Burial.trigger(graves[i].pos, ghostColor);

            run_score += 100;
            Best.total_buried += 1;

            const me = ff.getMe();

            _ = ff.addProgress(me, BADGE_GRAVEDIGGER, 1);
            _ = ff.addProgress(me, BADGE_GHOSTBUSTER, 1);
            _ = ff.addProgress(me, BADGE_SHEPHERD, 1);

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

/// Draws brick mortar lines + speckles into a local rect of
/// `long` x `cross` pixels, where `long` is the brick-row direction.
fn drawBrickPattern(px: i32, py: i32, w: i32, h: i32, seed: u32, comptime horizontal: bool) void {
    const brick_len: i32 = 16;
    const row_h: i32 = 8;

    const long: i32 = if (horizontal) w else h;
    const cross: i32 = if (horizontal) h else w;

    const M = if (horizontal) struct {
        fn x(along: i32, _: i32) i32 {
            return along;
        }
        fn y(_: i32, across: i32) i32 {
            return across;
        }
    } else struct {
        fn x(_: i32, across: i32) i32 {
            return across;
        }
        fn y(along: i32, _: i32) i32 {
            return along;
        }
    };

    const speck_x_mod: u32 = @intCast(brick_len - 1);
    const speck_y_mod: u32 = @intCast(row_h - 1);

    // Mortar rows + vertical joints.
    var row: i32 = 0;
    var row_index: i32 = 0;

    while (row < cross) : ({
        row += row_h;
        row_index += 1;
    }) {
        const row_end = @min(row + row_h, cross) - 1;

        if (row > 0) {
            draw.line(
                M.x(0, row) + px,
                M.y(0, row) + py,
                M.x(long - 1, row) + px,
                M.y(long - 1, row) + py,
                .{ .color = .gray },
            );
        }

        const stagger = if (row_index & 1 == 1) brick_len / 2 else 0;

        var joint = stagger;
        while (joint < long) : (joint += brick_len) {
            if (joint == 0) continue;

            draw.line(
                M.x(joint, row) + px,
                M.y(joint, row) + py,
                M.x(joint, row_end) + px,
                M.y(joint, row_end) + py,
                .{ .color = .gray },
            );
        }
    }

    // Speckles: 2-3 deterministic dots per brick.
    var brow: i32 = 0;
    while (brow < cross) : (brow += row_h) {
        var bcol: i32 = 0;
        while (bcol < long) : (bcol += brick_len) {
            const hsh = hash2(
                seed +% @as(u32, @bitCast(bcol)),
                @as(u32, @bitCast(brow)),
            );

            const n_specks = 2 + (hsh % 2);

            var s: u32 = 0;
            while (s < n_specks) : (s += 1) {
                const s_offset = s *% 2;

                const hx = hash2(hsh, s_offset +% 1);
                const hy = hash2(hsh, s_offset +% 2);

                const along = bcol + @as(i32, @intCast(hx % speck_x_mod));
                const across = brow + @as(i32, @intCast(hy % speck_y_mod));

                if (along >= long or across >= cross) continue;

                const color: ff.Color = if (hx & 1 == 0) .gray else .black;

                draw.Point(
                    .new(M.x(along, across) + px, M.y(along, across) + py),
                    color,
                );
            }
        }
    }
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

        // World-space seed so the pattern is stable across frames AND
        // continuous across adjacent wall segments.
        const seed: u32 = @bitCast(w.point.x *% 31 +% w.point.y *% 733);

        if (horizontal) {
            drawBrickPattern(bx, by, bw, bh, seed, true);
        } else {
            drawBrickPattern(bx, by, bw, bh, seed, false);
        }
    }
}

fn renderStars() void {
    const step: usize = @intCast(Palette.dawn_step);

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

fn hudPrint(comptime fmt: []const u8, args: anytype) std.fmt.BufPrintError![]u8 {
    return std.fmt.bufPrint(&hud_buf, fmt, args);
}

fn renderHud() void {
    const filled = filledGraves();

    var b = hudPrint("SOULS {d}/{d}", .{
        filled,
        ghost_count,
    }) catch return;

    text(b, .new(4, 12), .white);

    const secs: u64 = (remainingMs() + 999) / 1000;

    b = hudPrint("{d}:{d:0>2}", .{
        secs / 60,
        secs % 60,
    }) catch return;

    text(b, .new(ff.width - @as(i32, @intCast(b.len)) * 6 - 4, 12), .white);

    b = hudPrint("NIGHT {d}", .{
        level,
    }) catch return;

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
        @intCast((now - last_time) / 1000)
    else
        0;

    last_time = now;
    sound.tick(delta);
}

var follow_gate_ms: u32 = 0;

pub fn followSound() void {
    if (sound.elapsed_ms < follow_gate_ms) return;
    follow_gate_ms = sound.elapsed_ms + 90;

    sound.sine(.e4, .g4, 70, 0.06, 0);
}

fn burialSound() void {
    const now = sound.elapsed_ms;

    sound.sineAt(now, .e4, .a2, 100, 0.15);
    sound.sineAt(now + 100, .a2, .a2, 70, 0.08);
}

fn clearSound() void {
    sound.arp(&.{ .c4, .e4, .g4, .c5 }, 90, 0.12, 15, true);
    sound.melody(&.{
        .{
            .from = .b4,
            .to = .c5,
            .duration_ms = 280,
            .amplitude = 0.15,
        },
    }, 20);
}

fn dawnSound() void {
    sound.melody(&.{
        .{
            .from = .a4,
            .to = .a3,
            .duration_ms = 400,
            .amplitude = 0.12,
        },
        .{
            .from = .a3,
            .to = .e3,
            .duration_ms = 500,
            .amplitude = 0.12,
            .gap_ms = 60,
        },
    }, 0);

    sound.chord(&.{ .e3, .b3 }, 600, 0.08, 40);
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
    Palette.apply(0);

    fff = ff.loadFile("font", buf[0..]);

    for (&stars) |*s| {
        s.pos = Random.pos(SPACE);
        s.c = Random.starColor();
    }

    sound = Sound.init();
    Best.load();
}

pub export fn update() void {
    state.update();
}

pub export fn render() void {
    state.render();
}

pub export fn before_exit() void {
    Best.save();
}

comptime {
    if (levelMs(1) != 90_000) @compileError("level 1 should be 90 s");
    if (levelMs(99) != 45_000) @compileError("level time should bottom out at 45 s");
    if (ghostCount(1) != 4) @compileError("level 1 should have 4 ghosts");
    if (ghostCount(99) != 8) @compileError("ghost count should cap at 8");

    // Wall helpers are pure, so check them at compile time.
    {
        const r: ff.Rect = .new(100, 100, 20, 20);

        if (pointRectDistSq(.new(110, 110), r) != 0.0) {
            @compileError("a point inside a wall should have squared distance 0");
        }

        if (@abs(pointRectDistSq(.new(90, 110), r) - 100.0) > 0.001) {
            @compileError("a point left of a wall should be 10 px away (squared distance 100)");
        }
    }
}
