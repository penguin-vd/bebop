const bebop = @import("bebop");
const httpz = bebop.httpz;

const pc = @import("controllers/product_controller.zig");
const oc = @import("controllers/order_controller.zig");

pub const Router = bebop.http.Router(*bebop.App, bebop.App.Action);
pub const Group = bebop.http.Group(*bebop.App, bebop.App.Action);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check);
    router.get("api/test", testing);

    var products = router.group("/api/products");
    pc.register(&products);

    var orders = router.group("/api/orders");
    oc.register(&orders);
}

pub fn testing(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var em = bebop.orm.EntityManager(@import("models/order.zig")).init(res.arena, conn);
    defer em.deinit();

    var qb = em.query();
    defer qb.deinit();

    const orders = try em.find(&qb);
    defer em.freeModels(orders);

    try res.json(orders, .{});
}

pub fn health_check(ctx: *bebop.App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.release();

    try res.json(.{ .success = true }, .{});
}
