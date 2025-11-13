const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");

const User = @import("models/user.zig");
const ORM = @import("orm/mapper.zig");
const utils = @import("orm/utils.zig");
const pg_driver = @import("orm/drivers/pg.zig").driver;

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", health_check, .{});
    router.get("api/users", list_users, .{});
    router.post("api/users", create_user, .{});
}

pub fn list_users(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    const user_map = ORM.Map(User, pg_driver){};
    const query = try req.query();
    const relations_to_load = [_][]const u8{"role"};

    if (query.get("search")) |search| {
        const users = try user_map.list(res.arena, conn, .{
            .name__contains = search,
        }, null);
        try res.json(users, .{});
    } else {
        const users = try user_map.list(res.arena, conn, null, .{
            .with = &relations_to_load
        }
    );
        try res.json(users, .{});
    }
}

pub fn create_user(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    const body = try req.json(struct {
        name: []const u8,
    });

    if (body) |dto| {
        const user_map = ORM.Map(User, pg_driver){};
        const created_user = try user_map.create(res.arena, conn, .{
            .name = dto.name,
            .id = undefined,
        });
        try res.json(created_user, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

pub fn health_check(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    try res.json(.{ .success = true }, .{});
}
