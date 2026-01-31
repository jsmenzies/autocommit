const std = @import("std");
const llm = @import("../llm.zig");

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub fn buildRequest(provider: llm.Provider, diff: []const u8, prompt: []const u8) ![]const u8 {
    const allocator = provider.allocator;

    const user_content = try std.fmt.allocPrint(allocator, "Git diff:\n{s}", .{diff});
    defer allocator.free(user_content);

    const messages = &[_]Message{
        .{ .role = "system", .content = prompt },
        .{ .role = "user", .content = user_content },
    };

    const request = .{
        .model = provider.config.model,
        .messages = messages,
        .temperature = @as(f32, 0.7),
        .max_tokens = @as(u32, 1000),
    };

    return std.json.stringifyAlloc(allocator, request, .{
        .emit_null_optional_fields = false,
    });
}

pub fn parseResponse(provider: llm.Provider, response: []const u8) llm.LlmError![]const u8 {
    const allocator = provider.allocator;

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, response, .{}) catch {
        return llm.LlmError.InvalidResponse;
    };
    defer parsed.deinit();

    const root = parsed.value;

    if (root != .object) {
        return llm.LlmError.InvalidResponse;
    }

    if (root.object.get("error")) |error_obj| {
        if (error_obj == .object) {
            const error_map = error_obj.object;

            // Check for structured auth-related indicators first
            var is_auth_error = false;
            if (error_map.get("code")) |code_val| {
                if (code_val == .string) {
                    const code_str = code_val.string;
                    if (std.mem.eql(u8, code_str, "invalid_api_key") or
                        std.mem.eql(u8, code_str, "unauthorized"))
                    {
                        is_auth_error = true;
                    }
                }
            }
            if (!is_auth_error) {
                if (error_map.get("status")) |status_val| {
                    if (status_val == .integer) {
                        const status_int = status_val.integer;
                        if (status_int == 401 or status_int == 403) {
                            is_auth_error = true;
                        }
                    }
                }
            }

            if (error_map.get("message")) |msg| {
                if (msg == .string) {
                    const error_message = msg.string;

                    // Rate limit errors take precedence
                    if (std.mem.indexOf(u8, error_message, "rate limit") != null) {
                        return llm.LlmError.RateLimited;
                    }

                    // Check for auth errors in message
                    if (std.mem.indexOf(u8, error_message, "invalid api key") != null or
                        std.mem.indexOf(u8, error_message, "Invalid API key") != null or
                        std.mem.indexOf(u8, error_message, "Incorrect API key") != null or
                        std.mem.indexOf(u8, error_message, "unauthorized") != null or
                        std.mem.indexOf(u8, error_message, "Unauthorized") != null)
                    {
                        return llm.LlmError.InvalidApiKey;
                    }
                }

                // If we identified auth error from structured fields
                if (is_auth_error) {
                    return llm.LlmError.InvalidApiKey;
                }

                return llm.LlmError.ApiError;
            }

            if (is_auth_error) {
                return llm.LlmError.InvalidApiKey;
            }
        }
        return llm.LlmError.ApiError;
    }

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

    const trimmed = std.mem.trim(u8, content_str, " \n\r\t");
    if (trimmed.len == 0) return llm.LlmError.EmptyContent;

    return allocator.dupe(u8, trimmed) catch |err| switch (err) {
        error.OutOfMemory => return llm.LlmError.OutOfMemory,
    };
}

pub fn getEndpoint(provider: llm.Provider) []const u8 {
    return provider.config.endpoint;
}

pub fn getAuthHeader(provider: llm.Provider) ![]const u8 {
    return try std.fmt.allocPrint(provider.allocator, "Bearer {s}", .{provider.config.api_key});
}

pub fn makeVTable() llm.Provider.VTable {
    return llm.Provider.VTable{
        .buildRequest = buildRequest,
        .parseResponse = parseResponse,
        .getEndpoint = getEndpoint,
        .getAuthHeader = getAuthHeader,
    };
}
