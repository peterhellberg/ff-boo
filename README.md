# peter.boo :ghost:

My entry for the [Firefly Zero Jam #3](https://itch.io/jam/firefly-jam-3) 🎃 

> [!NOTE]
> You are a friendly ghost shepherd. Ghosts wander the graveyard at night;
> when you get close, they follow you. Herd each ghost back to its grave
> before dawn breaks — when the timer runs out, the sun rises and the night is over.

Using [Zig](https://ziglang.org/) to compile a ROM for use in [Firefly Zero](https://fireflyzero.com/),
built on the [ff](https://github.com/peterhellberg/ff) SDK 🎮

![peter.boo.002-8x](https://play.c7.se/ff/boo/shots/peter.boo.002-8x.png)
![peter.boo.004-8x](https://play.c7.se/ff/boo/shots/peter.boo.004-8x.png)

## How to play

- **Move** around the graveyard _(touchpad)_ to approach wandering ghosts.
- **Walls** form a loose maze
  - Walk around them. 
  - Ghosts drift straight through.
- Ghosts within range will **follow you**
  - Lead them gently, don't lose them.
- Guide each ghost to its **grave** before dawn breaks.

## Development

Build and run in the [Firefly Zero emulator](https://github.com/firefly-zero/firefly-emulator):
```sh
zig build run
```

File watcher (`spy`) can be started by calling:
```sh
zig build spy
```

## Technical notes

- **Callbacks:** the game loop uses the SDK's `update` (~60 Hz, game logic) and
    `render` (drawing) callbacks; `boot` loads the font and initializes state.
- **Steering:** ghosts wander, then seek a point just behind the shepherd when
    close, using `Point`/`Vec` math (lerp, dot, len) from the SDK.
- **Dawn:** timer-driven palette shift via `getTime()` and `Color.set`.
- **Levels:** procedural grave and maze layout generated with `getRandom()`
    (`setSeed` for reproducible layouts) — no level editor needed.
- **Persistence:** best times and progress stored with `saveStash`/`loadStash`,
    plus `addScore` (boards) and `addProgress` (badges) where appropriate.

