const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");
const bebop = @import("lib/bebop.zig");

const Product = @import("models/product.zig");
const Category = @import("models/category.zig");

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check, .{});
    router.get("api/test", btest, .{});
}

pub fn btest(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    var qb = bebop.orm.QueryBuilder(Product).init(res.arena);
    defer qb.deinit();

    const fields = [_][]const u8{ "name" };
    try qb.selectFields(&fields);
    
    var query = try req.query();
    defer query.deinit(req.arena);

    if (query.get("category_id")) |id| {
        try qb.where("category.id", "=", id);
    }

    const users = try qb.execute(conn, struct {
        name: []const u8,
    });

    try res.json(users, .{});
}

pub fn health_check(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.release();

    try res.json(.{ .success = true }, .{});
}
