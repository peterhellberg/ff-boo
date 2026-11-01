# peter.boo :ghost:

My entry for the [Firefly Zero Jam #3](https://itch.io/jam/firefly-jam-3) 🎃 

> [!NOTE]
> You are a friendly ghost shepherd. Ghosts wander the graveyard at night;
> when you get close, they follow you. Herd each ghost back to its grave
> before dawn breaks — when the timer runs out, the sun rises and the night is over.

Using [Zig](https://ziglang.org/) to compile a ROM for use in [Firefly Zero](https://fireflyzero.com/),
built on the [ff](https://github.com/peterhellberg/ff) SDK 🎮

## How to play

- **Move** around the graveyard (DPad or touchpad — `readPad`/`readButtons`) to approach wandering ghosts.
- Ghosts within range will **follow you** — lead them gently, don't lose them.
- Guide each ghost to its **grave** before the countdown hits zero.
- The palette slowly brightens as dawn approaches
    (`Color.set` / `Palette.set` shift the palette per dawn level) — watch the sky!

## Development

Build and run in the Firefly Zero emulator:
```sh
zig build run
```

File watcher (`spy`) can be started by calling:
```sh
zig build spy
```

Run the tests:
```sh
zig build test
```

## Technical notes

- **Callbacks:** the game loop uses the SDK's `update` (~60 Hz, game logic) and
    `render` (drawing) callbacks; `boot` loads fonts, sprites, and initializes state.
- **Steering:** simple "seek nearest ghost" behavior for herding, using `Point`/`Vec`
    math (lerp, dot, len) from the SDK.
- **Dawn:** timer-driven palette shift via `getTime()` and `Color.set`.
- **Levels:** procedural room layout generated with `getRandom()`
    (`setSeed` for reproducible layouts) — no level editor needed.
- **Persistence:** best times and progress stored with `saveStash`/`loadStash`,
    plus `addScore` (boards) and `addProgress` (badges) where appropriate.
