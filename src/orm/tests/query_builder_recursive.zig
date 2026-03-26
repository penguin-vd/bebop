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
