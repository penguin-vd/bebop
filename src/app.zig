const std = @import("std");
const builtin = @import("builtin");
const httpz = @import("httpz");
const pg = @import("pg");

const App = @This();

pub const RequestContext = struct {
    app: *App,
};

pub const Action = *const fn (*RequestContext, *httpz.Request, *httpz.Response) anyerror!void;

db: *pg.Pool,

pub fn init(db: *pg.Pool) App {
    return .{ .db = db };
}

pub fn notFound(_: *App, req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("404 {} {s}", .{ req.method, req.url.path });
    res.status = 404;
    try res.json(.{ .message = "Not Found" }, .{});
}

pub fn dispatch(self: *App, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    if (comptime builtin.mode == .Debug) {
        var timer = try std.time.Timer.start();

        var ctx = RequestContext{ .app = self };
        try action(&ctx, req, res);

        const elapsed = timer.lap() / 1000;
        std.log.info("{d}\t{}\t{s}\t{d}us", .{ res.status, req.method, req.url.path, elapsed });
    } else {
        var ctx = RequestContext{ .app = self };
        try action(&ctx, req, res);
    }
}
