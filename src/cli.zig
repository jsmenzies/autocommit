const std = @import("std");
const config = @import("config.zig");
const build_options = @import("build_options");

pub const Command = enum {
    main, // Default: generate commit message
    config,
};

pub const ConfigSubcommand = enum {
    edit, // Default when no subcommand given
    show,
    path,
    unknown,
};

pub const Args = struct {
    command: Command = .main,
    config_sub: ConfigSubcommand = .edit,
    auto_add: bool = false,
    auto_push: bool = false,
    auto_accept: bool = false,
    provider: ?[]const u8 = null,
    model: ?[]const u8 = null,
    debug: bool = false,
};

pub fn parse(allocator: std.mem.Allocator) !Args {
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var result = Args{};

    if (args.len <= 1) {
        return result;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        // Check for commands first
        if (std.mem.eql(u8, arg, "--help")) {
            // Just set a flag to indicate help was requested
            // Caller will handle this
            result.command = .main; // Stay in main mode, but we'll check for --help in main
            // We need a way to signal help was requested
            // For now, let's use a special approach
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--version")) {
            return error.VersionRequested;
        } else if (std.mem.eql(u8, arg, "config")) {
            result.command = .config;
            // Check for config subcommand
            if (i + 1 < args.len) {
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "show")) {
                    result.config_sub = .show;
                    i += 1;
                } else if (std.mem.eql(u8, sub, "path")) {
                    result.config_sub = .path;
                    i += 1;
                } else if (std.mem.eql(u8, sub, "edit")) {
                    result.config_sub = .edit;
                    i += 1;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    // Unknown subcommand
                    result.config_sub = .unknown;
                    i += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "--add")) {
            result.auto_add = true;
        } else if (std.mem.eql(u8, arg, "--push")) {
            result.auto_push = true;
        } else if (std.mem.eql(u8, arg, "--accept")) {
            result.auto_accept = true;
        } else if (std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingProviderValue;
            }
            result.provider = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--model")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingModelValue;
            }
            result.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--debug")) {
            result.debug = true;
        }
        // Ignore unknown arguments for now
    }

    return result;
}

pub fn printHelp(writer: anytype) !void {
    const help_text =
        \\autocommit - AI-powered conventional commit message generator
        \\
        \\Usage:
        \\  autocommit [options]              # Generate commit message for staged changes
        \\  autocommit config [subcommand]    # Manage configuration
        \\
        \\Commands:
        \\  config              Open configuration file in $EDITOR
        \\  config show         Display current configuration
        \\  config path         Show configuration file path
        \\
        \\Options:
        \\  --add               Auto-add all unstaged files before committing
        \\  --push              Auto-push after committing
        \\  --accept            Auto-accept generated commit message without prompting
        \\  --provider <name>   Override provider (zai, openai, groq)
        \\  --model <name>      Override model
        \\  --debug             Enable debug output
        \\  --version           Show version information
        \\  --help              Show this help message
        \\
        \\Examples:
        \\  autocommit                          # Generate commit message interactively
        \\  autocommit --add --accept --push    # Full automation (add, accept, push)
        \\  autocommit --provider groq          # Use specific provider
        \\  autocommit config                   # Edit configuration
        \\  autocommit config show              # Display current config
        \\
    ;

    try writer.print("{s}", .{help_text});
}

pub fn printVersion(writer: anytype) !void {
    try writer.print("autocommit {s} (zig)\n", .{build_options.version});
}

// Helper to check if API key is actually set (not a placeholder)
fn checkApiKeySet(provider_name: []const u8, api_key: []const u8) bool {
    if (api_key.len == 0) return false;

    // Check for placeholder pattern: "your-{provider}-api-key-here"
    const prefix = "your-";
    const suffix = "-api-key-here";

    if (api_key.len < prefix.len + provider_name.len + suffix.len) {
        return true; // Too short to be the placeholder
    }

    const is_placeholder = std.mem.startsWith(u8, api_key, prefix) and
        std.mem.endsWith(u8, api_key, suffix) and
        std.mem.containsAtLeast(u8, api_key, 1, provider_name);

    return !is_placeholder;
}

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
    const bold = "\x1b[1m";
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const cyan = "\x1b[36m";
    const gray = "\x1b[90m";
    const magenta = "\x1b[35m";
};

