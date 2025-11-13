const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");
const Driver = @import("drivers/base.zig").Driver;

pub fn make_migration(allocator: std.mem.Allocator, db: *pg.Pool, comptime Model: type, driver: Driver) !void {
    var conn = try db.acquire();
    defer conn.release();

    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

    var table_info = try driver.get_table_information(allocator, conn, table_name);
    defer {
        for (table_info.items) |info| {
            allocator.free(info.column);
            allocator.free(info.type);
        }
        table_info.deinit(allocator);
    }

    const sql = if (table_info.items.len == 0)
        try driver.build_create_table_query(allocator, Model)
    else
        try driver.build_alter_table_query(allocator, Model, table_info);
    defer allocator.free(sql);

    if (sql.len == 0) {
        return;
    }

    const timestamp = std.time.timestamp();
    const migration_name = try std.fmt.allocPrint(
        allocator,
        "{d}_{s}.sql",
        .{ timestamp, table_name },
    );
    defer allocator.free(migration_name);

    const file_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ "migrations", migration_name },
    );

    defer allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(sql);

    std.debug.print("Created migration: {s}\n", .{migration_name});
}

pub fn migrate(allocator: std.mem.Allocator, db: *pg.Pool, driver: Driver) !void {
    try driver.ensure_migrations_table(db);

    var applied_migrations: std.ArrayList([]const u8) = .{};
    defer {
        for (applied_migrations.items) |m| allocator.free(m);
        applied_migrations.deinit(allocator);
    }

    var conn = try db.acquire();
    defer conn.release();

    const result = try conn.query("SELECT migration_name FROM schema_migrations", .{});
    defer result.deinit();

    while (try result.next()) |row| {
        const migration_name = try allocator.dupe(u8, row.get([]const u8, 0));
        try applied_migrations.append(allocator, migration_name);
    }

    var migration_dir = try std.fs.cwd().openDir("migrations", .{ .iterate = true });
    defer migration_dir.close();

    var it = migration_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sql")) {
            continue;
        }

        var is_applied = false;
        for (applied_migrations.items) |applied| {
            if (std.mem.eql(u8, entry.name, applied)) {
                is_applied = true;
                break;
            }
        }

        if (!is_applied) {
            std.debug.print("Applying migration: {s}\n", .{entry.name});

            const file_path = try std.fs.path.join(
                allocator,
                &[_][]const u8{ "migrations", entry.name },
            );
            defer allocator.free(file_path);

            const sql = try std.fs.cwd().readFileAlloc(allocator, file_path, 1_000_000);
            defer allocator.free(sql);

            _ = try conn.exec(sql, .{});

            const insert_sql = "INSERT INTO schema_migrations (migration_name) VALUES ($1)";
            _ = try conn.exec(insert_sql, .{entry.name});
        }
    }

    std.debug.print("Migrations applied successfully.\n", .{});
}
