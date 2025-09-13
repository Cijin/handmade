const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

pub const GameMemory = struct {
    is_initialized: bool,
    game_state: *GameState,
    transient_storage: []u8,
};

pub const GameState = struct {
    tone_hz: f32,
    blue_offset: u32,
    green_offset: u32,
};

pub const InputType = enum {
    Keyboard,
    Gamepad,
};

pub const Input = struct {
    type: InputType,
    key: u32,
    key_released: u32,
    time: u32,
};

pub const SoundBuffer = struct {
    buffer: []i16,
    sample_rate: f32,
    channels: f32,
    tone_volume: f32,

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

fn fill_sound_buffer(game_state: *GameState, sound_buffer: *SoundBuffer) void {
    const period = sound_buffer.sample_rate / game_state.tone_hz;
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

fn handle_keypress_event(game_state: *GameState, input: *Input) void {
    switch (input.type) {
        .Keyboard => {
            switch (input.key) {
                'w' => {
                    game_state.tone_hz = 82;
                },
                'a' => {
                    game_state.tone_hz = 440;
                },
                's' => {
                    game_state.tone_hz = 880;
                },
                'd' => {
                    game_state.tone_hz = 294;
                },
                'f' => {
                    game_state.tone_hz = 175;
                },
                else => {},
            }
        },
        .Gamepad => unreachable,
    }
}

fn renderer(buffer: *OffScreenBuffer) void {
    var pixel_idx: usize = 0;
    for (0..buffer.window_height) |y| {
        pixel_idx = y * buffer.window_width;

        for (0..buffer.window_width) |x| {
            buffer.memory[pixel_idx + x] = @intCast(x + y);
        }
    }
}

pub fn GameUpdateAndRenderer(game_memory: *GameMemory, input: *Input, buffer: *OffScreenBuffer, sound_buffer: *SoundBuffer) void {
    if (!game_memory.is_initialized) {
        game_memory.game_state.tone_hz = 256;
        game_memory.game_state.blue_offset = 0;
        game_memory.game_state.green_offset = 0;

        game_memory.is_initialized = true;
    }

    handle_keypress_event(game_memory.game_state, input);
    fill_sound_buffer(game_memory.game_state, sound_buffer);
    renderer(buffer);
}
