const std = @import("std");
const builtin = @import("builtin");
const fs = std.fs;
const thread = std.Thread;
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;
const handmade = @import("handmade.zig");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    // Todo: check static linking options
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const BitmapPad = 32;
const TransientStorageSize = 1 * GB;
const InitialWindowHeight = 480;
const InitialWindowWidth = 600;
// Todo: Get monitor refresh rate
// Todo: Get current monitor
const TargetFPS = 30;
const TargetMsPerFrame = 1000 / TargetFPS;

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

    // 44k seems to work better than 48k
    GlobalSoundBuffer.sample_rate = 44100;
    GlobalSoundBuffer.tone_volume = 1000;
    GlobalSoundBuffer.channels = 2;
    GlobalSoundBuffer.fade_duration_ms = 20;
    GlobalSoundBuffer.buffer = arena.allocator().alloc(i16, GlobalSoundBuffer.get_buffer_size(TargetFPS)) catch unreachable;

    GlobalOffScreenBuffer.window_width = InitialWindowWidth;
    GlobalOffScreenBuffer.window_height = InitialWindowHeight;
    GlobalOffScreenBuffer.pitch = 0;
    GlobalOffScreenBuffer.memory = arena.allocator().alloc(u32, GlobalOffScreenBuffer.get_memory_size()) catch unreachable;

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16LE,
        .channels = @intFromFloat(GlobalSoundBuffer.channels),
        .rate = @intFromFloat(GlobalSoundBuffer.sample_rate),
    };
    var buffer_attr = c.struct_pa_buffer_attr{
        .maxlength = math.maxInt(u32) - 1,
        .tlength = math.maxInt(u32) - 1,
        .prebuf = math.maxInt(u32) - 1,
        .minreq = @intCast(GlobalSoundBuffer.get_buffer_size(TargetFPS)),
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
        &buffer_attr,
        null,
    ) orelse {
        std.debug.print("Failed to create audio stream\n", .{});
        return 1;
    };
    defer {
        _ = c.pa_simple_flush(audio_server, null);
        c.pa_simple_free(audio_server);
    }

    var audio_pool: thread.Pool = undefined;
    audio_pool.init(.{ .allocator = arena.allocator() }) catch |err| {
        std.debug.print("Failed to initialize thread pool: {any}\n", .{err});
        return 1;
    };
    defer audio_pool.deinit();

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
                    // Todo: handle window resize
                    //resize_memory(&GlobalOffScreenBuffer, &GlobalSoundBuffer, &arena);
                },
                else => continue,
            }
        }

        handmade.GameUpdateAndRenderer(
            game_memory,
            &GlobalKeyboardInput,
            &GlobalOffScreenBuffer,
            &GlobalSoundBuffer,
        );

        // Todo: RDTSC() to get cycles/frame
        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        while (time_per_frame < TargetMsPerFrame) {
            const sleep_time: u64 = @intCast(@divTrunc((TargetMsPerFrame - time_per_frame), 1000));
            // Todo: no precision of timing is guaranteed with thread.sleep, maybe set precision?
            thread.sleep(sleep_time);

            end_time = time.milliTimestamp();
            time_per_frame = end_time - start_time;
        }

        render_game(
            &GlobalOffScreenBuffer,
            &GlobalSoundBuffer,
            &audio_pool,
            audio_server,
            display,
            window,
            gc,
        );

        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;

        assert(time_per_frame != 0);
        fps = @divTrunc(1000, time_per_frame);

        std.debug.print("MsPerFrame: {d}\t FPS: {d}\t TargetFPS: {d}\t TargetMsPerFrame: {d}\n", .{
            time_per_frame,
            fps,
            TargetFPS,
            TargetMsPerFrame,
        });
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
        sound_buffer.get_buffer_size(TargetFPS) * @sizeOf(i16),
        &error_code,
    );
    if (result < 0) {
        std.debug.print("Audio write error: {s}\n", .{c.pa_strerror(error_code)});
        return;
    }
}

fn resize_memory(buffer: *handmade.OffScreenBuffer, sound_buffer: *handmade.SoundBuffer, arena: *std.heap.ArenaAllocator) void {
    // Todo: resize display buffer instead of reset all
    _ = arena.reset(.free_all);

    // Todo: handle this at some point?
    sound_buffer.buffer = arena.allocator().alloc(i16, sound_buffer.get_buffer_size()) catch unreachable;
    buffer.memory = arena.allocator().alloc(u32, buffer.get_memory_size()) catch unreachable;
}

fn render_game(
    screen_buffer: *handmade.OffScreenBuffer,
    sound_buffer: *handmade.SoundBuffer,
    audio_pool: *thread.Pool,
    audio_server: ?*c.struct_pa_simple,
    display: ?*c.Display,
    window: c.Window,
    gc: c.GC,
) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    audio_pool.spawn(write_audio, .{ audio_server, sound_buffer }) catch |err| {
        std.debug.print("Failed to spawn audio thread: {any}\n", .{err});
        return;
    };

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(screen_buffer.memory),
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
        BitmapPad,
        @intCast(screen_buffer.window_width * @sizeOf(u32)),
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(screen_buffer.window_width), @intCast(screen_buffer.window_height));
}
