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

pub const Input = struct {
    // Todo: mouse button
    mouse_x: i32,
    mouse_y: i32,
    key: u32,
    key_released: u32,
    time: u32,
};

pub const LinuxState = struct {
    filename: []const u8,
    recording_file: ?fs.File,
    playback_file: ?fs.File,

    game_input: *Input,
    game_state: *GameState,

    pub fn init(self: *LinuxState) !void {
        self.recording_file = fs.cwd().openFile(self.filename, .{ .mode = .write_only }) catch |err| {
            if (err == fs.File.OpenError.FileNotFound) {
                self.recording_file = try fs.cwd().createFile(self.filename, .{});
                self.playback_file = try fs.cwd().openFile(self.filename, .{ .mode = .read_only });
                return;
            } else {
                return err;
            }
        };

        self.playback_file = try fs.cwd().openFile(self.filename, .{ .mode = .read_only });
    }

    pub fn deinit(self: *LinuxState) void {
        self.recording_file.?.close();
        self.playback_file.?.close();
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

pub const InitialWindowWidth = 960;
pub const InitialWindowHeight = 480;
pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    // Todo: this might not work on resize
    memory: [InitialWindowWidth][InitialWindowHeight]u32,
    pitch: usize,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height;
    }
};

const ThreadContext = struct {
    // identifier for the current thread
    handle: u32,
};
