const std = @import("std");
const bebop = @import("bebop");

const Product = @import("../models/product.zig");
const Category = @import("../models/category.zig");

test "whereStartsWith filters products" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cats1 = [_]Category{.{ .name = "Electronics" }};
    var cats2 = [_]Category{.{ .name = "Books" }};

    _ = try em.create(.{ .name = "Laptop Pro", .categories = &cats1 });
    _ = try em.create(.{ .name = "Laptop Air", .categories = &cats1 });
    _ = try em.create(.{ .name = "Book Reader", .categories = &cats2 });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereStartsWith("name", "Laptop");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "whereEndsWith filters products" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cats = [_]Category{.{ .name = "Electronics" }};

    _ = try em.create(.{ .name = "Laptop Pro", .categories = &cats });
    _ = try em.create(.{ .name = "Tablet Pro", .categories = &cats });
    _ = try em.create(.{ .name = "Phone Mini", .categories = &cats });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereEndsWith("name", "Pro");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "get non-existent product returns null" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    const result = try em.get(999999);
    try std.testing.expectEqual(null, result);
}

test "find products on empty table returns empty slice" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "product with no categories" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var empty_cats = [_]Category{};

    const product = try em.create(.{
        .name = "Standalone Product",
        .categories = &empty_cats,
    });
    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(@as(usize, 0), product.categories.len);

    defer allocator.destroy(product);
    em.clear();

    const fetched = try em.get(product.id);
    try std.testing.expect(fetched != null);
    defer em.freeModel(fetched.?);
    try std.testing.expectEqual(@as(usize, 0), fetched.?.categories.len);
}

test "query products with limit" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cats = [_]Category{.{ .name = "General" }};

    _ = try em.create(.{ .name = "Product 1", .categories = &cats });
    _ = try em.create(.{ .name = "Product 2", .categories = &cats });
    _ = try em.create(.{ .name = "Product 3", .categories = &cats });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    qb.limit = 2;

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}
