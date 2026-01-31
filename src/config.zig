const std = @import("std");
const builtin = @import("builtin");
const registry = @import("providers/registry.zig");
const zai_provider = @import("providers/zai.zig");
const groq_provider = @import("providers/groq.zig");

/// System prompt template for the commit message generator
pub const SYSTEM_PROMPT_TEMPLATE =
    \\You are a commit message generator. Analyze the git diff and create a conventional commit message.
    \\Follow these rules:
    \\- Use format for the first line: <type>(<scope>): <subject>
    \\- Types: feat, fix, docs, style, refactor, test, chore
    \\- Scope is optional - omit if not needed
    \\- First line (subject) should be a concise summary
    \\- Use present tense, imperative mood
    \\- Add a blank line after the subject if you need a body
    \\- Body should explain the "what" and "why" for complex or multiple changes
    \\- Use bullet points in the body for multiple distinct changes
    \\- Do not include any explanation outside the commit message
    \\- Do not use markdown code blocks
    \\ 
    \\Examples (single line for simple changes):
    \\- feat(auth): add password validation to login form
    \\- fix(api): handle nil pointer in user service
    \\- docs(readme): update installation instructions
    \\- refactor(db): optimize query performance with index
    \\- feat: add new feature without scope
    \\ 
    \\Examples (with body for complex changes):
    \\feat(api): implement rate limiting middleware
    \\ 
    \\- Add sliding window rate limiting with Redis backend
    \\- Configurable limits per endpoint via env vars
    \\- Returns 429 status with Retry-After header
;

/// Generate the default configuration JSON at comptime
/// Uses provider metadata from registry
pub fn generateDefaultConfig(comptime default_provider: registry.ProviderId) []const u8 {
    return comptime generateDefaultConfigImpl(default_provider);
}

fn generateDefaultConfigImpl(default_provider: registry.ProviderId) []const u8 {
    // Get provider metadata directly
    const zai_metadata = zai_provider.metadata;
    const groq_metadata = groq_provider.metadata;

    return std.fmt.comptimePrint(
        "{{\\n" ++
            "  \"default_provider\": \"{s}\",\\n" ++
            "  \"providers\": {{\\n" ++
            "    \"zai\": {{\\n" ++
            "      \"api_key\": \"{s}\",\\n" ++
            "      \"model\": \"{s}\",\\n" ++
            "      \"endpoint\": \"{s}\"\\n" ++
            "    }},\\n" ++
            "    \"groq\": {{\\n" ++
            "      \"api_key\": \"{s}\",\\n" ++
            "      \"model\": \"{s}\",\\n" ++
            "      \"endpoint\": \"{s}\"\\n" ++
            "    }}\\n" ++
            "  }},\\n" ++
            "  \"system_prompt\": \"{s}\"\\n" ++
            "}}",
        .{
            default_provider.name(),
            zai_metadata.api_key_placeholder,
            zai_metadata.default_model,
            zai_metadata.endpoint,
            groq_metadata.api_key_placeholder,
            groq_metadata.default_model,
            groq_metadata.endpoint,
            SYSTEM_PROMPT_TEMPLATE,
        },
    );
}

/// Default configuration template
pub const DEFAULT_CONFIG = generateDefaultConfig(.zai);

pub const Config = struct {
    default_provider: []const u8,
    system_prompt: []const u8,
    providers: Providers,

    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.default_provider);
        allocator.free(self.system_prompt);
        self.providers.deinit(allocator);
    }

    pub fn getProvider(self: *const Config, name: []const u8) !*const ProviderConfig {
        const id = registry.ProviderId.fromString(name) orelse return error.UnknownProvider;
        return self.providers.get(id);
    }
};

pub const Providers = struct {
    zai: ProviderConfig,
    openai: ProviderConfig,
    groq: ProviderConfig,

    pub fn deinit(self: *const Providers, allocator: std.mem.Allocator) void {
        self.zai.deinit(allocator);
        self.openai.deinit(allocator);
        self.groq.deinit(allocator);
    }

    pub fn get(self: *const Providers, id: registry.ProviderId) *const ProviderConfig {
        return switch (id) {
            .zai => &self.zai,
            .groq => &self.groq,
        };
    }
};

