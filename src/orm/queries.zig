const std = @import("std");
const pg = @import("pg");

const utils = @import("utils.zig");

pub fn ensure_migrations_table(db: anytype) !void {
    const sql = "CREATE TABLE IF NOT EXISTS schema_migrations (id SERIAL PRIMARY KEY, migration_name VARCHAR(255) NOT NULL UNIQUE, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())";

    var conn = try db.acquire();
    defer conn.release();

    _ = try conn.exec(sql, .{});
}


pub fn build_create_table_query(
    allocator: std.mem.Allocator,
    comptime Model: type,
) ![]const u8 {
    const table_name = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    try sql.print(allocator, "CREATE TABLE IF NOT EXISTS {s} (\n", .{table_name});

    const type_info = @typeInfo(Model);
    if (type_info != .@"struct") return error.ModelMustBeStruct;

    const struct_info = type_info.@"struct";

    var primary_keys: std.ArrayList([]const u8) = .{};
    defer primary_keys.deinit(allocator);

    inline for (struct_info.fields) |field| {
        if (utils.get_field_meta(Model, field.name)) |meta| {
            if (meta.is_primary_key) {
                try primary_keys.append(allocator, meta.column_name orelse field.name);
            }
        }
    }

    inline for (struct_info.fields, 0..) |field, i| {
        var column_name_buf: [256]u8 = undefined;
        var column_name: []const u8 = field.name;
        var sql_type = utils.to_sql_type(field.type);

        if (!std.mem.eql(u8, sql_type, "SKIP")) { // Only execute if not SKIP
            if (std.mem.eql(u8, sql_type, "BELONGS_TO")) {
                column_name = try std.fmt.bufPrint(&column_name_buf, "{s}_id", .{field.name});
                sql_type = "INTEGER";
            } else {
                const meta = utils.get_field_meta(Model, field.name);
                if (meta) |m| {
                    if (m.column_name) |cn| {
                        column_name = cn;
                    }
                }
            }

            const nullable = @typeInfo(field.type) == .optional;

            try sql.print(allocator, "  {s} {s}", .{ column_name, sql_type });

            if (std.mem.eql(u8, utils.to_sql_type(field.type), "BELONGS_TO")) {
                const RelatedModel = comptime blk: {
                    const field_type_info = @typeInfo(field.type);
                    break :blk if (field_type_info == .optional) field_type_info.optional.child else field.type;
                };

                switch (@typeInfo(RelatedModel)) {
                    .@"struct" => {
                        const related_table_name = if (@hasDecl(RelatedModel, "table_name"))
                            RelatedModel.table_name
                        else
                            unreachable;
                        try sql.print(allocator, " REFERENCES {s}(id)", .{related_table_name});
                    },
                    else => unreachable,
                }
            }

            const meta = utils.get_field_meta(Model, field.name);
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
                if (m.default_value) |default| {
                    if (utils.needs_sql_quoting(sql_type)) {
                        try sql.print(allocator, " DEFAULT '{s}'", .{default});
                    } else {
                        try sql.print(allocator, " DEFAULT {s}", .{default});
                    }
                }
            }

            if (i < struct_info.fields.len - 1 or primary_keys.items.len > 0) {
                try sql.print(allocator, ",\n", .{});
            } else {
                try sql.print(allocator, "\n", .{});
            }
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

    try sql.print(allocator, ");", .{});
    return sql.toOwnedSlice(allocator);
}

pub fn build_pivot_table_queries(
    allocator: std.mem.Allocator,
    comptime Model: type,
) ![]const []const u8 {
    const owner_table = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    const struct_info = @typeInfo(Model).@"struct";
    comptime var m2m_count: usize = 0;
    inline for (struct_info.fields) |field| {
        if (comptime utils.is_many_relation(field.type) and utils.is_many_to_many(Model, field.name)) {
            m2m_count += 1;
        }
    }

    if (m2m_count == 0) return &.{};

    var results = try allocator.alloc([]const u8, m2m_count);
    comptime var idx: usize = 0;

    inline for (struct_info.fields) |field| {
        if (comptime utils.is_many_relation(field.type) and utils.is_many_to_many(Model, field.name)) {
            const ChildType = @typeInfo(field.type).pointer.child;
            const related_table = ChildType.table_name;
            const pivot_table = comptime utils.get_pivot_table_name(owner_table, related_table);
            const owner_fk = comptime owner_table ++ "_id";
            const related_fk = comptime related_table ++ "_id";

            var sql: std.ArrayList(u8) = .{};
            defer sql.deinit(allocator);

            try sql.print(allocator,
                "CREATE TABLE IF NOT EXISTS {s} (\n" ++
                "  {s} INTEGER REFERENCES {s}(id) NOT NULL,\n" ++
                "  {s} INTEGER REFERENCES {s}(id) NOT NULL,\n" ++
                "  PRIMARY KEY ({s}, {s})\n" ++
                ");", .{
                pivot_table,
                owner_fk,
                owner_table,
                related_fk,
                related_table,
                owner_fk,
                related_fk,
            });

            results[idx] = try sql.toOwnedSlice(allocator);
            idx += 1;
        }
    }

    return results;
}

pub fn build_alter_table_query(
    allocator: std.mem.Allocator,
    comptime Model: type,
    table_info: std.ArrayList(utils.TableInformation),
) ![]const u8 {
    const table_name = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    const type_info = @typeInfo(Model);
    if (type_info != .@"struct") return error.ModelMustBeStruct;

    const struct_info = type_info.@"struct";

    var model_columns: std.ArrayList([]const u8) = .{};
    defer {
        for (model_columns.items) |item| {
            allocator.free(item);
        }
        model_columns.deinit(allocator);
    }

    inline for (struct_info.fields) |field| {
        var column_name_buf: [256]u8 = undefined;
        var column_name: []const u8 = field.name;
        var sql_type = utils.to_sql_type(field.type);

        if (!std.mem.eql(u8, sql_type, "SKIP")) {
            if (std.mem.eql(u8, sql_type, "BELONGS_TO")) {
                column_name = try std.fmt.bufPrint(&column_name_buf, "{s}_id", .{field.name});
                sql_type = "INTEGER";
            } else {
                const meta = utils.get_field_meta(Model, field.name);
                if (meta) |m| {
                    if (m.column_name) |cn| {
                        column_name = cn;
                    }
                }
            }

            try model_columns.append(allocator, try allocator.dupe(u8, column_name));

            const nullable = @typeInfo(field.type) == .optional;

            var column_exists = false;
            var needs_type_update = false;

            for (table_info.items) |info| {
                if (std.mem.eql(u8, info.column, column_name)) {
                    column_exists = true;
                    needs_type_update = !utils.type_matches(sql_type, info.type);
                    break;
                }
            }

            if (!column_exists) {
                try sql.print(allocator, "ALTER TABLE {s} ADD COLUMN {s} {s}", .{
                    table_name,
                    column_name,
                    sql_type,
                });

                if (std.mem.eql(u8, utils.to_sql_type(field.type), "BELONGS_TO")) {
                    const RelatedModel = comptime blk: {
                        const field_type_info = @typeInfo(field.type);
                        break :blk if (field_type_info == .optional) field_type_info.optional.child else field.type;
                    };

                    switch (@typeInfo(RelatedModel)) {
                        .@"struct" => {
                            const related_table_name = if (@hasDecl(RelatedModel, "table_name"))
                                RelatedModel.table_name
                            else
                                unreachable;
                            try sql.print(allocator, " REFERENCES {s}(id)", .{related_table_name});
                        },
                        else => unreachable,
                    }
                }

                if (!nullable) {
                    if (utils.get_field_meta(Model, field.name)) |m| {
                        if (m.default_value) |default| {
                            if (utils.needs_sql_quoting(sql_type)) {
                                try sql.print(allocator, " DEFAULT '{s}'", .{default});
                            } else {
                                try sql.print(allocator, " DEFAULT {s}", .{default});
                            }
                        } else {
                            const default_val = utils.get_default_value(field.type);
                            try sql.print(allocator, " DEFAULT {s}", .{default_val});
                        }
                    } else {
                        const default_val = utils.get_default_value(field.type);
                        try sql.print(allocator, " DEFAULT {s}", .{default_val});
                    }
                }

                if (utils.get_field_meta(Model, field.name)) |m| {
                    if (m.is_unique and !m.is_primary_key) {
                        try sql.print(allocator, " UNIQUE", .{});
                    }
                }

                try sql.print(allocator, ";\n", .{});
            } else if (needs_type_update) {
                try sql.print(allocator, "ALTER TABLE {s} ALTER COLUMN {s} TYPE {s};\n", .{
                    table_name,
                    column_name,
                    sql_type,
                });

                try sql.print(allocator, "ALTER TABLE {s} ALTER COLUMN {s} ", .{
                    table_name,
                    column_name,
                });

                if (nullable) {
                    try sql.print(allocator, "DROP NOT NULL;\n", .{});
                } else {
                    try sql.print(allocator, "SET NOT NULL;\n", .{});
                }
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
                table_name,
                info.column,
            });
        }
    }

    return sql.toOwnedSlice(allocator);
}

