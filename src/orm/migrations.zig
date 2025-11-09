const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");

fn create(
    allocator: std.mem.Allocator,
    comptime Model: type,
    table_name: []const u8,
) ![]const u8 {
    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    try sql.print(allocator, "CREATE TABLE IF NOT EXISTS {s} (\n", .{table_name});

    const type_info = @typeInfo(Model);

    switch (type_info) {
        .@"struct" => |struct_info| {
            var has_primary_key = false;
            inline for (struct_info.fields) |field| {
                const meta = utils.getFieldMeta(Model, field.name);
                if (meta) |m| {
                    if (m.is_primary_key) {
                        has_primary_key = true;
                        break;
                    }
                }
            }

            var primary_keys: std.ArrayList([]const u8) = .{};
            defer primary_keys.deinit(allocator);

            inline for (struct_info.fields, 0..) |field, i| {
                const meta = utils.getFieldMeta(Model, field.name);

                const column_name = if (meta) |m| m.column_name orelse field.name else field.name;
                const sql_type = utils.toSqlType(field.type);
                const nullable = @typeInfo(field.type) == .optional;

                try sql.print(allocator, "  {s} {s}", .{ column_name, sql_type });

                if (meta) |m| {
                    if (m.is_auto_increment) {
                        try sql.print(allocator, " GENERATED ALWAYS AS IDENTITY", .{});
                    }
                }

                if (!nullable) {
                    try sql.print(allocator, " NOT NULL", .{});
                }

                if (meta) |m| {
                    if (m.is_unique and !m.is_primary_key) {
                        try sql.print(allocator, " UNIQUE", .{});
                    }
                }

                if (meta) |m| {
                    if (m.default_value) |default| {
                        try sql.print(allocator, " DEFAULT {s}", .{default});
                    }
                }

                if (meta) |m| {
                    if (m.is_primary_key) {
                        try primary_keys.append(allocator, column_name);
                    }
                }

                if (i < struct_info.fields.len - 1 or has_primary_key) {
                    try sql.print(allocator, ",\n", .{});
                } else {
                    try sql.print(allocator, "\n", .{});
                }
            }

            if (primary_keys.items.len > 0) {
                try sql.print(allocator, "  PRIMARY KEY (", .{});
                for (primary_keys.items, 0..) |pk, i| {
                    try sql.print(allocator, "{s}", .{pk});
                    if (i < primary_keys.items.len - 1) {
                        try sql.print(allocator, ", ", .{});
                    }
                }
                try sql.print(allocator, ")\n", .{});
            }
        },
        else => return error.ModelMustBeStruct,
    }

    try sql.print(allocator, ");", .{});

    return sql.toOwnedSlice(allocator);
}

fn alter(
    allocator: std.mem.Allocator,
    comptime Model: type,
    table_name: []const u8,
    table_info: std.ArrayList(utils.TableInformation),
) ![]const u8 {
    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    const type_info = @typeInfo(Model);

    switch (type_info) {
        .@"struct" => |struct_info| {
            var model_columns: std.ArrayList([]const u8) = .{};
            defer model_columns.deinit(allocator);

            inline for (struct_info.fields) |field| {
                const meta = utils.getFieldMeta(Model, field.name);
                const column_name = if (meta) |m| m.column_name orelse field.name else field.name;
                
                try model_columns.append(allocator, column_name);
                
                const sql_type = utils.toSqlType(field.type);
                const nullable = @typeInfo(field.type) == .optional;
                
                var column_exists = false;
                var needs_update = false;
                var existing_type: []const u8 = "";
                
                for (table_info.items) |info| {
                    if (std.mem.eql(u8, info.column, column_name)) {
                        column_exists = true;
                        existing_type = info.type;
                        
                        if (!utils.typeMatches(sql_type, info.type)) {
                            needs_update = true;
                        }
                        break;
                    }
                }
                
                if (!column_exists) {
                    try sql.print(allocator, "ALTER TABLE {s} ADD COLUMN {s} {s}", .{ 
                        table_name, column_name, sql_type 
                    });
                    
                    if (!nullable) {
                        try sql.print(allocator, " DEFAULT ", .{});
                        
                        const default_val = utils.getDefaultValue(field.type);
                        try sql.print(allocator, "{s}", .{default_val});
                    }
                    
                    if (meta) |m| {
                        if (m.is_unique and !m.is_primary_key) {
                            try sql.print(allocator, " UNIQUE", .{});
                        }
                    }
                    
                    try sql.print(allocator, ";\n", .{});
                } else if (needs_update) {
                    try sql.print(allocator, "ALTER TABLE {s} ALTER COLUMN {s} TYPE {s};\n", .{
                        table_name, column_name, sql_type
                    });
                    
                    try sql.print(allocator, "ALTER TABLE {s} ALTER COLUMN {s} ", .{
                        table_name, column_name
                    });
                    
                    if (nullable) {
                        try sql.print(allocator, "DROP NOT NULL;\n", .{});
                    } else {
                        try sql.print(allocator, "SET NOT NULL;\n", .{});
                    }
                }
            }
            
            for (table_info.items) |info| {
                var should_drop = true;
                
                for (model_columns.items) |model_col| {
                    if (std.mem.eql(u8, info.column, model_col)) {
                        should_drop = false;
                        break;
                    }
                }
                
                if (should_drop) {
                    try sql.print(allocator, "ALTER TABLE {s} DROP COLUMN {s};\n", .{
                        table_name, info.column
                    });
                }
            }
        },
        else => return error.ModelMustBeStruct,
    }

    return sql.toOwnedSlice(allocator);
}

pub fn makeMigration(allocator: std.mem.Allocator, db: *pg.Pool, comptime Model: type) !void {
    var conn = try db.acquire();
    defer conn.release();

    const table_name = try utils.getTableName(allocator, Model);
    defer allocator.free(table_name);

    var table_info = try utils.getTableInformation(allocator, conn, table_name);
    defer {
        for (table_info.items) |i| {
            allocator.free(i.column);
            allocator.free(i.type);
        }
        table_info.deinit(allocator);
    }

    const sql = if (table_info.items.len == 0)
        try create(allocator, Model, table_name)
    else
        try alter(allocator, Model, table_name, table_info);

    defer allocator.free(sql);

    std.debug.print("SQL: {s}\n", .{sql});

    const timestamp = std.time.timestamp();
    const migration_name = try std.fmt.allocPrint(allocator, "{d}_{s}.sql", .{ timestamp, table_name });
    defer allocator.free(migration_name);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ "migrations", migration_name });
    defer allocator.free(file_path);

    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();

    try file.writeAll(sql);

    std.debug.print("Created migration: {s}\n", .{migration_name});
}

pub fn migrate(allocator: std.mem.Allocator, db: *pg.Pool) !void {
    try utils.ensureMigrationsTable(db);

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
