const std = @import("std");
const Order = @import("models/order.zig");

const QueryBuilder = @import("../query_builder.zig").QueryBuilder;

test "simple query" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Order).init(allocator);
    defer qb.deinit();

    qb.select();
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expectEqualStrings("SELECT orders.id, orders.reference, order_lines.id, order_lines.quantity " ++
        "FROM orders " ++
        "LEFT JOIN order_lines ON orders.id = order_lines.order_id", result.sql);

    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}

test "order query includes many-relation columns in default select" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Order).init(allocator);
    defer qb.deinit();

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expect(std.mem.indexOf(u8, result.sql, "order_lines.id") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.sql, "order_lines.quantity") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.sql, "LEFT JOIN order_lines") != null);
}

test "order query with where on scalar field" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Order).init(allocator);
    defer qb.deinit();

    try qb.where("reference", "=", "REF-001");
    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer {
        for (result.params) |param| allocator.free(param);
        allocator.free(result.params);
    }

    try std.testing.expectEqualStrings(
        "SELECT orders.id, orders.reference, order_lines.id, order_lines.quantity " ++
            "FROM orders " ++
            "LEFT JOIN order_lines ON orders.id = order_lines.order_id " ++
            "WHERE orders.reference = $1",
        result.sql,
    );
    try std.testing.expectEqual(@as(usize, 1), result.params.len);
    try std.testing.expectEqualStrings("REF-001", result.params[0]);
}

test "order query select specific fields skips unused joins" {
    const allocator = std.testing.allocator;

    var qb = QueryBuilder(Order).init(allocator);
    defer qb.deinit();

    const fields = [_][]const u8{ "id", "reference" };
    try qb.selectFields(&fields);

    const result = try qb.toSql();
    defer allocator.free(result.sql);
    defer allocator.free(result.params);

    try std.testing.expectEqualStrings(
        "SELECT orders.id, orders.reference FROM orders",
        result.sql,
    );
    try std.testing.expectEqual(@as(usize, 0), result.params.len);
}
