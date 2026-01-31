const std = @import("std");
const llm = @import("../llm.zig");

/// Provider metadata exported for registry
pub const metadata = .{
    .name = "zai",
    .display_name = "Z AI",
    .default_model = "glm-4.7-Flash",
    .endpoint = "https://api.z.ai/api/paas/v4/chat/completions",
    .api_key_placeholder = "paste-key-here",
};

const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const vtable = llm.Provider.VTable{
    .buildRequest = buildRequest,
    .parseResponse = parseResponse,
    .getEndpoint = getEndpoint,
    .getAuthHeader = getAuthHeader,
};

fn buildRequest(provider: llm.Provider, diff: []const u8, prompt: []const u8) ![]const u8 {
    const allocator = provider.allocator;

    // Build user content
    const user_content = try std.fmt.allocPrint(allocator, "Git diff:\n{s}", .{diff});
    defer allocator.free(user_content);

    // Build messages array
    const messages = &[_]Message{
        .{ .role = "system", .content = prompt },
        .{ .role = "user", .content = user_content },
    };

    // Build request struct
    const request = .{
        .model = provider.config.model,
        .messages = messages,
        .temperature = @as(f32, 0.7),
        .max_tokens = @as(u32, 1000),
    };

    // Serialize to JSON
    return std.json.stringifyAlloc(allocator, request, .{
        .emit_null_optional_fields = false,
    });
}

fn parseResponse(provider: llm.Provider, response: []const u8) llm.LlmError![]const u8 {
    const allocator = provider.allocator;

    // Parse the JSON response using the provider's allocator
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
        return llm.LlmError.InvalidResponse;
    };
    defer parsed.deinit();

    const root = parsed.value;

    // Validate root is an object before accessing
    if (root != .object) {
        return llm.LlmError.InvalidResponse;
    }

    // Check for error response
    if (root.object.get("error")) |error_obj| {
        if (error_obj == .object) {
            if (error_obj.object.get("message")) |msg| {
                if (msg == .string) {
                    const error_message = msg.string;
                    if (std.mem.indexOf(u8, error_message, "rate limit") != null) {
                        return llm.LlmError.RateLimited;
                    }
                }
                return llm.LlmError.ApiError;
            }
        }
        return llm.LlmError.ApiError;
    }

    // Extract content from choices[0].message.content
    const choices = root.object.get("choices") orelse return llm.LlmError.InvalidResponse;
    if (choices != .array) return llm.LlmError.InvalidResponse;
    if (choices.array.items.len == 0) return llm.LlmError.EmptyContent;

    const first_choice = choices.array.items[0];
    if (first_choice != .object) return llm.LlmError.InvalidResponse;

    const message = first_choice.object.get("message") orelse return llm.LlmError.InvalidResponse;
    if (message != .object) return llm.LlmError.InvalidResponse;

    const content = message.object.get("content") orelse return llm.LlmError.InvalidResponse;
    if (content != .string) return llm.LlmError.InvalidResponse;

    const content_str = content.string;
    if (content_str.len == 0) return llm.LlmError.EmptyContent;

    // Trim whitespace and return
    const trimmed = std.mem.trim(u8, content_str, " \n\r\t");
    if (trimmed.len == 0) return llm.LlmError.EmptyContent;

    // Allocate a copy of the trimmed content using the provider's allocator
    return allocator.dupe(u8, trimmed) catch |err| switch (err) {
        error.OutOfMemory => return llm.LlmError.OutOfMemory,
    };
}

fn getEndpoint(provider: llm.Provider) []const u8 {
    return provider.config.endpoint;
}

fn getAuthHeader(provider: llm.Provider) ![]const u8 {
    return try std.fmt.allocPrint(provider.allocator, "Bearer {s}", .{provider.config.api_key});
}
