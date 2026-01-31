const std = @import("std");
const builtin = @import("builtin");
const registry = @import("providers/registry.zig");
const tomlz = @import("tomlz");

/// System prompt template for the commit message generator (multi-line for TOML)
pub const SYSTEM_PROMPT_TEMPLATE =
    \\  You are a commit message generator. Analyze the git diff and create ONLY a conventional commit message.
    \\  Follow these rules:
    \\      - Use format for the first line: <type>(<scope>): <subject>
    \\      - Types: feat, fix, docs, style, refactor, test, chore
    \\      - Scope is optional - omit if not needed
    \\      - First line (subject) should be a concise summary
    \\      - Use present tense, imperative mood
    \\      - Add a blank line after the subject if you need a body
    \\      - Body should explain the "highlights" of complex or multiple changes
    \\      - Use bullet points (-) in the body for multiple distinct changes, keep concise
    \\      - CRITICAL: Return ONLY the commit message itself
    \\      - NO suggestions, notes, or commentary after the commit message
    \\      - NO text like "Additionally...", "Note:", "Also...", or similar
    \\      - Do not use markdown code blocks
    \\ 
    \\  Examples (single line for simple changes):
    \\      - feat(auth): add password validation to login form
    \\      - docs(readme): update installation instructions
    \\      - feat: add new feature without scope
    \\ 
    \\  Example (with body for complex changes):
    \\      feat(api): implement rate limiting middleware
    \\ 
    \\       - Add sliding window rate limiting with Redis backend
    \\       - Configurable limits per endpoint via env vars
;

pub fn generateDefaultConfig(comptime default_provider: registry.ProviderId) []const u8 {
    // Build provider entries dynamically at compile time using TOML array of tables
    const provider_entries = comptime blk: {
        var entries: [registry.all.len][]const u8 = undefined;
        for (registry.all, 0..) |metadata, i| {
            entries[i] = std.fmt.comptimePrint(
                "[[providers]]\n" ++
                    "name = \"{s}\"\n" ++
                    "api_key = \"{s}\"\n" ++
                    "model = \"{s}\"\n" ++
                    "endpoint = \"{s}\"\n\n",
                .{
                    metadata.name,
                    metadata.api_key_placeholder,
                    metadata.default_model,
                    metadata.endpoint,
                },
            );
        }
        break :blk entries;
    };

    // Concatenate all provider entries
    const providers_section = comptime blk: {
        var section: []const u8 = "";
        for (provider_entries) |entry| {
            section = section ++ entry;
        }
        break :blk section;
    };

    return comptime std.fmt.comptimePrint(
        "default_provider = \"{s}\"\n\n" ++
            "system_prompt = \"\"\"\n{s}\"\"\"\n\n" ++
            "{s}",
        .{
            default_provider.name(),
            SYSTEM_PROMPT_TEMPLATE,
            providers_section,
        },
    );
}

/// Default configuration template
pub const DEFAULT_CONFIG = generateDefaultConfig(.groq);

pub const Config = struct {
    default_provider: []const u8,
    system_prompt: []const u8,
    providers: []ProviderConfig,

    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.default_provider);
        allocator.free(self.system_prompt);
        for (self.providers) |provider| {
            provider.deinit(allocator);
        }
        allocator.free(self.providers);
    }

    pub fn getProvider(self: *const Config, name: []const u8) !*const ProviderConfig {
        for (self.providers) |*provider| {
            if (std.mem.eql(u8, provider.name, name)) {
                return provider;
            }
        }
        return error.UnknownProvider;
    }
};

pub const ProviderConfig = struct {
    name: []const u8,
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,

    pub fn deinit(self: *const ProviderConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.api_key);
        allocator.free(self.model);
        allocator.free(self.endpoint);
    }
};

/// Get the configuration directory path
/// Priority: XDG_CONFIG_HOME > ~/.config
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    // Check XDG_CONFIG_HOME first (works on both macOS and Linux)
    if (std.process.getEnvVarOwned(allocator, "XDG_CONFIG_HOME")) |xdg_config| {
        return xdg_config;
    } else |_| {
        // Fall back to ~/.config for both macOS and Linux
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);

        return try std.fs.path.join(allocator, &[_][]const u8{ home, ".config" });
    }
}

