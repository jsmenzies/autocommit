const std = @import("std");
const http_client = @import("http_client.zig");
const config = @import("config.zig");
const registry = @import("providers/registry.zig");

pub const LlmError = error{
    InvalidApiKey,
    RateLimited,
    ServerError,
    Timeout,
    InvalidResponse,
    EmptyContent,
    ApiError,
    OutOfMemory,
};

pub const Provider = struct {
    name: []const u8,
    config: config.ProviderConfig,
    http: *http_client.HttpClient,
    allocator: std.mem.Allocator,
    vtable: *const VTable,

    pub const VTable = struct {
        buildRequest: *const fn (self: Provider, diff: []const u8, prompt: []const u8) std.mem.Allocator.Error![]const u8,
        parseResponse: *const fn (self: Provider, response: []const u8) LlmError![]const u8,
        getEndpoint: *const fn (self: Provider) []const u8,
        getAuthHeader: *const fn (self: Provider) std.mem.Allocator.Error![]const u8,
    };

    pub fn generateCommitMessage(self: Provider, diff: []const u8, system_prompt: []const u8) LlmError![]const u8 {
        // Build request body
        const request_body = self.vtable.buildRequest(self, diff, system_prompt) catch |err| {
            std.log.err("Failed to build request: {s}", .{@errorName(err)});
            return LlmError.OutOfMemory;
        };
        defer self.allocator.free(request_body);

        // Get endpoint and auth header
        const endpoint = self.vtable.getEndpoint(self);
        const auth_header = self.vtable.getAuthHeader(self) catch |err| {
            std.log.err("Failed to build auth header: {s}", .{@errorName(err)});
            return LlmError.OutOfMemory;
        };
        defer self.allocator.free(auth_header);

        // Make HTTP request
        const response_body = self.http.postJson(endpoint, auth_header, request_body) catch |err| {
            std.log.err("HTTP request failed: {s}", .{@errorName(err)});
            return mapHttpError(err);
        };
        defer self.allocator.free(response_body);

        // Parse response
        return self.vtable.parseResponse(self, response_body);
    }
};

fn mapHttpError(err: http_client.HttpError) LlmError {
    return switch (err) {
        http_client.HttpError.Timeout => LlmError.Timeout,
        http_client.HttpError.TlsError => LlmError.ServerError,
        else => LlmError.ServerError,
    };
}

pub fn createProvider(
    allocator: std.mem.Allocator,
    name: []const u8,
    provider_config: config.ProviderConfig,
    http: *http_client.HttpClient,
) !Provider {
    const provider_name = try allocator.dupe(u8, name);
    errdefer allocator.free(provider_name);

    const vtable = try getVtable(name);

    return Provider{
        .name = provider_name,
        .config = provider_config,
        .http = http,
        .allocator = allocator,
        .vtable = vtable,
    };
}

pub fn destroyProvider(provider: *Provider, allocator: std.mem.Allocator) void {
    allocator.free(provider.name);
}

fn getVtable(name: []const u8) !*const Provider.VTable {
    return registry.getVtable(name);
}

test "Provider vtable lookup" {
    _ = try getVtable("zai");
}
