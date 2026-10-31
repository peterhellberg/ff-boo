const ff = @import("ff");

const draw = ff.draw;

var buf: [1735]u8 = undefined;
var fff: ff.Font = undefined;
var btn: ff.Buttons = undefined;
var pad: ff.Pad = undefined;
var pal: ff.Palette = .{
    .black = 0x000000,
    .gray = 0x292929,
    .white = 0xffffff,
    .orange = 0xf7a41d,
};

pub export fn boot() void {
    pal.set();

    fff = ff.loadFile("font", buf[0..]);
}

pub export fn update() void {
    const me = ff.getMe();

    btn = ff.readButtons(me);
    pad = ff.readPad(me).?;
}

pub export fn render() void {
    ff.clearScreen(.black);
}
