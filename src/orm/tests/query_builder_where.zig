const std = @import("std");

const utils = @import("../utils.zig");
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
