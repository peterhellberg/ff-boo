const ff = @import("ff");

const Sound = @This();

gains: [2]ff.audio.Gain = undefined,
sines: [2]ff.audio.Sine = undefined,

queue: [16]Sine = undefined,
queue_len: usize = 0,

index: usize = 0,
elapsed_ms: u32 = 0,
next_start_ms: u32 = 0,

pub const Note = struct {
    from: ff.audio.Freq,
    to: ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32 = 0.12,
    gap_ms: u32 = 0,
};

const Sine = struct {
    start_ms: u32,
    duration_ms: u32,
    start_freq: ff.audio.Freq,
    end_freq: ff.audio.Freq,
    amplitude: f32,
    started: bool = false,
};

const tail_ms: u32 = 16;

pub fn init() Sound {
    var s: Sound = .{};

    for (&s.sines, &s.gains) |*oscillator, *gain| {
        gain.* = ff.audio.out.node.addGain(0.0);
        oscillator.* = gain.node.addSine(.hz(0.0), 0.0);
    }

    return s;
}

pub fn sineAt(
    self: *Sound,
    start_ms: u32,
    start: ff.audio.Freq,
    end: ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32,
) void {
    if (self.queue_len == self.queue.len) return;

    self.queue[self.queue_len] = .{
        .start_ms = start_ms,
        .duration_ms = duration_ms,
        .start_freq = start,
        .end_freq = end,
        .amplitude = amplitude,
    };
    self.queue_len += 1;
}

pub fn sine(
    self: *Sound,
    start: ff.audio.Freq,
    end: ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32,
    gap_ms: u32,
) void {
    const start_ms = @max(self.elapsed_ms, self.next_start_ms);

    self.sineAt(start_ms, start, end, duration_ms, amplitude);

    self.next_start_ms = start_ms +| duration_ms +| gap_ms;
}

pub fn note(self: *Sound, n: Note) void {
    self.sine(n.from, n.to, n.duration_ms, n.amplitude, n.gap_ms);
}

pub fn melody(self: *Sound, notes: []const Note, default_gap_ms: u32) void {
    for (notes) |n| {
        self.note(.{
            .from = n.from,
            .to = n.to,
            .duration_ms = n.duration_ms,
            .amplitude = n.amplitude,
            .gap_ms = if (n.gap_ms == 0) default_gap_ms else n.gap_ms,
        });
    }
}

pub fn arp(
    self: *Sound,
    freqs: []const ff.audio.Freq,
    note_ms: u32,
    amplitude: f32,
    gap_ms: u32,
    up: bool,
) void {
    for (0..freqs.len) |i| {
        const f = freqs[if (up) i else freqs.len - 1 - i];
        self.sine(f, f, note_ms, amplitude, gap_ms);
    }
}

/// Schedule a chord after the last queued note.
pub fn chordAfter(
    self: *Sound,
    freqs: []const ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32,
    strum_ms: u32,
) void {
    const start_ms = @max(self.elapsed_ms, self.next_start_ms);

    for (freqs, 0..) |freq, i| {
        const offset = strum_ms *| @as(u32, @intCast(i));
        self.sineAt(start_ms +| offset, freq, freq, duration_ms, amplitude);
    }

    if (freqs.len > 0) {
        const last_offset = strum_ms *| @as(u32, @intCast(freqs.len - 1));
        self.next_start_ms = start_ms +| last_offset +| duration_ms;
    }
}

pub fn tick(self: *Sound, delta_ms: u32) void {
    self.elapsed_ms +|= delta_ms;

    var i: usize = 0;

    while (i < self.queue_len) {
        const sound = &self.queue[i];

        const has_started = self.elapsed_ms >= sound.start_ms;
        const local_ms = if (has_started)
            self.elapsed_ms - sound.start_ms
        else
            0;

        if (has_started and local_ms >= sound.duration_ms +| tail_ms) {
            self.queue_len -= 1;
            if (i != self.queue_len) {
                self.queue[i] = self.queue[self.queue_len];
            }
            continue;
        }

        if (!sound.started and has_started) {
            const slot = self.index;

            self.index = (self.index + 1) % self.sines.len;

            const s = &self.sines[slot];
            const g = &self.gains[slot];

            g.node.reset_all();

            s.modulate(.{
                .linear = .{
                    .start = sound.start_freq.h,
                    .end = sound.end_freq.h,
                    .start_at = .ms(0),
                    .end_at = .ms(sound.duration_ms),
                },
            });

            const fade_in_ms = @min(sound.duration_ms / 2, 4);

            g.modulate(.{
                .linear = .{
                    .start = 0.0,
                    .end = sound.amplitude,
                    .start_at = .ms(0),
                    .end_at = .ms(fade_in_ms),
                },
            });

            g.modulate(.{
                .linear = .{
                    .start = sound.amplitude,
                    .end = 0.0,
                    .start_at = .ms(fade_in_ms),
                    .end_at = .ms(sound.duration_ms),
                },
            });

            sound.started = true;
        }

        i += 1;
    }
}
