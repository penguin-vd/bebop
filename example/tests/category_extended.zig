const std = @import("std");
const bebop = @import("bebop");

const Category = @import("../models/category.zig");

test "whereStartsWith filters categories" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Electronics" });
    _ = try em.create(.{ .name = "Education" });
    _ = try em.create(.{ .name = "Books" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereStartsWith("name", "Elec");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Electronics", results[0].name);
}

test "whereEndsWith filters categories" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Electronics" });
    _ = try em.create(.{ .name = "Mechanics" });
    _ = try em.create(.{ .name = "Books" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereEndsWith("name", "ics");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
}

test "get non-existent category returns null" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const result = try em.get(999999);
    try std.testing.expectEqual(null, result);
}

test "find on empty table returns empty slice" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "create and update category name" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const category = try em.create(.{ .name = "Old Name" });
    defer allocator.destroy(category);
    try em.flush();

    category.name = "New Name";
    try em.flush();

    em.clear();

    const fetched = try em.get(category.id);
    try std.testing.expect(fetched != null);
    defer em.freeModel(fetched.?);
    try std.testing.expectEqualStrings("New Name", fetched.?.name);
}

test "create multiple categories and list all" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Cat A" });
    _ = try em.create(.{ .name = "Cat B" });
    _ = try em.create(.{ .name = "Cat C" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
}

test "delete non-existent category is no-op after flush" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const category = try em.create(.{ .name = "To Delete" });
    try em.flush();

    const id = category.id;

    try em.remove(category);
    try em.flush();

    // Verify gone
    const result = try em.get(id);
    try std.testing.expectEqual(null, result);
}

test "whereILike is case insensitive" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Electronics" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereILike("name", "electronics");

    const results = try em.find(&qb);
    defer em.freeModels(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
}

test "query with limit and pagination" {
    const allocator = std.testing.allocator;

    var conn = try bebop.testing.pool().acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Cat 1" });
    _ = try em.create(.{ .name = "Cat 2" });
    _ = try em.create(.{ .name = "Cat 3" });
    _ = try em.create(.{ .name = "Cat 4" });
    _ = try em.create(.{ .name = "Cat 5" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    qb.limit = 2;

    const page1 = try em.find(&qb);
    defer em.freeModels(page1);

    try std.testing.expectEqual(@as(usize, 2), page1.len);
}
