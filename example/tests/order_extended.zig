const std = @import("std");
const bebop = @import("bebop");

const Order = @import("../models/order.zig");
const OrderLine = @import("../models/order_line.zig");
const Product = @import("../models/product.zig");
const Category = @import("../models/category.zig");

fn createProduct(allocator: std.mem.Allocator, conn: anytype, name: []const u8, category_name: []const u8) !Product {
    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const cat = try cat_em.create(.{ .name = category_name });
    try cat_em.flush();

    var prod_em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer prod_em.deinit();

    var categories = [_]Category{cat.*};

    const prod = try prod_em.create(.{ .name = name, .categories = &categories });
    try prod_em.flush();

    return prod.*;
}

test "get non-existent order returns null" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    const result = try em.get(999999);
    try std.testing.expectEqual(null, result);
}

test "find orders on empty table returns empty slice" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "whereStartsWith filters orders by reference" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Widget", "Widgets");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines1 = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines2 = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines3 = [_]OrderLine{
        .{ .quantity = 3, .order = std.mem.zeroes(Order), .product = product },
    };

    _ = try em.create(.{ .reference = "ORD-100", .order_lines = &lines1 });
    _ = try em.create(.{ .reference = "ORD-200", .order_lines = &lines2 });
    _ = try em.create(.{ .reference = "RET-100", .order_lines = &lines3 });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereStartsWith("reference", "ORD");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "whereEndsWith filters orders by reference" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Gadget", "Gadgets");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines1 = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines2 = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
    };

    _ = try em.create(.{ .reference = "ORD-ABC", .order_lines = &lines1 });
    _ = try em.create(.{ .reference = "ORD-XYZ", .order_lines = &lines2 });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereEndsWith("reference", "ABC");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
}

test "create multiple orders and list all" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Item", "Items");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines1 = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines2 = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines3 = [_]OrderLine{
        .{ .quantity = 3, .order = std.mem.zeroes(Order), .product = product },
    };

    _ = try em.create(.{ .reference = "ORD-A", .order_lines = &lines1 });
    _ = try em.create(.{ .reference = "ORD-B", .order_lines = &lines2 });
    _ = try em.create(.{ .reference = "ORD-C", .order_lines = &lines3 });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
}

test "order with single order line" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Single", "Singles");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 10, .order = std.mem.zeroes(Order), .product = product },
    };

    const order = try em.create(.{ .reference = "ORD-SINGLE", .order_lines = &lines });
    defer allocator.destroy(order);
    try em.flush();

    em.clear();

    const fetched = try em.get(order.id);
    try std.testing.expect(fetched != null);
    defer em.freeModel(fetched.?);

    try std.testing.expectEqual(@as(usize, 1), fetched.?.order_lines.len);
    try std.testing.expectEqual(@as(i32, 10), fetched.?.order_lines[0].quantity);
}

test "query orders with limit" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Limited", "Limits");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines1 = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines2 = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
    };
    var lines3 = [_]OrderLine{
        .{ .quantity = 3, .order = std.mem.zeroes(Order), .product = product },
    };

    _ = try em.create(.{ .reference = "LIM-1", .order_lines = &lines1 });
    _ = try em.create(.{ .reference = "LIM-2", .order_lines = &lines2 });
    _ = try em.create(.{ .reference = "LIM-3", .order_lines = &lines3 });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    qb.limit = 2;

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}
