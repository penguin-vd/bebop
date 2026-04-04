const std = @import("std");
const pg = @import("pg");
const db = @import("db/db.zig");
const orm = @import("orm/orm.zig");

var shared_pool: ?*pg.Pool = null;

fn initOnce() void {
    const allocator = std.heap.page_allocator;
    const pool_instance = db.get_testing_pool(allocator) catch @panic("failed to create testing pool");

    // Reset the test database schema so migrations always replay cleanly
    var conn = pool_instance.acquire() catch @panic("failed to acquire connection");
    defer conn.release();
    _ = conn.exec("DROP SCHEMA public CASCADE", .{}) catch @panic("failed to drop schema");
    _ = conn.exec("CREATE SCHEMA public", .{}) catch @panic("failed to create schema");

    orm.migrate(allocator, pool_instance) catch @panic("failed to run migrations");
    shared_pool = pool_instance;
}

var once = std.once(initOnce);

pub fn setup() void {
    once.call();
}

pub fn clear() !void {
    try truncate(shared_pool.?, std.heap.page_allocator);
}

pub fn pool() *pg.Pool {
    return shared_pool.?;
}

fn truncate(p: *pg.Pool, allocator: std.mem.Allocator) !void {
    var conn = try p.acquire();
    defer conn.release();

    const query =
        \\SELECT tablename FROM pg_tables
        \\WHERE schemaname = 'public'
        \\AND tablename != 'schema_migrations'
    ;

    var result = try conn.query(query, .{});
    defer result.deinit();

    var tables = std.ArrayList([]const u8){};
    defer {
        for (tables.items) |table| {
            allocator.free(table);
        }
        tables.deinit(allocator);
    }

    while (try result.next()) |row| {
        const tablename = row.get([]const u8, 0);
        const owned_name = try allocator.dupe(u8, tablename);
        try tables.append(allocator, owned_name);
    }

    if (tables.items.len == 0) return;

    var truncate_query = std.ArrayList(u8){};
    defer truncate_query.deinit(allocator);

    try truncate_query.appendSlice(allocator, "TRUNCATE ");
    for (tables.items, 0..) |table, i| {
        if (i > 0) try truncate_query.appendSlice(allocator, ", ");
        try truncate_query.appendSlice(allocator, table);
    }
    try truncate_query.appendSlice(allocator, " CASCADE");

    _ = try conn.exec(truncate_query.items, .{});
}

pub const TestEnvironment = struct {
    pool: *pg.Pool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !TestEnvironment {
        once.call();
        const p = shared_pool.?;
        try truncate(p, allocator);
        return .{ .pool = p, .allocator = allocator };
    }

    pub fn deinit(self: *TestEnvironment) void {
        _ = self;
    }
};
