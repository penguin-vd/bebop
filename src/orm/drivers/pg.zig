const std = @import("std");
const pg = @import("pg");
const base = @import("base.zig");
const utils = @import("../utils.zig");

fn build_list_query(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

    const field_list = try utils.get_field_list(allocator, Model);
    defer allocator.free(field_list);

    return std.fmt.allocPrint(allocator, "SELECT {s} FROM {s};", .{ field_list, table_name });
}

fn build_insert_query(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

    var fields = std.ArrayList(u8){};
    defer fields.deinit(allocator);

    var placeholders = std.ArrayList(u8){};
    defer placeholders.deinit(allocator);

    const struct_info = @typeInfo(Model).@"struct";
    var param_count: usize = 0;

    inline for (struct_info.fields) |field| {
        if (comptime utils.should_skip_field(Model, field.name)) continue;

        const column_name = utils.get_column_name(Model, field.name);

        if (param_count > 0) {
            try fields.appendSlice(allocator, ", ");
            try placeholders.appendSlice(allocator, ", ");
        }

        try fields.appendSlice(allocator, column_name);

        param_count += 1;
        const placeholder = try std.fmt.allocPrint(allocator, "${d}", .{param_count});
        defer allocator.free(placeholder);
        try placeholders.appendSlice(allocator, placeholder);
    }

    const returning_fields = try utils.get_field_list(allocator, Model);
    defer allocator.free(returning_fields);

    return std.fmt.allocPrint(
        allocator,
        "INSERT INTO {s} ({s}) VALUES ({s}) RETURNING {s};",
        .{ table_name, fields.items, placeholders.items, returning_fields },
    );
}

fn build_create_table_query(
    allocator: std.mem.Allocator,
    comptime Model: type,
) ![]const u8 {
    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

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
        const meta = utils.get_field_meta(Model, field.name);
        const column_name = if (meta) |m| m.column_name orelse field.name else field.name;
        const sql_type = to_sql_type(field.type);
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
            if (m.default_value) |default| {
                try sql.print(allocator, " DEFAULT {s}", .{default});
            }
        }

        if (i < struct_info.fields.len - 1 or primary_keys.items.len > 0) {
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

    try sql.print(allocator, ");", .{});
    return sql.toOwnedSlice(allocator);
}

