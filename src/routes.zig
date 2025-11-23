const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");
const bebop = @import("lib/bebop.zig");

const Product = @import("models/product.zig");
const Category = @import("models/category.zig");

const pc = @import("controllers/product_controller.zig");

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check, .{});

    pc.register(router);
}

pub fn health_check(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.release();

    try res.json(.{ .success = true }, .{});
}
