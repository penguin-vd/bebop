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

const ModelWithDefaults = struct {
    id: i32,
    name: []const u8,
    score: i32,
    active: bool,
    status: []const u8,

    pub const table_name = "players";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 100 },
        .score = utils.FieldMeta(i32){ .default_value = "0" },
        .active = utils.FieldMeta(bool){ .default_value = "true" },
        .status = utils.FieldMeta([]const u8){ .max_length = 50, .default_value = "active" },
    };
};

const ModelWithOptional = struct {
    id: i32,
    name: []const u8,
    bio: ?[]const u8,

    pub const table_name = "profiles";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .name = utils.FieldMeta([]const u8){ .max_length = 255 },
        .bio = utils.FieldMeta(?[]const u8){},
    };
};

const ModelWithUnique = struct {
    id: i32,
    email: []const u8,

    pub const table_name = "accounts";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .email = utils.FieldMeta([]const u8){ .is_unique = true, .max_length = 255 },
    };
};

const RelatedModel = struct {
    id: i32,

    pub const table_name = "teams";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
    };
};

const ModelWithFK = struct {
    id: i32,
    team: RelatedModel,

    pub const table_name = "members";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .team = utils.FieldMeta(RelatedModel){},
    };
};

fn table_info_from(allocator: std.mem.Allocator, columns: []const [2][]const u8) !std.ArrayList(utils.TableInformation) {
    var list: std.ArrayList(utils.TableInformation) = .{};
    for (columns) |col| {
        try list.append(allocator, .{
            .column = try allocator.dupe(u8, col[0]),
            .type = try allocator.dupe(u8, col[1]),
        });
    }
    return list;
}

fn free_table_info(allocator: std.mem.Allocator, info: *std.ArrayList(utils.TableInformation)) void {
    for (info.items) |item| {
        allocator.free(item.column);
        allocator.free(item.type);
    }
    info.deinit(allocator);
}

// -- ALTER TABLE tests --

test "alter table: add new column" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, SimpleModel, info);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN age INTEGER") != null);
}

test "alter table: add new column with user-defined default" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, ModelWithDefaults, info);
    defer allocator.free(sql);

    // Should use the user-defined default from field_meta, not the type-based fallback
    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN score INTEGER") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN active BOOLEAN") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT true") != null);
    // String defaults must be single-quoted for valid SQL
    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN status TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 'active'") != null);
}

test "alter table: drop removed column" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
        .{ "age", "INTEGER" },
        .{ "old_column", "TEXT" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, SimpleModel, info);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "DROP COLUMN old_column") != null);
}

test "alter table: no changes needed" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
        .{ "age", "INTEGER" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, SimpleModel, info);
    defer allocator.free(sql);

    try std.testing.expectEqual(@as(usize, 0), sql.len);
}

test "alter table: add column with unique constraint" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, ModelWithUnique, info);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN email TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "UNIQUE") != null);
}

test "alter table: add foreign key column" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, ModelWithFK, info);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN team_id INTEGER REFERENCES teams(id)") != null);
}

test "alter table: add optional column has no default" {
    const allocator = std.testing.allocator;
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_alter_table_query(allocator, ModelWithOptional, info);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN bio TEXT") != null);
    // Optional columns should not get a DEFAULT
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT") == null);
}

// -- DROP TABLE tests --

test "drop table: generates correct SQL" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_drop_table_query(allocator, SimpleModel);
    defer allocator.free(sql);

    try std.testing.expectEqualStrings("DROP TABLE IF EXISTS users CASCADE;", sql);
}

// -- REVERSE ALTER TABLE tests --

test "reverse alter: undo add column" {
    const allocator = std.testing.allocator;
    // Table currently has id and name; model adds age
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_reverse_alter_table_query(allocator, SimpleModel, info);
    defer allocator.free(sql);

    // Reversing ADD COLUMN age -> DROP COLUMN age
    try std.testing.expect(std.mem.indexOf(u8, sql, "DROP COLUMN IF EXISTS age") != null);
}

test "reverse alter: undo drop column" {
    const allocator = std.testing.allocator;
    // Table has an extra column that the model doesn't have
    var info = try table_info_from(allocator, &.{
        .{ "id", "INTEGER" },
        .{ "name", "TEXT" },
        .{ "age", "INTEGER" },
        .{ "old_col", "VARCHAR(255)" },
    });
    defer free_table_info(allocator, &info);

    const sql = try queries.build_reverse_alter_table_query(allocator, SimpleModel, info);
    defer allocator.free(sql);

    // Reversing DROP COLUMN old_col -> ADD COLUMN old_col with original type
    try std.testing.expect(std.mem.indexOf(u8, sql, "ADD COLUMN old_col VARCHAR(255)") != null);
}
