const std = @import("std");
const bebop = @import("../lib/bebop.zig");

const Category = @import("../models/category.zig");

test "test create category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const category = try em.create(.{ .name = "Test Category" });

    try std.testing.expectEqual(@as(i32, 0), category.id);

    try em.flush();

    try std.testing.expect(category.id != 0);
}

test "test list categories" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    try std.testing.expectEqual(@as(u32, 0), em.tracked_entities.count());

    var qb = em.query();
    defer qb.deinit();

    const empty = try em.find(&qb);
    defer em.freeModels(empty);

    try std.testing.expectEqual(@as(usize, 0), empty.len);

    _ = try em.create(.{ .name = "Test Category" });
    try em.flush();

    try std.testing.expectEqual(@as(u32, 1), em.tracked_entities.count());

    const one = try em.find(&qb);
    defer em.freeModels(one);

    try std.testing.expectEqual(@as(usize, 1), one.len);
    try std.testing.expectEqual(@as(u32, 1), em.tracked_entities.count());
}

test "test filtering categories" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    _ = try em.create(.{ .name = "Test Category" });
    try em.flush();

    var qb = em.query();
    defer qb.deinit();

    try qb.whereILike("name", "Test");

    const one = try em.find(&qb);
    defer em.freeModels(one);

    try std.testing.expectEqual(@as(usize, 1), one.len);
    qb.clear();

    try qb.whereILike("name", "Gibberish");

    const empty = try em.find(&qb);
    defer em.freeModels(empty);

    try std.testing.expectEqual(@as(usize, 0), empty.len);
}

test "test get category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const createdCategory = try em.create(.{ .name = "Test Category" });
    // Due to clearing we now have owner ship of this
    defer allocator.destroy(createdCategory);

    try em.flush();
    em.clear();

    const category = try em.get(createdCategory.id);
    try std.testing.expect(category != null);
    defer em.freeModel(category.?);
    try std.testing.expectEqual(category.?.id, createdCategory.id);
}

test "delete category" {
    const allocator = std.testing.allocator;

    var pool = try bebop.testing.setup_testing_enviroment(allocator);
    defer pool.deinit();

    defer bebop.testing.cleanup_testing_database(pool, allocator) catch {};

    var conn = try pool.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Category).init(allocator, conn);
    defer em.deinit();

    const createdCategory = try em.create(.{ .name = "Test Category" });
    try em.flush();

    try std.testing.expect(createdCategory.id != 0);
    const id = createdCategory.id;

    try em.remove(createdCategory);
    try em.flush();

    const category = try em.get(id);
    try std.testing.expectEqual(null, category);
}
