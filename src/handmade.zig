const std = @import("std");
const common = @import("common.zig");
const math = std.math;
const assert = std.debug.assert;

const BlueOffset = 0x0000ff;
const RedOffset = 0xff0000;
const GreenOffset = 0x00ff00;

fn fill_sound_buffer(game_state: *common.GameState, sound_buffer: *common.SoundBuffer) void {
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

fn handle_keypress_event(game_state: *common.GameState, input: *common.Input) void {
    switch (input.key) {
        'w' => {
            game_state.tone_hz = 82;
            game_state.height_offset -= 1;
        },
        'a' => {
            game_state.tone_hz = 440;
            game_state.width_offset -= 1;
        },
        's' => {
            game_state.tone_hz = 880;
            game_state.height_offset += 1;
        },
        'd' => {
            game_state.tone_hz = 294;
            game_state.width_offset += 1;
        },
        else => {},
    }
}

fn renderer(game_state: *common.GameState, buffer: *common.OffScreenBuffer) void {
    for (0..buffer.window_width) |i| {
        for (0..buffer.window_height) |j| {
            const blue = j + game_state.width_offset;
            const green = i + game_state.height_offset;

            buffer.memory[i][j] = @intCast(blue & green);
        }
    }
}

export fn GameUpdateAndRenderer(
    game_memory: *common.GameMemory,
    input: *common.Input,
    buffer: *common.OffScreenBuffer,
    sound_buffer: *common.SoundBuffer,
) void {
    if (!game_memory.is_initialized) {
        game_memory.init();
    }

    handle_keypress_event(game_memory.game_state, input);
    fill_sound_buffer(game_memory.game_state, sound_buffer);
    renderer(game_memory.game_state, buffer);
}
