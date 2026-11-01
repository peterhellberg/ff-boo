const Cheats = @This();

followLines: bool = false,
stateName: bool = false,
stateFlip: bool = false,
jumpToGame: bool = false,

pub fn apply(self: *Cheats, cmd: i32, val: i32) i32 {
    if (cmd == 1 and val == 42) {
        self.followLines = !self.followLines;

        return 0;
    }

    if (cmd == 2 and val == 42) {
        self.stateName = !self.stateName;

        return 0;
    }

    if (cmd == 3 and val == 42) {
        self.stateFlip = true;

        return 0;
    }

    if (cmd == 4 and val == 42) {
        self.jumpToGame = true;

        return 0;
    }

    return -1;
}
