const std = @import("std");
const types = @import("../types.zig");

test "Uuid: new produces v4 with correct version/variant bits" {
    const u = types.Uuid.new();
    try std.testing.expectEqual(@as(u8, 0x40), u.bytes[6] & 0xF0);
    try std.testing.expectEqual(@as(u8, 0x80), u.bytes[8] & 0xC0);
}

test "Uuid: toString and parse roundtrip" {
    const original = types.Uuid.new();
    var buf: [36]u8 = undefined;
    original.toString(&buf);

    const parsed = try types.Uuid.parse(&buf);
    try std.testing.expectEqualSlices(u8, &original.bytes, &parsed.bytes);
}

test "Uuid: parse accepts known fixture" {
    const fixture = "550e8400-e29b-41d4-a716-446655440000";
    const u = try types.Uuid.parse(fixture);
    try std.testing.expectEqual(@as(u8, 0x55), u.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0x0e), u.bytes[1]);
    try std.testing.expectEqual(@as(u8, 0x41), u.bytes[6]);
    try std.testing.expectEqual(@as(u8, 0xa7), u.bytes[8]);
}

test "Uuid: parse rejects malformed input" {
    try std.testing.expectError(error.InvalidUuid, types.Uuid.parse("not-a-uuid"));
    try std.testing.expectError(error.InvalidUuid, types.Uuid.parse("550e8400e29b41d4a716446655440000"));
}

test "Uuid: to_sql_param returns hyphenated 36-char string" {
    const u = try types.Uuid.parse("550e8400-e29b-41d4-a716-446655440000");
    const allocator = std.testing.allocator;
    const s = try u.to_sql_param(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualSlices(u8, "550e8400-e29b-41d4-a716-446655440000", s);
}

test "Uuid: sql_type is UUID" {
    try std.testing.expectEqualSlices(u8, "UUID", types.Uuid.sql_type);
}

test "DateTime: fromUnix + to_sql_param formats correctly" {
    const allocator = std.testing.allocator;
    // 2024-01-02 03:04:05 UTC = 1704164645
    const dt = types.DateTime.fromUnix(1704164645);
    const s = try dt.to_sql_param(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualSlices(u8, "2024-01-02 03:04:05.000000+00:00", s);
}

test "DateTime: roundtrip via to_sql_param / from_sql_param" {
    const allocator = std.testing.allocator;
    const original = types.DateTime{ .micros = 1704164645_123456 };
    const s = try original.to_sql_param(allocator);
    defer allocator.free(s);

    const parsed = try types.DateTime.from_sql_param(allocator, s);
    try std.testing.expectEqual(original.micros, parsed.micros);
}

test "DateTime: from_sql_param handles timezone offset" {
    const allocator = std.testing.allocator;
    // 2024-01-02 05:04:05 +02:00 == 2024-01-02 03:04:05 UTC
    const dt = try types.DateTime.from_sql_param(allocator, "2024-01-02 05:04:05+02:00");
    try std.testing.expectEqual(@as(i64, 1704164645_000_000), dt.micros);
}

test "DateTime: from_sql_param handles negative timezone" {
    const allocator = std.testing.allocator;
    const dt = try types.DateTime.from_sql_param(allocator, "2024-01-02 00:04:05-03:00");
    try std.testing.expectEqual(@as(i64, 1704164645_000_000), dt.micros);
}

test "DateTime: sql_type is TIMESTAMPTZ" {
    try std.testing.expectEqualSlices(u8, "TIMESTAMPTZ", types.DateTime.sql_type);
}

test "Date: fromYmd + to_sql_param roundtrip" {
    const allocator = std.testing.allocator;
    const d = types.Date.fromYmd(2024, 1, 2);
    const s = try d.to_sql_param(allocator);
    defer allocator.free(s);

    try std.testing.expectEqualSlices(u8, "2024-01-02", s);

    const parsed = try types.Date.from_sql_param(allocator, s);
    try std.testing.expectEqual(d.days, parsed.days);
}

test "Date: epoch anchor is 1970-01-01" {
    const d = types.Date.fromYmd(1970, 1, 1);
    try std.testing.expectEqual(@as(i32, 0), d.days);
}

test "Date: sql_type is DATE" {
    try std.testing.expectEqualSlices(u8, "DATE", types.Date.sql_type);
}

test "is_custom_type: true for Uuid/DateTime/Date, false for primitives and models" {
    const FakeModel = struct {
        id: i32,
        pub const table_name = "x";
        pub const field_meta = .{};
    };

    try std.testing.expect(types.is_custom_type(types.Uuid));
    try std.testing.expect(types.is_custom_type(types.DateTime));
    try std.testing.expect(types.is_custom_type(types.Date));
    try std.testing.expect(!types.is_custom_type(i32));
    try std.testing.expect(!types.is_custom_type([]const u8));
    try std.testing.expect(!types.is_custom_type(FakeModel));
}
