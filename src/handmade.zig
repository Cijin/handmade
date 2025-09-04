const std = @import("std");
const math = std.math;

pub const SoundBuffer = struct {
    buffer: []i16,
    tone_volume: f32,
    sample_rate: f32,
    channels: f32,
    hz: f32,

    pub fn get_buffer_size(self: *SoundBuffer) usize {
        return @intFromFloat(self.sample_rate * self.channels);
    }
};

// Todo: seperate out window and buffer width
pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    memory: []u32,
    bytes_per_pixel: u8,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height * self.bytes_per_pixel;
    }
};

fn fill_sound_buffer(sound_buffer: *SoundBuffer) void {
    const period = sound_buffer.sample_rate / sound_buffer.hz;
    var wave_pos: f32 = 0;
    var t: f32 = 0;
    var i: usize = 0;
    while (i < sound_buffer.buffer.len) : (i += 2) {
        if (wave_pos >= period) {
            wave_pos = 0;
        }

        t = 2 * math.pi * (wave_pos / period);
        const sine_t = @sin(t) * sound_buffer.tone_volume;

        sound_buffer.buffer[i] = @intFromFloat(sine_t);
        sound_buffer.buffer[i + 1] = @intFromFloat(sine_t);
        wave_pos += 1;
    }
}

fn renderer(buffer: *OffScreenBuffer) void {
    var pixel_idx: usize = 0;
    for (0..buffer.window_height) |y| {
        pixel_idx = y * buffer.window_width;

        for (0..buffer.window_width) |x| {
            buffer.memory[pixel_idx + x] = @intCast(x * y);
        }
    }
}

pub fn GameUpdateAndRenderer(buffer: *OffScreenBuffer, sound_buffer: *SoundBuffer) void {
    fill_sound_buffer(sound_buffer);
    renderer(buffer);
}
