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
    wave_pos: f32,
    target_fps: f32,
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
    fade_duration_ms: f32,

    pub fn get_buffer_size(self: *SoundBuffer, target_fps: f32) usize {
        const frame_duration_sec = 1.0 / target_fps;
        return @intFromFloat(self.sample_rate * self.channels * frame_duration_sec);
    }
};

// Todo: seperate out window and buffer width
pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    memory: []u32,
    pitch: usize,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height * @sizeOf(u32);
    }
};

fn fill_sound_buffer(game_state: *GameState, sound_buffer: *SoundBuffer) void {
    const period = sound_buffer.sample_rate / game_state.tone_hz;
    var t: f32 = 0;
    var i: usize = 0;
    while (i < sound_buffer.buffer.len) : (i += 2) {
        if (game_state.wave_pos >= period) {
            game_state.wave_pos = 0;
        }

        t = 2 * math.pi * (game_state.wave_pos / period);
        const amplitude = 1 - (t / sound_buffer.fade_duration_ms);
        const sine_t = @sin(t) * sound_buffer.tone_volume * amplitude;

        sound_buffer.buffer[i] = @intFromFloat(sine_t);
        sound_buffer.buffer[i + 1] = @intFromFloat(sine_t);
        game_state.wave_pos += 1;
    }
}

fn handle_keypress_event(game_state: *GameState, input: *Input) void {
    switch (input.type) {
        .Keyboard => {
            switch (input.key) {
                'w' => {
                    // Todo:
                    // move -blue -green offset
                    game_state.tone_hz = 82;
                },
                'a' => {
                    // move -blue offset
                    game_state.tone_hz = 440;
                },
                's' => {
                    // move +blue +green offset
                    game_state.tone_hz = 880;
                },
                'd' => {
                    // move +green offset
                    game_state.tone_hz = 294;
                },
                else => {},
            }
        },
        .Gamepad => unreachable,
    }
}

// Todo: use/update pitch
fn renderer(buffer: *OffScreenBuffer) void {
    var pixel_idx: usize = 0;
    for (0..buffer.window_height) |y| {
        pixel_idx = (y * buffer.window_width);

        for (0..buffer.window_width) |x| {
            buffer.memory[pixel_idx + x] = @intCast(x + y);
        }
    }
}

fn debug_sound(buffer: *OffScreenBuffer, sound_buffer: *SoundBuffer) void {
    const pad = 16;
    //const coefficent: f32 = @divTrunc(buffer.window_width, sound_buffer.buffer.len);

    const width = buffer.window_width;
    const height = buffer.window_height - pad;
    const start_y = height - (2 * pad);
    var pixel_idx: usize = 0;
    var sound_idx: usize = 0;
    var pixel: u32 = 0;
    var offset: usize = 0;
    var sound_elem: u32 = 0;

    for (start_y..height) |y| {
        sound_elem = @abs(sound_buffer.buffer[sound_idx]);
        pixel = 0xff0000 | sound_elem;

        sound_idx = (sound_idx + 1) % (sound_buffer.buffer.len - 1);
        if (sound_idx == width) {
            offset += 1;
        }
        for (offset..width) |x| {
            pixel_idx = (y * width) + x;
            buffer.memory[pixel_idx] = pixel;
        }
    }
}

pub fn GameUpdateAndRenderer(
    game_memory: *GameMemory,
    input: *Input,
    buffer: *OffScreenBuffer,
    sound_buffer: *SoundBuffer,
) void {
    if (!game_memory.is_initialized) {
        game_memory.game_state.tone_hz = 256;
        game_memory.game_state.blue_offset = 0;
        game_memory.game_state.green_offset = 0;
        game_memory.game_state.wave_pos = 0;

        game_memory.is_initialized = true;
    }

    handle_keypress_event(game_memory.game_state, input);
    fill_sound_buffer(game_memory.game_state, sound_buffer);
    renderer(buffer);
    debug_sound(buffer, sound_buffer);
}
