const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const dyn_lib = std.DynLib;
const fs = std.fs;
const thread = std.Thread;
const mem = std.mem;
const time = std.time;
const math = std.math;
const assert = std.debug.assert;
const c = @cImport({
    // https://tronche.com/gui/x/xlib/
    @cInclude("X11/Xlib.h");
    @cInclude("X11/keysym.h");
    // https://www.x.org/archive/X11R7.6/doc/man/man3/Xrandr.3.xhtml
    @cInclude("X11/extensions/Xrandr.h");
    // Todo: check static linking options
    @cInclude("pulse/simple.h");
    @cInclude("pulse/error.h");
});

const GameUpdateAndRendererFn = *fn (
    *common.GameMemory,
    *common.Input,
    *common.OffScreenBuffer,
    *common.SoundBuffer,
) callconv(.c) void;

var SourceModifiedAt: i128 = 0;
const MaxRetryAttempt = 10;
const GameCode = "src/handmade.zig";
const SourceSo = "game_source/libhandmade.so";
const TempSo = "game_source/temp_handmade.so";
const KiB = 1024;
const MB = KiB * 1024;
const GB = MB * 1024;
const BitmapPad = 32;
const TransientStorageSize = 1 * GB;

pub fn main() !u8 {
    var X11RefreshRate: u32 = 60;
    var X11MsPerFrame = 1000 / X11RefreshRate;
    var run_playback: bool = false;
    var is_recording: bool = false;

    var GlobalSoundBuffer: common.SoundBuffer = undefined;
    var GlobalOffScreenBuffer: common.OffScreenBuffer = undefined;

    // Todo: this could be done better?
    // total_mem = [ game_state audio_buffer screen_buffer]
    // allocate(total_mem)
    // game_state = total_mem[0..@sizeOf(game_state)]
    // game_state.audio -> total_mem[@sizeOf(game_state)..@sizeOf(audio_buffer)]
    // audio_buffer = total_mem[0..@sizeOf(audio_buffer)]
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Todo: combine with linux state
    const game_memory = arena.allocator().create(common.GameMemory) catch unreachable;
    game_memory.* = common.GameMemory{
        .is_initialized = false,
        .game_state = arena.allocator().create(common.GameState) catch unreachable,
        .transient_storage = arena.allocator().alloc(u8, TransientStorageSize) catch unreachable,
    };

    var GlobalLinuxState = arena.allocator().create(common.LinuxState) catch unreachable;
    GlobalLinuxState.* = common.LinuxState{
        .filename = "playback/game_state.hmh",
        .recording_file = null,
        .playback_file = null,
        .game_input = arena.allocator().create(common.Input) catch unreachable,
        .game_state = game_memory.game_state,
    };
    GlobalLinuxState.game_input.* = common.Input{
        .mouse_x = -1,
        .mouse_y = -1,
        .key = 0,
        .key_released = 0,
        .time = 0,
    };
    GlobalLinuxState.init() catch |err| {
        std.debug.print("Failed to init LinuxState: {any}\n", .{err});
        return 1;
    };
    defer GlobalLinuxState.deinit();

    // 44k seems to work better than 48k
    GlobalSoundBuffer.sample_rate = 44100;
    GlobalSoundBuffer.tone_volume = 0;
    GlobalSoundBuffer.channels = 2;
    GlobalSoundBuffer.fade_duration_ms = 20;
    GlobalSoundBuffer.buffer = arena.allocator().alloc(i16, GlobalSoundBuffer.get_buffer_size(@floatFromInt(X11RefreshRate))) catch unreachable;

    GlobalOffScreenBuffer.window_width = common.InitialWindowWidth;
    GlobalOffScreenBuffer.window_height = common.InitialWindowHeight;
    GlobalOffScreenBuffer.pitch = 0;

    var sample_spec = c.struct_pa_sample_spec{
        .format = c.PA_SAMPLE_S16LE,
        .channels = @intFromFloat(GlobalSoundBuffer.channels),
        .rate = @intFromFloat(GlobalSoundBuffer.sample_rate),
    };
    var buffer_attr = c.struct_pa_buffer_attr{
        .maxlength = math.maxInt(u32) - 1,
        .tlength = math.maxInt(u32) - 1,
        .prebuf = math.maxInt(u32) - 1,
        .minreq = @intCast(GlobalSoundBuffer.get_buffer_size(@floatFromInt(X11RefreshRate))),
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

    // Todo: get thread spawn count?
    var audio_thread_pool: thread.Pool = undefined;
    audio_thread_pool.init(.{ .allocator = arena.allocator() }) catch |err| {
        std.debug.print("Failed to initialize thread pool: {any}\n", .{err});
        return 1;
    };
    defer audio_thread_pool.deinit();

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

    const XRRScreenConf = c.XRRGetScreenInfo(display, window);
    const XRRCurrentRate = c.XRRConfigCurrentRate(XRRScreenConf);
    if (XRRCurrentRate > 0) {
        X11RefreshRate = @intCast(XRRCurrentRate);
        X11MsPerFrame = 1000 / X11RefreshRate;
    }

    const gc = c.XCreateGC(display, window, 0, null);

    var delete_atom: c.Atom = undefined;
    delete_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", 0);
    const protocol_status = c.XSetWMProtocols(display, window, &delete_atom, 1);
    if (protocol_status == 0) {
        std.debug.print("failed to set wm_delete protocol", .{});
        return 1;
    }

    _ = c.XStoreName(display, window, "Handmade");

    // events don't get triggered without masks
    _ = c.XSelectInput(
        display,
        window,
        c.KeyPressMask | c.KeyReleaseMask | c.StructureNotifyMask | c.PointerMotionMask | c.ButtonPressMask | c.ButtonReleaseMask,
    );

    _ = c.XMapWindow(display, window);

    // window will not show up without sync
    _ = c.XSync(display, 0);

    var game_lib = load_game_lib(arena.allocator()) catch |err| {
        std.debug.print("{any}\n", .{err});
        std.debug.print("Exiting\n", .{});
        return 1;
    };
    var dynamic_game_code = game_lib.lookup(
        GameUpdateAndRendererFn,
        "GameUpdateAndRenderer",
    );

    var quit = false;
    var event: c.XEvent = undefined;
    var start_time = time.milliTimestamp();
    var fps: i64 = 0;
    var time_per_frame: i64 = 0;
    var end_time: i64 = 0;
    while (!quit) {
        if (game_code_changed()) {
            game_lib.close();

            game_lib = load_game_lib(arena.allocator()) catch {
                return 1;
            };

            dynamic_game_code = game_lib.lookup(GameUpdateAndRendererFn, "GameUpdateAndRenderer");
        }

        while (c.XPending(display) > 0) {
            _ = c.XNextEvent(display, &event);
            switch (event.type) {
                c.KeyPress => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    if (keysym == c.XK_Escape) {
                        quit = true;
                        break;
                    } else if (keysym == 'l') {
                        if (!is_recording) {
                            is_recording = true;
                            run_playback = false;
                            std.debug.print("Recording input...\n", .{});
                        } else {
                            is_recording = false;
                            run_playback = true;

                            std.debug.print("Playback recording...\n", .{});
                        }
                    } else {
                        if (is_recording) {
                            GlobalLinuxState.game_input.key = @intCast(keysym);
                            write_linux_state(GlobalLinuxState);
                        } else {
                            GlobalLinuxState.game_input.key = @intCast(keysym);
                        }
                    }
                },
                c.KeyRelease => {
                    const keysym = c.XLookupKeysym(&event.xkey, 0);
                    GlobalLinuxState.game_input.key_released = @intCast(keysym);
                    GlobalLinuxState.game_input.key = 0;
                    GlobalLinuxState.game_input.time = @intCast(event.xkey.time);
                },
                c.ButtonRelease => {
                    std.debug.print("button release: {d}\n", .{event.xbutton.button});
                },
                c.ButtonPress => {
                    std.debug.print("button press: {d}\n", .{event.xbutton.button});
                },
                c.MotionNotify => {
                    GlobalLinuxState.game_input.mouse_x = @intCast(event.xmotion.x);
                    GlobalLinuxState.game_input.mouse_y = @intCast(event.xmotion.y);
                    std.debug.print("mouse x:{d} | mouse y: {d}\n", .{ event.xmotion.x, event.xmotion.y });
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
                    // Todo: currently window width and height is fixed, can be "streched" once
                    // prototyping is done
                },
                else => continue,
            }
        }

        if (dynamic_game_code) |dyn_gc| {
            if (run_playback) {
                read_linux_state(GlobalLinuxState) catch |err| {
                    std.debug.print("Failed to read playback file: {any}\n", .{err});
                    return 1;
                };
            }
            dyn_gc(game_memory, GlobalLinuxState.game_input, &GlobalOffScreenBuffer, &GlobalSoundBuffer);
        }

        // Todo: RDTSC() to get cycles/frame
        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;
        while (time_per_frame < X11MsPerFrame) {
            const sleep_time: u64 = @intCast(@divTrunc((X11MsPerFrame - time_per_frame), 1000));
            thread.sleep(sleep_time);

            end_time = time.milliTimestamp();
            time_per_frame = end_time - start_time;
        }

        render_game(
            &GlobalOffScreenBuffer,
            &GlobalSoundBuffer,
            &audio_thread_pool,
            audio_server,
            display,
            window,
            gc,
        );

        end_time = time.milliTimestamp();
        time_per_frame = end_time - start_time;

        assert(time_per_frame != 0);
        fps = @divTrunc(1000, time_per_frame);

        //std.debug.print("MsPerFrame: {d}\t FPS: {d}\t TargetFPS: {d}\n", .{
        //    time_per_frame,
        //    fps,
        //    X11RefreshRate,
        //});
        start_time = end_time;
    }

    game_lib.close();
    return 0;
}

