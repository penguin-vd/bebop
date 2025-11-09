const std = @import("std");
const pg = @import("pg");
const utils = @import("utils.zig");

pub fn Map(comptime Model: type) type {
    return struct {
        const Self = @This();

        pub fn list(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn) ![]Model {
            const table_name = try utils.getTableName(allocator, Model);
            defer allocator.free(table_name);

            const field_list = try utils.getFieldList(allocator, Model);
            defer allocator.free(field_list);

            const sql = try std.fmt.allocPrint(allocator, "SELECT {s} FROM {s};", .{ field_list, table_name });
            defer allocator.free(sql);

            var result = try conn.query(sql, .{});
            defer result.deinit();

            var models = std.ArrayList(Model){};
            errdefer models.deinit(allocator);

            while (try result.next()) |row| {
                const model = try rowToModel(allocator, row);
                try models.append(allocator, model);
            }

            return models.toOwnedSlice(allocator);
        }

        pub fn create(_: *const Self, allocator: std.mem.Allocator, conn: *pg.Conn, model: Model) !Model {
            const table_name = try utils.getTableName(allocator, Model);
            defer allocator.free(table_name);

            const insert_sql = try buildInsertSQL(allocator, table_name);
            defer allocator.free(insert_sql);

            var result = try executeInsertQuery(conn, model, insert_sql);
            defer result.deinit();

            if (try result.next()) |row| {
                return try rowToModel(allocator, row);
            }

            return error.InsertFailed;
        }

        fn buildInsertSQL(allocator: std.mem.Allocator, table_name: []const u8) ![]const u8 {
            var fields = std.ArrayList(u8){};
            defer fields.deinit(allocator);

            var placeholders = std.ArrayList(u8){};
            defer placeholders.deinit(allocator);

            const struct_info = @typeInfo(Model).@"struct";
            var param_count: usize = 0;

            inline for (struct_info.fields) |field| {
                if (comptime shouldSkipField(field.name)) continue;

                const column_name = getColumnName(field.name);

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

            const returning_fields = try utils.getFieldList(allocator, Model);
            defer allocator.free(returning_fields);

            return std.fmt.allocPrint(
                allocator,
                "INSERT INTO {s} ({s}) VALUES ({s}) RETURNING {s};",
                .{ table_name, fields.items, placeholders.items, returning_fields },
            );
        }

        fn executeInsertQuery(conn: *pg.Conn, model: Model, sql: []const u8) !*pg.Result {
            const struct_info = @typeInfo(Model).@"struct";

            comptime var field_count: usize = 0;
            inline for (struct_info.fields) |field| {
                if (!comptime shouldSkipField(field.name)) {
                    field_count += 1;
                }
            }

            comptime var tuple_fields: [field_count]std.builtin.Type.StructField = undefined;
            comptime var idx: usize = 0;

            inline for (struct_info.fields) |field| {
                if (comptime shouldSkipField(field.name)) continue;

                tuple_fields[idx] = .{
                    .name = std.fmt.comptimePrint("{d}", .{idx}),
                    .type = field.type,
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(field.type),
                };
                idx += 1;
            }

            const TupleType = @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &tuple_fields,
                .decls = &.{},
                .is_tuple = true,
            } });

            var tuple: TupleType = undefined;
            idx = 0;
            inline for (struct_info.fields) |field| {
                if (comptime shouldSkipField(field.name)) continue;

                tuple[idx] = @field(model, field.name);
                idx += 1;
            }

            return try conn.query(sql, tuple);
        }

        fn rowToModel(allocator: std.mem.Allocator, row: anytype) !Model {
            var model: Model = undefined;
            const struct_info = @typeInfo(Model).@"struct";

            inline for (struct_info.fields, 0..) |field, i| {
                @field(model, field.name) = try getFieldValue(allocator, field.type, row, i);
            }

            return model;
        }

        fn getFieldValue(allocator: std.mem.Allocator, comptime T: type, row: anytype, index: usize) !T {
            return switch (@typeInfo(T)) {
                .int, .float, .bool => row.get(T, index),
                .pointer => |ptr_info| blk: {
                    if (ptr_info.size == .slice and ptr_info.child == u8) {
                        const str = row.get([]const u8, index);
                        break :blk try allocator.dupe(u8, str);
                    }
                    @compileError("Unsupported pointer type: " ++ @typeName(T));
                },
                .optional => |opt_info| blk: {
                    if (row.isNull(index)) {
                        break :blk null;
                    }
                    break :blk try getFieldValue(allocator, opt_info.child, row, index);
                },
                else => @compileError("Unsupported field type: " ++ @typeName(T)),
            };
        }

        fn shouldSkipField(comptime field_name: []const u8) bool {
            const meta = comptime utils.getFieldMeta(Model, field_name);
            return if (meta) |m| m.is_auto_increment else false;
        }

        fn getColumnName(comptime field_name: []const u8) []const u8 {
            const meta = comptime utils.getFieldMeta(Model, field_name);
            return if (meta) |m| m.column_name orelse field_name else field_name;
        }
    };
}
