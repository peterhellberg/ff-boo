# DESIGN - peter.boo

This document turns the gameplay in `README.md` into concrete rules and code
structure. It is the plan for completing `src/main.zig` using the modules that
already exist under `src/boo/`.

## 1. Pitch and core loop

You are a friendly ghost shepherd in a graveyard at night.

1. The graveyard is larger than the screen. Walk around with the touchpad.
2. Ghosts wander slowly. Walk close to one and it starts following you.
3. Lead each ghost to its own grave. A following ghost that reaches its grave
   is laid to rest.
4. Put every ghost to rest before dawn. Dawn is a countdown: the sky and the
   whole palette brighten as it approaches.
5. If dawn arrives first, the run ends. If you finish, the next night starts
   with more ghosts and less time.

There is no combat and no death. The only pressure is the timer and the risk of
losing a ghost by walking too far away from it.

## 2. What exists today and what happens to it

| Module | Role after this change |
| --- | --- |
| `boo/Camera.zig` | Unchanged. Follows the shepherd, clamps to the world, converts world points to screen points, culls. |
| `boo/Circle.zig` | Unchanged. Used for the shepherd, ghosts and the sun. |
| `boo/Random.zig` | Unchanged. Used for stars, grave layout and ghost spawns. |
| `boo/Star.zig` | Unchanged, except that stars fade out as dawn progresses. |
| `boo/Cheats.zig` | Renamed `preyLines` to `followLines`. Other cheats keep working. |
| `boo/Sound.zig` | Used as-is for the event blips. |
| `boo/Player.zig` | Keeps movement, bouncing, eyes and rendering. The size-growth fields (`f`, `SIZE_PLAYER_MAX`) are removed because nothing eats or grows any more. |
| `boo/Enemy.zig` | Repurposed and renamed to `boo/Ghost.zig`. The size-based predator/prey logic is replaced by wander/follow/buried behaviour. |
| `src/main.zig` | Owns the state machine, level generation, graves, timer/dawn, scoring, persistence and HUD. |

The uncommitted prototype in the working tree is the starting point, not a
second game mode. Nothing from the old predator/prey rules is kept.

## 3. World, camera and coordinates

- The world is `SPACE`, the same as today:
  `ff.width * SIZE_SPACE` by `ff.height * SIZE_SPACE` = **720 x 480**.
- The screen is 240 x 160. The camera is one screen big.
- `Camera.center(player.pos)` then `Camera.clamp(SPACE)` runs every update.
- Every world object is drawn through `cam.screen(pos)` and culled with
  `cam.sees(point)` or `cam.intersects(rect)`.
- The HUD and the sun are drawn in screen space, after the world.
- Y grows downwards, matching the SDK. `Player.padDir` already flips the pad Y.

## 4. State machine

```
Menu -> Init -> Game -> Clear -> Init -> ... (next level)
                  |
                  +-> Over -> Menu
                        |
                        +-> Init (new run, level 1)
```

| State | Update | Render |
| --- | --- | --- |
| `Menu` | Blink prompt. `E` starts a new run. Cheat `stateFlip` + `S` jumps to `Over`. | Stars, title, controls. Night palette. |
| `Init` | Reset player and camera, generate level, set `started_at = ff.getTime()`, apply night palette, go to `Game`. | Nothing (one frame). |
| `Game` | Player, camera, ghosts, separation, burial checks, dawn step, timer expiry, level clear. | World, sun, HUD. |
| `Clear` | Count `CLEAR_FRAMES` (120), then `level += 1` and go to `Init`. | Frozen world plus "NIGHT N CLEARED" and the bonus. |
| `Over` | Save once. `E` starts a new run. `N` goes to `Menu`. | Dawn world, "DAWN", score, best score/night, souls, fastest clear. |

`Died` is removed. Nothing kills the shepherd.

Run-level globals:

```zig
var level: u32 = 1;
var run_score: i32 = 0;
var buried_this_run: u32 = 0;
var best_level: u32 = 1;
var best_score: i32 = 0;
```

`startRun()` sets `level = 1`, `run_score = 0`, `buried_this_run = 0`, then
`state = .Init`. Clearing a level keeps `run_score` and only increments `level`.

## 5. Entities

