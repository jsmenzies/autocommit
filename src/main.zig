const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");
const git = @import("git.zig");
const http_client = @import("http_client.zig");
const llm = @import("llm.zig");
const colors = @import("colors.zig");
const Color = colors.Color;

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
            _ = file.writer().print("{s}Debug:{s} {s}\n", .{ Color.yellow, Color.reset, message }) catch {};
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
        try colors.debug(stderr, "provider={s}, model={s}\n", .{ provider_name, provider_cfg.model });
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
            try stdout.print("\n{s}Auto-adding {d} file(s)...{s}\n", .{ Color.green, addable_count, Color.reset });
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
            var prompt_buf: [64]u8 = undefined;
            const prompt = try std.fmt.bufPrint(&prompt_buf, "\n{d} file(s) can be added. Add them?", .{addable_count});
            const should_add = try confirmYesNo(stdout, stderr, prompt, true);

            if (should_add) {
                try stdout.print("{s}Adding {d} file(s)...{s}\n", .{ Color.green, addable_count, Color.reset });
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
        try colors.debug(stderr, "Diff size: {d} bytes\n", .{diff.len});
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

    try stdout.print("\n{s}Generated commit message:{s}\n{s}{s}{s}\n", .{ Color.bold, Color.reset, Color.cyan, commit_message, Color.reset });

    if (!args.auto_accept) {
        var commit_prompt_buf: [64]u8 = undefined;
        const commit_prompt = try std.fmt.bufPrint(&commit_prompt_buf, "\n{s}Proceed with commit?{s}", .{ Color.bold, Color.reset });
        const should_commit = try confirmYesNo(stdout, stderr, commit_prompt, false);
        if (!should_commit) {
            allocator.free(commit_message);
            try stdout.print("\n{s}Aborted, no commit made.{s}\n", .{ Color.yellow, Color.reset });
            std.process.exit(0);
        }
    } else {
        try stdout.print("\n{s}Auto-accept enabled, committing...{s}\n", .{ Color.yellow, Color.reset });
    }

    try stdout.print("\n{s}Committing...{s}\n", .{ Color.green, Color.reset });
    try git.commit(allocator, commit_message);
    try stdout.print("{s}Committed successfully!{s}\n", .{ Color.green, Color.reset });

    var should_push = args.auto_push;
    if (args.debug) {
        try colors.debug(stderr, "auto_push flag={}, should_push={}\n", .{ args.auto_push, should_push });
    }

    if (!should_push) {
        var push_prompt_buf: [64]u8 = undefined;
        const push_prompt = try std.fmt.bufPrint(&push_prompt_buf, "\n{s}Push to remote?{s}", .{ Color.bold, Color.reset });
        should_push = try confirmYesNo(stdout, stderr, push_prompt, true);
    } else if (args.debug) {
        try colors.debug(stderr, "Auto-push enabled, skipping prompt\n", .{});
    }

    if (should_push) {
        try stdout.print("{s}Pushing...{s}\n", .{ Color.green, Color.reset });
        if (git.push(allocator)) {
            try stdout.print("{s}Pushed successfully!{s}\n", .{ Color.green, Color.reset });
        } else |err| {
            try stderr.print("{s}Warning: Push failed: {s}{s}\n", .{ Color.yellow, @errorName(err), Color.reset });
            // Don't exit - commit succeeded, just push failed
        }
    } else if (args.debug) {
        try colors.debug(stderr, "Push skipped\n", .{});
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
    try colors.debug(stderr, "Command={s}\n", .{@tagName(args.command)});
    if (args.command == .config) {
        try colors.debug(stderr, "ConfigSubcommand={s}\n", .{@tagName(args.config_sub)});
    }
    try colors.debug(stderr, "auto_add={}\n", .{args.auto_add});
    try colors.debug(stderr, "auto_push={}\n", .{args.auto_push});
    try colors.debug(stderr, "auto_accept={}\n", .{args.auto_accept});
    if (args.provider) |p| {
        try colors.debug(stderr, "provider={s}\n", .{p});
    }
}

fn refreshStatus(allocator: std.mem.Allocator, status: *git.GitStatus, writer: anytype) !bool {
    status.deinit();
    status.* = try git.getStatus(allocator);
    return git.printGitStatus(writer, status);
}

/// Generic Y/n confirmation prompt
/// Returns true for yes (empty, y, Y), false for no (n, N, error, EOF)
fn confirmYesNo(
    stdout: anytype,
    stderr: anytype,
    prompt: []const u8,
    default_on_eof: bool,
) !bool {
    try stdout.print("{s} [{s}Y/n{s}] ", .{ prompt, Color.green, Color.reset });

    var input_buffer: [10]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    const input = stdin.readUntilDelimiterOrEof(&input_buffer, '\n') catch |err| {
        try stderr.print("Error reading input: {s}\n", .{@errorName(err)});
        return false;
    };

    if (input) |line| {
        const choice = std.mem.trim(u8, line, " \r\t");
        return choice.len == 0 or std.mem.eql(u8, choice, "y") or std.mem.eql(u8, choice, "Y");
    }

    return default_on_eof;
}
