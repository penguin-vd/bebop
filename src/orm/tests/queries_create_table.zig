const std = @import("std");

const utils = @import("../utils.zig");
const queries = @import("../queries.zig");
const types = @import("../types.zig");

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

test "create table: simple model" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, SimpleModel);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "CREATE TABLE IF NOT EXISTS users") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "id INTEGER") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "name TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "age INTEGER") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "PRIMARY KEY (id)") != null);
}

test "create table: model with defaults" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithDefaults);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "score INTEGER") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "active BOOLEAN") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT true") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "status TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "DEFAULT 'active'") != null);
}

test "create table: model with optional field" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithOptional);
    defer allocator.free(sql);

    // bio is optional, so it should NOT have NOT NULL
    try std.testing.expect(std.mem.indexOf(u8, sql, "bio TEXT") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "bio TEXT NOT NULL") == null);
    // name is required
    try std.testing.expect(std.mem.indexOf(u8, sql, "name TEXT NOT NULL") != null);
}

test "create table: model with unique field" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithUnique);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "email TEXT NOT NULL UNIQUE") != null);
}

test "create table: model with foreign key" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithFK);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "team_id INTEGER REFERENCES teams(id)") != null);
}

test "create table: auto increment" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, SimpleModel);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "GENERATED ALWAYS AS IDENTITY") != null);
}

const ModelWithCustomTypes = struct {
    id: i32,
    external_id: types.Uuid,
    created_at: types.DateTime,
    birth_date: types.Date,

    pub const table_name = "events";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .external_id = utils.FieldMeta(types.Uuid){},
        .created_at = utils.FieldMeta(types.DateTime){},
        .birth_date = utils.FieldMeta(types.Date){},
    };
};

test "create table: UUID, TIMESTAMPTZ, DATE columns" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithCustomTypes);
    defer allocator.free(sql);

    try std.testing.expect(std.mem.indexOf(u8, sql, "external_id UUID") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "created_at TIMESTAMPTZ") != null);
    try std.testing.expect(std.mem.indexOf(u8, sql, "birth_date DATE") != null);
}

const ModelWithEncrypted = struct {
    id: i32,
    ssn: []const u8,

    pub const table_name = "secrets";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .ssn = utils.FieldMeta([]const u8){ .is_encrypted = true, .max_length = 255 },
    };
};

test "create table: encrypted field stores as TEXT" {
    const allocator = std.testing.allocator;
    const sql = try queries.build_create_table_query(allocator, ModelWithEncrypted);
    defer allocator.free(sql);

    // Encryption is transparent to DDL: field stays TEXT.
    try std.testing.expect(std.mem.indexOf(u8, sql, "ssn TEXT NOT NULL") != null);
}