### 5.1 Shepherd (`Player.zig`)

- Movement stays as implemented: analog pad with deadzone 300, speed 2.5,
  friction 0.9985, bounce off `SPACE`.
- `d` stays at `SIZE_PLAYER` (21) and no longer shrinks.
- Rendering stays as implemented: yellow body, orange outline, trailing aura
  and eyes that point along velocity.
- The shepherd has no collision with ghosts; ghosts are never pushed away by
  the body, only by their own separation rule.

### 5.2 Ghost (`Ghost.zig`)

```zig
const Ghost = struct {
    pos: ff.Point,
    vec: ff.Vec,
    dir: ff.Vec,          // current steering direction, used for bounce
    state: State,         // wander, follow, buried
    color: ff.Color,      // also used as the grave marker colour
    wander_frames: u16,   // frames until the next wander direction
};
```

Constants:

| Constant | Value | Meaning |
| --- | --- | --- |
| `RADIUS` | 9 (`d = 18`) | Drawn diameter. |
| `WANDER_SPEED` | 0.35 px/frame | Slow drift. |
| `FOLLOW_SPEED` | 2.4 px/frame | Slightly slower than the shepherd's 2.5, so a ghost can be lost by sprinting away. |
| `FOLLOW_RADIUS` | 64 px | A wandering ghost starts following inside this distance. |
| `LOSE_RADIUS` | 140 px | A following ghost gives up beyond this distance. |
| `TRAIL_DISTANCE` | 26 px | Following ghosts aim for a point this far behind the shepherd, so they do not sit on top of the player. |
| `BURY_RADIUS` | 16 px | Distance from its own grave at which a following ghost is buried. |
| `SEPARATION` | 18 px | Minimum distance between two ghosts. |

`FOLLOW_RADIUS < LOSE_RADIUS` is the hysteresis that stops a ghost from
flickering between wander and follow at the boundary.

### 5.3 Grave

A plain struct in `main.zig`, one per ghost, indexed the same way:

```zig
const Grave = struct {
    pos: ff.Point,
    filled: bool = false,
};
```

- Drawn as a headstone: a 14 x 18 rounded rect in `.dark_gray` with a `.gray`
  outline.
- An unfilled grave has a small marker dot in the matching ghost colour above
  the stone. This is how the player knows which grave belongs to which ghost.
- A filled grave drops the marker and draws a small `.light_green` cross.

## 6. Ghost behaviour

This is the only non-trivial logic in the game.

### 6.1 Wander

- On spawn, and every 60-180 frames (`Random.mod`), pick a new random unit
  direction.
- Move at `WANDER_SPEED`.
- Bounce off the four world edges, the same way `Enemy.bounce` does today.
- A wandering ghost has a thin `.dark_blue` outline.
- Transition to follow when `distance(ghost, player) < FOLLOW_RADIUS`.

### 6.2 Follow

- Aim for a point `TRAIL_DISTANCE` from the shepherd, on the line from the
  shepherd to the ghost:

  ```zig
  const d = player.pos.sub(self.pos);
  const dist = d.len();                       // ff.Point.len
  if (dist > 1) {
      const target = player.pos.sub(d.scale(TRAIL_DISTANCE / dist));
      const to = target.sub(self.pos);
      const step = @min(to.len() * 0.12, FOLLOW_SPEED);
      self.dir = to.vec() * @as(ff.Vec, @splat(step / to.len()));
      self.vec += self.dir;
      self.pos = ff.Point.from_vec(self.vec);
  }
  ```

  `to.len() * 0.12` is the arrival slowdown: far away the ghost runs at full
  `FOLLOW_SPEED`, close to the target it eases to a stop instead of orbiting.
- Do not bounce while following; the shepherd is always inside `SPACE`, so the
  trail target is too. Keep the bounce clamp as a safety net.
- A following ghost has a brighter `.yellow` outline and a small `.white`
  highlight, so it is obvious which ghosts are currently with you.
- Transition back to wander when `distance > LOSE_RADIUS`.
- If the shepherd is standing still and the ghost is within `TRAIL_DISTANCE`,
  the ghost stops. It does not push the player.

### 6.3 Separation

After all ghosts update, do the same pairwise pass that exists in
`Game.enemyCollisions`, but only separate positions:

