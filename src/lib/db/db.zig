const std = @import("std");
const pg = @import("pg");

pub fn get_pool(allocator: std.mem.Allocator) !*pg.Pool {
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