// Todo: this won't work for higher fps
fn write_audio(server: ?*c.struct_pa_simple, sound_buffer: *common.SoundBuffer) void {
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
}

fn render_game(
    screen_buffer: *common.OffScreenBuffer,
    sound_buffer: *common.SoundBuffer,
    audio_thread_pool: *thread.Pool,
    audio_server: ?*c.struct_pa_simple,
    display: ?*c.Display,
    window: c.Window,
    gc: c.GC,
) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    audio_thread_pool.spawn(write_audio, .{ audio_server, sound_buffer }) catch |err| {
        std.debug.print("Failed to spawn audio thread: {any}\n", .{err});
        return;
    };

    const image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(&screen_buffer.memory),
        @intCast(screen_buffer.window_width),
        @intCast(screen_buffer.window_height),
        BitmapPad,
        0,
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(screen_buffer.window_width), @intCast(screen_buffer.window_height));
}

// Todo: read entire file at once
fn read_linux_state(linux_state: *common.LinuxState) !void {
    const current_pos = try linux_state.playback_file.?.getPos();
    const stat = try linux_state.playback_file.?.stat();

    if (current_pos == stat.size) {
        try linux_state.playback_file.?.seekTo(0);
    }

    var buffer: [@sizeOf(common.GameState) + @sizeOf(common.Input)]u8 = undefined;
    _ = linux_state.playback_file.?.read(&buffer) catch |err| {
        std.debug.print("Failed to read input: {any}\n", .{err});
    };

    linux_state.game_state.* = mem.bytesToValue(common.GameState, buffer[0..@sizeOf(common.GameState)]);
    linux_state.game_input.* = mem.bytesToValue(common.Input, buffer[@sizeOf(common.GameState)..]);
}