- For each pair closer than `SEPARATION`, push both apart by half the overlap.
- No size changes, no eating, no state changes.
- This keeps a herd readable and stops graves from being blocked by a stack.

`Ghost.bounce` must be used by both wander movement and the separation
correction so a ghost can never be pushed outside `SPACE`.

### 6.4 Burial

For each ghost with `state == .follow`:

```zig
if (ghost.pos.sub(graves[i].pos).len() < BURY_RADIUS) {
    ghost.state = .buried;
    graves[i].filled = true;
    run_score += 100;
    buried_this_run += 1;
    ff.addProgress(me, BADGE_SHEPHERD, 1);
}
```

- Only the ghost's own grave counts.
- A wandering ghost standing on its grave is not buried; it has to be
  following you.
- Buried ghosts are skipped in update and render.
- `buried_this_level` is not stored separately: count `filled` graves.
- Level clear when every grave is filled.

## 7. Level generation

`Init` calls `generate(level)`.

- `ff.setSeed(0xB00 + level)`: the same level always has the same layout, so a
  retry is fair. A new run restarts at level 1 with the same first night.
- Ghost count: `@min(3 + level, 8)` -> level 1 has 4, level 5+ has 8.
- Time limit: `90_000 - @min(level - 1, 9) * 5_000` ms -> 90 s at level 1,
  45 s from level 10.
- Graves:
  - Sample `Random.pos` inside an inner rect with a 48 px margin.
  - Reject a position closer than 96 px to an already placed grave, and closer
    than 80 px to the world centre (the shepherd spawn).
  - Give up after 200 tries and accept the last candidate, so generation can
    never hang.
- Ghosts:
  - Spawn in a ring 130-219 px from the shepherd, clamped 20 px inside the
    world edges.
  - Reject a candidate while the camera sees it (no ghost starts on screen) or
    while it is closer than 120 px to its own grave.
  - Give up after 100 tries and accept the last candidate.
  - Assign `GHOST_COLORS[i]` from a fixed table:
    `.white, .cyan, .light_blue, .light_green, .light_gray, .green, .blue,
    .red`. Yellow and orange are reserved for the shepherd.

`ff.setSeed` is only called from `generate`, never in `boot`, so the menu stars
still look different on each launch.

## 8. Dawn and palette

### 8.1 Timer

- `started_at: u64` is set in `Init` from `ff.getTime()`. Firefly's
  `getTime()` is in **microseconds**, so the level table stays in
  milliseconds and the comparison converts: `end = started_at + level_ms * 1000`.
- `level_ms` comes from the level table.
- `remaining = if (now >= end) 0 else (end - now) / 1000` milliseconds.
- `progress = 1 - remaining / level_ms`, clamped to 0..1.
- `remaining == 0` in `Game` -> `enterOver()`.
- The HUD shows `M:SS` from `remaining`, rounded up.

### 8.2 Palette steps

Six dawn steps (0..5). The step is
`@min(5, @as(u32, @intFromFloat(progress * 6.0)))`.
The palette is only rewritten when the step changes, so `Color.set` is not
called 60 times per second.

`applyPalette(step)` lerps every field of `ff.Palette` between `NIGHT` and
`DAWN`:

```zig
const t = @as(f32, @floatFromInt(step)) / 5.0;
var p: ff.Palette = NIGHT;
inline for (@typeInfo(ff.Palette).@"struct".field_names) |name| {
    @field(p, name) = lerpHex(@field(NIGHT, name), @field(DAWN, name), t);
}
p.set(); // Palette.set -> Color.set for all 16 colors
```

`lerpHex` interpolates each of R, G and B separately and returns a `u32` hex
value.

Night palette is the current custom palette in `main.zig` (near-black sky,
greys, amber). Dawn palette is a warm sunrise:

