const std = @import("std");
const db = @import("../../db/db.zig");
const orm = @import("../../orm/orm.zig");

pub const command = "migrations:apply";

pub fn run(allocator: std.mem.Allocator, args: []const []const u8, io: std.Io) !void {
    _ = args;
    std.log.info("applying migrations...", .{});

    var pool = try db.get_pool(io, allocator);
    defer pool.deinit();

    try orm.migrate(allocator, io, pool);
}
