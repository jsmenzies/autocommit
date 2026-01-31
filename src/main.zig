const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const http_client = @import("http_client.zig");
const llm = @import("llm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

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
            else => {
                try stderr.print("Error parsing arguments: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            },
        }
    };

    defer cli.free(&args, allocator);

    // Handle debug logging of flags
    if (args.debug) {
        try printDebugInfo(&args, stderr);
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

    if (!git.isRepo()) {
        try stderr.print("Not a git repository. Run 'git init' first.\n", .{});
        std.process.exit(1);
    }

    const cfg = config.load(allocator) catch |err| {
        try stderr.print("Failed to load config: {s}. Run 'autocommit config' to create one.\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer cfg.deinit(allocator);

    const provider_name = args.provider orelse cfg.default_provider;

    const provider_cfg = cfg.getProvider(provider_name) catch |err| {
        switch (err) {
            error.UnknownProvider => {
                try stderr.print("Unknown provider: {s}\n", .{provider_name});
                std.process.exit(1);
            },
        }
    };

    if (args.debug) {
        try stderr.print("Debug: Using provider={s}, model={s}\n", .{ provider_name, provider_cfg.model });
    }

    try stdout.print("\n", .{});

    var status = git.getStatus(allocator) catch {
        try stderr.print("Failed to get git status\n", .{});
        std.process.exit(1);
    };
    defer status.deinit();

    var has_changes = git.printGitStatus(stderr, &status) catch {
        try stderr.print("Failed to print git status\n", .{});
        std.process.exit(1);
    };

    if (!has_changes) {
        std.process.exit(0);
    }

    const addable_count = git.unstagedAndUntrackedCount(&status);
    if (addable_count > 0) {
        if (args.auto_add) {
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
            try stdout.print("\n{d} file(s) can be added. Add them? [Y/n] ", .{addable_count});

            var input_buffer: [10]u8 = undefined;
            const stdin = std.io.getStdIn().reader();
            const input = stdin.readUntilDelimiterOrEof(&input_buffer, '\n') catch null;

            var should_add = true;
            if (input) |line| {
                const trimmed = std.mem.trim(u8, line, " \r\t");
                if (std.mem.eql(u8, trimmed, "n") or std.mem.eql(u8, trimmed, "N")) {
                    should_add = false;
                }
            }

            if (should_add) {
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

    if (status.stagedCount() == 0) {
        try stdout.print("\nNo staged changes to commit.\n", .{});
        std.process.exit(0);
    }

    var http = http_client.HttpClient.init(allocator);
    defer http.deinit();

    var provider = llm.createProvider(allocator, provider_name, provider_cfg.*, &http) catch |err| {
        try stderr.print("Failed to create provider: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer llm.destroyProvider(&provider, allocator);

    const diff = try getStagedDiff(allocator);
    defer allocator.free(diff);

    if (args.debug) {
        try stderr.print("Debug: Diff size: {d} bytes\n", .{diff.len});
    }

    const max_diff_size = 100 * 1024;
    const truncated_diff = if (diff.len > max_diff_size)
        try std.fmt.allocPrint(allocator, "{s}\n... (truncated)", .{diff[0..max_diff_size]})
    else
        try allocator.dupe(u8, diff);
    defer allocator.free(truncated_diff);

    // Generate commit message
    var commit_message: []const u8 = undefined;
    var needs_regeneration = true;

    while (needs_regeneration) {
        if (args.debug) {
            try stderr.print("Debug: Generating commit message...\n", .{});
        }

        commit_message = provider.generateCommitMessage(truncated_diff, cfg.system_prompt) catch |err| {
            const error_message = switch (err) {
                llm.LlmError.InvalidApiKey => "Invalid API key. Check your config file.",
                llm.LlmError.RateLimited => "Rate limit exceeded. Please try again later.",
                llm.LlmError.ServerError => "Server error. Please try again later.",
                llm.LlmError.Timeout => "Request timed out. Check your internet connection.",
                llm.LlmError.InvalidResponse => "Invalid response from API.",
                llm.LlmError.EmptyContent => "LLM returned empty message.",
                llm.LlmError.ApiError => "API error occurred.",
                llm.LlmError.OutOfMemory => "Out of memory.",
            };
            if (args.debug) {
                try stderr.print("Debug: LLM error: {s}\n", .{@errorName(err)});
            }
            try stderr.print("Error: {s}\n", .{error_message});
            std.process.exit(1);
        };

        needs_regeneration = false;
    }

    // Commit the changes
    try stdout.print("\n{s}Committing...{s}\n", .{ "\x1b[32m", "\x1b[0m" });
    try commitChanges(allocator, commit_message);
    try stdout.print("{s}Committed successfully!{s}\n", .{ "\x1b[32m", "\x1b[0m" });

    // Push if enabled
    if (args.auto_push) {
        try stdout.print("{s}Pushing...{s}\n", .{ "\x1b[32m", "\x1b[0m" });
        try pushChanges(allocator);
        try stdout.print("{s}Pushed successfully!{s}\n", .{ "\x1b[32m", "\x1b[0m" });
    }

    allocator.free(commit_message);
}

fn getStagedDiff(allocator: std.mem.Allocator) ![]const u8 {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "diff", "--cached" },
        .max_output_bytes = 10 * 1024 * 1024, // 10MB max
    }) catch return error.GitCommandFailed;

    if (result.term.Exited != 0) {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
        return error.GitCommandFailed;
    }

    allocator.free(result.stderr);
    return result.stdout;
}

fn commitChanges(allocator: std.mem.Allocator, message: []const u8) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "commit", "-m", message },
        .max_output_bytes = 10 * 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }
}

fn pushChanges(allocator: std.mem.Allocator) !void {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "push" },
        .max_output_bytes = 10 * 1024,
    }) catch return error.GitCommandFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term.Exited != 0) {
        return error.GitCommandFailed;
    }
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
    _ = @import("http_client.zig");
    _ = @import("llm.zig");
}

fn printDebugInfo(args: *const cli.Args, stderr: anytype) !void {
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
    try stderr.print("\n", .{});
}
