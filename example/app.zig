const App = @This();

const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

pub const RequestContext = struct {
    app: *App,
};

db: *pg.Pool,

pub fn notFound(_: *App, req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("404 {} {s}", .{ req.method, req.url.path });
    res.status = 404;
    res.body = "Not Found";
}

pub fn dispatch(self: *App, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    var timer = try std.time.Timer.start();

    var ctx = RequestContext{
        .app = self,
    };

    try action(&ctx, req, res);

    const elapsed = timer.lap() / 1000; // ns -> us
    std.log.info("{d}\t{}\t{s}\t{d}us", .{ res.status, req.method, req.url.path, elapsed });
}
