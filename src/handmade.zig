const std = @import("std");

// Todo: seperate out window and buffer width
pub const OffScreenBuffer = struct {
    window_width: u32,
    window_height: u32,
    memory: []u32,
    pa_memory: []i16,
    bytes_per_pixel: u8,

    pub fn get_memory_size(self: *OffScreenBuffer) usize {
        return self.window_width * self.window_height * self.bytes_per_pixel;
    }
};

pub fn GameUpdateAndRenderer(buffer: *OffScreenBuffer) void {
    var pixel_idx: usize = 0;
    for (0..buffer.window_height) |y| {
        pixel_idx = y * buffer.window_width;

        for (0..buffer.window_width) |x| {
            buffer.memory[pixel_idx + x] = @intCast(x * y);
        }
    }
}
