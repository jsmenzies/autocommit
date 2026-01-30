const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const git = @import("git.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try cli.parse(allocator);
    defer cli.free(&args, allocator);

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Handle commands
    switch (args.command) {
        .help => {
            try cli.printHelp(stdout);
            return;
        },
        .version => {
            try cli.printVersion(stdout);
            return;
        },
        .config => {
            switch (args.config_sub) {
                .edit => try config.openInEditor(allocator),
                .print => try cli.printConfigInfo(allocator, stdout),
                .unknown => {
                    try stderr.print("Unknown config subcommand\nUsage: autocommit config [print]\n", .{});
                    std.process.exit(1);
                },
            }
            return;
        },
        .generate => {},
        .unknown => {
            try stderr.print("Unknown command\n", .{});
            try cli.printHelp(stderr);
            std.process.exit(1);
        },
    }

    // Check git repo
    if (!git.isRepo()) {
        try stderr.print("Not a git repository. Run 'git init' first.\n", .{});
        std.process.exit(1);
    }

    // Load config for auto_add setting
    const cfg = config.load(allocator) catch |err| {
        try stderr.print("Failed to load config: {s}. Run 'autocommit config' to create one.\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cfg.deinit(allocator);

    // Print a blank line before starting CLI output for easier reading
    try stdout.print("\n", .{});

    // Get git status
    var status = git.getStatus(allocator) catch {
        try stderr.print("Failed to get git status\n", .{});
        std.process.exit(1);
    };
    defer status.deinit();

    // Print git status with colors
    var has_changes = git.printGitStatus(stderr, &status) catch {
        try stderr.print("Failed to print git status\n", .{});
        std.process.exit(1);
    };

    if (!has_changes) {
        std.process.exit(0);
    }

    // Check for unstaged/untracked files
    const addable_count = git.unstagedAndUntrackedCount(&status);
    if (addable_count > 0) {
        if (cfg.auto_add) {
            // Auto-add enabled - add files automatically
            try stdout.print("\n{s}Auto-adding {d} file(s)...{s}\n", .{ "\x1b[32m", addable_count, "\x1b[0m" });
            git.addAll(allocator) catch {
                try stderr.print("Failed to add files\n", .{});
                std.process.exit(1);
            };
            try stdout.print("\n", .{});

            // Re-fetch and print updated status
            status.deinit();
            status = git.getStatus(allocator) catch {
                try stderr.print("Failed to get updated git status\n", .{});
                std.process.exit(1);
            };

            has_changes = git.printGitStatus(stderr, &status) catch {
                try stderr.print("Failed to print updated git status\n", .{});
                std.process.exit(1);
            };
        } else {
            // Ask user if they want to add files
            try stdout.print("\n{d} file(s) can be added. Add them? [Y/n] ", .{addable_count});

            var input_buffer: [10]u8 = undefined;
            const stdin = std.io.getStdIn().reader();
            const input = stdin.readUntilDelimiterOrEof(&input_buffer, '\n') catch null;

            // Default to yes (Y) if input is empty or 'y'/'Y'
            var should_add = true;
            if (input) |line| {
                const trimmed = std.mem.trim(u8, line, " \r\t");
                if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N")) {
                    should_add = false;
                }
                // Empty or anything else defaults to yes
            }

            if (should_add) {
                // User said yes - add files with green color
                try stdout.print("{s}Adding {d} file(s)...{s}\n", .{ "\x1b[32m", addable_count, "\x1b[0m" });
                git.addAll(allocator) catch {
                    try stderr.print("Failed to add files\n", .{});
                    std.process.exit(1);
                };

                // Re-fetch and print updated status
                status.deinit();
                status = git.getStatus(allocator) catch {
                    try stderr.print("Failed to get updated git status\n", .{});
                    std.process.exit(1);
                };

                try stdout.print("\n", .{});
                has_changes = git.printGitStatus(stderr, &status) catch {
                    try stderr.print("Failed to print updated git status\n", .{});
                    std.process.exit(1);
                };
            }
        }
    }

    // Check if we have staged changes to work with
    if (status.stagedCount() == 0) {
        try stdout.print("\nNo staged changes to commit.\n", .{});
        std.process.exit(0);
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
}
