const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");
const bebop = @import("lib/bebop.zig");

const Product = @import("models/product.zig");
const Category = @import("models/category.zig");
const Order = @import("models/order.zig");

const pc = @import("controllers/product_controller.zig");

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check, .{});
    router.get("api/test", testing, .{});

    pc.register(router);
}

pub fn testing(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(Order).init(res.arena, conn);
    defer em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const orders = try em.find(&qb);
    defer em.freeModels(orders);

    try res.json(orders, .{});
}

pub fn health_check(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.release();

    try res.json(.{ .success = true }, .{});
}
