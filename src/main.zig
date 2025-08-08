const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
});

var Height: usize = 480;
var Width: usize = 600;

fn redraw(arena: *std.heap.ArenaAllocator, display: ?*c.Display, window: c.Window, gc: c.GC) void {
    var wa: c.XWindowAttributes = undefined;
    _ = c.XGetWindowAttributes(display, window, &wa);

    const bytes_per_pixel = @sizeOf(u32);
    const size: usize = Height * Width * bytes_per_pixel;

    // always true
    _ = arena.reset(.free_all);

    var pixels = arena.allocator().alloc(u32, size) catch unreachable;

    var pixel_idx: usize = 0;
    for (0..Height) |y| {
        pixel_idx = y * Width;

        for (0..Width) |x| {
            pixels[pixel_idx + x] = @intCast(x * y);
        }
    }

    var image = arena.allocator().create(c.XImage) catch unreachable;
    image = c.XCreateImage(
        display,
        wa.visual,
        @intCast(wa.depth),
        c.ZPixmap,
        0,
        @ptrCast(pixels),
        @intCast(Width),
        @intCast(Height),
        32,
        0,
    );

    _ = c.XPutImage(display, window, gc, image, 0, 0, 0, 0, @intCast(image.width), @intCast(image.height));
}

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

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
        @intCast(Width),
        @intCast(Height),
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
                c.KeyPress => std.debug.print("Key pressed, not sure which one.\n", .{}),
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
                    Height = @intCast(event.xconfigure.height);
                    Width = @intCast(event.xconfigure.width);

                    redraw(&arena, display, window, gc);
                },
                else => continue,
            }
        }

        redraw(&arena, display, window, gc);
    }

    return 0;
}
