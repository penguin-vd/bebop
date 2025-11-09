const App = @import("app.zig");
const std = @import("std");
const httpz = @import("httpz");

const User = @import("models/user.zig");
const ORM = @import("orm/mapper.zig");

pub const Router = httpz.Router(*App, *const fn (*App.RequestContext, *httpz.Request, *httpz.Response) anyerror!void);

pub fn register(router: *Router) !void {
    router.get("api/healthz", healthCheck, .{});
    router.get("api/users", listUsers, .{});
    router.post("api/users", createUser, .{});
}

pub fn listUsers(ctx: *App.RequestContext, _: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    const userMap = ORM.Map(User){};
    const users = try userMap.list(res.arena, conn);
    defer res.arena.free(users);

    try res.json(users, .{});
}

pub fn createUser(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    var conn = try ctx.app.db.acquire();
    defer conn.release();

    const body = try req.json(struct {
        name: []const u8,
    });

    if (body) |dto| {
        const userMap = ORM.Map(User){};
        const created_user = try userMap.create(res.arena, conn, .{
            .name = dto.name,
            .id = undefined,
        });
        try res.json(created_user, .{});
        return;
    }

    res.setStatus(.bad_request);
    try res.json(.{ .message = "Invalid body" }, .{});
}

pub fn healthCheck(ctx: *App.RequestContext, req: *httpz.Request, res: *httpz.Response) !void {
    _ = req;

    var conn = try ctx.app.db.acquire();
    defer conn.deinit();

    try res.json(.{ .success = true }, .{});
}
