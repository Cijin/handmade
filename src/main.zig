const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3/SDL_video.h");
});

const WIDTH = 640;
const HEIGHT = 480;

pub fn main() !u8 {
    var window: ?*sdl.SDL_Window = null;
    var renderer: ?*sdl.SDL_Renderer = null;
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

    if (!sdl.SDL_CreateWindowAndRenderer("Handmade Hero Window", WIDTH, HEIGHT, 0, &window, &renderer)) {
        std.debug.print("Failed to create window or renderer. Err:{s}\n", .{sdl.SDL_GetError()});
        return 1;
    }

    defer {
        if (window) |w| {
            sdl.SDL_DestroyWindow(w);
        }

        if (renderer) |r| {
            sdl.SDL_DestroyRenderer(r);
        }
    }

    while (!done) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event)) {
            if (event.type == sdl.SDL_EVENT_QUIT) {
                done = true;
            }
        }

        _ = sdl.SDL_SetRenderDrawColorFloat(renderer, 0.0, 0.0, 0.0, sdl.SDL_ALPHA_OPAQUE_FLOAT);
        _ = sdl.SDL_RenderClear(renderer);

        _ = sdl.SDL_SetRenderDrawColorFloat(renderer, 1.0, 0.0, 0.0, sdl.SDL_ALPHA_OPAQUE_FLOAT);
        const rect = sdl.SDL_FRect{
            .x = 100,
            .y = 100,
            .w = 200,
            .h = 150,
        };
        _ = sdl.SDL_RenderFillRect(renderer, &rect);

        _ = sdl.SDL_RenderPresent(renderer);
    }

    return 0;
}
