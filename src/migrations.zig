const std = @import("std");
const pg = @import("pg");

fn getTableName(allocator: std.mem.Allocator, model: anytype) ![]const u8 {
    const input = @typeName(model);
    const result = try allocator.alloc(u8, input.len);
    for (input, 0..) |char, i| {
        if (char == '.') {
            result[i] = '_';
        } else {
            result[i] = std.ascii.toLower(char);
        }
    }

    return result;
}

fn zigTypeToSqlType(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => |int_info| {
            if (int_info.bits <= 32) return "INTEGER";
            return "BIGINT";
        },
        .float => "REAL",
        .bool => "BOOLEAN",
        .pointer => |ptr_info| {
            if (ptr_info.size == .slice and ptr_info.child == u8) {
                return "TEXT";
            }
            return "BLOB";
        },
        .optional => |opt_info| zigTypeToSqlType(opt_info.child),
        else => "TEXT",
    };
}

fn generateCreateTableSql(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const table_name = try getTableName(allocator, Model);
    defer allocator.free(table_name);

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    try sql.print(allocator, "CREATE TABLE IF NOT EXISTS {s} (\n", .{table_name});
    try sql.print(allocator, "  id SERIAL PRIMARY KEY,\n", .{});

    const type_info = @typeInfo(Model);

    switch (type_info) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields, 0..) |field, i| {
                const sql_type = zigTypeToSqlType(field.type);
                const nullable = @typeInfo(field.type) == .optional;

                try sql.print(allocator, "  {s} {s}", .{ field.name, sql_type });

                if (!nullable) {
                    try sql.print(allocator, " NOT NULL", .{});
                }

                if (i < struct_info.fields.len - 1) {
                    try sql.print(allocator, ",\n", .{});
                } else {
                    try sql.print(allocator, "\n", .{});
                }
            }
        },
        else => return error.ModelMustBeStruct,
    }

    try sql.print(allocator, ");", .{});

    return sql.toOwnedSlice(allocator);
}

pub fn ensureMigrationsTable(db: *pg.Pool) !void {
    const sql = "CREATE TABLE IF NOT EXISTS schema_migrations (id SERIAL PRIMARY KEY, migration_name VARCHAR(255) NOT NULL UNIQUE, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())";

    var conn = try db.acquire();
    defer conn.release();

    _ = try conn.exec(sql, .{});
}

pub fn makeMigration(allocator: std.mem.Allocator, comptime Model: type) !void {
    const sql = try generateCreateTableSql(allocator, Model);
    defer allocator.free(sql);

    const table_name = try getTableName(allocator, Model);
    defer allocator.free(table_name);

    const timestamp = std.time.timestamp();
    const migration_name = try std.fmt.allocPrint(allocator, "{d}_create_{s}_table.sql", .{ timestamp, table_name });
    defer allocator.free(migration_name);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ "migrations", migration_name });
    defer allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(sql);

    std.debug.print("Created migration: {s}\n", .{migration_name});
}

pub fn runMigrations(allocator: std.mem.Allocator, db: *pg.Pool) !void {
    try ensureMigrationsTable(db);

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

            const file_path = try std.fs.path.join(allocator, &[_][]const u8{ "migrations", entry.name });
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