pub fn build_drop_table_query(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const table_name = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    return std.fmt.allocPrint(allocator, "DROP TABLE IF EXISTS {s} CASCADE;", .{table_name});
}

pub fn build_reverse_alter_table_query(
    allocator: std.mem.Allocator,
    comptime Model: type,
    table_info: std.ArrayList(utils.TableInformation),
) ![]const u8 {
    const table_name = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    const type_info = @typeInfo(Model);
    if (type_info != .@"struct") return error.ModelMustBeStruct;

    const struct_info = type_info.@"struct";

    var model_columns: std.ArrayList([]const u8) = .{};
    defer {
        for (model_columns.items) |item| allocator.free(item);
        model_columns.deinit(allocator);
    }

    inline for (struct_info.fields) |field| {
        var column_name_buf: [256]u8 = undefined;
        var column_name: []const u8 = field.name;
        const sql_type = utils.to_sql_type(field.type);

        if (!std.mem.eql(u8, sql_type, "SKIP")) {
            if (std.mem.eql(u8, sql_type, "BELONGS_TO")) {
                column_name = try std.fmt.bufPrint(&column_name_buf, "{s}_id", .{field.name});
            } else {
                const meta = utils.get_field_meta(Model, field.name);
                if (meta) |m| {
                    if (m.column_name) |cn| column_name = cn;
                }
            }

            try model_columns.append(allocator, try allocator.dupe(u8, column_name));

            var column_exists = false;
            for (table_info.items) |info| {
                if (std.mem.eql(u8, info.column, column_name)) {
                    column_exists = true;
                    break;
                }
            }

            if (!column_exists) {
                try sql.print(allocator, "ALTER TABLE {s} DROP COLUMN IF EXISTS {s};\n", .{
                    table_name,
                    column_name,
                });
            }
        }
    }

    for (table_info.items) |info| {
        var should_readd = true;
        for (model_columns.items) |model_col| {
            if (std.mem.eql(u8, info.column, model_col)) {
                should_readd = false;
                break;
            }
        }

        if (should_readd) {
            try sql.print(allocator, "ALTER TABLE {s} ADD COLUMN {s} {s};\n", .{
                table_name,
                info.column,
                info.type,
            });
        }
    }

    return sql.toOwnedSlice(allocator);
}

pub fn build_drop_pivot_table_queries(
    allocator: std.mem.Allocator,
    comptime Model: type,
) ![]const []const u8 {
    const owner_table = if (@hasDecl(Model, "table_name"))
        Model.table_name
    else
        unreachable;

    const struct_info = @typeInfo(Model).@"struct";
    comptime var m2m_count: usize = 0;
    inline for (struct_info.fields) |field| {
        if (comptime utils.is_many_relation(field.type) and utils.is_many_to_many(Model, field.name)) {
            m2m_count += 1;
        }
    }

    if (m2m_count == 0) return &.{};

    var results = try allocator.alloc([]const u8, m2m_count);
    comptime var idx: usize = 0;

    inline for (struct_info.fields) |field| {
        if (comptime utils.is_many_relation(field.type) and utils.is_many_to_many(Model, field.name)) {
            const ChildType = @typeInfo(field.type).pointer.child;
            const related_table = ChildType.table_name;
            const pivot_table = comptime utils.get_pivot_table_name(owner_table, related_table);

            results[idx] = try std.fmt.allocPrint(allocator, "DROP TABLE IF EXISTS {s} CASCADE;", .{pivot_table});
            idx += 1;
        }
    }

    return results;
}
