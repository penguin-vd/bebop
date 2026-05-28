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
app_key: []const u8,
io: std.Io,

pub fn init(io: std.Io, db: *pg.Pool, app_key: []const u8) App {
    return .{ .io = io, .db = db, .app_key = app_key };
}

pub fn notFound(_: *App, req: *httpz.Request, res: *httpz.Response) !void {
    std.log.info("404 {} {s}", .{ req.method, req.url.path });
    res.status = 404;
    try res.json(.{ .message = "Not Found" }, .{});
}

pub fn dispatch(self: *App, action: httpz.Action(*RequestContext), req: *httpz.Request, res: *httpz.Response) !void {
    if (comptime builtin.mode == .Debug) {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        const start_ns: i128 = @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;

        var ctx = RequestContext{ .app = self };
        try action(&ctx, req, res);

        _ = std.os.linux.clock_gettime(.MONOTONIC, &ts);
        const end_ns: i128 = @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
        const elapsed = @divTrunc(end_ns - start_ns, 1000);
        std.log.info("{d}\t{}\t{s}\t{d}us", .{ res.status, req.method, req.url.path, elapsed });
    } else {
        var ctx = RequestContext{ .app = self };
        try action(&ctx, req, res);
    }
}
