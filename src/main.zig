const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
});

const width = 800;
const height = 600;

pub fn main() !u8 {
    var done = false;

    const meta_data_set = sdl.SDL_SetAppMetadata("Handmade", "0.0.1", "handmade");
    if (!meta_data_set) {
        std.debug.print("Failed to set meta_data. Error:{s}\n", .{sdl.SDL_GetError()});
    }

    const sdl_init = sdl.SDL_Init(sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_VIDEO);
    if (!sdl_init) {
        std.debug.print("Failed to set init sdl. Error:{s}\n", .{sdl.SDL_GetError()});
    }
    defer sdl.SDL_Quit();

    const window = sdl.SDL_CreateWindow("Handmade", width, height, sdl.SDL_WINDOW_RESIZABLE) orelse {
        std.debug.print("Failed to create window. Error:{s}\n", .{sdl.SDL_GetError()});
        return 1;
    };
    defer sdl.SDL_DestroyWindow(window);

    while (!done) {
        var event: sdl.SDL_Event = undefined;

        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                done = true;
            }
        }
    }

    return 0;
}
