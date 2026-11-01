//! Burial effects: particle puff, grave flash, floating score popup.
//! Owns no game state — main.zig decides when a burial happens and calls
//! `trigger()`; this module just makes it look good.
//!
//! Wire-up from main.zig:
//!     const Burial = @import("boo/Burial.zig");
//!     Burial.update(dt);          // in your update step
//!     Burial.render(cam, draw);   // after ghosts/walls render, so effects draw on top
//!     Burial.trigger(pos, color); // at the moment of burial

const std = @import("std");
const ff = @import("ff");

const Burial = @This();

const Boo = @import("../main.zig");

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const BURIAL_PARTICLES = 14;
const FLASH_DURATION: f32 = 0.4;
const POPUP_LIFETIME: f32 = 1.0;
const POPUP_RISE_SPEED: f32 = 30;

// ---------------------------------------------------------------------------
// Particles
// ---------------------------------------------------------------------------

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32, // velocity, pixels per second
    vy: f32,
    life: f32, // seconds remaining
    max_life: f32, // for fade normalization
    color: ff.Color,
};

const MAX_PARTICLES = 256;

var particles: [MAX_PARTICLES]Particle = undefined;
var particle_count: usize = 0;

// ---------------------------------------------------------------------------
// Score popups
// ---------------------------------------------------------------------------

const Popup = struct {
    x: f32,
    y: f32,
    life: f32,
    text: [8]u8, // fixed buffer, e.g. "+100"
    text_len: usize,
};

const MAX_POPUPS = 16;

var popups: [MAX_POPUPS]Popup = undefined;
var popup_count: usize = 0;

// ---------------------------------------------------------------------------
// Grave flashes
// ---------------------------------------------------------------------------

const Flash = struct {
    x: f32,
    y: f32,
    timer: f32,
    color: ff.Color,
};

const MAX_FLASHES = 16;

var flashes: [MAX_FLASHES]Flash = undefined;
var flash_count: usize = 0;

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Call once per frame from the update step.
pub fn update(dt: f32) void {
    // Particles: move, age, swap-remove.
    var i: usize = 0;

    while (i < particle_count) {
        const p = &particles[i];

        p.life -= dt;

        if (p.life <= 0) {
            particle_count -= 1;
            particles[i] = particles[particle_count];
            continue; // re-process the swapped-in particle
        }

        p.x += p.vx * dt;
        p.y += p.vy * dt;

        // Wisps drift upward and slow down over time.
        p.vy -= 20 * dt;

        const damp = 1 - 1.5 * dt;

        p.vx *= damp;
        p.vy *= damp;

        i += 1;
    }

    // Popups: rise, age, swap-remove.
    i = 0;

    while (i < popup_count) {
        popups[i].life -= dt;
        popups[i].y -= POPUP_RISE_SPEED * dt;

        if (popups[i].life <= 0) {
            popup_count -= 1;
            popups[i] = popups[popup_count];
            continue;
        }

        i += 1;
    }

    // Flashes: count down, swap-remove.
    i = 0;
    while (i < flash_count) {
        flashes[i].timer -= dt;

        if (flashes[i].timer <= 0) {
            flash_count -= 1;
            flashes[i] = flashes[flash_count];
            continue;
        }

        i += 1;
    }
}

