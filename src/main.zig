const std = @import("std");
const httpz = @import("httpz");
const pg = @import("pg");

const App = @import("app.zig");
const routes = @import("routes.zig");
const m = @import("orm/migrations.zig");
const User = @import("models/user.zig");

fn get_db_pool(allocator: std.mem.Allocator) !*pg.Pool {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    return try pg.Pool.init(
        allocator,
        .{
            .connect = .{
                .port = try std.fmt.parseInt(u16, env_map.get("POSTGRES_PORT") orelse "5432", 10),
                .host = env_map.get("POSTGRES_HOST") orelse "postgres",
            },
            .auth = .{
                .username = env_map.get("POSTGRES_USER").?,
                .database = env_map.get("POSTGRES_DATABASE").?,
                .password = env_map.get("POSTGRES_PASSWORD").?,
            },
        },
    );
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        const command = args[1];
        if (std.mem.eql(u8, command, "makemigrations")) {
            var db = try get_db_pool(allocator);
            defer db.deinit();

            try m.make_migration(allocator, db, User);
            return;
        } else if (std.mem.eql(u8, command, "migrate")) {
            var db = try get_db_pool(allocator);
            defer db.deinit();

            try m.migrate(allocator, db);
            return;
        } else {
            std.debug.print("Unknown command: {s}\n", .{command});
            return;
        }
    }

    var db = try get_db_pool(allocator);
    defer db.deinit();

    var app = App{
        .db = db,
    };

    var server = try httpz.Server(*App).init(allocator, .{
        .port = 8080,
        .address = "0.0.0.0",
    }, &app);

    const router = try server.router(.{});
    try routes.register(router);

    try server.listen();
}
