const ff = @import("ff");

const Sound = @This();

gains: [2]ff.audio.Gain = undefined,
sines: [2]ff.audio.Sine = undefined,

queue: [16]Sine = undefined,
queue_len: usize = 0,

index: usize = 0,

elapsed_ms: u32 = 0,

/// One note in the scheduling queue.
pub const Note = struct {
    from: ff.audio.Freq,
    to: ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32 = 0.12,
    gap_ms: u32 = 0,
};

pub fn init() Sound {
    var s: Sound = .{};
    var i: usize = 0;

    while (i < s.sines.len) : (i += 1) {
        s.gains[i] = ff.audio.out.node.addGain(0.0);
        s.sines[i] = s.gains[i].node.addSine(.hz(0.0), 0.0);
    }

    return s;
}

/// Core scheduler: queue a note with an explicit absolute start time
/// (ms since engine start). Used by `chord` for simultaneous starts;
/// everything else goes through `sine`.
pub fn sineAt(
    self: *Sound,
    start_ms: u32,
    start: ff.audio.Freq,
    end: ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32,
) void {
    if (self.queue_len >= self.queue.len) return;
    self.queue[self.queue_len] = .{
        .start_ms = start_ms,
        .duration_ms = duration_ms,
        .start_freq = start,
        .end_freq = end,
        .amplitude = amplitude,
        .started = false,
    };
    self.queue_len += 1;
}

/// Queue a single sliding sine tone, starting as soon as the previous
/// queued note ends (plus `gap_ms`). If nothing is queued, it starts
/// immediately.
pub fn sine(self: *Sound, start: ff.audio.Freq, end: ff.audio.Freq, duration_ms: u32, amplitude: f32, gap_ms: u32) void {
    if (self.queue_len >= self.queue.len) return;

    var start_time: u32 = self.elapsed_ms;

    if (self.queue_len > 0) {
        const last = self.queue[self.queue_len - 1];
        start_time = last.start_ms + last.duration_ms + gap_ms;
    }

    self.sineAt(start_time, start, end, duration_ms, amplitude);
}

/// Queue a single note described by `n`. Uniform entry point for the
/// sequence helpers below.
pub fn note(self: *Sound, n: Note) void {
    self.sine(n.from, n.to, n.duration_ms, n.amplitude, n.gap_ms);
}

/// Queue a sequence of notes back-to-back. Each note starts when the
/// previous one ends, plus its own `gap_ms` (or `default_gap_ms` when
/// the note doesn't override it). Notes may slide (`from != to`).
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

/// Queue an arpeggio over `freqs`: each held for `note_ms`, separated
/// by `gap_ms`. Descending when `up` is false.
pub fn arp(
    self: *Sound,
    freqs: []const ff.audio.Freq,
    note_ms: u32,
    amplitude: f32,
    gap_ms: u32,
    up: bool,
) void {
    var i: usize = 0;
    while (i < freqs.len) : (i += 1) {
        const f = if (up) freqs[i] else freqs[freqs.len - 1 - i];
        self.sine(f, f, note_ms, amplitude, gap_ms);
    }
}

/// Queue a chord: all notes start together, staggered by `strum_ms`
/// for a soft strummed feel. Pass 0 for a tight block chord.
/// Note: with only 2 voices, keep chords to 2 notes (or raise the
/// `gains`/`sines` arrays).
pub fn chord(
    self: *Sound,
    freqs: []const ff.audio.Freq,
    duration_ms: u32,
    amplitude: f32,
    strum_ms: u32,
) void {
    const base: u32 = self.elapsed_ms;
    for (freqs, 0..) |f, i| {
        self.sineAt(
            base + strum_ms * @as(u32, @intCast(i)),
            f,
            f,
            duration_ms,
            amplitude,
        );
    }
}

/// Queue `count` repeated hits of one pitch — staccato by default
/// (`duty` = fraction of each period that actually sounds).
pub fn pulse(
    self: *Sound,
    f: ff.audio.Freq,
    count: usize,
    period_ms: u32,
    amplitude: f32,
    duty: f32,
) void {
    const hold_ms: u32 = @intFromFloat(@as(f32, @floatFromInt(period_ms)) * duty);
    const rest_ms = period_ms - hold_ms;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        self.sine(f, f, hold_ms, amplitude, rest_ms);
    }
}

/// Silent tail after a note's audible end. Keeps the voice occupied
/// for a few ms past the fade-out so expired-envelope artifacts land
/// in silence instead of producing an end-of-note click.
const tail_ms: u32 = 16;

pub fn tick(self: *Sound, delta_ms: u32) void {
    self.elapsed_ms += delta_ms;

    var i: usize = 0;

    while (i < self.queue_len) {
        var sound = self.queue[i];

        const local_ms: i32 = @as(i32, @intCast(self.elapsed_ms)) -
            @as(i32, @intCast(sound.start_ms));

        // Remove only after the audible end PLUS the silent tail.
        if (local_ms >= @as(i32, @intCast(sound.duration_ms + tail_ms))) {
            self.queue_len -= 1;
            if (i != self.queue_len) self.queue[i] = self.queue[self.queue_len];
            // Re-check slot i, it now holds the entry swapped in from the tail.
            continue;
        }

        if (!sound.started and local_ms >= 0) {
            const slot = self.index;
            const s = &self.sines[slot];
            const g = &self.gains[slot];

            self.index = (self.index + 1) % self.sines.len;

            // Clear all modulators left over from whatever note last
            // used this voice.
            g.node.reset_all();

            s.modulate(.{
                .linear = .{
                    .start = sound.start_freq.h,
                    .end = sound.end_freq.h,
                    .start_at = .ms(0),
                    .end_at = .ms(sound.duration_ms),
                },
            });

            const fade_in_frac: f32 = 0.2;
            const fade_in_ms: u32 = @as(u32, @intFromFloat(@as(f32, @floatFromInt(sound.duration_ms)) * fade_in_frac));
            const fade_out_start_ms: u32 = fade_in_ms;

            g.modulate(.{
                .linear = .{
                    .start = 0.0,
                    .end = sound.amplitude,
                    .start_at = .ms(0),
                    .end_at = .ms(fade_in_ms),
                },
            });

            // Fade out fully by the audible end; the tail afterwards is
            // silent buffer time.
            g.modulate(.{
                .linear = .{
                    .start = sound.amplitude,
                    .end = 0.0,
                    .start_at = .ms(fade_out_start_ms),
                    .end_at = .ms(sound.duration_ms),
                },
            });

            sound.started = true;
            self.queue[i] = sound;
        }

        i += 1;
    }
}

const Sine = struct {
    start_ms: u32,
    duration_ms: u32,
    start_freq: ff.audio.Freq,
    end_freq: ff.audio.Freq,
    amplitude: f32,
    started: bool = false,
};
