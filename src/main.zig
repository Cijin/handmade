const std = @import("std");
const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
});

const Width = 600;
const Height = 480;
const WindowName: c_char = "Yellow";
const IconName = "X Window";

pub fn main() !u8 {
    // On a POSIX-conformant system, if the display_name is NULL, it defaults to the value of the DISPLAY environment variable.
    const display = c.XOpenDisplay(null) orelse {
        std.debug.print("failed to open display", .{});

        return 1;
    };
    defer c.XCloseDisplay(display);

    const screen = c.XDefaultScreen(display);
    const display_width = c.XDisplayWidth(display, screen);
    const display_height = c.XDisplayHeight(display, screen);

    const x: u16 = 0;
    const y: u16 = 0;
    const f: c_int = 3;
    const w = @divTrunc(display_width, f);
    const h = @divTrunc(display_height, f);
    const border_width: c_uint = 0;

    const window_parent = c.XRootWindow(display, screen);
    const window = c.XCreateSimpleWindow(
        display,
        window_parent,
        x,
        y,
        @intCast(w),
        @intCast(h),
        border_width,
        c.XBlackPixel(display, screen),
        c.XWhitePixel(display, screen),
    );
    defer c.XDestroyWindow(display, window);

    var window_name: c.XTextProperty = undefined;
    var icon_name: c.XTextProperty = undefined;
    if (c.XStringListToTextProperty(WindowName, 1, &window_name) == 0) {
        std.debug.print("structure allocation failed for window name", .{});

        return 1;
    }

    if (c.XStringListToTextProperty(&IconName, 1, &icon_name) == 0) {
        std.debug.print("structure allocation failed for window name", .{});

        return 1;
    }

    _ = c.XMapWindow(display, window);

    while (true) {}

    return 0;
}
