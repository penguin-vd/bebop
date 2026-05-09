const std = @import("std");
const pg = @import("pg");

fn getenv(key: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.c.environ[i]) |entry| : (i += 1) {
        const s = std.mem.span(entry);
        if (std.mem.startsWith(u8, s, key) and s.len > key.len and s[key.len] == '=') {
            return s[key.len + 1 ..];
        }
    }
    return null;
}

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
