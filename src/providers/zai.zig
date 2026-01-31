const openai_compat = @import("openai_compat.zig");

pub const metadata = .{
    .name = "zai",
    .display_name = "Z AI",
    .default_model = "glm-4.7-Flash",
    .endpoint = "https://api.z.ai/api/paas/v4/chat/completions",
    .api_key_placeholder = "paste-key-here",
};

pub const vtable = openai_compat.makeVTable();
