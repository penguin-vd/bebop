const std = @import("std");
const db = @import("../../db/db.zig");
const orm = @import("../../orm/orm.zig");

pub fn MigrationsCreate(comptime models: anytype) type {
    return struct {
        pub const command = "migrations:create";

        pub fn run(allocator: std.mem.Allocator) !void {
            std.log.info("creating migrations...", .{});

            var pool = try db.get_pool(allocator);
            defer pool.deinit();

            try orm.make_migrations(allocator, pool, models);
        }
    };
}
