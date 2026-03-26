const std = @import("std");

const bebop = @import("bebop");

pub const command = "migrations:apply";

pub fn run(allocator: std.mem.Allocator) !void {
    std.log.info("applying migrations...", .{});

    var pool = try bebop.db.get_pool(allocator);
    defer pool.deinit();

    try bebop.orm.migrate(allocator, pool);
}