pub fn printConfigInfo(allocator: std.mem.Allocator, writer: anytype) !void {
    // Get config path
    const config_path = config.getConfigPath(allocator) catch |err| {
        try writer.print("Error getting config path: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(config_path);

    try writer.print("{s}Configuration:{s}\n", .{ Color.bold, Color.reset });
    try writer.print("  Path: {s}{s}{s}\n", .{ Color.cyan, config_path, Color.reset });

    // Check if file exists
    const file_exists = blk: {
        std.fs.accessAbsolute(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!file_exists) {
        try writer.print("  Status: {s}Not created{s} (run 'autocommit config' to create)\n", .{ Color.red, Color.reset });
        return;
    }

    try writer.print("  Status: {s}Exists{s}\n", .{ Color.green, Color.reset });

    // Load and display config info
    const cfg = config.load(allocator) catch |err| {
        try writer.print("  Error loading config: {s}\n", .{@errorName(err)});
        return;
    };
    defer cfg.deinit(allocator);

    try writer.print("\n{s}Current Settings:{s}\n", .{ Color.bold, Color.reset });
    try writer.print("  Default Provider: {s}{s}{s}\n", .{ Color.cyan, cfg.default_provider, Color.reset });

    try writer.print("  {s}System Prompt:{s}\n{s}{s}{s}\n", .{ Color.bold, Color.reset, Color.magenta, cfg.system_prompt, Color.reset });

    // Show provider info
    try writer.print("\n{s}Providers:{s}\n", .{ Color.bold, Color.reset });

    const providers = [_]struct { name: []const u8, cfg: config.ProviderConfig }{
        .{ .name = "zai", .cfg = cfg.providers.zai },
        .{ .name = "openai", .cfg = cfg.providers.openai },
        .{ .name = "groq", .cfg = cfg.providers.groq },
    };

    for (providers) |p| {
        const is_default = std.mem.eql(u8, cfg.default_provider, p.name);

        // Check if API key is set (not a placeholder and not empty)
        const api_set = checkApiKeySet(p.name, p.cfg.api_key);

        // Provider name with default marker in yellow
        if (is_default) {
            try writer.print("  {s}{s}{s} {s}(default){s}:\n", .{ Color.cyan, p.name, Color.reset, Color.yellow, Color.reset });
        } else {
            try writer.print("  {s}{s}{s}:\n", .{ Color.gray, p.name, Color.reset });
        }

        // Model (always shown in normal color)
        try writer.print("    Model: {s}\n", .{p.cfg.model});

        // API Key with color coding
        if (api_set) {
            try writer.print("    API Key: {s}✓ set{s}\n", .{ Color.green, Color.reset });
        } else {
            try writer.print("    API Key: {s}✗ not set{s}\n", .{ Color.red, Color.reset });
        }
    }
}

pub fn printConfigPath(allocator: std.mem.Allocator, writer: anytype) !void {
    const config_path = config.getConfigPath(allocator) catch |err| {
        try writer.print("Error getting config path: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(config_path);

    try writer.print("{s}Configuration:{s}\n", .{ Color.bold, Color.reset });
    try writer.print("  Path: {s}{s}{s}\n", .{ Color.cyan, config_path, Color.reset });

    // Check if file exists
    const file_exists = blk: {
        std.fs.accessAbsolute(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!file_exists) {
        try writer.print("  Status: {s}Not created{s} (run 'autocommit config' to create)\n", .{ Color.red, Color.reset });
        return;
    }

    try writer.print("  Status: {s}Exists{s}\n", .{ Color.green, Color.reset });
}

// Free any allocated memory in Args
pub fn free(args: *const Args, allocator: std.mem.Allocator) void {
    if (args.provider) |provider| {
        allocator.free(provider);
    }
    if (args.model) |model| {
        allocator.free(model);
    }
}

// Error types for special handling
pub const ParseError = error{
    HelpRequested,
    VersionRequested,
    MissingProviderValue,
    MissingModelValue,
};

// Test section
test "parse with no arguments defaults to main" {
    const test_args = &[_][]const u8{"autocommit"};
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.main, result.command);
    try std.testing.expect(!result.debug);
    try std.testing.expect(!result.auto_add);
    try std.testing.expect(!result.auto_push);
    try std.testing.expect(!result.auto_accept);
}

test "parse config command defaults to edit" {
    const test_args = &[_][]const u8{ "autocommit", "config" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.config, result.command);
    try std.testing.expectEqual(ConfigSubcommand.edit, result.config_sub);
}

test "parse config show subcommand" {
    const test_args = &[_][]const u8{ "autocommit", "config", "show" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.config, result.command);
    try std.testing.expectEqual(ConfigSubcommand.show, result.config_sub);
}

test "parse config path subcommand" {
    const test_args = &[_][]const u8{ "autocommit", "config", "path" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.config, result.command);
    try std.testing.expectEqual(ConfigSubcommand.path, result.config_sub);
}

test "parse with auto_add flag" {
    const test_args = &[_][]const u8{ "autocommit", "--add" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expect(result.auto_add);
    try std.testing.expect(!result.auto_push);
    try std.testing.expect(!result.auto_accept);
}

test "parse with auto_push flag" {
    const test_args = &[_][]const u8{ "autocommit", "--push" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expect(!result.auto_add);
    try std.testing.expect(result.auto_push);
    try std.testing.expect(!result.auto_accept);
}

test "parse with auto_accept flag" {
    const test_args = &[_][]const u8{ "autocommit", "--accept" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expect(!result.auto_add);
    try std.testing.expect(!result.auto_push);
    try std.testing.expect(result.auto_accept);
}

test "parse with provider flag" {
    const test_args = &[_][]const u8{ "autocommit", "--provider", "groq" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqualStrings("groq", result.provider.?);
}

test "parse with model flag" {
    const test_args = &[_][]const u8{ "autocommit", "--model", "llama-3.1-8b" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqualStrings("llama-3.1-8b", result.model.?);
}

test "parse with debug flag" {
    const test_args = &[_][]const u8{ "autocommit", "--debug" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expect(result.debug);
}

test "parse with all flags" {
    const test_args = &[_][]const u8{
        "autocommit",
        "--add",
        "--push",
        "--accept",
        "--provider",
        "groq",
        "--model",
        "llama-3.1-8b",
        "--debug",
    };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.main, result.command);
    try std.testing.expect(result.auto_add);
    try std.testing.expect(result.auto_push);
    try std.testing.expect(result.auto_accept);
    try std.testing.expectEqualStrings("groq", result.provider.?);
    try std.testing.expectEqualStrings("llama-3.1-8b", result.model.?);
    try std.testing.expect(result.debug);
}

test "help text output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try printHelp(stream.writer());
    const help_output = stream.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "autocommit - AI-powered conventional commit message generator"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "config"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "config show"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "config path"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--push"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--accept"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--provider"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--model"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--debug"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--version"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "--help"));
}

test "version output" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try printVersion(stream.writer());
    const version_output = stream.getWritten();

    // Verify format: "autocommit vX.Y.Z (zig)\n"
    try std.testing.expect(std.mem.startsWith(u8, version_output, "autocommit v"));
    try std.testing.expect(std.mem.endsWith(u8, version_output, " (zig)\n"));
    // Should contain at least one dot in the version (e.g., v0.0.0 or v1.2.3)
    try std.testing.expect(std.mem.indexOf(u8, version_output, ".") != null);
}

test "parse missing provider value" {
    const test_args = &[_][]const u8{ "autocommit", "--provider" };
    const result = parseArgsFromSlice(std.testing.allocator, test_args);
    try std.testing.expectError(error.MissingProviderValue, result);
}

test "parse missing model value" {
    const test_args = &[_][]const u8{ "autocommit", "--model" };
    const result = parseArgsFromSlice(std.testing.allocator, test_args);
    try std.testing.expectError(error.MissingModelValue, result);
}

// Internal helper function for testing
fn parseArgsFromSlice(allocator: std.mem.Allocator, args: []const []const u8) !Args {
    var result = Args{};

    if (args.len <= 1) {
        return result;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "config")) {
            result.command = .config;
            if (i + 1 < args.len) {
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "show")) {
                    result.config_sub = .show;
                    i += 1;
                } else if (std.mem.eql(u8, sub, "path")) {
                    result.config_sub = .path;
                    i += 1;
                } else if (std.mem.eql(u8, sub, "edit")) {
                    result.config_sub = .edit;
                    i += 1;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    result.config_sub = .unknown;
                    i += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "--add")) {
            result.auto_add = true;
        } else if (std.mem.eql(u8, arg, "--push")) {
            result.auto_push = true;
        } else if (std.mem.eql(u8, arg, "--accept")) {
            result.auto_accept = true;
        } else if (std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingProviderValue;
            }
            result.provider = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--model")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingModelValue;
            }
            result.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "--debug")) {
            result.debug = true;
        }
    }

    return result;
}
