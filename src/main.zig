const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const git = @import("git.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // Parse arguments (handles --help and --version as special errors)
    const args = cli.parse(allocator) catch |err| {
        switch (err) {
            error.HelpRequested => {
                try cli.printHelp(stdout);
                return;
            },
            error.VersionRequested => {
                try cli.printVersion(stdout);
                return;
            },
            error.MissingProviderValue => {
                try stderr.print("Error: --provider requires a provider name\n", .{});
                std.process.exit(1);
            },
            error.MissingModelValue => {
                try stderr.print("Error: --model requires a model name\n", .{});
                std.process.exit(1);
            },
            else => {
                try stderr.print("Error parsing arguments: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            },
        }
    };
    defer cli.free(&args, allocator);

    // Handle debug logging of flags
    if (args.debug) {
        try stderr.print("Debug: Command={s}\n", .{@tagName(args.command)});
        if (args.command == .config) {
            try stderr.print("Debug: ConfigSubcommand={s}\n", .{@tagName(args.config_sub)});
        }
        try stderr.print("Debug: auto_add={}\n", .{args.auto_add});
        try stderr.print("Debug: auto_push={}\n", .{args.auto_push});
        try stderr.print("Debug: auto_accept={}\n", .{args.auto_accept});
        if (args.provider) |p| {
            try stderr.print("Debug: provider={s}\n", .{p});
        }
        if (args.model) |m| {
            try stderr.print("Debug: model={s}\n", .{m});
        }
        try stderr.print("\n", .{});
    }

    // Handle commands
    switch (args.command) {
        .config => {
            switch (args.config_sub) {
                .edit => try config.openInEditor(allocator),
                .show => try cli.printConfigInfo(allocator, stdout),
                .path => try cli.printConfigPath(allocator, stdout),
                .unknown => {
                    try stderr.print("Unknown config subcommand\nUsage: autocommit config [show|path]\n", .{});
                    std.process.exit(1);
                },
            }
            return;
        },
        .main => {
            // Continue to main commit generation logic
        },
    }

    // Main commit generation logic

    // Check git repo
    if (!git.isRepo()) {
        try stderr.print("Not a git repository. Run 'git init' first.\n", .{});
        std.process.exit(1);
    }

    // Load config
    const cfg = config.load(allocator) catch |err| {
        try stderr.print("Failed to load config: {s}. Run 'autocommit config' to create one.\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cfg.deinit(allocator);

    // Determine provider and model (CLI overrides config)
    const provider_name = args.provider orelse cfg.default_provider;

    // Get provider config based on name
    const provider_cfg = if (std.mem.eql(u8, provider_name, "zai"))
        cfg.providers.zai
    else if (std.mem.eql(u8, provider_name, "openai"))
        cfg.providers.openai
    else if (std.mem.eql(u8, provider_name, "groq"))
        cfg.providers.groq
    else {
        try stderr.print("Unknown provider: {s}\n", .{provider_name});
        std.process.exit(1);
    };

    const model_name = args.model orelse provider_cfg.model;

    if (args.debug) {
        try stderr.print("Debug: Using provider={s}, model={s}\n", .{ provider_name, model_name });
    }

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
        if (args.auto_add) {
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

    // TODO: Implement commit message generation
    // For now, just indicate what would happen
    if (args.auto_accept) {
        try stdout.print("\n{s}Auto-accept enabled - would commit without prompting{s}\n", .{ "\x1b[32m", "\x1b[0m" });
    } else {
        try stdout.print("\nWould prompt for commit message confirmation...\n", .{});
    }

    if (args.auto_push) {
        try stdout.print("{s}Auto-push enabled - would push after commit{s}\n", .{ "\x1b[32m", "\x1b[0m" });
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
}
