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

    // Print git status with colors and exit
    const has_changes = git.printGitStatus(stderr) catch {
        try stderr.print("Failed to get git status\n", .{});
        std.process.exit(1);
    };

    if (!has_changes) {
        std.process.exit(0);
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
}
