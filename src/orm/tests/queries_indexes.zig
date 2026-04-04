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

const ModelWithIndex = struct {
    id: i32,
    name: []const u8,

    pub const table_name = "items";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"name"} },
    };
};

const ModelWithNamedIndex = struct {
    id: i32,
    email: []const u8,

    pub const table_name = "contacts";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .email = utils.FieldMeta([]const u8){ .max_length = 255 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"email"}, .unique = true, .name = "contacts_email_unique" },
    };
};

const ModelWithCompositeIndex = struct {
    id: i32,
    first_name: []const u8,
    last_name: []const u8,

    pub const table_name = "people";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .first_name = utils.FieldMeta([]const u8){ .max_length = 100 },
        .last_name = utils.FieldMeta([]const u8){ .max_length = 100 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{ "first_name", "last_name" } },
    };
};

const ModelWithHashIndex = struct {
    id: i32,
    token: []const u8,

    pub const table_name = "tokens";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .token = utils.FieldMeta([]const u8){ .max_length = 255 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"token"}, .method = .hash },
    };
};

const ModelWithPartialIndex = struct {
    id: i32,
    status: []const u8,

    pub const table_name = "jobs";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .status = utils.FieldMeta([]const u8){ .max_length = 50 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"status"}, .where_clause = "status = 'pending'" },
    };
};

const ModelWithIncludeIndex = struct {
    id: i32,
    email: []const u8,
    name: []const u8,

    pub const table_name = "subscribers";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .email = utils.FieldMeta([]const u8){ .max_length = 255 },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"email"}, .include = &.{"name"} },
    };
};

const ModelWithConcurrentIndex = struct {
    id: i32,
    slug: []const u8,

    pub const table_name = "posts";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .slug = utils.FieldMeta([]const u8){ .max_length = 255 },
    };

    pub const indexes = &[_]utils.Index{
        .{ .fields = &.{"slug"}, .unique = true, .concurrently = true },
    };
};

const ModelWithNoIndexes = struct {
    id: i32,
    value: i32,

    pub const table_name = "raw_data";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .value = utils.FieldMeta(i32){},
    };
};

// -- CREATE INDEX tests --

test "create index: simple btree index with auto-generated name" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "CREATE INDEX") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "IF NOT EXISTS") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "idx_items_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "ON items") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "(name)") != null);
    // btree is default and should not appear
    try std.testing.expect(std.mem.indexOf(u8, result[0], "USING") == null);
}

test "create index: unique named index" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithNamedIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "CREATE UNIQUE INDEX") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "contacts_email_unique") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "ON contacts") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "(email)") != null);
}

test "create index: composite index auto-generated name includes all fields" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithCompositeIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "idx_people_first_name_last_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "(first_name, last_name)") != null);
}

test "create index: non-btree method emits USING clause" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithHashIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "USING hash") != null);
}

test "create index: partial index emits WHERE clause" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithPartialIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "WHERE status = 'pending'") != null);
}

test "create index: INCLUDE clause" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithIncludeIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "INCLUDE (name)") != null);
}

test "create index: CONCURRENTLY flag" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithConcurrentIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expect(std.mem.indexOf(u8, result[0], "CONCURRENTLY") != null);
}

test "create index: model without indexes returns empty" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, ModelWithNoIndexes);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

test "create index: model without indexes decl returns empty" {
    const allocator = std.testing.allocator;
    const result = try queries.build_create_index_queries(allocator, SimpleModel);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

// -- DROP INDEX tests --

test "drop index: auto-generated name" {
    const allocator = std.testing.allocator;
    const result = try queries.build_drop_index_queries(allocator, ModelWithIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_items_name;", result[0]);
}

test "drop index: named index uses custom name" {
    const allocator = std.testing.allocator;
    const result = try queries.build_drop_index_queries(allocator, ModelWithNamedIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("DROP INDEX IF EXISTS contacts_email_unique;", result[0]);
}

test "drop index: composite index auto-generated name" {
    const allocator = std.testing.allocator;
    const result = try queries.build_drop_index_queries(allocator, ModelWithCompositeIndex);
    defer {
        for (result) |q| allocator.free(q);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("DROP INDEX IF EXISTS idx_people_first_name_last_name;", result[0]);
}

test "drop index: model without indexes returns empty" {
    const allocator = std.testing.allocator;
    const result = try queries.build_drop_index_queries(allocator, ModelWithNoIndexes);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}

// -- GET INDEX NAMES tests --

test "get index names: auto-generated name" {
    const allocator = std.testing.allocator;
    const result = try queries.get_index_names(allocator, ModelWithIndex);
    defer {
        for (result) |n| allocator.free(n);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("idx_items_name", result[0]);
}

test "get index names: custom name returned as-is" {
    const allocator = std.testing.allocator;
    const result = try queries.get_index_names(allocator, ModelWithNamedIndex);
    defer {
        for (result) |n| allocator.free(n);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("contacts_email_unique", result[0]);
}

test "get index names: composite index" {
    const allocator = std.testing.allocator;
    const result = try queries.get_index_names(allocator, ModelWithCompositeIndex);
    defer {
        for (result) |n| allocator.free(n);
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);
    try std.testing.expectEqualStrings("idx_people_first_name_last_name", result[0]);
}

test "get index names: model without indexes returns empty" {
    const allocator = std.testing.allocator;
    const result = try queries.get_index_names(allocator, ModelWithNoIndexes);

    try std.testing.expectEqual(@as(usize, 0), result.len);
}
