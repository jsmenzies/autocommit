const std = @import("std");

pub const GitError = error{
    NotARepo,
    GitCommandFailed,
};

/// Check if current directory is a git repository
pub fn isRepo() bool {
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "git", "rev-parse", "--git-dir" },
        .max_output_bytes = 1024,
    }) catch return false;
    defer {
        std.heap.page_allocator.free(result.stdout);
        std.heap.page_allocator.free(result.stderr);
    }
    return result.term.Exited == 0;
}

/// Print formatted git status
pub fn printGitStatus(writer: anytype) !bool {
    // Get git status --short
    const result = std.process.Child.run(.{
        .allocator = std.heap.page_allocator,
        .argv = &[_][]const u8{ "git", "status", "--short" },
        .max_output_bytes = 10 * 1024 * 1024,
    }) catch return error.GitCommandFailed;
    defer std.heap.page_allocator.free(result.stdout);
    defer std.heap.page_allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }

    const green = "\x1b[32m";
    const red = "\x1b[31m";
    const yellow = "\x1b[33m";
    const reset = "\x1b[0m";

    var has_untracked = false;
    var has_unstaged = false;
    var has_staged = false;

    // First pass - check what we have
    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len < 3) continue;
        const staged = line[0];
        const unstaged = line[1];

        if (staged == 'A' or staged == 'M' or staged == 'D') {
            has_staged = true;
        }
        if (unstaged == '?') {
            has_untracked = true;
        } else if (unstaged == 'M' or unstaged == 'D') {
            has_unstaged = true;
        }
    }

    if (!has_untracked and !has_unstaged and !has_staged) {
        try writer.print("No changes to commit\n", .{});
        return false;
    }

    var first_section = true;

    // Print untracked files
    if (has_untracked) {
        try writer.print("Untracked:\n", .{});
        iter = std.mem.splitScalar(u8, result.stdout, '\n');
        while (iter.next()) |line| {
            if (line.len < 3) continue;
            const staged = line[0];
            const unstaged = line[1];
            const filename = line[3..];

            if (staged == '?' and unstaged == '?') {
                try writer.print("  {s}?{s} {s}\n", .{ red, reset, filename });
            }
        }
        first_section = false;
    }

    // Print unstaged changes
    if (has_unstaged) {
        if (!first_section) {
            try writer.print("\n", .{});
        }
        try writer.print("Unstaged:\n", .{});
        iter = std.mem.splitScalar(u8, result.stdout, '\n');
        while (iter.next()) |line| {
            if (line.len < 3) continue;
            const unstaged = line[1];
            const filename = line[3..];

            // Show any file with unstaged M or D
            if (unstaged == 'M' or unstaged == 'D') {
                try writer.print("  {s}{c}{s} {s}\n", .{ yellow, unstaged, reset, filename });
            }
        }
        first_section = false;
    }

    // Print staged changes
    if (has_staged) {
        if (!first_section) {
            try writer.print("\n", .{});
        }
        try writer.print("Staged:\n", .{});
        iter = std.mem.splitScalar(u8, result.stdout, '\n');
        while (iter.next()) |line| {
            if (line.len < 3) continue;
            const staged = line[0];
            const filename = line[3..];

            if (staged == 'A' or staged == 'M' or staged == 'D') {
                try writer.print("  {s}{c}{s} {s}\n", .{ green, staged, reset, filename });
            }
        }
        first_section = false;
    }

    return true;
}

test "isRepo detects git repository" {
    try std.testing.expect(isRepo());
}