// Todo: write larger chunks of inputs at once instead of one at a time
fn write_linux_state(linux_state: *common.LinuxState) void {
    const buffer = mem.asBytes(linux_state.game_state) ++ mem.asBytes(linux_state.game_input);
    _ = linux_state.recording_file.?.write(buffer) catch |err| {
        std.debug.print("Failed to write input: {any}\n", .{err});
    };
}

fn game_code_changed() bool {
    const cwd = fs.cwd();

    const stat = cwd.statFile(GameCode) catch |err| {
        std.debug.print("Failed to get source object file stat. Will retry next frame. Error={any}\n", .{err});
        return false;
    };

    return stat.mtime != SourceModifiedAt;
}

fn copyFile(from: []const u8, to: []const u8) !void {
    const cwd = fs.cwd();

    try cwd.copyFile(from, cwd, to, .{});

    const stat = try cwd.statFile(GameCode);
    SourceModifiedAt = stat.mtime;
}

fn load_game_lib(allocator: mem.Allocator) !dyn_lib {
    var retry_attempt: u8 = 0;

    const cwd = fs.cwd();

    const build_result = build_lib(allocator, cwd) catch |err| {
        std.debug.print("{any}\n", .{err});
        return err;
    };

    if (build_result != 0) {
        return error.Error;
    }

    copyFile(SourceSo, TempSo) catch |err| {
        std.debug.print("Failed to copy handmade lib: {any}\n", .{err});
        return err;
    };

    const real_path = try fs.Dir.realpathAlloc(cwd, allocator, TempSo);

    var game_lib: ?dyn_lib = null;
    var lib_err: dyn_lib.Error = undefined;
    while (retry_attempt <= MaxRetryAttempt) : (retry_attempt += 1) {
        game_lib = dyn_lib.open(real_path) catch |err| {
            std.debug.print("Failed to load handmade lib: {any}\n", .{err});
            lib_err = err;

            // Todo: this might no longer be needed or exponential retry
            thread.sleep(1000000000);
            continue;
        };
        return game_lib.?;
    }

    return lib_err;
}

fn build_lib(allocator: mem.Allocator, cwd: fs.Dir) !u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig",
            "build-lib",
            GameCode,
            "-dynamic",
            // Todo: use some sort of sprintf
            "-femit-bin=game_source/libhandmade.so",
        },
        .cwd_dir = cwd,
    });

    return result.term.Exited;
}
