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

// 27 Aug: Todo:
// RTDSC asm (after 0.15.1 update)
const SampleRate: f32 = 48000;
const Channels: u8 = 2;
const SoundBufferSize: usize = SampleRate * Channels;
const Hz: f32 = 256;
const Period: f32 = SampleRate / Hz;

var GlobalOffScreenBuffer: handmade.OffScreenBuffer = undefined;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    GlobalOffScreenBuffer.window_width = 600;
    GlobalOffScreenBuffer.window_height = 480;
    GlobalOffScreenBuffer.bytes_per_pixel = @sizeOf(u32);

    GlobalOffScreenBuffer.memory = arena.allocator().alloc(u32, GlobalOffScreenBuffer.get_memory_size()) catch unreachable;
    GlobalOffScreenBuffer.pa_memory = arena.allocator().alloc(i16, SoundBufferSize) catch unreachable;

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16NE,
        .channels = Channels,
        .rate = SampleRate,
    };

    const audio_stream = c.pa_simple_new(
        null,
        "handmade",
        c.PA_STREAM_PLAYBACK,
        null,
        "game",
        &sample_spec,
        null,
        null,
        null,
    );
    defer c.pa_simple_free(audio_stream);

    // Todo: run in a different thread (blocking operation)
    // I forogot to close the server while testing async, so this does not work
    // right now
    play_audio(audio_stream, &GlobalOffScreenBuffer);

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
                    // Todo: send this to the renderer
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    switch (keysym) {
                        c.XK_W => {},
                        c.XK_A => {},
                        c.XK_S => {},
                        c.XK_D => {},
                        c.XK_F => {},
                        c.XK_space => {},
                        c.XK_Escape => {},
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

                    resize_memory(&GlobalOffScreenBuffer, &arena);

                    redraw(&GlobalOffScreenBuffer, display, window, gc);
                },
                else => continue,
            }
        }

        redraw(&GlobalOffScreenBuffer, display, window, gc);

        // Todo: RDTSC() to get cycles/frame
        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        if (time_per_frame != 0) {
            fps = @divFloor(1000, time_per_frame);
        }

        //std.debug.print("MsPerFrame: {d}\t FPS: {d}\n", .{ time_per_frame, fps });
        start_time = end_time;
    }

    return 0;
}

fn play_audio(server: ?*c.struct_pa_simple, buffer: *handmade.OffScreenBuffer) void {
    var wave_pos: f32 = 0;
    var t: f32 = 0;
    const volume: f32 = 1000;
    var tone_volume: i16 = @intFromFloat(volume);
    var i: usize = 0;
    while (i < SoundBufferSize) : (i += 2) {
        if (wave_pos <= Period) {
            wave_pos = 0;
        }

        t = 2 * math.pi * (wave_pos / Period);
        const sine_t = @sin(t) * volume;
        tone_volume = @intFromFloat(sine_t);

        buffer.pa_memory[i] = tone_volume;
        buffer.pa_memory[i + 1] = tone_volume;
        wave_pos += 1;
    }

    // Todo: this method blocks, use a async one instead
    const write_err = c.pa_simple_write(server, @ptrCast(buffer.pa_memory), SoundBufferSize * @sizeOf(i16), null);
    if (write_err < 0) {
        std.debug.print("Audio write error:{s}\n", .{c.pa_strerror(write_err)});
    }
}

fn resize_memory(buffer: *handmade.OffScreenBuffer, arena: *std.heap.ArenaAllocator) void {
    // Todo: re-calculate the aspect ratio and stretch image onto window
    _ = arena.reset(.free_all);

    // Todo: handle this at some point?
    buffer.memory = arena.allocator().alloc(u32, buffer.get_memory_size()) catch unreachable;
}

fn redraw(buffer: *handmade.OffScreenBuffer, display: ?*c.Display, window: c.Window, gc: c.GC) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    @memset(buffer.memory, 0);

    handmade.GameUpdateAndRenderer(buffer);

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(buffer.memory),
        @intCast(buffer.window_width),
        @intCast(buffer.window_height),
        32,
        0,
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(buffer.window_width), @intCast(buffer.window_height));
}
