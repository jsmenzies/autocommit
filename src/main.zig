const std = @import("std");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("autocommit v0.1.0 (zig)\n", .{});
}
