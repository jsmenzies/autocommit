const openai_compat = @import("openai_compat.zig");

pub const metadata = .{
    .name = "custom",
    .display_name = "Custom",
    .default_model = "gpt-4",
    .endpoint = "https://api.example.com/v1/chat/completions",
    .api_key_placeholder = "paste-key-here",
};

pub const vtable = openai_compat.makeVTable();