| Colour | Night | Dawn |
| --- | --- | --- |
| `black` (sky) | `0x131313` | `0x6E3B4E` |
| `dark_gray` | `0x505050` | `0x7A4A5A` |
| `gray` | `0x8D8D8D` | `0xA86A5A` |
| `cyan` | `0xA8A8A8` | `0xD08A6A` |
| `light_gray` | `0xCECECE` | `0xE0B090` |
| `white` | `0xF2F0E5` | `0xFFF0D0` |
| `light_blue` | `0xA8A8A8` | `0xE8A06A` |
| `orange` | `0xF7A41D` | `0xFFB347` |
| `dark_green` | `0xC77C03` | `0xD97B4A` |
| `red` | `0xB4202A` | `0xC0504A` |
| `purple` | `0x73172D` | `0x8C4A5A` |
| `yellow` | `0xFFCD75` | `0xFFE08A` |
| `light_green` | `0xA7F070` | `0xC8D890` |
| `green` | `0x38B764` | `0x8AA070` |
| `dark_blue` | `0x29366F` | `0x5A4A6A` |
| `blue` | `0x3B5DC9` | `0x7A6A9A` |

`Init` resets the step to 0 and applies the night palette, so `Clear` and the
next night start dark again. `Over` keeps the final dawn palette. `Menu`
applies night on entry.

### 8.3 Stars and sun

- Stars fade by skipping a growing fraction as dawn progresses:
  `if (@mod(i + dawn_step, 6) < dawn_step) continue;`. No alpha blending is
  needed.
- The sun is drawn in screen space once `dawn_step >= 2`:
  `x = 196`, `y = 150 - progress * 90`, diameter 36, fill `.orange`, stroke
  `.yellow`, width 1.
- A horizon line at `y = 150` in `.dark_green` sells the sunrise. It is drawn
  under the sun and over the world.

## 9. Rendering order

```
clearScreen(.black)
stars (faded)
graves (culled)
ghosts (culled, buried skipped)
shepherd (hidden on the Over screen)
debug follow lines (cheat)
horizon + sun (screen space, Game/Clear/Over)
HUD (screen space, Game/Clear)
state overlay text (Clear/Over/Menu)
```

HUD:

- Top left: `SOULS 2/4` (filled graves / total).
- Top right: `1:07` remaining, and `NIGHT 3` underneath.
- Use the existing `text()` helper and a small `hud_buf: [32]u8` with
  `std.fmt.bufPrint`.

## 10. Input

- `pad`/`pre` and `btn`/`old` stay as globals in `main.zig`.
- Edge detection is `!btn.e and old.e`, exactly as the current menu does.
- `E` (east/south? current code uses `e`) starts and restarts.
- `N` returns to the menu from `Over`.
- Cheats:
  - `1` (42): toggle `followLines` (draw a line from each following ghost to
    the shepherd).
  - `2` (42): toggle the state name overlay.
  - `3` (42): enable `stateFlip` (`S` in `Game` -> `Over`).
  - `4` (42): jump straight to a fresh run (profiling).

## 11. Scoring, persistence, boards and badges

### 11.1 Score

- `+100` per ghost buried.
- `+remaining_seconds * 5` when a level is cleared.
- The run ends at dawn. `run_score` is what goes to the board and the stash.
- `best_time_s` keeps the fastest night clear (elapsed seconds, including any
  partial second) and is shown as `FAST M:SS` on the dawn screen.

### 11.2 Stash

16-byte little-endian buffer, saved with `ff.saveStash(me, &stash_buf)` and
read with `ff.loadStash(me, &stash_buf)`:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 4 | magic `"BOO1"` |
| 4 | 2 | `best_level` u16 |
| 6 | 2 | `best_score` u16 (clamped) |
| 8 | 4 | `total_buried` u32 |
| 12 | 2 | `best_time_s` u16 (fastest clear, 0 = none) |
| 14 | 2 | reserved, zero |

- Loaded in `boot`; bad magic or a short buffer means defaults.
- Saved when a level is cleared, when entering `Over`, and in `before_exit`.
- `total_buried` and `best_time_s` are updated on the event and saved with the
  rest, so a crash loses at most the current night.

### 11.3 Firefly boards and badges

- Board `1`: `ff.addScore(me, 1, @intCast(run_score))` once when entering
  `Over`. Higher is better.
- Badge `1` ("Shepherd", goal 50): `ff.addProgress(me, 1, 1)` on every burial.
- Both are declared in `firefly.toml`; Firefly IDs start at 1, and calling
  `addScore`/`addProgress` for an undeclared ID aborts the app.
