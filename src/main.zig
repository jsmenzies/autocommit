const std = @import("std");
const cli = @import("cli.zig");
const config = @import("config.zig");

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
                .edit => {
                    try config.openInEditor(allocator);
                },
                .print => {
                    try cli.printConfigInfo(allocator, stdout);
                },
                .unknown => {
                    try stderr.print("Unknown config subcommand\n", .{});
                    try stderr.print("Usage: autocommit config [print]\n", .{});
                    std.process.exit(1);
                },
            }
            return;
        },
        .generate => {
            // Continue to generation workflow
        },
        .unknown => {
            try stderr.print("Unknown command\n", .{});
            try cli.printHelp(stderr);
            std.process.exit(1);
        },
    }

    // Load configuration for generation
    var cfg = config.load(allocator) catch |err| {
        const config_path = config.getConfigPath(allocator) catch "unknown";
        defer if (config_path.ptr != "unknown".ptr) allocator.free(config_path);

        switch (err) {
            error.ConfigNotFound => {
                try stderr.print("Config file not found at {s}\n", .{config_path});
                try stderr.print("Run 'autocommit config' to create one.\n", .{});
                std.process.exit(1);
            },
            error.InvalidConfig => {
                try stderr.print("Invalid JSON in config file: {s}\n", .{config_path});
                std.process.exit(1);
            },
            error.MissingDefaultProvider => {
                try stderr.print("Config error: missing 'default_provider' field\n", .{});
                std.process.exit(1);
            },
            error.MissingSystemPrompt => {
                try stderr.print("Config error: missing 'system_prompt' field\n", .{});
                std.process.exit(1);
            },
            error.MissingProviders => {
                try stderr.print("Config error: missing 'providers' section\n", .{});
                std.process.exit(1);
            },
            error.MissingProvider => {
                try stderr.print("Config error: missing provider configuration\n", .{});
                std.process.exit(1);
            },
            error.MissingApiKey => {
                try stderr.print("Config error: missing 'api_key' in provider config\n", .{});
                std.process.exit(1);
            },
            error.MissingModel => {
                try stderr.print("Config error: missing 'model' in provider config\n", .{});
                std.process.exit(1);
            },
            error.MissingEndpoint => {
                try stderr.print("Config error: missing 'endpoint' in provider config\n", .{});
                std.process.exit(1);
            },
            else => {
                try stderr.print("Failed to load config: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            },
        }
    };
    defer cfg.deinit(allocator);

    // Determine which provider to use
    const provider_name = args.provider orelse cfg.default_provider;

    // Validate the selected provider
    config.validateConfig(&cfg, provider_name) catch |err| {
        switch (err) {
            error.UnknownProvider => {
                try stderr.print("Unknown provider: {s}\n", .{provider_name});
                std.process.exit(1);
            },
            error.ApiKeyNotSet => {
                try stderr.print("API key not set for provider '{s}'. Edit your config file.\n", .{provider_name});
                std.process.exit(1);
            },
        }
    };

    // Get the provider config
    const provider_cfg = if (std.mem.eql(u8, provider_name, "zai"))
        cfg.providers.zai
    else if (std.mem.eql(u8, provider_name, "openai"))
        cfg.providers.openai
    else if (std.mem.eql(u8, provider_name, "groq"))
        cfg.providers.groq
    else
        unreachable;

    // Apply CLI overrides
    const model = args.model orelse provider_cfg.model;

    if (args.debug) {
        const config_path = try config.getConfigPath(allocator);
        defer allocator.free(config_path);

        try stderr.print("[DEBUG] Config path: {s}\n", .{config_path});
        try stderr.print("[DEBUG] Provider: {s}\n", .{provider_name});
        try stderr.print("[DEBUG] Model: {s}\n", .{model});
        try stderr.print("[DEBUG] Endpoint: {s}\n", .{provider_cfg.endpoint});
    }

    // Main generation workflow (to be implemented in later phases)
    try stderr.print("Generating commit message...\n", .{});
    try stderr.print("Provider: {s}\n", .{provider_name});
    try stderr.print("Model: {s}\n", .{model});
}

test {
    // Run all tests in the imported modules
    _ = @import("cli.zig");
    _ = @import("config.zig");
}
