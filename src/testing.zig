const std = @import("std");
const pg = @import("pg");
const db = @import("db/db.zig");
const orm = @import("orm/orm.zig");

pub fn setup_testing_enviroment(allocator: std.mem.Allocator) !*pg.Pool {
    const pool = try db.get_testing_pool(allocator);
    try orm.migrate(allocator, pool);
    return pool;
}

pub fn cleanup_testing_database(pool: *pg.Pool, allocator: std.mem.Allocator) !void {
    var conn = try pool.acquire();
    defer conn.release();

    const query =
        \\SELECT tablename FROM pg_tables 
        \\WHERE schemaname = 'public'
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

    for (tables.items) |table| {
        const drop_query = try std.fmt.allocPrint(
            allocator,
            "DROP TABLE IF EXISTS {s} CASCADE",
            .{table},
        );
        defer allocator.free(drop_query);
        
        _ = try conn.exec(drop_query, .{});
    }
}
