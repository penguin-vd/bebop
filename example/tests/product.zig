const std = @import("std");
const bebop = @import("bebop");

const Product = @import("../models/product.zig");
const Category = @import("../models/category.zig");

test "test create product with existing category" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const category = try cat_em.create(.{ .name = "Electronics" });
    try cat_em.flush();

    try std.testing.expect(category.id != 0);

    var categories = [_]Category{category.*};

    const product = try em.create(.{
        .name = "Laptop",
        .categories = &categories,
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(@as(usize, 1), product.categories.len);
    try std.testing.expectEqual(category.id, product.categories[0].id);
}

test "test create product with new category" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var categories = [_]Category{.{ .name = "Electronics" }};

    const product = try em.create(.{
        .name = "Phone",
        .categories = &categories,
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(@as(usize, 1), product.categories.len);
    try std.testing.expect(product.categories[0].id != 0);
}

test "test list products" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    try std.testing.expectEqual(@as(u32, 0), em.tracked_entities.count());

    var qb = em.query();
    defer qb.deinit();

    const empty = try em.find(&qb);
    defer em.freeModels(empty);

    try std.testing.expectEqual(@as(usize, 0), empty.len);

    var categories = [_]Category{.{ .name = "Test Category" }};

    _ = try em.create(.{
        .name = "Test Product",
        .categories = &categories,
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

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cats1 = [_]Category{.{ .name = "Electronics" }};
    var cats2 = [_]Category{.{ .name = "Literature" }};

    _ = try em.create(.{
        .name = "Laptop",
        .categories = &cats1,
    });
    _ = try em.create(.{
        .name = "Book",
        .categories = &cats2,
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

    const noone = try em.find(&qb);
    defer em.freeModels(noone);

    try std.testing.expectEqual(@as(usize, 0), noone.len);
}

test "test get product" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var categories = [_]Category{.{ .name = "Test Category" }};

    const createdProduct = try em.create(.{
        .name = "Test Product",
        .categories = &categories,
    });

    defer allocator.destroy(createdProduct);

    try em.flush();

    em.clear();

    const product = try em.get(createdProduct.id);

    try std.testing.expect(product != null);

    if (product) |p| {
        defer em.freeModel(p);

        try std.testing.expectEqual(p.id, createdProduct.id);
        try std.testing.expectEqual(@as(usize, 1), p.categories.len);
        try std.testing.expect(p.categories[0].id != 0);
        try std.testing.expectEqualStrings(createdProduct.name, p.name);
    }
}

test "test update product" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var categories = [_]Category{.{ .name = "Electronics" }};

    const createdProduct = try em.create(.{
        .name = "Old Name",
        .categories = &categories,
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

test "test update product categories" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const cat1 = try cat_em.create(.{ .name = "Electronics" });
    const cat2 = try cat_em.create(.{ .name = "Books" });
    try cat_em.flush();

    var categories = [_]Category{cat1.*};

    const createdProduct = try em.create(.{
        .name = "Product",
        .categories = &categories,
    });
    defer allocator.destroy(createdProduct);
    try em.flush();

    const original_id = createdProduct.id;

    // Update to use cat2 instead
    var new_categories = [_]Category{cat2.*};
    createdProduct.categories = &new_categories;
    try em.flush();

    em.clear();

    const product = try em.get(original_id);
    try std.testing.expect(product != null);

    defer em.freeModel(product.?);
    try std.testing.expectEqual(@as(usize, 1), product.?.categories.len);
    try std.testing.expectEqual(cat2.id, product.?.categories[0].id);
}

test "delete product" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var categories = [_]Category{.{ .name = "Test Category" }};

    const product = try em.create(.{
        .name = "Test Product",
        .categories = &categories,
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

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const category = try cat_em.create(.{ .name = "Electronics" });
    try cat_em.flush();

    var cats1 = [_]Category{category.*};
    var cats2 = [_]Category{category.*};

    const product1 = try em.create(.{
        .name = "Laptop",
        .categories = &cats1,
    });
    const product2 = try em.create(.{
        .name = "Phone",
        .categories = &cats2,
    });
    try em.flush();

    try std.testing.expect(product1.id != 0);
    try std.testing.expect(product2.id != 0);
    try std.testing.expectEqual(category.id, product1.categories[0].id);
    try std.testing.expectEqual(category.id, product2.categories[0].id);
}

test "test create product with multiple new category" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var categories = [_]Category{
        .{ .name = "Electronics" },
        .{ .name = "Handheld" },
    };

    const product = try em.create(.{
        .name = "Phone",
        .categories = &categories,
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(@as(usize, 2), product.categories.len);
    try std.testing.expect(product.categories[0].id != 0);
    try std.testing.expect(product.categories[1].id != 0);
}

test "test create product with existing category and new category" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Product).init(allocator, conn);
    defer em.deinit();

    var cat_em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer cat_em.deinit();

    const category = try cat_em.create(.{ .name = "Electronics" });
    try cat_em.flush();

    try std.testing.expect(category.id != 0);

    var categories = [_]Category{
        category.*,
        .{ .name = "Handheld" },
    };

    const product = try em.create(.{
        .name = "Laptop",
        .categories = &categories,
    });

    try std.testing.expectEqual(@as(i32, 0), product.id);

    try em.flush();

    try std.testing.expect(product.id != 0);
    try std.testing.expectEqual(@as(usize, 2), product.categories.len);
    try std.testing.expectEqual(category.id, product.categories[0].id);
    try std.testing.expect(product.categories[1].id != 0);
}
