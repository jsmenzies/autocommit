const llm = @import("../llm.zig");
const openai_compat = @import("openai_compat.zig");

pub const metadata = .{
    .name = "groq",
    .display_name = "Groq",
    .default_model = "llama-3.1-8b-instant",
    .endpoint = "https://api.groq.com/openai/v1/chat/completions",
    .api_key_placeholder = "paste-key-here",
};

pub const vtable = openai_compat.makeVTable();
