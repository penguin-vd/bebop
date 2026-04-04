const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");
const queries = @import("queries.zig");

const up_marker = "-- UP\n";
const down_marker = "-- DOWN\n";

pub fn make_migrations(allocator: std.mem.Allocator, db: *pg.Pool, comptime models: []const type) !void {
    if (models.len == 0) {
        std.debug.print("No models provided.\n", .{});
        return;
    }

    std.fs.cwd().makeDir("migrations") catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    var seq: usize = 0;
    inline for (models) |Model| {
        seq = try make_migration(allocator, db, Model, seq);
    }
}

fn write_migration_file(allocator: std.mem.Allocator, table_name: []const u8, suffix: []const u8, seq: usize, up_sql: []const u8, down_sql: []const u8) !void {
    const timestamp = std.time.timestamp();
    const migration_name = try std.fmt.allocPrint(allocator, "{d}_{d:0>4}_{s}{s}.sql", .{ timestamp, seq, table_name, suffix });
    defer allocator.free(migration_name);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ "migrations", migration_name });
    defer allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(up_marker);
    try file.writeAll(up_sql);
    try file.writeAll("\n");
    try file.writeAll(down_marker);
    try file.writeAll(down_sql);

    std.debug.print("Created migration: {s}\n", .{migration_name});
}

pub fn make_migration(allocator: std.mem.Allocator, db: *pg.Pool, comptime Model: type, seq: usize) !usize {
    var conn = try db.acquire();
    defer conn.release();

    const table_name = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    var table_info = try utils.get_table_information(allocator, conn, table_name);
    defer {
        for (table_info.items) |info| {
            allocator.free(info.column);
            allocator.free(info.type);
        }
        table_info.deinit(allocator);
    }

    const is_new_table = table_info.items.len == 0;

    const up_sql = if (is_new_table)
        try queries.build_create_table_query(allocator, Model)
    else
        try queries.build_alter_table_query(allocator, Model, table_info);
    defer allocator.free(up_sql);

    if (up_sql.len == 0) {
        std.debug.print("No changes needed for table: {s}\n", .{table_name});
        return seq;
    }

    const down_sql = if (is_new_table)
        try queries.build_drop_table_query(allocator, Model)
    else
        try queries.build_reverse_alter_table_query(allocator, Model, table_info);
    defer allocator.free(down_sql);

    var current_seq = seq;
    try write_migration_file(allocator, table_name, "", current_seq, up_sql, down_sql);
    current_seq += 1;

    // Generate pivot table migrations for M2M relations
    const pivot_up = try queries.build_pivot_table_queries(allocator, Model);
    defer {
        for (pivot_up) |pq| allocator.free(pq);
        allocator.free(pivot_up);
    }

    const pivot_down = try queries.build_drop_pivot_table_queries(allocator, Model);
    defer {
        for (pivot_down) |pq| allocator.free(pq);
        allocator.free(pivot_down);
    }

    for (pivot_up, pivot_down) |up, down| {
        if (up.len == 0) continue;
        try write_migration_file(allocator, table_name, "_pivot", current_seq, up, down);
        current_seq += 1;
    }

    return current_seq;
}

fn parse_migration_section(contents: []const u8, marker: []const u8) ?[]const u8 {
    const start = if (std.mem.indexOf(u8, contents, marker)) |pos| pos + marker.len else return null;
    const end = if (std.mem.indexOfPos(u8, contents, start, "-- ")) |pos| pos else contents.len;

    const section = std.mem.trim(u8, contents[start..end], &std.ascii.whitespace);
    return if (section.len > 0) section else null;
}

pub fn migrate(allocator: std.mem.Allocator, db: *pg.Pool) !void {
    try queries.ensure_migrations_table(db);

    var conn = try db.acquire();
    defer conn.release();

    var applied = try get_applied_migrations(allocator, conn);
    defer {
        for (applied.items) |m| allocator.free(m);
        applied.deinit(allocator);
    }

    var pending = try get_pending_migrations(allocator, applied);
    defer {
        for (pending.items) |name| allocator.free(name);
        pending.deinit(allocator);
    }

    for (pending.items) |migration_name| {
        std.debug.print("Applying migration: {s}\n", .{migration_name});

        const sql = try read_migration_file(allocator, migration_name);
        defer allocator.free(sql);

        const up_sql = parse_migration_section(sql, up_marker) orelse sql;

        _ = try conn.exec(up_sql, .{});
        _ = try conn.exec("INSERT INTO schema_migrations (migration_name) VALUES ($1)", .{migration_name});
    }

    std.debug.print("Migrations applied successfully.\n", .{});
}

pub fn rollback(allocator: std.mem.Allocator, db: *pg.Pool) !void {
    try queries.ensure_migrations_table(db);

    var conn = try db.acquire();
    defer conn.release();

    var applied = try get_applied_migrations(allocator, conn);
    defer {
        for (applied.items) |m| allocator.free(m);
        applied.deinit(allocator);
    }

    if (applied.items.len == 0) {
        std.debug.print("No migrations to roll back.\n", .{});
        return;
    }

    // Roll back the last applied migration
    const last = applied.items[applied.items.len - 1];
    std.debug.print("Rolling back migration: {s}\n", .{last});

    const sql = try read_migration_file(allocator, last);
    defer allocator.free(sql);

    const down_sql = parse_migration_section(sql, down_marker) orelse {
        std.debug.print("No DOWN section found in migration: {s}\n", .{last});
        return;
    };

    _ = try conn.exec(down_sql, .{});
    _ = try conn.exec("DELETE FROM schema_migrations WHERE migration_name = $1", .{last});

    std.debug.print("Rolled back migration: {s}\n", .{last});
}

fn get_applied_migrations(allocator: std.mem.Allocator, conn: anytype) !std.ArrayList([]const u8) {
    var applied: std.ArrayList([]const u8) = .{};

    const result = try conn.query("SELECT migration_name FROM schema_migrations ORDER BY id ASC", .{});
    defer result.deinit();

    while (try result.next()) |row| {
        try applied.append(allocator, try allocator.dupe(u8, row.get([]const u8, 0)));
    }

    return applied;
}

fn get_pending_migrations(allocator: std.mem.Allocator, applied: std.ArrayList([]const u8)) !std.ArrayList([]const u8) {
    var pending: std.ArrayList([]const u8) = .{};

    var migration_dir = try std.fs.cwd().openDir("migrations", .{ .iterate = true });
    defer migration_dir.close();

    var it = migration_dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".sql")) continue;

        const is_applied = for (applied.items) |a| {
            if (std.mem.eql(u8, entry.name, a)) break true;
        } else false;

        if (!is_applied) {
            try pending.append(allocator, try allocator.dupe(u8, entry.name));
        }
    }

    std.mem.sort([]const u8, pending.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    return pending;
}

fn read_migration_file(allocator: std.mem.Allocator, migration_name: []const u8) ![]const u8 {
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ "migrations", migration_name });
    defer allocator.free(file_path);

    return std.fs.cwd().readFileAlloc(allocator, file_path, 1_000_000);
}
