const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const WIDTH = 600;
const HEIGHT = 480;

pub fn shutdown(_: *c.GtkApplication, _: c.gpointer) callconv(.C) void {
    // Todo: for later use
    std.debug.print("shutdown\n", .{});
}

pub fn activate(app: *c.GtkApplication, _: c.gpointer) callconv(.C) void {
    const window = c.gtk_application_window_new(app);
    const window_cast: *c.GtkWindow = @ptrCast(window);

    c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(window)), "Handmade Hero");
    c.gtk_window_set_default_size(window_cast, WIDTH, HEIGHT);

    const header = c.gtk_header_bar_new();
    c.gtk_header_bar_set_title_widget(@as(*c.GtkHeaderBar, @ptrCast(header)), c.gtk_label_new("Handmade Hero"));
    c.gtk_window_set_titlebar(window_cast, header);

    c.gtk_window_present(@as(*c.GtkWindow, @ptrCast(window)));
}

pub fn main() !void {
    const app = c.gtk_application_new("handmade.hero.zig", 0);
    defer c.g_object_unref(app);

    const activate_handler_id = c.g_signal_connect_data(
        app,
        "activate",
        @as(c.GCallback, @ptrCast(&activate)),
        null,
        null,
        0,
    );
    defer c.g_signal_handler_disconnect(app, activate_handler_id);

    const shutdown_handler_id = c.g_signal_connect_data(
        app,
        "shutdown",
        @as(c.GCallback, @ptrCast(&shutdown)),
        null,
        null,
        0,
    );
    defer c.g_signal_handler_disconnect(app, shutdown_handler_id);

    _ = c.g_application_run(@as(*c.GApplication, @ptrCast(app)), 0, null);
}
