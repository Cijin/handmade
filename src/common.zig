const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub const GameMemory = struct {
    is_initialized: bool,
    game_state: *GameState,
    transient_storage: []u8,

    pub fn init(self: *GameMemory) void {
        self.game_state.tone_hz = 256;
        self.game_state.wave_pos = 0;

        self.game_state.height_offset = 0;
        self.game_state.width_offset = 0;

        self.game_state.player_x = 200;
        self.game_state.player_y = 200;

        self.is_initialized = true;
    }
};

pub const GameState = struct {
    tone_hz: f32,
    wave_pos: f32,
    target_fps: f32,
    height_offset: u32,
    width_offset: u32,
    player_x: u32,
    player_y: u32,
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

pub const X11State = struct {
    recording_file: ?fs.File,
    recording_idx: u32,

    playback_file: ?fs.File,
    playback_idx: u32,

    pub fn init(self: *X11State) !void {
        self.recording_file = fs.cwd().openFile("game_state.hmh", .{ .mode = .write_only }) catch |err| {
            // Todo: this can be done better
            if (err == fs.File.OpenError.FileNotFound) {
                self.recording_file = try fs.cwd().createFile("game_state.hmh", .{});
                self.playback_file = try fs.cwd().openFile("game_state.hmh", .{ .mode = .read_only });
                return;
            } else {
                return err;
            }
        };

        self.playback_file = try fs.cwd().openFile("game_state.hmh", .{ .mode = .read_only });
    }

    pub fn deinit(self: *X11State) void {
        self.recording_file.?.close();
        self.playback_file.?.close();
    }

    pub fn read(self: *X11State, input: *Input) !void {
        // Todo: can stop playback if reached EOF
        const current_pos = try self.playback_file.?.getPos();
        const stat = try self.playback_file.?.stat();

        if (current_pos == stat.size) {
            try self.playback_file.?.seekTo(0);
        }

        var buffer: [@sizeOf(Input)]u8 = undefined;
        _ = self.playback_file.?.read(&buffer) catch |err| {
            std.debug.print("Failed to read input: {any}\n", .{err});
        };

        input.* = mem.bytesToValue(Input, &buffer);
    }

    pub fn write(self: *X11State, input: *Input) void {
        _ = self.recording_file.?.write(mem.asBytes(input)) catch |err| {
            std.debug.print("Failed to write input: {any}\n", .{err});
        };
    }
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

pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    memory: []u32,
    pitch: usize,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height;
    }
};
