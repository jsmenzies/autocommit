const std = @import("std");
const config = @import("config.zig");

pub const Command = enum {
    generate,
    config,
    help,
    version,
    unknown,
};

pub const ConfigSubcommand = enum {
    edit,
    print,
    unknown,
};

pub const Args = struct {
    command: Command = .generate,
    config_sub: ConfigSubcommand = .edit,
    config_file: ?[]const u8 = null,
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
        if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.command = .help;
            return result;
        } else if (std.mem.eql(u8, arg, "version") or std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.command = .version;
            return result;
        } else if (std.mem.eql(u8, arg, "config")) {
            result.command = .config;
            // Check for config subcommand
            if (i + 1 < args.len) {
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "print")) {
                    result.config_sub = .print;
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
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--config")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingConfigValue;
            }
            result.config_file = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingProviderValue;
            }
            result.provider = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingModelValue;
            }
            result.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
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
        \\  config                Open configuration file in editor
        \\  config print           Show current configuration info
        \\  help, --help, -h      Show this help message
        \\  version, --version    Show version information
        \\
        \\Options:
        \\  -c, --config <path>   Use custom configuration file
        \\  -p, --provider <name> Override provider (zai, openai, groq)
        \\  -m, --model <name>    Override model
        \\  -d, --debug           Enable debug output
        \\
        \\Examples:
        \\  autocommit                          # Generate commit message
        \\  autocommit -p groq -m llama-3.1     # Use groq with specific model
        \\  autocommit config                   # Edit configuration
        \\  autocommit config print              # Show current config
        \\
    ;

    try writer.print("{s}", .{help_text});
}

pub fn printVersion(writer: anytype) !void {
    try writer.print("autocommit v0.1.0 (zig)\n", .{});
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

    // Color-coded Auto Add
    if (cfg.auto_add) {
        try writer.print("  Auto Add: {s}enabled{s}\n", .{ Color.green, Color.reset });
    } else {
        try writer.print("  Auto Add: {s}disabled{s}\n", .{ Color.gray, Color.reset });
    }

    // Color-coded Auto Push
    if (cfg.auto_push) {
        try writer.print("  Auto Push: {s}enabled{s}\n", .{ Color.green, Color.reset });
    } else {
        try writer.print("  Auto Push: {s}disabled{s}\n", .{ Color.gray, Color.reset });
    }

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

// Free any allocated memory in Args
pub fn free(args: *const Args, allocator: std.mem.Allocator) void {
    if (args.config_file) |config_file| {
        allocator.free(config_file);
    }
    if (args.provider) |provider| {
        allocator.free(provider);
    }
    if (args.model) |model| {
        allocator.free(model);
    }
}

// Test section
test "parse with no arguments defaults to generate" {
    const test_args = &[_][]const u8{"autocommit"};
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.generate, result.command);
    try std.testing.expect(!result.debug);
}

test "parse help command" {
    const test_args = &[_][]const u8{ "autocommit", "help" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.help, result.command);
}

test "parse version command" {
    const test_args = &[_][]const u8{ "autocommit", "version" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.version, result.command);
}

test "parse config command defaults to edit" {
    const test_args = &[_][]const u8{ "autocommit", "config" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.config, result.command);
    try std.testing.expectEqual(ConfigSubcommand.edit, result.config_sub);
}

test "parse config print subcommand" {
    const test_args = &[_][]const u8{ "autocommit", "config", "print" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.config, result.command);
    try std.testing.expectEqual(ConfigSubcommand.print, result.config_sub);
}

test "parse with provider and model" {
    const test_args = &[_][]const u8{ "autocommit", "-p", "groq", "-m", "llama-3.1-8b" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqualStrings("groq", result.provider.?);
    try std.testing.expectEqualStrings("llama-3.1-8b", result.model.?);
}

test "parse with debug flag" {
    const test_args = &[_][]const u8{ "autocommit", "-d" };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expect(result.debug);
}

test "parse with all generation flags" {
    const test_args = &[_][]const u8{
        "autocommit",
        "-p",
        "zai",
        "-m",
        "glm-4.7-Flash",
        "-d",
    };
    var result = try parseArgsFromSlice(std.testing.allocator, test_args);
    defer free(&result, std.testing.allocator);

    try std.testing.expectEqual(Command.generate, result.command);
    try std.testing.expectEqualStrings("zai", result.provider.?);
    try std.testing.expectEqualStrings("glm-4.7-Flash", result.model.?);
    try std.testing.expect(result.debug);
}

test "parse missing provider value" {
    const test_args = &[_][]const u8{ "autocommit", "-p" };
    const result = parseArgsFromSlice(std.testing.allocator, test_args);
    try std.testing.expectError(error.MissingProviderValue, result);
}

test "parse missing model value" {
    const test_args = &[_][]const u8{ "autocommit", "-m" };
    const result = parseArgsFromSlice(std.testing.allocator, test_args);
    try std.testing.expectError(error.MissingModelValue, result);
}

test "help text output" {
    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try printHelp(stream.writer());
    const help_output = stream.getWritten();

    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "autocommit - AI-powered conventional commit message generator"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "config"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "config print"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "-p, --provider"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "-m, --model"));
    try std.testing.expect(std.mem.containsAtLeast(u8, help_output, 1, "-d, --debug"));
}

test "version output" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    try printVersion(stream.writer());
    const version_output = stream.getWritten();

    try std.testing.expect(std.mem.eql(u8, version_output, "autocommit v0.1.0 (zig)\n"));
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

        if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.command = .help;
            return result;
        } else if (std.mem.eql(u8, arg, "version") or std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.command = .version;
            return result;
        } else if (std.mem.eql(u8, arg, "config")) {
            result.command = .config;
            if (i + 1 < args.len) {
                const sub = args[i + 1];
                if (std.mem.eql(u8, sub, "print")) {
                    result.config_sub = .print;
                    i += 1;
                } else if (std.mem.eql(u8, sub, "edit")) {
                    result.config_sub = .edit;
                    i += 1;
                } else if (!std.mem.startsWith(u8, sub, "-")) {
                    result.config_sub = .unknown;
                    i += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--provider")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingProviderValue;
            }
            result.provider = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--model")) {
            i += 1;
            if (i >= args.len) {
                return error.MissingModelValue;
            }
            result.model = try allocator.dupe(u8, args[i]);
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--debug")) {
            result.debug = true;
        }
    }

    return result;
}
