const std = @import("std");

pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const red = "\x1b[31m";
    pub const green = "\x1b[32m";
    pub const yellow = "\x1b[33m";
    pub const cyan = "\x1b[36m";
    pub const gray = "\x1b[90m";
    pub const magenta = "\x1b[35m";
};

pub fn printColor(writer: anytype, comptime color: []const u8, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("{s}" ++ fmt ++ "{s}", .{color} ++ args ++ .{Color.reset});
}

pub fn debug(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("{s}Debug:{s} " ++ fmt, .{ Color.yellow, Color.reset } ++ args);
}
