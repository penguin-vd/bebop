const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");

const User = @import("models/user.zig");
const utils = @import("orm/utils.zig");

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check, .{});
    router.get("api/test", btest, .{});
}



pub fn btest(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    try res.json(.{ .success = true }, .{});
}

pub fn health_check(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    try res.json(.{ .success = true }, .{});
}