/// Get the full path to the config file
pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    return try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "autocommit", "config.toml" });
}

/// Ensure the config directory exists
pub fn ensureConfigDir(allocator: std.mem.Allocator) !void {
    const config_dir = try getConfigDir(allocator);
    defer allocator.free(config_dir);

    const autocommit_dir = try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "autocommit" });
    defer allocator.free(autocommit_dir);

    std.fs.cwd().makePath(autocommit_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };
}

/// Create default config file if it doesn't exist
pub fn createDefaultConfig(allocator: std.mem.Allocator, path: []const u8) !void {
    try ensureConfigDir(allocator);

    const file = try std.fs.createFileAbsolute(path, .{});
    defer file.close();

    try file.writeAll(DEFAULT_CONFIG);
}

/// Load configuration from a specific path (relative or absolute)
pub fn loadFromPath(allocator: std.mem.Allocator, config_path: []const u8) !Config {
    // Determine if path is absolute
    const is_absolute = std.fs.path.isAbsolute(config_path);

    // Check if file exists
    const file_exists = blk: {
        if (is_absolute) {
            std.fs.accessAbsolute(config_path, .{}) catch {
                break :blk false;
            };
        } else {
            std.fs.cwd().access(config_path, .{}) catch {
                break :blk false;
            };
        }
        break :blk true;
    };

    if (!file_exists) {
        return error.ConfigNotFound;
    }

    // Read file contents
    const file = if (is_absolute)
        try std.fs.openFileAbsolute(config_path, .{})
    else
        try std.fs.cwd().openFile(config_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // Max 1MB
    defer allocator.free(content);

    // Parse TOML
    return try parseConfig(allocator, content);
}

/// Load configuration from default location
pub fn load(allocator: std.mem.Allocator) !Config {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    return try loadFromPath(allocator, config_path);
}

/// Parse TOML config content using tomlz
fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    // Use an arena allocator to prevent memory leaks during parsing.
    // tomlz may allocate memory before encountering errors, leaving
    // allocations unfreed. Using arena ensures cleanup on any error.
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Parse with arena - all allocations tracked
    const parsed = try tomlz.decode(Config, arena_allocator, content);

    // Successfully parsed - now copy data to caller's allocator
    var config = Config{
        .default_provider = try allocator.dupe(u8, parsed.default_provider),
        .system_prompt = try allocator.dupe(u8, parsed.system_prompt),
        .providers = try allocator.alloc(ProviderConfig, parsed.providers.len),
    };
    errdefer config.deinit(allocator);

    // Copy providers
    for (parsed.providers, 0..) |provider, i| {
        config.providers[i] = ProviderConfig{
            .name = try allocator.dupe(u8, provider.name),
            .api_key = try allocator.dupe(u8, provider.api_key),
            .model = try allocator.dupe(u8, provider.model),
            .endpoint = try allocator.dupe(u8, provider.endpoint),
        };
    }

    return config;
}

/// Validate configuration for a specific provider
pub fn validateConfig(config: *const Config, provider_name: []const u8) !void {
    const provider = config.getProvider(provider_name) catch return error.UnknownProvider;
    const metadata = registry.getByName(provider_name) orelse return error.UnknownProvider;

    // Check if API key is a placeholder or empty
    const placeholder = try std.fmt.allocPrint(std.heap.page_allocator, "your-{s}-api-key-here", .{metadata.name});
    defer std.heap.page_allocator.free(placeholder);

    if (std.mem.eql(u8, provider.api_key, metadata.api_key_placeholder) or
        std.mem.eql(u8, provider.api_key, placeholder) or
        provider.api_key.len == 0)
    {
        return error.ApiKeyNotSet;
    }
}

