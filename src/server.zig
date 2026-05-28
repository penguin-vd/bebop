const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");
const db_module = @import("db/db.zig");
const cmd = @import("commands/cmd.zig");
const http = @import("http.zig");

pub const Config = struct {
    port: u16 = 8080,
    address: []const u8 = "0.0.0.0",
};

const DefaultApp = @import("app.zig");
const DefaultRouter = http.Router(*DefaultApp, DefaultApp.Action);

pub fn start(
    init: std.process.Init,
    config: Config,
    comptime registerRoutes: fn (*DefaultRouter) anyerror!void,
    comptime registerCommands: ?fn (std.mem.Allocator) anyerror!void,
) !void {
    try Server(*DefaultApp, DefaultApp.Action).start(init, config, DefaultApp.init, registerRoutes, registerCommands);
}

pub fn Server(comptime Handler: type, comptime Action: type) type {
    const App = std.meta.Child(Handler);

    return struct {
        pub fn start(
            init: std.process.Init,
            config: Config,
            comptime initFn: fn (std.Io, *pg.Pool, []const u8) App,
            comptime registerRoutes: fn (*http.Router(Handler, Action)) anyerror!void,
            comptime registerCommands: ?fn (std.mem.Allocator) anyerror!void,
        ) !void {
            const allocator = init.gpa;

            defer cmd.deinit(allocator);
            try cmd.register(allocator, cmd.migrations.Apply);
            try cmd.register(allocator, cmd.migrations.Rollback);
            try cmd.register(allocator, cmd.debug.Router(Handler, Action, registerRoutes));
            try cmd.register(allocator, cmd.key.Generate);
            if (registerCommands) |f| try f(allocator);
            try cmd.handle(allocator, init.minimal.args, init.io);

            const app_key = blk: {
                const key = init.environ_map.get("APP_KEY") orelse return error.MissingAppKey;
                break :blk try allocator.dupe(u8, key);
            };
            defer allocator.free(app_key);

            var pool = try db_module.get_pool(init.io, allocator);
            defer pool.deinit();

            var app = initFn(init.io, pool, app_key);

            const httpz_address = if (std.mem.eql(u8, config.address, "127.0.0.1"))
                httpz.Config.Address.localhost(config.port)
            else
                httpz.Config.Address.all(config.port);
            var server = try httpz.Server(Handler).init(init.io, allocator, .{
                .address = httpz_address,
            }, &app);

            const httpz_router = try server.router(.{});
            var router = http.Router(Handler, Action).from(httpz_router);
            try registerRoutes(&router);

            try server.listen();
        }
    };
}
