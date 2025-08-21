const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

// Todo: seperate out window and buffer width
const X11BackBuffer = struct {
    width: u32,
    height: u32,
    memory: []u32,
    bytes_per_pixel: u8,
};

const SampleRate: u32 = 48000;
const Channels: u8 = 2;
const SoundBufferSize = SampleRate * 2;
const Hz = 256;
const Period = (SampleRate / Hz) / 2;

var SoundBuffer: [SoundBufferSize]i16 = undefined;
var GlobalBackBuffer: X11BackBuffer = undefined;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16NE,
        .channels = Channels,
        .rate = SampleRate,
    };

    // Todo: replace with async?
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

    GlobalBackBuffer.width = 600;
    GlobalBackBuffer.height = 480;
    GlobalBackBuffer.bytes_per_pixel = @sizeOf(u32);

    GlobalBackBuffer.memory = arena.allocator().alloc(u32, get_memory_size(GlobalBackBuffer)) catch unreachable;

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

    var quit = false;
    var event: c.XEvent = undefined;
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
    }

    return 0;
}

fn play_audio(server: ?*c.struct_pa_simple) void {
    var wave_pos: u32 = 0;
    var audio: i16 = 1000;
    var i: usize = 0;
    while (i < SoundBufferSize) : (i += 2) {
        if (wave_pos == Period) {
            wave_pos = 0;
            audio = -audio;
        }

        SoundBuffer[i] = audio;
        SoundBuffer[i + 1] = audio;
        wave_pos += 1;
    }

    _ = c.pa_simple_write(server, @ptrCast(SoundBuffer[0..]), SoundBufferSize * @sizeOf(i16), null);
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
