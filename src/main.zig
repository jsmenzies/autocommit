const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const http_client = @import("http_client.zig");
const llm = @import("llm.zig");

/// Print a debug message with "Debug:" prefix in yellow
pub fn debug(writer: anytype, comptime fmt: []const u8, args: anytype) !void {
    try writer.print("{s}Debug:{s} " ++ fmt, .{ "\x1b[33m", "\x1b[0m" } ++ args);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr();
    const stderr = stderr_file.writer();

    // Create debug callback that writes to stderr
    const debug_log = struct {
        fn call(ctx: ?*anyopaque, message: []const u8) void {
            const file: *std.fs.File = @ptrCast(@alignCast(ctx orelse return));
            _ = file.writer().print("{s}Debug:{s} {s}\n", .{ "\x1b[33m", "\x1b[0m", message }) catch {};
        }
    }.call;

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
        try debug(stderr, "provider={s}, model={s}\n", .{ provider_name, provider_cfg.model });
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

            has_changes = refreshStatus(allocator, &status, stderr) catch {
                try stderr.print("Failed to refresh git status\n", .{});
                std.process.exit(1);
            };
        } else {
            try stdout.print("\n{d} file(s) can be added. Add them? [{s}Y/n{s}] ", .{ addable_count, "\x1b[32m", "\x1b[0m" });

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

                try stdout.print("\n", .{});
                has_changes = refreshStatus(allocator, &status, stderr) catch {
                    try stderr.print("Failed to refresh git status\n", .{});
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

    var provider = llm.createProvider(
        allocator,
        provider_name,
        provider_cfg.*,
        &http,
        if (args.debug) debug_log else null,
        if (args.debug) @ptrCast(@constCast(&stderr_file)) else null,
    ) catch |err| {
        try stderr.print("Failed to create provider: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer llm.destroyProvider(&provider, allocator);

    const diff = try git.getStagedDiff(allocator);
    defer allocator.free(diff);

    if (args.debug) {
        try stdout.print("\n", .{});
        try debug(stderr, "Diff size: {d} bytes\n", .{diff.len});
    }

    const max_diff_size = 100 * 1024;
    const truncated_diff = try git.truncateDiff(allocator, diff, max_diff_size);
    defer allocator.free(truncated_diff);

    // Generate commit message (debug logging handled internally by llm module when debug is enabled)
    const commit_message = provider.generateCommitMessage(truncated_diff, cfg.system_prompt) catch |err| {
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
        try stderr.print("Error: {s}\n", .{error_message});
        std.process.exit(1);
    };

    try stdout.print("\n{s}Generated commit message:{s}\n{s}{s}{s}\n", .{ "\x1b[1m", "\x1b[0m", "\x1b[36m", commit_message, "\x1b[0m" });

    if (!args.auto_accept) {
        const should_commit = try confirmCommit(stdout, stderr);
        if (!should_commit) {
            allocator.free(commit_message);
            try stdout.print("\n{s}Aborted, no commit made.{s}\n", .{ "\x1b[33m", "\x1b[0m" });
            std.process.exit(0);
        }
    } else {
        try stdout.print("\n{s}Auto-accept enabled, committing...{s}\n", .{ "\x1b[33m", "\x1b[0m" });
    }

    try stdout.print("\n{s}Committing...{s}\n", .{ "\x1b[32m", "\x1b[0m" });
    try git.commit(allocator, commit_message);
    try stdout.print("{s}Committed successfully!{s}\n", .{ "\x1b[32m", "\x1b[0m" });

    var should_push = args.auto_push;
    if (args.debug) {
        try debug(stderr, "auto_push flag={}, should_push={}\n", .{ args.auto_push, should_push });
    }

    if (!should_push) {
        should_push = try confirmPush(stdout, stderr);
    } else if (args.debug) {
        try debug(stderr, "Auto-push enabled, skipping prompt\n", .{});
    }

    if (should_push) {
        try stdout.print("{s}Pushing...{s}\n", .{ "\x1b[32m", "\x1b[0m" });
        if (git.push(allocator)) {
            try stdout.print("{s}Pushed successfully!{s}\n", .{ "\x1b[32m", "\x1b[0m" });
        } else |err| {
            try stderr.print("{s}Warning: Push failed: {s}{s}\n", .{ "\x1b[33m", @errorName(err), "\x1b[0m" });
            // Don't exit - commit succeeded, just push failed
        }
    } else if (args.debug) {
        try debug(stderr, "Push skipped\n", .{});
    }

    allocator.free(commit_message);
}

test {
    _ = @import("cli.zig");
    _ = @import("config.zig");
    _ = @import("git.zig");
    _ = @import("http_client.zig");
    _ = @import("llm.zig");
}

fn printDebugInfo(args: *const cli.Args, stderr: anytype) !void {
    try debug(stderr, "Command={s}\n", .{@tagName(args.command)});
    if (args.command == .config) {
        try debug(stderr, "ConfigSubcommand={s}\n", .{@tagName(args.config_sub)});
    }
    try debug(stderr, "auto_add={}\n", .{args.auto_add});
    try debug(stderr, "auto_push={}\n", .{args.auto_push});
    try debug(stderr, "auto_accept={}\n", .{args.auto_accept});
    if (args.provider) |p| {
        try debug(stderr, "provider={s}\n", .{p});
    }
}

fn refreshStatus(allocator: std.mem.Allocator, status: *git.GitStatus, writer: anytype) !bool {
    status.deinit();
    status.* = try git.getStatus(allocator);
    return git.printGitStatus(writer, status);
}

/// Simple confirmation prompt - returns true to commit, false to abort
fn confirmCommit(stdout: anytype, stderr: anytype) !bool {
    const stdin = std.io.getStdIn().reader();

    try stdout.print("\n{s}Proceed with commit?{s} [{s}Y/n{s}] ", .{ "\x1b[1m", "\x1b[0m", "\x1b[32m", "\x1b[0m" });

    var input_buffer: [10]u8 = undefined;
    const input = stdin.readUntilDelimiterOrEof(&input_buffer, '\n') catch |err| {
        try stderr.print("Error reading input: {s}\n", .{@errorName(err)});
        return false;
    };

    if (input) |line| {
        const choice = std.mem.trim(u8, line, " \r\t");
        // Default to yes (empty or 'y'/'Y')
        return choice.len == 0 or std.mem.eql(u8, choice, "y") or std.mem.eql(u8, choice, "Y");
    }

    // EOF - treat as abort
    return false;
}

/// Ask user if they want to push - returns true to push, false to skip
fn confirmPush(stdout: anytype, stderr: anytype) !bool {
    const stdin = std.io.getStdIn().reader();

    try stdout.print("\n{s}Push to remote?{s} [{s}Y/n{s}] ", .{ "\x1b[1m", "\x1b[0m", "\x1b[32m", "\x1b[0m" });

    var input_buffer: [10]u8 = undefined;
    const input = stdin.readUntilDelimiterOrEof(&input_buffer, '\n') catch |err| {
        try stderr.print("Error reading input: {s}\n", .{@errorName(err)});
        return false;
    };

    if (input) |line| {
        const choice = std.mem.trim(u8, line, " \r\t");
        // Default to yes (empty or 'y'/'Y')
        return choice.len == 0 or std.mem.eql(u8, choice, "y") or std.mem.eql(u8, choice, "Y");
    }

    // EOF - treat as yes (push by default)
    return true;
}