/// Call once per frame from the render step, after world geometry.
pub fn render(cam: anytype, draw: anytype) void {
    // Particles: shrink from 3x3 to 1x1 as they die.
    for (particles[0..particle_count]) |p| {
        const t = p.life / p.max_life; // 1.0 -> 0.0
        const sp = cam.screen(ff.Point.new(
            @intFromFloat(@round(p.x)),
            @intFromFloat(@round(p.y)),
        ));

        const size: i32 = if (t > 0.66) 3 else if (t > 0.33) 2 else 1;

        const half: i32 = switch (size) {
            3 => 1,
            2 => 1,
            else => 0,
        };

        draw.rect(sp.x - half, sp.y - half, size, size, .{
            .fill_color = p.color,
        });
    }

    // Flashes: ghost-colored expanding ring, drawn under popups.
    for (flashes[0..flash_count]) |f| {
        const t = f.timer / FLASH_DURATION; // 1.0 -> 0.0
        const sp = cam.screen(ff.Point.new(
            @intFromFloat(@round(f.x)),
            @intFromFloat(@round(f.y)),
        ));

        const glow: i32 = @as(i32, @intFromFloat(6 * t)) + 2;

        draw.line(sp.x - glow, sp.y - glow, sp.x + glow, sp.y - glow, .{ .color = f.color });
        draw.line(sp.x - glow, sp.y + glow, sp.x + glow, sp.y + glow, .{ .color = f.color });
        draw.line(sp.x - glow, sp.y - glow, sp.x - glow, sp.y + glow, .{ .color = f.color });
        draw.line(sp.x + glow, sp.y - glow, sp.x + glow, sp.y + glow, .{ .color = f.color });
    }

    // Popups on top.
    for (popups[0..popup_count]) |p| {
        const sp = cam.screen(ff.Point.new(
            @intFromFloat(@round(p.x)),
            @intFromFloat(@round(p.y)),
        ));

        Boo.text(p.text[0..p.text_len], sp, .white);
    }
}

/// Spawn the full burial effect at a world position, in the ghost's color.
pub fn trigger(pos: ff.Point, ghost_color: ff.Color) void {
    const x = @as(f32, @floatFromInt(pos.x));
    const y = @as(f32, @floatFromInt(pos.y));

    spawnParticles(x, y, ghost_color);
    spawnFlash(x, y, ghost_color);
    spawnPopup(x, y, 100);
}

// ---------------------------------------------------------------------------
// Internals
// ---------------------------------------------------------------------------

fn spawnParticle(x: f32, y: f32, vx: f32, vy: f32, life: f32, color: ff.Color) void {
    if (particle_count >= MAX_PARTICLES) return;

    particles[particle_count] = .{
        .x = x,
        .y = y,
        .vx = vx,
        .vy = vy,
        .life = life,
        .max_life = life,
        .color = color,
    };

    particle_count += 1;
}

fn spawnParticles(x: f32, y: f32, color: ff.Color) void {
    const tau = std.math.tau;

    var k: usize = 0;

    while (k < BURIAL_PARTICLES) : (k += 1) {
        const delay: f32 = @as(f32, @floatFromInt(k % 4)); // 0..3, staggers lifetimes
        const speed: f32 = 15 + @as(f32, @floatFromInt((k * 37) % 25)); // 15..39
        const angle: f32 = @as(f32, @floatFromInt(k)) * (tau / @as(f32, BURIAL_PARTICLES));
        const vx = @cos(angle) * speed;
        const vy = @sin(angle) * speed * 0.6 - 25; // squashed vertically + upward bias
        const jitter_x = @as(f32, @floatFromInt(@as(i32, @intCast(k * 13 % 7)) - 3));
        const jitter_y = @as(f32, @floatFromInt(@as(i32, @intCast(k * 5 % 5)) - 2));

        spawnParticle(x + jitter_x, y + jitter_y, vx, vy, 0.5 + delay * 0.1, color);
    }
}

fn spawnFlash(x: f32, y: f32, color: ff.Color) void {
    if (flash_count >= MAX_FLASHES) return;

    flashes[flash_count] = .{ .x = x, .y = y, .timer = FLASH_DURATION, .color = color };
    flash_count += 1;
}

fn spawnPopup(x: f32, y: f32, points: i32) void {
    if (popup_count >= MAX_POPUPS) return;

    var p = Popup{
        .x = x,
        .y = y,
        .life = POPUP_LIFETIME,
        .text = undefined,
        .text_len = 0,
    };

    const buf = std.fmt.bufPrint(&p.text, "+{d}", .{points}) catch return;

    p.text_len = buf.len;
    popups[popup_count] = p;
    popup_count += 1;
}
