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

test "create order with order lines" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Laptop", "Electronics");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };

    const order = try em.create(.{
        .reference = "ORD-001",
        .order_lines = &lines,
    });

    try std.testing.expectEqual(@as(i32, 0), order.id);

    try em.flush();

    try std.testing.expect(order.id != 0);
    try std.testing.expectEqual(@as(i32, 2), lines[0].quantity);
    try std.testing.expect(lines[0].id != 0);
    try std.testing.expect(lines[1].id != 0);
}

test "list orders with order lines loaded" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Phone", "Gadgets");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 3, .order = std.mem.zeroes(Order), .product = product },
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };

    _ = try em.create(.{ .reference = "ORD-002", .order_lines = &lines });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    const orders = try em.find(&qb);
    defer em.freeModels(orders);

    try std.testing.expectEqual(@as(usize, 1), orders.len);
    try std.testing.expectEqual(@as(usize, 2), orders[0].order_lines.len);
}

test "get order by id" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Tablet", "Devices");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 5, .order = std.mem.zeroes(Order), .product = product },
    };

    const created = try em.create(.{ .reference = "ORD-003", .order_lines = &lines });
    defer allocator.destroy(created);
    try em.flush();

    em.clear();

    const order = try em.get(created.id);
    try std.testing.expect(order != null);

    if (order) |o| {
        defer em.freeModel(o);
        try std.testing.expectEqualStrings("ORD-003", o.reference);
        try std.testing.expectEqual(@as(usize, 1), o.order_lines.len);
        try std.testing.expectEqual(@as(i32, 5), o.order_lines[0].quantity);
    }
}

test "update order reference" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Monitor", "Electronics");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };

    const order = try em.create(.{ .reference = "OLD-REF", .order_lines = &lines });
    defer allocator.destroy(order);
    try em.flush();

    order.reference = "NEW-REF";
    try em.flush();

    em.clear();

    const fetched = try em.get(order.id);
    try std.testing.expect(fetched != null);
    if (fetched) |f| {
        defer em.freeModel(f);
        try std.testing.expectEqualStrings("NEW-REF", f.reference);
    }
}

test "add order line to existing order" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Keyboard", "Peripherals");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var initial_lines = [_]OrderLine{
        .{ .quantity = 1, .order = std.mem.zeroes(Order), .product = product },
    };

    const order = try em.create(.{ .reference = "ORD-ADD", .order_lines = &initial_lines });
    defer allocator.destroy(order);
    try em.flush();

    try std.testing.expect(initial_lines[0].id != 0);

    // Build a new slice with both the existing line and a new one
    var updated_lines = try allocator.alloc(OrderLine, 2);
    defer allocator.free(updated_lines);
    updated_lines[0] = initial_lines[0];
    updated_lines[1] = .{ .quantity = 4, .order = std.mem.zeroes(Order), .product = product };

    order.order_lines = updated_lines;
    try em.flush();

    try std.testing.expect(updated_lines[1].id != 0);

    em.clear();

    var qb = em.query();
    defer qb.deinit();
    try qb.where("id", "=", order.id);

    const orders = try em.find(&qb);
    defer em.freeModels(orders);

    try std.testing.expectEqual(@as(usize, 1), orders.len);
    try std.testing.expectEqual(@as(usize, 2), orders[0].order_lines.len);
}

test "delete order" {
    const allocator = std.testing.allocator;

    var env = try bebop.testing.TestEnvironment.init(allocator);
    defer env.deinit();

    var conn = try env.pool.acquire();
    defer conn.release();

    const product = try createProduct(allocator, conn, "Mouse", "Peripherals");

    var em = bebop.orm.EntityManager(Order).init(allocator, conn);
    defer em.deinit();

    var lines = [_]OrderLine{
        .{ .quantity = 2, .order = std.mem.zeroes(Order), .product = product },
    };

    const order = try em.create(.{ .reference = "ORD-DEL", .order_lines = &lines });
    try em.flush();

    const id = order.id;
    try std.testing.expect(id != 0);

    // Delete order lines first (no cascade in schema)
    var line_em = bebop.orm.EntityManager(OrderLine).init(allocator, conn);
    defer line_em.deinit();

    var line_qb = line_em.query();
    defer line_qb.deinit();
    try line_qb.where("order", "=", id);

    const order_lines = try line_em.find(&line_qb);
    defer line_em.freeModels(order_lines);

    for (order_lines) |line| {
        try line_em.remove(line);
    }
    try line_em.flush();

    try em.remove(order);
    try em.flush();

    const deleted = try em.get(id);
    try std.testing.expectEqual(null, deleted);
}
