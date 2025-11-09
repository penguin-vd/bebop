const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

const App = @import("app.zig");
const routes = @import("routes.zig");
const m = @import("migrations.zig");
const User = @import("models/user.zig");


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const migration = try m.generateMigration(allocator, User);
    std.debug.print("{s}\n", .{migration});

    // var env_map = try std.process.getEnvMap(allocator);
    // defer env_map.deinit();
    //
    // var db = try pg.Pool.init(
    //     allocator,
    //     .{
    //         .connect = .{
    //             .port = try std.fmt.parseInt(u16, env_map.get("POSTGRES_PORT") orelse "5432", 10),
    //             .host = env_map.get("POSTGRES_HOST") orelse "postgres",
    //         },
    //         .auth = .{
    //             .username = env_map.get("POSTGRES_USER").?,
    //             .database = env_map.get("POSTGRES_DATABASE").?,
    //             .password = env_map.get("POSTGRES_PASSWORD").?,
    //         },
    //     },
    // );
    // defer db.deinit();
    //
    // var app = App{
    //     .db = db,
    // };
    //
    // var server = try httpz.Server(*App).init(allocator, .{
    //     .port = 8080,
    //     .address = "0.0.0.0",
    // }, &app);
    //
    // const router = try server.router(.{});
    // try routes.register(router);
    //
    // try server.listen();
}