fn build_alter_table_query(
    allocator: std.mem.Allocator,
    comptime Model: type,
    table_info: std.ArrayList(base.TableInformation),
) ![]const u8 {
    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    const type_info = @typeInfo(Model);
    if (type_info != .@"struct") return error.ModelMustBeStruct;

    const struct_info = type_info.@"struct";

    var model_columns: std.ArrayList([]const u8) = .{};
    defer model_columns.deinit(allocator);

    inline for (struct_info.fields) |field| {
        const meta = utils.get_field_meta(Model, field.name);
        const column_name = if (meta) |m| m.column_name orelse field.name else field.name;

        try model_columns.append(allocator, column_name);

        const sql_type = to_sql_type(field.type);
        const nullable = @typeInfo(field.type) == .optional;

        var column_exists = false;
        var needs_type_update = false;

        for (table_info.items) |info| {
            if (std.mem.eql(u8, info.column, column_name)) {
                column_exists = true;
                needs_type_update = !type_matches(sql_type, info.type);
                break;
            }
        }

        if (!column_exists) {
            try sql.print(allocator, "ALTER TABLE {s} ADD COLUMN {s} {s}", .{
                table_name,
                column_name,
                sql_type,
            });

            if (!nullable) {
                const default_val = get_default_value(field.type);
                try sql.print(allocator, " DEFAULT {s}", .{default_val});
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

fn get_table_information(allocator: std.mem.Allocator, conn: anytype, table_name: []const u8) !std.ArrayList(base.TableInformation) {
    const sql = "SELECT column_name, data_type, character_maximum_length FROM INFORMATION_SCHEMA.COLUMNS WHERE table_name = $1";
    var result = try conn.query(sql, .{table_name});
    defer result.deinit();

    var array: std.ArrayList(base.TableInformation) = .{};

    while (try result.next()) |row| {
        const t = row.get([]const u8, 1);
        const tUpper = try allocator.alloc(u8, t.len);
        for (t, 0..) |char, i| {
            tUpper[i] = std.ascii.toLower(char);
        }

        const c = row.get([]const u8, 0);
        const cClone = try allocator.dupe(u8, c);
        try array.append(allocator, .{
            .type = tUpper,
            .column = cClone,
        });
    }

    return array;
}

fn to_sql_type(comptime T: type) []const u8 {
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
        .optional => |opt_info| to_sql_type(opt_info.child),
        else => "TEXT",
    };
}

fn type_matches(model_type: []const u8, db_type: []const u8) bool {
    if (std.mem.eql(u8, model_type, "INTEGER") and
        (std.mem.eql(u8, db_type, "integer") or std.mem.eql(u8, db_type, "int4")))
    {
        return true;
    }
    if (std.mem.eql(u8, model_type, "BIGINT") and
        (std.mem.eql(u8, db_type, "bigint") or std.mem.eql(u8, db_type, "int8")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "TEXT") and
        (std.mem.eql(u8, db_type, "text") or std.mem.eql(u8, db_type, "character varying")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "REAL") and
        (std.mem.eql(u8, db_type, "real") or std.mem.eql(u8, db_type, "float4")))
    {
        return true;
    }

    if (std.mem.eql(u8, model_type, "BOOLEAN") and
        (std.mem.eql(u8, db_type, "boolean") or std.mem.eql(u8, db_type, "bool")))
    {
        return true;
    }

    return std.mem.eql(u8, model_type, db_type);
}

fn get_default_value(comptime T: type) []const u8 {
    return switch (@typeInfo(T)) {
        .int => "0",
        .float => "0.0",
        .bool => "false",
        .pointer => "''",
        .optional => "NULL",
        else => "''",
    };
}

fn ensure_migrations_table(db: anytype) !void {
    const sql = "CREATE TABLE IF NOT EXISTS schema_migrations (id SERIAL PRIMARY KEY, migration_name VARCHAR(255) NOT NULL UNIQUE, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW())";

    var conn = try db.acquire();
    defer conn.release();

    _ = try conn.exec(sql, .{});
}

fn build_list_query_with_filter(allocator: std.mem.Allocator, comptime Model: type, filter: anytype) ![]const u8 {
    const table_name = try utils.get_table_name(allocator, Model);
    defer allocator.free(table_name);

    const field_list = try utils.get_field_list(allocator, Model);
    defer allocator.free(field_list);

    var sql: std.ArrayList(u8) = .{};
    defer sql.deinit(allocator);

    try sql.print(allocator, "SELECT {s} FROM {s}", .{ field_list, table_name });

    var has_where = false;

    inline for (@typeInfo(@TypeOf(filter)).@"struct".fields) |field| {
        const val = @field(filter, field.name);
        if (val) |v| {
            if (!has_where) {
                try sql.print(allocator, " WHERE ", .{});
                has_where = true;
            } else {
                try sql.print(allocator, " AND ", .{});
            }

            // Parse field name and operator
            const field_name = comptime blk: {
                if (std.mem.indexOf(u8, field.name, "__")) |idx| {
                    break :blk field.name[0..idx];
                }
                break :blk field.name;
            };

            const operator = comptime blk: {
                if (std.mem.indexOf(u8, field.name, "__")) |idx| {
                    break :blk field.name[idx + 2 ..];
                }
                break :blk "eq";
            };

            const column_name = utils.get_column_name(Model, field_name);
            try sql.print(allocator, "{s}", .{column_name});

            // Format the value directly into SQL (with proper escaping!)
            const value_str = try formatSqlValue(allocator, v);
            defer allocator.free(value_str);

            if (std.mem.eql(u8, operator, "contains")) {
                try sql.print(allocator, " ILIKE '%' || {s} || '%'", .{value_str});
            } else if (std.mem.eql(u8, operator, "startsWith")) {
                try sql.print(allocator, " ILIKE {s} || '%'", .{value_str});
            } else if (std.mem.eql(u8, operator, "endsWith")) {
                try sql.print(allocator, " ILIKE '%' || {s}", .{value_str});
            } else if (std.mem.eql(u8, operator, "gt")) {
                try sql.print(allocator, " > {s}", .{value_str});
            } else if (std.mem.eql(u8, operator, "gte")) {
                try sql.print(allocator, " >= {s}", .{value_str});
            } else if (std.mem.eql(u8, operator, "lt")) {
                try sql.print(allocator, " < {s}", .{value_str});
            } else if (std.mem.eql(u8, operator, "lte")) {
                try sql.print(allocator, " <= {s}", .{value_str});
            } else {
                try sql.print(allocator, " = {s}", .{value_str});
            }
        }
    }

    try sql.print(allocator, ";", .{});
    return sql.toOwnedSlice(allocator);
}

fn formatSqlValue(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    const T = @TypeOf(value);
    
    switch (@typeInfo(T)) {
        .int, .comptime_int => {
            return std.fmt.allocPrint(allocator, "{d}", .{value});
        },
        .float, .comptime_float => {
            return std.fmt.allocPrint(allocator, "{d}", .{value});
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return std.fmt.allocPrint(allocator, "'{s}'", .{escapeSqlString(value)});
            }
            return std.fmt.allocPrint(allocator, "'{any}'", .{value});
        },
        else => {
            return std.fmt.allocPrint(allocator, "'{any}'", .{value});
        },
    }
}

fn escapeSqlString(str: []const u8) []const u8 {
    // TODO: Properly escape single quotes by doubling them
    // For now, this is a placeholder - you should implement proper escaping
    // Replace ' with ''
    return str; // FIXME: implement actual escaping!
}

pub const driver = base.Driver{
    .build_list_query = build_list_query,
    .build_insert_query = build_insert_query,
    .build_create_table_query = build_create_table_query,
    .build_alter_table_query = build_alter_table_query,
    .get_table_information = get_table_information,
    .to_sql_type = to_sql_type,
    .type_matches = type_matches,
    .get_default_value = get_default_value,
    .ensure_migrations_table = ensure_migrations_table,
    .build_list_query_with_filter = build_list_query_with_filter,
};
