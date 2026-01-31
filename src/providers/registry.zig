const std = @import("std");

const zai = @import("zai.zig");
const groq = @import("groq.zig");

pub const ProviderId = enum {
    zai,
    groq,

    pub fn name(self: ProviderId) []const u8 {
        return @tagName(self);
    }

    pub fn fromString(str: []const u8) ?ProviderId {
        inline for (@typeInfo(ProviderId).Enum.fields) |field| {
            if (std.mem.eql(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return null;
    }
};

pub const ProviderMetadata = struct {
    id: ProviderId,
    name: []const u8,
    display_name: []const u8,
    default_model: []const u8,
    endpoint: []const u8,
    api_key_placeholder: []const u8,
};

const RegistryBuilder = struct {
    const provider_modules = .{ zai, groq };

    fn buildMetadata() [provider_modules.len]ProviderMetadata {
        comptime {
            var metadata_array: [provider_modules.len]ProviderMetadata = undefined;

            for (provider_modules, 0..) |provider_module, i| {
                metadata_array[i] = ProviderMetadata{
                    .id = @enumFromInt(i),
                    .name = provider_module.metadata.name,
                    .display_name = provider_module.metadata.display_name,
                    .default_model = provider_module.metadata.default_model,
                    .endpoint = provider_module.metadata.endpoint,
                    .api_key_placeholder = provider_module.metadata.api_key_placeholder,
                };
            }

            return metadata_array;
        }
    }
};

pub const all = RegistryBuilder.buildMetadata();

pub fn getById(id: ProviderId) ?*const ProviderMetadata {
    const index = @intFromEnum(id);
    if (index >= all.len) return null;
    return &all[index];
}

pub fn getByName(name: []const u8) ?*const ProviderMetadata {
    const id = ProviderId.fromString(name) orelse return null;
    return getById(id);
}

pub fn getVtable(name: []const u8) !*const @import("../llm.zig").Provider.VTable {
    const metadata = getByName(name) orelse return error.UnknownProvider;

    inline for (RegistryBuilder.provider_modules, 0..) |provider_module, i| {
        if (metadata.id == @as(ProviderId, @enumFromInt(i))) {
            return &provider_module.vtable;
        }
    }

    unreachable; // Should never reach here if metadata is valid
}

pub fn getIndex(id: ProviderId) usize {
    return @intFromEnum(id);
}

pub fn isValidProvider(name: []const u8) bool {
    return ProviderId.fromString(name) != null;
}

// Test section
test "ProviderId name and fromString" {
    try std.testing.expectEqualStrings("zai", ProviderId.zai.name());
    try std.testing.expectEqualStrings("groq", ProviderId.groq.name());
    try std.testing.expectEqual(ProviderId.zai, ProviderId.fromString("zai").?);
    try std.testing.expectEqual(ProviderId.groq, ProviderId.fromString("groq").?);
    try std.testing.expect(ProviderId.fromString("unknown") == null);
}

test "getById returns correct metadata" {
    const zai_metadata = getById(.zai).?;
    try std.testing.expectEqual(ProviderId.zai, zai_metadata.id);
    try std.testing.expectEqualStrings("zai", zai_metadata.name);
    try std.testing.expectEqualStrings("Z AI", zai_metadata.display_name);
    try std.testing.expectEqualStrings("glm-4.7-Flash", zai_metadata.default_model);

    const groq_metadata = getById(.groq).?;
    try std.testing.expectEqual(ProviderId.groq, groq_metadata.id);
    try std.testing.expectEqualStrings("groq", groq_metadata.name);
    try std.testing.expectEqualStrings("Groq", groq_metadata.display_name);
    try std.testing.expectEqualStrings("llama-3.1-8b-instant", groq_metadata.default_model);
}

test "getByName returns correct metadata" {
    const zai_metadata = getByName("zai").?;
    try std.testing.expectEqual(ProviderId.zai, zai_metadata.id);
    try std.testing.expectEqualStrings("glm-4.7-Flash", zai_metadata.default_model);

    const groq_metadata = getByName("groq").?;
    try std.testing.expectEqual(ProviderId.groq, groq_metadata.id);
    try std.testing.expectEqualStrings("llama-3.1-8b-instant", groq_metadata.default_model);
}

test "getIndex returns correct indices" {
    try std.testing.expectEqual(0, getIndex(.zai));
    try std.testing.expectEqual(1, getIndex(.groq));
}

test "isValidProvider correctly identifies valid names" {
    try std.testing.expect(isValidProvider("zai"));
    try std.testing.expect(isValidProvider("groq"));
    try std.testing.expect(!isValidProvider("unknown"));
    try std.testing.expect(!isValidProvider("openai"));
}

test "getVtable returns vtable for implemented providers" {
    // Just verify we can get the vtable without error
    _ = try getVtable("zai");
    _ = try getVtable("groq");
}

test "getVtable returns error for unknown providers" {
    const result = getVtable("unknown");
    try std.testing.expectError(error.UnknownProvider, result);
}
