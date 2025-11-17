const std = @import("std");

const bebop = @import("../../lib/bebop.zig");

const Category = @import("../../models/category.zig");
const Product = @import("../../models/product.zig");

pub const command = "migrations:create";

pub fn run(allocator: std.mem.Allocator) !void {
    std.log.info("creating migrations...", .{});

    var pool = try bebop.db.get_pool(allocator);
    defer pool.deinit();

    try bebop.orm.make_migrations(allocator, pool, &[_]type{
        Category,
        Product,
    });
}
