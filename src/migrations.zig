const std = @import("std");

fn getTableName(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
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

pub fn inspectModel(allocator: std.mem.Allocator, comptime Model: type) !void {
    const table_name = try getTableName(allocator, @typeName(Model));
    defer allocator.free(table_name);

    std.debug.print("Table: {s}\n", .{table_name});
    std.debug.print("Fields:\n", .{});

    const type_info = @typeInfo(Model);

    switch (type_info) {
        .@"struct" => |struct_info| {
            inline for (struct_info.fields) |field| {
                const sql_type = zigTypeToSqlType(field.type);
                const nullable = @typeInfo(field.type) == .optional;

                std.debug.print("  - {s}: {s}", .{ field.name, sql_type });

                if (nullable) {
                    std.debug.print(" (nullable)", .{});
                } else {
                    std.debug.print(" NOT NULL", .{});
                }

                std.debug.print("\n", .{});
            }
        },
        else => {
            std.debug.print("Error: Model must be a struct type\n", .{});
        },
    }
}

pub fn generateMigration(allocator: std.mem.Allocator, comptime Model: type) ![]const u8 {
    const table_name = try getTableName(allocator, @typeName(Model));
    defer allocator.free(table_name);

    var sql: std.ArrayList(u8) = .{};
    errdefer sql.deinit(allocator);

    try sql.print(allocator, "CREATE TABLE {s} (\n", .{table_name});

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

                // Add comma if not last field
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