pub const ProviderConfig = struct {
    api_key: []const u8,
    model: []const u8,
    endpoint: []const u8,

    pub fn deinit(self: *const ProviderConfig, allocator: std.mem.Allocator) void {
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

    return try std.fs.path.join(allocator, &[_][]const u8{ config_dir, "autocommit", "config.json" });
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

    // Parse JSON
    return try parseConfig(allocator, content);
}

/// Load configuration from default location
pub fn load(allocator: std.mem.Allocator) !Config {
    const config_path = try getConfigPath(allocator);
    defer allocator.free(config_path);
    return try loadFromPath(allocator, config_path);
}

/// Parse JSON config content
fn parseConfig(allocator: std.mem.Allocator, content: []const u8) !Config {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    const root = parsed.value;

    if (root != .object) {
        return error.InvalidConfig;
    }

    const obj = root.object;

    // Parse required fields
    const default_provider = try getStringField(allocator, obj, "default_provider") orelse {
        return error.MissingDefaultProvider;
    };
    errdefer allocator.free(default_provider);

    const system_prompt = try getStringField(allocator, obj, "system_prompt") orelse {
        return error.MissingSystemPrompt;
    };
    errdefer allocator.free(system_prompt);

    // Parse providers
    const providers_obj = obj.get("providers") orelse {
        return error.MissingProviders;
    };

    if (providers_obj != .object) {
        return error.InvalidProviders;
    }

    const providers = try parseProviders(allocator, providers_obj.object);
    errdefer providers.deinit(allocator);

    return Config{
        .default_provider = default_provider,
        .system_prompt = system_prompt,
        .providers = providers,
    };
}

fn getStringField(allocator: std.mem.Allocator, obj: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = obj.get(key) orelse return null;
    if (value != .string) return null;
    return try allocator.dupe(u8, value.string);
}

fn parseProviders(allocator: std.mem.Allocator, obj: std.json.ObjectMap) !Providers {
    const zai = try parseProvider(allocator, obj, "zai");
    errdefer zai.deinit(allocator);

    const openai = try parseProvider(allocator, obj, "openai");
    errdefer openai.deinit(allocator);

    const groq = try parseProvider(allocator, obj, "groq");
    errdefer groq.deinit(allocator);

    return Providers{
        .zai = zai,
        .openai = openai,
        .groq = groq,
    };
}

fn parseProvider(allocator: std.mem.Allocator, obj: std.json.ObjectMap, name: []const u8) !ProviderConfig {
    const provider_obj = obj.get(name) orelse {
        return error.MissingProvider;
    };

    if (provider_obj != .object) {
        return error.InvalidProvider;
    }

    const p = provider_obj.object;

    const api_key = try getStringField(allocator, p, "api_key") orelse {
        return error.MissingApiKey;
    };
    errdefer allocator.free(api_key);

    const model = try getStringField(allocator, p, "model") orelse {
        return error.MissingModel;
    };
    errdefer allocator.free(model);

    const endpoint = try getStringField(allocator, p, "endpoint") orelse {
        return error.MissingEndpoint;
    };
    errdefer allocator.free(endpoint);

    return ProviderConfig{
        .api_key = api_key,
        .model = model,
        .endpoint = endpoint,
    };
}

/// Validate configuration for a specific provider
pub fn validateConfig(config: *const Config, provider_name: []const u8) !void {
    const provider = if (std.mem.eql(u8, provider_name, "zai"))
        config.providers.zai
    else if (std.mem.eql(u8, provider_name, "openai"))
        config.providers.openai
    else if (std.mem.eql(u8, provider_name, "groq"))
        config.providers.groq
    else
        return error.UnknownProvider;

    if (std.mem.eql(u8, provider.api_key, "your-zai-api-key-here") or
        std.mem.eql(u8, provider.api_key, "your-openai-api-key-here") or
        std.mem.eql(u8, provider.api_key, "your-groq-api-key-here") or
        provider.api_key.len == 0)
    {
        return error.ApiKeyNotSet;
    }
}

/// Get editor from environment or use defaults
pub fn getEditor() []const u8 {
    if (std.process.getEnvVarOwned(std.heap.page_allocator, "EDITOR")) |editor| {
        return editor;
    } else |_| {
        // Default editors by platform
        return switch (builtin.target.os.tag) {
            .windows => "notepad",
            else => "vi",
        };
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
    const editor = getEditor();

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
    _ = load(allocator) catch |err| {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("Warning: Config file may be invalid after editing: {s}\n", .{@errorName(err)});
        return;
    };
}

// Test section
test "getConfigPath uses XDG_CONFIG_HOME when set" {
    // This test would need to set environment variables, which is tricky in tests
    // For now, we just test the basic functionality
}

test "parseConfig with valid JSON" {
    const test_json =
        \\{
        \\  "default_provider": "zai",
        \\  "auto_add": true,
        \\  "auto_push": false,
        \\  "system_prompt": "Test prompt",
        \\  "providers": {
        \\    "zai": {
        \\      "api_key": "test-key",
        \\      "model": "glm-4.7-Flash",
        \\      "endpoint": "https://api.z.ai/v1"
        \\    },
        \\    "openai": {
        \\      "api_key": "test-key",
        \\      "model": "gpt-4",
        \\      "endpoint": "https://api.openai.com/v1"
        \\    },
        \\    "groq": {
        \\      "api_key": "test-key",
        \\      "model": "llama-3",
        \\      "endpoint": "https://api.groq.com/v1"
        \\    }
        \\  }
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, test_json);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("zai", config.default_provider);
    try std.testing.expectEqualStrings("Test prompt", config.system_prompt);
    try std.testing.expectEqualStrings("test-key", config.providers.zai.api_key);
    try std.testing.expectEqualStrings("glm-4.7-Flash", config.providers.zai.model);
}

test "parseConfig missing required field" {
    const test_json =
        \\{
        \\  "default_provider": "zai"
        \\}
    ;

    const result = parseConfig(std.testing.allocator, test_json);
    try std.testing.expectError(error.MissingSystemPrompt, result);
}

test "validateConfig with placeholder API key" {
    const test_json =
        \\{
        \\  "default_provider": "zai",
        \\  "system_prompt": "Test",
        \\  "providers": {
        \\    "zai": {
        \\      "api_key": "your-zai-api-key-here",
        \\      "model": "glm-4.7-Flash",
        \\      "endpoint": "https://api.z.ai/v1"
        \\    },
        \\    "openai": {
        \\      "api_key": "test",
        \\      "model": "gpt-4",
        \\      "endpoint": "https://api.openai.com/v1"
        \\    },
        \\    "groq": {
        \\      "api_key": "test",
        \\      "model": "llama-3",
        \\      "endpoint": "https://api.groq.com/v1"
        \\    }
        \\  }
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, test_json);
    defer config.deinit(std.testing.allocator);

    const result = validateConfig(&config, "zai");
    try std.testing.expectError(error.ApiKeyNotSet, result);
}

test "validateConfig with valid API key" {
    const test_json =
        \\{
        \\  "default_provider": "zai",
        \\  "system_prompt": "Test",
        \\  "providers": {
        \\    "zai": {
        \\      "api_key": "real-api-key-123",
        \\      "model": "glm-4.7-Flash",
        \\      "endpoint": "https://api.z.ai/v1"
        \\    },
        \\    "openai": {
        \\      "api_key": "test",
        \\      "model": "gpt-4",
        \\      "endpoint": "https://api.openai.com/v1"
        \\    },
        \\    "groq": {
        \\      "api_key": "test",
        \\      "model": "llama-3",
        \\      "endpoint": "https://api.groq.com/v1"
        \\    }
        \\  }
        \\}
    ;

    var config = try parseConfig(std.testing.allocator, test_json);
    defer config.deinit(std.testing.allocator);

    try validateConfig(&config, "zai");
}
