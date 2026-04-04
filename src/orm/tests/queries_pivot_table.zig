const std = @import("std");

const utils = @import("../utils.zig");
const queries = @import("../queries.zig");

const SimpleModel = struct {
    id: i32,
    name: []const u8,
    age: i32,

    pub const table_name = "users";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
        .age = utils.FieldMeta(i32){},
    };
};

const Tag = struct {
    id: i32,
    name: []const u8,

    pub const table_name = "tags";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 100 },
    };
};

const ModelWithM2M = struct {
    id: i32,
    title: []const u8,
    tags: []Tag,

    pub const table_name = "articles";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .title = utils.FieldMeta([]const u8){ .max_length = 255 },
        .tags = utils.FieldMeta([]Tag){ .many_to_many = true },
    };
};

test "pivot table: generates create query" {
    const allocator = std.testing.allocator;
    const result = try queries.build_pivot_table_queries(allocator, ModelWithM2M);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "CREATE TABLE IF NOT EXISTS articles_tags") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "articles_id INTEGER REFERENCES articles(id)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "tags_id INTEGER REFERENCES tags(id)") != null);
}

test "pivot table: generates drop query" {
    const allocator = std.testing.allocator;
    const result = try queries.build_drop_pivot_table_queries(allocator, ModelWithM2M);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("DROP TABLE IF EXISTS articles_tags CASCADE;", result[0]);
}

test "pivot table: model without m2m returns empty" {
    const allocator = std.testing.allocator;
    const result = try queries.build_pivot_table_queries(allocator, SimpleModel);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}
