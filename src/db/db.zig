const std = @import("std");
const pg = @import("pg");
const getenv = @import("../env.zig").getenv;

pub fn get_pool(io: std.Io, allocator: std.mem.Allocator) !*pg.Pool {
    return try pg.Pool.init(io, allocator, .{
        .size = 50,
        .connect = .{
            .port = try std.fmt.parseInt(u16, getenv("POSTGRES_PORT") orelse "5432", 10),
            .host = getenv("POSTGRES_HOST") orelse "postgres",
        },
        .auth = .{
            .username = getenv("POSTGRES_USER").?,
            .database = getenv("POSTGRES_DATABASE").?,
            .password = getenv("POSTGRES_PASSWORD").?,
        },
    });
}

pub fn get_testing_pool(io: std.Io, allocator: std.mem.Allocator) !*pg.Pool {
    return try pg.Pool.init(io, allocator, .{
        .connect = .{
            .port = try std.fmt.parseInt(u16, getenv("POSTGRES_PORT") orelse "5432", 10),
            .host = getenv("POSTGRES_HOST") orelse "postgres",
        },
        .auth = .{
            .username = getenv("POSTGRES_USER").?,
            .database = "zig-testing-database",
            .password = getenv("POSTGRES_PASSWORD").?,
        },
    });
}
