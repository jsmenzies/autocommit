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

pub const DebugLogFn = *const fn (ctx: ?*anyopaque, message: []const u8) void;

pub const Provider = struct {
    name: []const u8,
    config: config.ProviderConfig,
    http: *http_client.HttpClient,
    allocator: std.mem.Allocator,
    vtable: *const VTable,
    debug_log: ?DebugLogFn,
    debug_ctx: ?*anyopaque,

    pub const VTable = struct {
        buildRequest: *const fn (self: Provider, diff: []const u8, prompt: []const u8) std.mem.Allocator.Error![]const u8,
        parseResponse: *const fn (self: Provider, response: []const u8) LlmError![]const u8,
        getEndpoint: *const fn (self: Provider) []const u8,
        getAuthHeader: *const fn (self: Provider) std.mem.Allocator.Error![]const u8,
    };

    fn logDebug(self: Provider, comptime fmt: []const u8, args: anytype) void {
        if (self.debug_log) |log_fn| {
            var buf: [2048]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, fmt, args) catch |err| {
                log_fn(self.debug_ctx, std.fmt.bufPrint(&buf, "Debug log formatting error: {s}", .{@errorName(err)}) catch "Debug log error");
                return;
            };
            log_fn(self.debug_ctx, msg);
        }
    }

    pub fn generateCommitMessage(self: Provider, diff: []const u8, system_prompt: []const u8) LlmError![]const u8 {
        self.logDebug("Building LLM request...", .{});

        const request_body = self.vtable.buildRequest(self, diff, system_prompt) catch |err| {
            std.log.err("Failed to build request: {s}", .{@errorName(err)});
            return LlmError.OutOfMemory;
        };
        defer self.allocator.free(request_body);

        self.logDebug("Request body size: {d} bytes", .{request_body.len});

        const endpoint = self.vtable.getEndpoint(self);
        const auth_header = self.vtable.getAuthHeader(self) catch |err| {
            std.log.err("Failed to build auth header: {s}", .{@errorName(err)});
            return LlmError.OutOfMemory;
        };
        defer self.allocator.free(auth_header);

        self.logDebug("Sending request to {s}", .{endpoint});

        const response_body = self.http.postJson(endpoint, auth_header, request_body) catch |err| {
            std.log.err("HTTP request failed: {s}", .{@errorName(err)});
            return mapHttpError(err);
        };
        defer self.allocator.free(response_body);

        self.logDebug("Raw LLM response: {s}", .{response_body});

        const parsed = self.vtable.parseResponse(self, response_body);

        if (parsed) |message| {
            self.logDebug("Parsed commit message: {s}", .{message});
        } else |err| {
            switch (err) {
                error.EmptyContent => self.logDebug("Parsed response: (empty content)", .{}),
                error.InvalidResponse => self.logDebug("Parsed response: (invalid response)", .{}),
                error.InvalidApiKey => self.logDebug("Parsed response: (invalid API key)", .{}),
                error.RateLimited => self.logDebug("Parsed response: (rate limited)", .{}),
                error.ServerError => self.logDebug("Parsed response: (server error)", .{}),
                error.Timeout => self.logDebug("Parsed response: (timeout)", .{}),
                error.ApiError => self.logDebug("Parsed response: (API error)", .{}),
                error.OutOfMemory => self.logDebug("Parsed response: (out of memory)", .{}),
            }
        }

        return parsed;
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
    debug_log: ?DebugLogFn,
    debug_ctx: ?*anyopaque,
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
        .debug_log = debug_log,
        .debug_ctx = debug_ctx,
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