- No other board or badge. Badge progress is the lifetime ghost count, which
  matches `total_buried` in the stash.

### 11.4 Audio

`boo/Sound.zig` already provides two sine voices, each with a gain envelope,
a frequency sweep and a queue. It is used as-is:

```zig
sound = Sound.init();                 // boot, adds 2 gain+sine pairs to ff.audio.out
sound.tick(delta_ms);                 // every update
sound.sine(start, end, duration_ms, amplitude, gap_ms);
```

`main.zig` tracks `last_time` from `ff.getTime()` and passes the delta to
`tick`, converted from microseconds to milliseconds and clamped to 100 ms so a
stalled frame cannot skip a whole envelope.
One sound per event:

| Event | Sweep | Duration | Amplitude |
| --- | --- | --- | --- |
| a ghost starts following | `e4` -> `e4` | 90 ms | 0.12 |
| a ghost is buried | `c5` -> `e5` | 140 ms | 0.15 |
| night cleared | `g4` -> `c5` | 260 ms | 0.15 |
| dawn | `a3` -> `e3` | 600 ms | 0.15 |

The two voices mean a burial and a follow blip can overlap. If the queue is
full, `Sound.sine` drops the new event rather than stalling the game. No music
and no sound on the menu.

## 12. Edge cases and rules

- Dawn and burial in the same frame: burial runs first, then the timer check.
  A ghost buried on the last frame counts.
- Level clear and dawn in the same frame: level clear wins if all graves are
  filled after the burial pass.
- A following ghost whose grave is on the other side of the map can be lost;
  that is intended. The player can re-approach and pick it up again.
- A ghost can be pushed by separation onto its grave; it is only buried if it
  was following before the burial check.
- `Init` is the only place that resets the player, camera, graves, ghosts and
  palette. Advancing a level therefore cannot leave stale state behind.
- `Clear` freezes the world; ghosts and the timer do not update for 120 frames.
- Camera clamping means the sun and HUD are always on screen even at world
  edges.
- No multiplayer and no level editor. They are out of scope.

## 13. Implementation order

1. `Player.zig`: remove the growth fields and keep the size constant.
2. `Enemy.zig` -> `Ghost.zig`: replace size logic with wander/follow/buried,
   keep `bounce`, add `render` with camera culling.
3. `Cheats.zig`: rename `preyLines` to `followLines`.
4. `main.zig`:
   - constants, globals and the new `State` enum
   - `Grave` and `generate`
   - palette lerp and `applyPalette`
   - `Init`, `Game` (update order, separation, burial, dawn)
   - `Clear`, `Over`, `Menu`
   - HUD, sun, stars fade
   - stash load/save, board/badge calls, `before_exit`
   - audio setup with `Sound.init`, `tickSound`, and the four event sounds
5. Delete the old predator/prey code paths (`Died`, `enemyCollisions` size
   changes, `SIZE_ENEMY_MAX`, `SIZE_PLAYER_MAX`).
6. `comptime` asserts for the pure helpers:
   - `lerpHex(0x000000, 0xFFFFFF, 0.5) == 0x7F7F7F`
   - `levelMs(1) == 90_000` and `levelMs(99) == 45_000`
   - `ghostCount(1) == 4` and `ghostCount(99) == 8`
   - stash offsets fit the 16-byte buffer

## 14. Verification

- `zig build` must stay warning-free for the wasm32 target.
- `zig build run` in the emulator:
  - menu -> game, ghosts visible away from the spawn
  - approach a ghost, it follows; walk away, it gives up
  - lead it to its matching grave, it disappears and the grave fills
  - palette steps visibly brighter as the timer runs down
  - dawn at 0:00 -> `Over` with score; `E` restarts, `N` returns to menu
  - clearing all graves -> `Clear` -> next night with more ghosts
  - a ghost starts following, a burial, a cleared night and dawn each play a
    short tone
- Restart the emulator and confirm the best score/level survive via the stash.
- The comptime asserts cover the palette and level-table arithmetic.

## 15. Confirmed decisions

1. The predator/prey prototype is replaced; there is one game mode.
2. Nights are endless with scaling difficulty.
3. The first night is 4 ghosts and 90 seconds.
4. Audio is in scope: one short generated tone per game event.
