const std = @import("std");
const bebop = @import("bebop");

const Example = @import("example.zig");

const Category = @import("../models/category.zig");
const Product = @import("../models/product.zig");
const Order = @import("../models/order.zig");
const OrderLine = @import("../models/order_line.zig");

const models = &[_]type{ Category, Product, Order, OrderLine };

pub fn handle(allocator: std.mem.Allocator) !void {
    defer bebop.cmd.deinit(allocator);

    try bebop.cmd.register(allocator, bebop.cmd.migrations.Apply);
    try bebop.cmd.register(allocator, bebop.cmd.migrations.Create(models));
    try bebop.cmd.register(allocator, Example);
    try bebop.cmd.handle(allocator);
}