/// Get editor from environment or use defaults
/// Caller owns the returned memory and must free it with the provided allocator
pub fn getEditor(allocator: std.mem.Allocator) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, "EDITOR")) |editor| {
        return editor;
    } else |_| {
        // Default editors by platform - these are string literals, need to dup
        const default_editor = switch (builtin.target.os.tag) {
            .windows => "notepad",
            else => "vi",
        };
        return try allocator.dupe(u8, default_editor);
    }
}

/// Open config file in editor
pub fn openInEditor(allocator: std.mem.Allocator) !void {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);

    // Check if file exists, create default if not
    const file_exists = blk: {
        std.fs.accessAbsolute(config_path, .{}) catch {
            break :blk false;
        };
        break :blk true;
    };

    if (!file_exists) {
        try createDefaultConfig(allocator, config_path);
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Created default config at {s}\n", .{config_path});
    }

    // Get editor
    const editor = try getEditor(allocator);
    defer allocator.free(editor);

    // Spawn editor process
    var child = std.process.Child.init(&[_][]const u8{ editor, config_path }, allocator);

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) {
                return error.EditorFailed;
            }
        },
        else => return error.EditorFailed,
    }

    // Validate the config is still parseable after editing
    var loaded_config = load(allocator) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Warning: Config file may be invalid after editing: {s}\n", .{@errorName(err)});
        return;
    };
    loaded_config.deinit(allocator);
}

// Test section
test "parseConfig with valid TOML" {
    const test_toml =
        \\default_provider = "zai"
        \\system_prompt = "Test prompt"
        \\
        \\[[providers]]
        \\name = "zai"
        \\api_key = "test-key"
        \\model = "glm-4.7-Flash"
        \\endpoint = "https://api.z.ai/v1"
        \\
        \\[[providers]]
        \\name = "groq"
        \\api_key = "test-key"
        \\model = "llama-3"
        \\endpoint = "https://api.groq.com/v1"
    ;

    var config = try parseConfig(std.testing.allocator, test_toml);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("zai", config.default_provider);
    try std.testing.expectEqualStrings("Test prompt", config.system_prompt);
    const zai_provider = try config.getProvider("zai");
    try std.testing.expectEqualStrings("test-key", zai_provider.api_key);
    try std.testing.expectEqualStrings("glm-4.7-Flash", zai_provider.model);
}

test "parseConfig missing required field" {
    const test_toml =
        \\default_provider = "zai"
    ;

    // Use an arena allocator to avoid leak detection on expected error
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // TOML parsing will fail because system_prompt is missing from the struct
    const result = parseConfig(allocator, test_toml);
    try std.testing.expectError(error.MissingField, result);
}

test "validateConfig with placeholder API key" {
    const test_toml =
        \\default_provider = "zai"
        \\system_prompt = "Test"
        \\
        \\[[providers]]
        \\name = "zai"
        \\api_key = "paste-key-here"
        \\model = "glm-4.7-Flash"
        \\endpoint = "https://api.z.ai/v1"
        \\
        \\[[providers]]
        \\name = "groq"
        \\api_key = "test"
        \\model = "llama-3"
        \\endpoint = "https://api.groq.com/v1"
    ;

    var config = try parseConfig(std.testing.allocator, test_toml);
    defer config.deinit(std.testing.allocator);

    const result = validateConfig(&config, "zai");
    try std.testing.expectError(error.ApiKeyNotSet, result);
}

test "validateConfig with valid API key" {
    const test_toml =
        \\default_provider = "zai"
        \\system_prompt = "Test"
        \\
        \\[[providers]]
        \\name = "zai"
        \\api_key = "real-api-key-123"
        \\model = "glm-4.7-Flash"
        \\endpoint = "https://api.z.ai/v1"
        \\
        \\[[providers]]
        \\name = "groq"
        \\api_key = "test"
        \\model = "llama-3"
        \\endpoint = "https://api.groq.com/v1"
    ;

    var config = try parseConfig(std.testing.allocator, test_toml);
    defer config.deinit(std.testing.allocator);

    try validateConfig(&config, "zai");
}
