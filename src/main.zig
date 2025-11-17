const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

const App = @import("app.zig");
const routes = @import("routes.zig");
const bebop = @import("lib/bebop.zig");

const Product = @import("models/product.zig");
const Category = @import("models/category.zig");
const CreateMigrations = @import("commands/migrations/create.zig");
const cmd = @import("commands/cmd.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    try cmd.handle(allocator);

    var db = try bebop.db.get_pool(allocator);
    defer db.deinit();

    var app = App{
        .db = db,
    };

    var server = try httpz.Server(*App).init(allocator, .{
        .port = 8080,
        .address = "0.0.0.0",
    }, &app);

    const router = try server.router(.{});
    try routes.register(router);

    try server.listen();
}
