const std = @import("std");
const bebop = @import("bebop");

const Example = @import("example.zig");

const Category = @import("../models/category.zig");
const Product = @import("../models/product.zig");
const Order = @import("../models/order.zig");
const OrderLine = @import("../models/order_line.zig");
const Secret = @import("../models/secret.zig");

const models = &[_]type{ Category, Product, Order, OrderLine, Secret };

pub fn register(allocator: std.mem.Allocator) !void {
    try bebop.cmd.register(allocator, bebop.cmd.migrations.Create(models));
    try bebop.cmd.register(allocator, Example);
}
