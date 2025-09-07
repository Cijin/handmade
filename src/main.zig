const std = @import("std");
const time = std.time;
const math = std.math;
const handmade = @import("handmade.zig");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

var GlobalSoundBuffer: handmade.SoundBuffer = undefined;
var GlobalOffScreenBuffer: handmade.OffScreenBuffer = undefined;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    GlobalOffScreenBuffer.window_width = 600;
    GlobalOffScreenBuffer.window_height = 480;
    GlobalOffScreenBuffer.bytes_per_pixel = @sizeOf(u32);
    GlobalOffScreenBuffer.memory = arena.allocator().alloc(u32, GlobalOffScreenBuffer.get_memory_size()) catch unreachable;

    // Todo: set frame rate
    GlobalSoundBuffer.sample_rate = 48000;
    GlobalSoundBuffer.tone_volume = 8000;
    GlobalSoundBuffer.channels = 2;
    GlobalSoundBuffer.hz = 256;
    GlobalSoundBuffer.buffer = arena.allocator().alloc(i16, GlobalSoundBuffer.get_buffer_size()) catch unreachable;

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16NE,
        .channels = @intFromFloat(GlobalSoundBuffer.channels),
        .rate = @intFromFloat(GlobalSoundBuffer.sample_rate),
    };
    const audio_server = c.pa_simple_new(
        null,
        // if audio does not work out of the blue, try changing server name seems to work for some reason
        // Todo: check previously open servers that are not closed
        "handmade_audio",
        c.PA_STREAM_PLAYBACK,
        null,
        "game",
        &sample_spec,
        null,
        null,
        null,
    ) orelse {
        std.debug.print("Failed to create audio stream\n", .{});
        return 1;
    };
    defer c.pa_simple_free(audio_server);

    // On a POSIX-conformant system, if the display_name is NULL, it defaults to the value of the DISPLAY environment variable.
    const display = c.XOpenDisplay(null) orelse {
        std.debug.print("failed to open display", .{});

        return 1;
    };
    defer _ = c.XCloseDisplay(display);

    const screen = c.XDefaultScreen(display);

    const window_parent = c.XRootWindow(display, screen);
    const window = c.XCreateSimpleWindow(
        display,
        window_parent,
        0,
        0,
        @intCast(GlobalOffScreenBuffer.window_width),
        @intCast(GlobalOffScreenBuffer.window_height),
        0,
        c.XBlackPixel(display, screen),
        c.XBlackPixel(display, screen),
    );

    const gc = c.XCreateGC(display, window, 0, null);

    var delete_atom: c.Atom = undefined;
    delete_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", 0);
    const protocol_status = c.XSetWMProtocols(display, window, &delete_atom, 1);
    if (protocol_status == 0) {
        std.debug.print("failed to set wm_delete protocol", .{});
        return 1;
    }

    _ = c.XStoreName(display, window, "Handmade");

    // you will not get events without this
    _ = c.XSelectInput(display, window, c.KeyPressMask | c.StructureNotifyMask);

    _ = c.XMapWindow(display, window);

    // window will not show up without sync
    _ = c.XSync(display, 0);

    var quit = false;
    var event: c.XEvent = undefined;
    var start_time = time.milliTimestamp();
    var fps: i64 = 0;
    var time_per_frame: i64 = 0;
    var end_time: i64 = 0;
    while (!quit) {
        while (c.XPending(display) > 0) {
            _ = c.XNextEvent(display, &event);
            switch (event.type) {
                c.KeyPress => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    switch (keysym) {
                        'w' => {
                            GlobalSoundBuffer.hz = 82;
                        },
                        'a' => {
                            GlobalSoundBuffer.hz = 440;
                        },
                        's' => {
                            GlobalSoundBuffer.hz = 880;
                        },
                        'd' => {
                            GlobalSoundBuffer.hz = 294;
                        },
                        'f' => {
                            GlobalSoundBuffer.hz = 175;
                        },
                        c.XK_Escape => {
                            quit = true;
                            break;
                        },
                        else => {},
                    }
                },
                c.KeyRelease => {
                    // Todo: send this to renderer, maybe?
                },
                // Todo: handle window destroyed or prematurely closed
                // so that it can be restarted if it was unintended
                c.ClientMessage => {
                    if (event.xclient.data.l[0] == delete_atom) {
                        std.debug.print("Closing window.\n", .{});
                        quit = true;
                        break;
                    }
                },
                c.ConfigureNotify => {
                    GlobalOffScreenBuffer.window_height = @intCast(event.xconfigure.height);
                    GlobalOffScreenBuffer.window_width = @intCast(event.xconfigure.width);
                    resize_memory(&GlobalOffScreenBuffer, &GlobalSoundBuffer, &arena);
                },
                else => continue,
            }
        }

        render_game(
            &GlobalOffScreenBuffer,
            &GlobalSoundBuffer,
            audio_server,
            display,
            window,
            gc,
        );

        // Todo: RDTSC() to get cycles/frame
        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        if (time_per_frame != 0) {
            fps = @divFloor(1000, time_per_frame);
        }

        std.debug.print("MsPerFrame: {d}\t FPS: {d}\n", .{ time_per_frame, fps });
        start_time = end_time;
    }

    return 0;
}

fn write_audio(server: ?*c.struct_pa_simple, sound_buffer: *handmade.SoundBuffer) void {
    var error_code: c_int = 0;
    const result = c.pa_simple_write(
        server,
        @ptrCast(sound_buffer.buffer),
        sound_buffer.buffer.len * @sizeOf(i16),
        &error_code,
    );
    if (result < 0) {
        std.debug.print("Audio write error: {s}\n", .{c.pa_strerror(error_code)});
        return;
    }

    _ = c.pa_simple_drain(server, null);
}

fn resize_memory(buffer: *handmade.OffScreenBuffer, sound_buffer: *handmade.SoundBuffer, arena: *std.heap.ArenaAllocator) void {
    // Todo: re-calculate the aspect ratio and stretch image onto window
    _ = arena.reset(.free_all);

    // Todo: handle this at some point?
    sound_buffer.buffer = arena.allocator().alloc(i16, sound_buffer.get_buffer_size()) catch unreachable;
    buffer.memory = arena.allocator().alloc(u32, buffer.get_memory_size()) catch unreachable;
}

fn render_game(
    screen_buffer: *handmade.OffScreenBuffer,
    sound_buffer: *handmade.SoundBuffer,
    audio_server: ?*c.struct_pa_simple,
    display: ?*c.Display,
    window: c.Window,
    gc: c.GC,
) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    handmade.GameUpdateAndRenderer(screen_buffer, sound_buffer);

    // Todo: run in a different thread (blocking operation)
    std.debug.print("Hz:{d}\n", .{GlobalSoundBuffer.hz});
    write_audio(audio_server, &GlobalSoundBuffer);

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(screen_buffer.memory),
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
        32,
        0,
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(screen_buffer.window_width), @intCast(screen_buffer.window_height));
}
