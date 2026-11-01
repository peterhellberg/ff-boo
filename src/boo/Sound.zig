const ff = @import("ff");

const Sound = @This();

gains: [2]ff.audio.Gain = undefined,
sines: [2]ff.audio.Sine = undefined,

queue: [2]Sine = undefined,
queue_len: usize = 0,

index: usize = 0,

elapsed_ms: u32 = 0,

pub fn init() Sound {
    var s: Sound = .{};
    var i: usize = 0;

    while (i < s.sines.len) : (i += 1) {
        s.gains[i] = ff.audio.out.node.addGain(0.0);
        s.sines[i] = s.gains[i].node.addSine(.hz(0.0), 0.0);
    }

    return s;
}

pub fn sine(self: *Sound, start: ff.audio.Freq, end: ff.audio.Freq, duration_ms: u32, amplitude: f32, gap_ms: u32) void {
    if (self.queue_len >= self.queue.len) return;

    var start_time: u32 = self.elapsed_ms;

    if (self.queue_len > 0) {
        const last = self.queue[self.queue_len - 1];
        start_time = last.start_ms + last.duration_ms + gap_ms;
    }

    const total_duration: u32 = duration_ms;

    self.queue[self.queue_len] = .{
        .start_ms = start_time,
        .duration_ms = total_duration,
        .start_freq = start,
        .end_freq = end,
        .amplitude = amplitude,
        .started = false,
    };

    self.queue_len += 1;
}

pub fn tick(self: *Sound, delta_ms: u32) void {
    self.elapsed_ms += delta_ms;

    var i: usize = 0;

    while (i < self.queue_len) {
        var sound = self.queue[i];

        const local_ms: i32 = @as(i32, @intCast(self.elapsed_ms)) -
            @as(i32, @intCast(sound.start_ms));

        if (local_ms >= @as(i32, @intCast(sound.duration_ms))) {
            self.queue_len -= 1;
            if (i != self.queue_len) self.queue[i] = self.queue[self.queue_len];
            // Re-check slot i, it now holds the entry swapped in from the tail.
            continue;
        }

        if (!sound.started and local_ms >= 0) {
            const s = &self.sines[self.index];
            const g = &self.gains[self.index];

            self.index = (self.index + 1) % self.sines.len;

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
