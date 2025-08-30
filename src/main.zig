const std = @import("std");
const time = std.time;
const math = std.math;
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

// 27 Aug: Todo:
// RTDSC asm (after 0.15.1 update)

// Todo: seperate out window and buffer width
const X11BackBuffer = struct {
    width: u32,
    height: u32,
    memory: []u32,
    pa_memory: []i16,
    bytes_per_pixel: u8,
};

var SoundStream: ?*c.pa_stream = null;
var MainLoopReturnVal: c_int = 0;
var SoundMainLoop: ?*c.pa_mainloop = null;
const SampleRate: f32 = 48000;
const Channels: u8 = 2;
const SoundBufferSize: usize = SampleRate * Channels;
const Hz: f32 = 256;
const Period: f32 = SampleRate / Hz;

var GlobalBackBuffer: X11BackBuffer = undefined;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    GlobalBackBuffer.width = 600;
    GlobalBackBuffer.height = 480;
    GlobalBackBuffer.bytes_per_pixel = @sizeOf(u32);

    GlobalBackBuffer.memory = arena.allocator().alloc(u32, get_memory_size(GlobalBackBuffer)) catch unreachable;
    GlobalBackBuffer.pa_memory = arena.allocator().alloc(i16, SoundBufferSize) catch unreachable;

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16NE,
        .channels = Channels,
        .rate = SampleRate,
    };

    _ = c.pa_simple_new(
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

    // Todo: bind to WM?
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
        @intCast(GlobalBackBuffer.width),
        @intCast(GlobalBackBuffer.height),
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

    // Todo: run in a different thread (blocking operation)
    // I forogot to close the server while testing async, so this does not work
    // right now
    // play_audio(audio_handle, &GlobalBackBuffer);

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
                    // Todo: not sure what to do with this at this point
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
                    GlobalBackBuffer.height = @intCast(event.xconfigure.height);
                    GlobalBackBuffer.width = @intCast(event.xconfigure.width);

                    resize_memory(&GlobalBackBuffer, &arena);

                    redraw(&GlobalBackBuffer, display, window, gc);
                },
                else => continue,
            }
        }

        redraw(&GlobalBackBuffer, display, window, gc);

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

fn play_audio(server: ?*c.struct_pa_simple, buffer: *X11BackBuffer) void {
    var wave_pos: f32 = 0;
    var t: f32 = 0;
    const volume: f32 = 8000;
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
    _ = c.pa_simple_write(server, @ptrCast(buffer.pa_memory), SoundBufferSize * @sizeOf(i16), null);
}

fn get_memory_size(buffer: X11BackBuffer) usize {
    return buffer.width * buffer.height * buffer.bytes_per_pixel;
}

fn resize_memory(buffer: *X11BackBuffer, arena: *std.heap.ArenaAllocator) void {
    // Todo: re-calculate the aspect ratio and stretch image onto window
    _ = arena.reset(.free_all);

    // Todo: handle this at some point?
    buffer.memory = arena.allocator().alloc(u32, get_memory_size(buffer.*)) catch unreachable;
}

fn redraw(buffer: *X11BackBuffer, display: ?*c.Display, window: c.Window, gc: c.GC) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    @memset(buffer.memory, 0);

    var pixel_idx: usize = 0;
    for (0..buffer.height) |y| {
        pixel_idx = y * buffer.width;

        for (0..buffer.width) |x| {
            buffer.memory[pixel_idx + x] = @intCast(x * y);
        }
    }

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(buffer.memory),
        @intCast(buffer.width),
        @intCast(buffer.height),
        32,
        0,
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(buffer.width), @intCast(buffer.height));
}
