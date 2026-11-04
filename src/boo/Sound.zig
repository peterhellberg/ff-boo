const ff = @import("ff");

const a = ff.audio;

const Sound = @This();

pub fn init() Sound {
    return .{
        .follow_voice = .init(&a.out),
        .burial_mute = buildBurial(&a.out),
        .oneshot = a.out.node.addMix(),
    };
}

pub fn follow(self: *Sound) void {
    const now = ff.getTime() / 1000;

    if (now < self.follow_gate_ms) return;

    self.follow_gate_ms = now + 90;

    self.follow_voice.play(.e4, .g4, 70, 0.06);
}

pub fn burial(self: *Sound) void {
    self.burial_mute.node.reset_all();
}

pub fn clear(self: *Sound) void {
    self.oneshot.node.clear();
    {
        buildClear(&self.oneshot);
    }
    self.oneshot.node.reset_all();
}

pub fn dawn(self: *Sound) void {
    self.oneshot.node.clear();
    {
        buildDawn(&self.oneshot);
    }
    self.oneshot.node.reset_all();
}

const Voice = struct {
    gain: a.Gain,
    osc: a.Sine,

    fn init(parent: *const a.BaseNode) Voice {
        const gain = parent.node.addGain(0);
        const osc = gain.node.addSine(a.Freq.zero, 0);

        return .{ .gain = gain, .osc = osc };
    }

    fn play(
        self: Voice,
        from: a.Freq,
        to: a.Freq,
        dur_ms: u32,
        amp: f32,
    ) void {
        self.osc.modulate(.{
            .linear = .{
                .start = from.h,
                .end = to.h,
                .start_at = a.Time.zero,
                .end_at = a.Time.ms(dur_ms),
            },
        });

        self.gain.modulate(.{
            .adsr = .{
                .attack = a.Time.ms(3),
                .decay = a.Time.ms(3),
                .sustain = a.Time.ms(dur_ms -| 8),
                .sustain_level = 1,
                .release = a.Time.ms(dur_ms),
                .low = 0,
                .high = amp,
            },
        });

        self.gain.node.reset_all();
    }
};

follow_voice: Voice,
burial_mute: a.Mute,
oneshot: a.Mix,
follow_gate_ms: u64 = 0,

fn note(
    parent: *const a.BaseNode,
    at_ms: u32,
    from: a.Freq,
    to: a.Freq,
    dur_ms: u32,
    amp: f32,
) void {
    const gate = parent.node.addPause();

    gate.modulate(.{
        .hold = .{
            .before = 0,
            .after = 1,
            .time = a.Time.ms(at_ms),
        },
    });

    const gain = gate.node.addGain(0);

    gain.modulate(.{
        .adsr = .{
            .attack = a.Time.ms(3),
            .decay = a.Time.ms(3),
            .sustain = a.Time.ms(dur_ms -| 8),
            .sustain_level = 1,
            .release = a.Time.ms(dur_ms),
            .low = 0,
            .high = amp,
        },
    });

    const osc = gain.node.addSine(from, 0);

    if (from.h != to.h) {
        osc.modulate(.{
            .linear = .{
                .start = from.h,
                .end = to.h,
                .start_at = a.Time.zero,
                .end_at = a.Time.ms(dur_ms),
            },
        });
    }
}

fn buildBurial(parent: *const a.BaseNode) a.Mute {
    const mute = parent.node.addMute();
    const root = mute.node.addMix();

    note(&root, 0, .e4, .a2, 100, 0.15);
    note(&root, 100, .a2, .a2, 70, 0.08);

    // Silent until the first burial; reset_all() unmutes the node.
    mute.mute();

    return mute;
}

fn buildClear(parent: *const a.BaseNode) void {
    const root = parent.node.addMix();

    _ = root.node.addZero();

    const arp = root.node.addMix();
    {
        note(&arp, 0, .c4, .c4, 90, 0.12);
        note(&arp, 105, .e4, .e4, 90, 0.12);
        note(&arp, 210, .g4, .g4, 90, 0.12);
    }

    const melody = root.node.addMix();
    {
        note(&melody, 315, .c5, .c5, 90, 0.12);
        note(&melody, 420, .b4, .c5, 280, 0.15);
    }
}

fn buildDawn(parent: *const a.BaseNode) void {
    const root = parent.node.addMix();

    _ = root.node.addZero();

    const melody = root.node.addMix();
    {
        note(&melody, 0, .a4, .a3, 400, 0.12);
        note(&melody, 400, .a3, .e3, 500, 0.12);
    }

    const chord = root.node.addMix();
    {
        note(&chord, 960, .e3, .e3, 600, 0.08);
        note(&chord, 1000, .b3, .b3, 600, 0.08);
    }
}
