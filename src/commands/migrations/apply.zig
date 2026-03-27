const std = @import("std");
const db = @import("../../db/db.zig");
const orm = @import("../../orm/orm.zig");

pub const command = "migrations:apply";

pub fn run(allocator: std.mem.Allocator) !void {
    std.log.info("applying migrations...", .{});

    var pool = try db.get_pool(allocator);
    defer pool.deinit();

    try orm.migrate(allocator, pool);
}
