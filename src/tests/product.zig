const std = @import("std");
const bebop = @import("../lib/bebop.zig");

const Product = @import("../models/product.zig");
const Category = @import("../models/category.zig");

test "test create product with existing category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const category = try cat_em.create(.{ .name = "Electronics" });
    try cat_em.flush();

    try std.testing.expect(category.id != 0);

    const product = try em.create(.{
        .name = "Laptop",
        .category = category.*,
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(category.id, product.category.id);
}

test "test create product with new category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    // Create product with an unsaved category
    const product = try em.create(.{
        .name = "Phone",
        .category = .{ .name = "Electronics" },
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);
    try std.testing.expectEqual(@as(i32, 0), product.category.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expect(product.category.id != 0);
}

test "test list products" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    try std.testing.expectEqual(@as(u32, 0), em.tracked_entities.count());

    var qb = em.query();
    defer qb.deinit();

    const empty = try em.find(&qb);
    defer em.freeModels(empty);

    try std.testing.expectEqual(@as(usize, 0), empty.len);

    _ = try em.create(.{
        .name = "Test Product",
        .category = .{ .name = "Test Category" },
    });
    try em.flush();

    try std.testing.expectEqual(@as(u32, 1), em.tracked_entities.count());

    const one = try em.find(&qb);
    defer em.freeModels(one);

    try std.testing.expectEqual(@as(usize, 1), one.len);
    try std.testing.expectEqual(@as(u32, 1), em.tracked_entities.count());
}

test "test filtering products" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{
        .name = "Laptop",
        .category = .{ .name = "Electronics" },
    });
    _ = try em.create(.{
        .name = "Book",
        .category = .{ .name = "Literature" },
    });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereILike("name", "Laptop");

    const laptops = try em.find(&qb);
    defer em.freeModels(laptops);

    try std.testing.expectEqual(@as(usize, 1), laptops.len);
    qb.clear();

    try qb.whereILike("name", "Gibberish");

    const empty = try em.find(&qb);
    defer em.freeModels(empty);

    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "test get product" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    const createdProduct = try em.create(.{
        .name = "Test Product",
        .category = .{ .name = "Test Category" },
    });

    defer allocator.destroy(createdProduct);

    try em.flush();

    em.clear();

    const product = try em.get(createdProduct.id);

    try std.testing.expect(product != null);

    if (product) |p| {
        defer em.freeModel(p);

        try std.testing.expectEqual(p.id, createdProduct.id);
        try std.testing.expect(p.category.id != 0);
        try std.testing.expectEqualStrings(createdProduct.name, p.name);
    }
}

test "test update product" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    const createdProduct = try em.create(.{
        .name = "Old Name",
        .category = .{ .name = "Electronics" },
    });
    defer allocator.destroy(createdProduct);

    try em.flush();

    createdProduct.name = "New Name";

    try em.flush();
    em.clear();

    const product = try em.get(createdProduct.id);

    try std.testing.expect(product != null);

    if (product) |p| {
        defer em.freeModel(p);

        try std.testing.expectEqualStrings("New Name", p.name);
    }
}

test "test update product category to existing" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const cat1 = try cat_em.create(.{ .name = "Electronics" });
    const cat2 = try cat_em.create(.{ .name = "Books" });
    try cat_em.flush();

    const createdProduct = try em.create(.{
        .name = "Product",
        .category = cat1.*,
    });
    defer allocator.destroy(createdProduct);
    try em.flush();

    const original_id = createdProduct.id;

    createdProduct.category = cat2.*;
    try em.flush();

    em.clear();

    const product = try em.get(original_id);
    try std.testing.expect(product != null);

    defer em.freeModel(product.?);
    try std.testing.expectEqual(cat2.id, product.?.category.id);
}

test "test update product category to new" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    const createdProduct = try em.create(.{
        .name = "Product",
        .category = .{ .name = "Old Category" },
    });
    defer allocator.destroy(createdProduct);
    try em.flush();

    const old_category_id = createdProduct.category.id;

    createdProduct.category = .{ .name = "New Category" };
    try em.flush();

    em.clear();

    const product = try em.get(createdProduct.id);
    try std.testing.expect(product != null);

    defer em.freeModel(product.?);
    try std.testing.expect(product.?.category.id != 0);
    try std.testing.expect(product.?.category.id != old_category_id);
}

test "delete product" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    const product = try em.create(.{
        .name = "Test Product",
        .category = .{ .name = "Test Category" },
    });
    try em.flush();

    try std.testing.expect(product.id != 0);
    const id = product.id;

    try em.remove(product);
    try em.flush();

    const deleted = try em.get(id);
    try std.testing.expectEqual(null, deleted);
}

test "test multiple products same category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const category = try cat_em.create(.{ .name = "Electronics" });
    try cat_em.flush();

    const product1 = try em.create(.{
        .name = "Laptop",
        .category = category.*,
    });
    const product2 = try em.create(.{
        .name = "Phone",
        .category = category.*,
    });
    try em.flush();

    try std.testing.expect(product1.id != 0);
    try std.testing.expect(product2.id != 0);
    try std.testing.expectEqual(category.id, product1.category.id);
    try std.testing.expectEqual(category.id, product2.category.id);
}
