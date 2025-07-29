const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
});

const WIDTH = 600;
const HEIGHT = 480;

pub fn activate(app: *c.GtkApplication, user_data: c.gpointer) callconv(.C) void {
    _ = user_data;

    const window = c.gtk_application_window_new(app);
    c.gtk_window_set_title(@as(*c.GtkWindow, @ptrCast(window)), "Handmade Hero");
    c.gtk_window_set_default_size(@as(*c.GtkWindow, @ptrCast(window)), WIDTH, HEIGHT);

    const header = c.gtk_header_bar_new();
    c.gtk_header_bar_set_title_widget(@as(*c.GtkHeaderBar, @ptrCast(header)), c.gtk_label_new("Handmade Hero"));
    c.gtk_window_set_titlebar(@as(*c.GtkWindow, @ptrCast(window)), header);

    c.gtk_window_present(@as(*c.GtkWindow, @ptrCast(window)));
}

pub fn main() !void {
    const app = c.gtk_application_new("handmade.hero.zig", 0);
    defer c.g_object_unref(app);

    _ = c.g_signal_connect_data(app, "activate", @as(c.GCallback, @ptrCast(&activate)), null, null, 0);
    _ = c.g_application_run(@as(*c.GApplication, @ptrCast(app)), 0, null);
}
