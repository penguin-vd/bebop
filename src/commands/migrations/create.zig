const std = @import("std");
const db = @import("../../db/db.zig");
const orm = @import("../../orm/orm.zig");

pub fn MigrationsCreate(comptime models: anytype) type {
    return struct {
        pub const command = "migrations:create";

        pub fn run(allocator: std.mem.Allocator, io: std.Io) !void {
            std.log.info("creating migrations...", .{});

            var pool = try db.get_pool(io, allocator);
            defer pool.deinit();

            try orm.make_migrations(allocator, io, pool, models);
        }
    };
}
