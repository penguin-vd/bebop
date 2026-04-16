const std = @import("std");

const utils = @import("../utils.zig");
const types = @import("../types.zig");
const QueryBuilder = @import("../query_builder.zig").QueryBuilder;

const User = struct {
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

const Product = struct {
    id: i32,
    price: f64,
    in_stock: bool,

    pub const table_name = "products";

    pub const field_meta = .{
        .id = utils.FieldMeta(i32){ .is_primary_key = true, .is_auto_increment = true },
        .price = utils.FieldMeta(f64){},
        .in_stock = utils.FieldMeta(bool){},
    };
};

const Event = struct {
    id: types.Uuid,
    created_at: types.DateTime,
    scheduled_date: types.Date,
    deleted_at: ?types.DateTime,

    pub const table_name = "events";

    pub const field_meta = .{
        .id = utils.FieldMeta(types.Uuid){ .is_primary_key = true },
        .created_at = utils.FieldMeta(types.DateTime){},
        .scheduled_date = utils.FieldMeta(types.Date){},
        .deleted_at = utils.FieldMeta(?types.DateTime){},
    };
};

fn freeResult(allocator: std.mem.Allocator, result: anytype) void {
    allocator.free(result.sql);
    for (result.params) |param| {
        allocator.free(param);
    }
    allocator.free(result.params);
}

test "whereStartsWith generates ILIKE with suffix wildcard" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.whereStartsWith("name", "Al");
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.name ILIKE $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("Al%", result.params[0]);
}

test "whereEndsWith generates ILIKE with prefix wildcard" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.whereEndsWith("name", "son");
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.name ILIKE $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("%son", result.params[0]);
}

test "whereILike generates ILIKE with both wildcards" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.whereILike("name", "bob");
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.name ILIKE $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("%bob%", result.params[0]);
}

test "where with != operator" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("age", "!=", 18);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.age != $1", result.sql);

    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("18", result.params[0]);
}

test "where with < operator" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("age", "<", 30);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.age < $1", result.sql);

    try std.testing.expectEqualStrings("30", result.params[0]);
}

test "where with <= operator" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Product).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("price", "<=", 9.99);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT products.id, products.price, products.in_stock " ++
        "FROM products " ++
        "WHERE products.price <= $1", result.sql);

    try std.testing.expectEqualStrings("9.99", result.params[0]);
}

test "whereStartsWith combined with where" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.whereStartsWith("name", "A");
    try qb.where("age", ">", 21);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.name ILIKE $1 AND users.age > $2", result.sql);

    try std.testing.expectEqual(@as(usize, 2), result.params.len);
    try std.testing.expectEqualStrings("A%", result.params[0]);
    try std.testing.expectEqualStrings("21", result.params[1]);
}

test "whereEndsWith combined with whereStartsWith" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.whereStartsWith("name", "A");
    try qb.whereEndsWith("name", "z");
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "WHERE users.name ILIKE $1 AND users.name ILIKE $2", result.sql);

    try std.testing.expectEqual(@as(usize, 2), result.params.len);
    try std.testing.expectEqualStrings("A%", result.params[0]);
    try std.testing.expectEqualStrings("%z", result.params[1]);
}

test "clear resets where conditions and limit" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    try qb.where("age", ">", 18);
    qb.limit = 5;
    qb.page = 2;

    qb.clear();
    qb.select();

    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age FROM users", result.sql);
    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "limit without page defaults to offset 0" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    qb.limit = 10;

    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "LIMIT 10 OFFSET 0", result.sql);
}

test "page 0 with limit gives offset 0" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    qb.limit = 5;
    qb.page = 0;

    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "LIMIT 5 OFFSET 0", result.sql);
}

test "high page number computes correct offset" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();
    qb.limit = 10;
    qb.page = 100;

    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age " ++
        "FROM users " ++
        "LIMIT 10 OFFSET 1000", result.sql);
}

test "default select with no conditions" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(User).init(allocator);
    defer qb.deinit();

    qb.select();

    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings("SELECT users.id, users.name, users.age FROM users", result.sql);
    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "where with Uuid custom type serialises to hyphenated string param" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Event).init(allocator);
    defer qb.deinit();

    qb.select();
    const uuid = try types.Uuid.parse("550e8400-e29b-41d4-a716-446655440000");
    try qb.where("id", "=", uuid);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings(
        "SELECT events.id, events.created_at, events.scheduled_date, events.deleted_at " ++
            "FROM events " ++
            "WHERE events.id = $1",
        result.sql,
    );
    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("550e8400-e29b-41d4-a716-446655440000", result.params[0]);
}

test "where with DateTime custom type serialises to timestamp string param" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Event).init(allocator);
    defer qb.deinit();

    qb.select();
    // 2024-01-02 03:04:05 UTC
    const dt = types.DateTime.fromUnix(1704164645);
    try qb.where("created_at", ">=", dt);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings(
        "SELECT events.id, events.created_at, events.scheduled_date, events.deleted_at " ++
            "FROM events " ++
            "WHERE events.created_at >= $1",
        result.sql,
    );
    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("2024-01-02 03:04:05.000000+00:00", result.params[0]);
}

test "where with Date custom type serialises to date string param" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Event).init(allocator);
    defer qb.deinit();

    qb.select();
    const date = types.Date.fromYmd(2024, 6, 15);
    try qb.where("scheduled_date", "=", date);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings(
        "SELECT events.id, events.created_at, events.scheduled_date, events.deleted_at " ++
            "FROM events " ++
            "WHERE events.scheduled_date = $1",
        result.sql,
    );
    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("2024-06-15", result.params[0]);
}

test "where with optional DateTime set serialises to timestamp string param" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Event).init(allocator);
    defer qb.deinit();

    qb.select();
    const dt: ?types.DateTime = types.DateTime.fromUnix(1704164645);
    try qb.where("deleted_at", "IS NOT", dt);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings(
        "SELECT events.id, events.created_at, events.scheduled_date, events.deleted_at " ++
            "FROM events " ++
            "WHERE events.deleted_at IS NOT $1",
        result.sql,
    );
    try std.testing.expectEqualStrings("2024-01-02 03:04:05.000000+00:00", result.params[0]);
}

test "where with optional DateTime null serialises to NULL param" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Event).init(allocator);
    defer qb.deinit();

    qb.select();
    const dt: ?types.DateTime = null;
    try qb.where("deleted_at", "IS", dt);
    const result = try qb.toSql();
    defer freeResult(allocator, result);

    try std.testing.expectEqualStrings(
        "SELECT events.id, events.created_at, events.scheduled_date, events.deleted_at " ++
            "FROM events " ++
            "WHERE events.deleted_at IS $1",
        result.sql,
    );
    try std.testing.expectEqualStrings("NULL", result.params[0]);
}
