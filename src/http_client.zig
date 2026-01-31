const std = @import("std");

pub const HttpError = error{
    InvalidUrl,
    ConnectionFailed,
    Timeout,
    TlsError,
    RequestFailed,
    OutOfMemory,
};

pub const HttpClient = struct {
    client: std.http.Client,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) HttpClient {
        return .{
            .client = std.http.Client{ .allocator = allocator },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *HttpClient) void {
        self.client.deinit();
    }

    /// Make a POST request with JSON body and return response body
    /// Caller owns the returned memory and must free it
    pub fn postJson(
        self: *HttpClient,
        url: []const u8,
        auth_header: ?[]const u8,
        body: []const u8,
    ) ![]const u8 {
        // Parse URL
        const uri = std.Uri.parse(url) catch return HttpError.InvalidUrl;

        // Build extra headers (Content-Type is required!)
        var server_header_buffer: [16 * 1024]u8 = undefined;

        const header_count: usize = if (auth_header != null) 3 else 2;
        const extra_headers = try self.allocator.alloc(std.http.Header, header_count);
        defer self.allocator.free(extra_headers);

        extra_headers[0] = .{
            .name = "Content-Type",
            .value = "application/json",
        };

        extra_headers[1] = .{
            .name = "User-Agent",
            .value = "autocommit/1.0",
        };

        if (auth_header) |auth| {
            extra_headers[2] = .{
                .name = "Authorization",
                .value = auth,
            };
        }

        // Open connection and send request
        var req = self.client.open(.POST, uri, .{
            .server_header_buffer = &server_header_buffer,
            .extra_headers = extra_headers,
        }) catch |err| {
            return switch (err) {
                error.OutOfMemory => HttpError.OutOfMemory,
                else => HttpError.ConnectionFailed,
            };
        };
        defer req.deinit();

        // Send body
        req.transfer_encoding = .{ .content_length = body.len };
        req.send() catch return HttpError.RequestFailed;
        req.writeAll(body) catch return HttpError.RequestFailed;
        req.finish() catch return HttpError.RequestFailed;
        req.wait() catch return HttpError.RequestFailed;

        // Read response
        const max_size = 1024 * 1024; // 1MB max response
        const body_content = req.reader().readAllAlloc(self.allocator, max_size) catch return HttpError.RequestFailed;

        return body_content;
    }
};

test "HttpClient initialization" {
    var client = HttpClient.init(std.testing.allocator);
    defer client.deinit();
}
