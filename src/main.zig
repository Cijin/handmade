const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const builtin = @import("builtin");
const time = std.time;
const math = std.math;
const handmade = @import("handmade.zig");
// Todo: check static linking options
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

const KB = 1024;
const MB = KB * 1024;
const GB = MB * 1024;
const TransientStorageSize = 1 * GB;

var GlobalSoundBuffer: handmade.SoundBuffer = undefined;
var GlobalOffScreenBuffer: handmade.OffScreenBuffer = undefined;
var GlobalKeyboardInput: handmade.Input = undefined;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Todo: transient memory unused
    const game_memory = arena.allocator().create(handmade.GameMemory) catch unreachable;
    game_memory.* = handmade.GameMemory{
        .is_initialized = false,
        .game_state = arena.allocator().create(handmade.GameState) catch unreachable,
        .transient_storage = arena.allocator().alloc(u8, TransientStorageSize) catch unreachable,
    };

    GlobalKeyboardInput.type = handmade.InputType.Keyboard;

    // Todo: set frame rate
    GlobalSoundBuffer.sample_rate = 48000;
    GlobalSoundBuffer.tone_volume = 8000;
    GlobalSoundBuffer.channels = 2;
    GlobalSoundBuffer.buffer = arena.allocator().alloc(i16, GlobalSoundBuffer.get_buffer_size()) catch unreachable;

    GlobalOffScreenBuffer.window_width = 600;
    GlobalOffScreenBuffer.window_height = 480;
    GlobalOffScreenBuffer.bytes_per_pixel = @sizeOf(u32);
    GlobalOffScreenBuffer.memory = arena.allocator().alloc(u32, GlobalOffScreenBuffer.get_memory_size()) catch unreachable;

    std.debug.print("Current memory usage: {d}\n", .{arena.queryCapacity()});

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16NE,
        .channels = @intFromFloat(GlobalSoundBuffer.channels),
        .rate = @intFromFloat(GlobalSoundBuffer.sample_rate),
    };
    const audio_server = c.pa_simple_new(
        null,
        // if audio does not work out of the blue, try changing server name seems to work for some reason
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
                    // Todo: handle this in the game at some point
                    if (keysym == c.XK_Escape) {
                        quit = true;
                        break;
                    } else {
                        GlobalKeyboardInput.key = @intCast(keysym);
                    }
                },
                c.KeyRelease => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    GlobalKeyboardInput.key_released = @intCast(keysym);
                    GlobalKeyboardInput.time = @intCast(event.xkey.time);
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
                    //resize_memory(&GlobalOffScreenBuffer, &GlobalSoundBuffer, &arena);
                },
                else => continue,
            }
        }

        render_game(
            game_memory,
            &GlobalKeyboardInput,
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

        //std.debug.print("MsPerFrame: {d}\t FPS: {d}\n", .{ time_per_frame, fps });
        start_time = end_time;
    }

    return 0;
}

fn platform_read_entire_file(allocator: mem.Allocator) !fs.File {
    const pwd = fs.cwd();
    const file = try pwd.createFile("test", .{ .lock = .exclusive, .read = true });
    defer file.close();

    const file_stat = try file.stat();
    const file_size = file_stat.size;

    const written = try file.write("this is some test to verify file write");

    // Todo: i'm not sure this is the right way to reset the file handle
    try file.seekTo(0);
    const seek_pos = try file.getPos();

    const dest: []u8 = try allocator.alloc(u8, file_size);
    const bytes_read = file.read(dest) catch |err| {
        allocator.free(dest);
        return err;
    };

    std.debug.print("File stats: SeekPos: {d} | Size:{d}| Read: {d}| Written: {d}| Contents:\n {s}\n", .{
        seek_pos,
        file_size,
        bytes_read,
        written,
        dest,
    });

    return file;
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
    // Todo: resize display buffer instead of reset all
    _ = arena.reset(.free_all);

    // Todo: handle this at some point?
    sound_buffer.buffer = arena.allocator().alloc(i16, sound_buffer.get_buffer_size()) catch unreachable;
    buffer.memory = arena.allocator().alloc(u32, buffer.get_memory_size()) catch unreachable;
}

fn render_game(
    game_memory: *handmade.GameMemory,
    input: *handmade.Input,
    screen_buffer: *handmade.OffScreenBuffer,
    sound_buffer: *handmade.SoundBuffer,
    _: ?*c.struct_pa_simple,
    display: ?*c.Display,
    window: c.Window,
    gc: c.GC,
) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    handmade.GameUpdateAndRenderer(game_memory, input, screen_buffer, sound_buffer);

    // Todo: run in a different thread (blocking operation)
    //write_audio(audio_server, &GlobalSoundBuffer);

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
