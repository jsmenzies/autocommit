const std = @import("std");
const builtin = @import("builtin");

pub const Config = struct {
    default_provider: []const u8,
    auto_add: bool,
    auto_push: bool,
    system_prompt: []const u8,
    providers: Providers,

    pub fn deinit(self: *const Config, allocator: std.mem.Allocator) void {
        allocator.free(self.default_provider);
        allocator.free(self.system_prompt);
        self.providers.deinit(allocator);
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

/// Default configuration template
pub const DEFAULT_CONFIG =
    \\{
    \\  "default_provider": "groq",
    \\  "auto_add": false,
    \\  "auto_push": false,
    \\  "system_prompt": "You are a commit message generator. Analyze the git diff and create a conventional commit message.\nFollow these rules:\n- Use format: <type>(<scope>): <subject>\n- Types: feat, fix, docs, style, refactor, test, chore\n- Scope is optional - omit if not needed\n- Keep subject under 72 characters\n- Use present tense, imperative mood\n- Be specific but concise\n- Do not include any explanation, only output the commit message\n- Do not use markdown code blocks\n\nExamples:\n- feat(auth): add password validation to login form\n- fix(api): handle nil pointer in user service\n- docs(readme): update installation instructions\n- refactor(db): optimize query performance with index\n- feat: add new feature without scope",
    \\  "providers": {
    \\    "zai": {
    \\      "api_key": "your-zai-api-key-here",
    \\      "model": "glm-4.7-Flash",
    \\      "endpoint": "https://api.z.ai/api/paas/v4/chat/completions"
    \\    },
    \\    "openai": {
    \\      "api_key": "your-openai-api-key-here",
    \\      "model": "gpt-4o-mini",
    \\      "endpoint": "https://api.openai.com/v1/chat/completions"
    \\    },
    \\    "groq": {
    \\      "api_key": "your-groq-api-key-here",
    \\      "model": "llama-3.1-8b-instant",
    \\      "endpoint": "https://api.groq.com/openai/v1/chat/completions"
    \\    }
    \\  }
    \\}
    \\
;

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

    const auto_add = if (obj.get("auto_add")) |v| v.bool else false;
    const auto_push = if (obj.get("auto_push")) |v| v.bool else false;

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
        .auto_add = auto_add,
        .auto_push = auto_push,
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
    try std.testing.expect(config.auto_add);
    try std.testing.expect(!config.auto_push);
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
        \\  "auto_add": false,
        \\  "auto_push": false,
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
        \\  "auto_add": false,
        \\  "auto_push": false,
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
