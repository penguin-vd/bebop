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
    config: Config,
    comptime registerRoutes: fn (*DefaultRouter) anyerror!void,
    comptime registerCommands: ?fn (std.mem.Allocator) anyerror!void,
) !void {
    try Server(*DefaultApp, DefaultApp.Action).start(config, DefaultApp.init, registerRoutes, registerCommands);
}

pub fn Server(comptime Handler: type, comptime Action: type) type {
    const App = std.meta.Child(Handler);

    return struct {
        pub fn start(
            config: Config,
            comptime initFn: fn (*pg.Pool) App,
            comptime registerRoutes: fn (*http.Router(Handler, Action)) anyerror!void,
            comptime registerCommands: ?fn (std.mem.Allocator) anyerror!void,
        ) !void {
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            const allocator = gpa.allocator();
            defer _ = gpa.deinit();

            defer cmd.deinit(allocator);
            try cmd.register(allocator, cmd.migrations.Apply);
            try cmd.register(allocator, cmd.migrations.Rollback);
            try cmd.register(allocator, cmd.debug.Router(Handler, Action, registerRoutes));
            try cmd.register(allocator, cmd.key.Generate);
            if (registerCommands) |f| try f(allocator);
            try cmd.handle(allocator);

            var pool = try db_module.get_pool(allocator);
            defer pool.deinit();

            var app = initFn(pool);

            var server = try httpz.Server(Handler).init(allocator, .{
                .port = config.port,
                .address = config.address,
            }, &app);

            const httpz_router = try server.router(.{});
            var router = http.Router(Handler, Action).from(httpz_router);
            try registerRoutes(&router);

            try server.listen();
        }
    };
}
